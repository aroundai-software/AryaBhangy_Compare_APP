"""JSON-line worker for the Flutter UI.

One JSON object per stdin line (commands). One JSON object per stdout line
(events). stderr is for logs only. Tally stays read-only. Tracksheet writes follow the website address. The hosted demo uses its save.
The original Tracksheet updates the row that was read when its token is in the app.
"""

from __future__ import annotations

import json
import sys
import threading
import time
import traceback
from datetime import timedelta

from compare.engine import (
    ADDED,
    BOTH_MATCH,
    CHECK,
    KEEP,
    NOT_MATCHING,
    ONE_MATCH,
    REMOVED,
    compare,
)
from compare.normalize import as_date, bill_compare_key, format_date, is_hirise_invoice_service
from compare.records import Outcome, VoucherRow
from compare.report import summary_lines, write_report
from compare.session import (
    ALL_BRANCHES,
    branches_in,
    company_branch,
    filter_records,
    merge_tracksheet_for_tally_jcs,
)
from compare.tally_gateway import (
    apply_tally_port,
    current_company,
    hirise_vouchers,
    tally_status,
    voucher_type_names,
)
from compare.tracksheet_site import (
    SITE,
    apply_website,
    branch_names,
    can_save_site,
    confirm_site,
    is_practice_site,
    job_cards,
    job_cards_by_numbers,
    probe_website,
    save_blocked_reason,
    write_practice_cards,
)

WATCH_SECONDS = 3
# Tracksheet and Tally reads refuse a span longer than this. A sync past it
# is read in pieces and compared once.
_READ_SPAN_DAYS = 31


def date_slices(start, end, span=_READ_SPAN_DAYS):
    """Split a From–To range into pieces each read can accept."""
    slices = []
    cursor = start
    while cursor <= end:
        chunk_end = min(end, cursor + timedelta(days=span))
        slices.append((cursor, chunk_end))
        cursor = chunk_end + timedelta(days=1)
    return slices


class Worker:
    def __init__(self, stdin=None, stdout=None):
        self.stdin = stdin or sys.stdin
        self.stdout = stdout or sys.stdout
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._busy = False
        self._allow_practice_save = False
        self._last_company = ""
        self._last_online = None
        self._last_result = None
        self._last_tally_records = []
        self._last_company_name = ""
        self._skipped = 0

    def emit(self, payload):
        line = json.dumps(payload, ensure_ascii=True)
        with self._lock:
            self.stdout.write(line + "\n")
            self.stdout.flush()

    def run(self):
        watcher = threading.Thread(target=self._watch_tally, daemon=True)
        watcher.start()
        for raw in self.stdin:
            if self._stop.is_set():
                break
            line = raw.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                self.emit({"event": "error", "message": "Command was not valid JSON."})
                continue
            if not isinstance(message, dict):
                self.emit({"event": "error", "message": "Command must be a JSON object."})
                continue
            command = message.get("cmd")
            try:
                self.handle(command, message)
            except Exception as error:
                self.emit({"event": "error", "message": str(error) or type(error).__name__})
                traceback.print_exc(file=sys.stderr)
            if command == "shutdown":
                break
        self._stop.set()

    def handle(self, command, message):
        if command == "ping":
            self.emit({"event": "pong"})
            return
        if command == "settings.apply":
            self._apply_settings(message)
            return
        if command == "settings.check":
            self._check_settings(message)
            return
        if command == "branches.load":
            self._branches()
            return
        if command == "voucher_types.list":
            self._voucher_types()
            return
        if command == "compare.run":
            self._compare(message)
            return
        if command == "report.save":
            self._save(message)
            return
        if command == "tracksheet.write":
            self._write_cards(message)
            return
        if command == "shutdown":
            self.emit({"event": "shutdown"})
            self._stop.set()
            return
        self.emit({"event": "error", "message": "Unknown command: " + str(command)})

    def _apply_settings(self, message):
        port = apply_tally_port(message.get("tally_port"))
        apply_website(message.get("website"))
        save_site = confirm_site()
        allow = bool(message.get("allow_practice_save")) and save_site
        self._allow_practice_save = allow
        self.emit(
            {
                "event": "settings.applied",
                "tally_port": port,
                "website": SITE,
                "practice": is_practice_site(),
                "save_site": save_site,
                "allow_practice_save": allow,
            }
        )
        return port

    def _check_settings(self, message):
        port = self._apply_settings(message)
        status = tally_status(timeout=4)
        online = bool(status.get("online"))
        company = status.get("name") or ""
        if online and company:
            tally_message = f"Connected to Tally on port {port}. {company}."
        elif online:
            tally_message = f"Connected to Tally on port {port}. Open a company in Tally."
        else:
            tally_message = f"Unable to connect to Tally on port {port}."
        website_ok, website_message = probe_website(timeout=8)
        self._last_online = online
        self._last_company = company
        self.emit({"event": "tally.status", "online": online, "company": company})
        self.emit(
            {
                "event": "settings.checked",
                "tally_online": online,
                "tally_message": tally_message,
                "website_ok": website_ok,
                "website_message": website_message,
                "practice": is_practice_site(),
                "save_site": can_save_site(),
                "allow_practice_save": self._allow_practice_save,
            }
        )

    def _watch_tally(self):
        while not self._stop.is_set():
            if not self._busy:
                try:
                    status = tally_status(timeout=3)
                except Exception:
                    status = {"online": False, "name": "", "period": None}
                online = bool(status.get("online"))
                name = status.get("name") or ""
                if online != self._last_online or name != self._last_company:
                    self._last_online = online
                    self._last_company = name
                    self.emit({"event": "tally.status", "online": online, "company": name})
            self._stop.wait(WATCH_SECONDS)

    def _branches(self):
        names = branch_names()
        matched = company_branch(self._last_company, names) if self._last_company else ""
        self.emit({"event": "branches.loaded", "names": names, "preferred": matched})

    def _voucher_types(self):
        names = voucher_type_names()
        company = self._last_company or ""
        try:
            company = current_company() or company
        except Exception:
            pass

        def rank(name):
            folded = name.upper()
            if folded == "HIRISE INVOICE SERVICE":
                return (0, folded)
            if "SERVICE BILL" in folded:
                return (1, folded)
            return (2, folded)

        self.emit(
            {
                "event": "voucher_types.loaded",
                "company": company,
                "names": sorted(names, key=rank),
            }
        )

    def _chosen_voucher_types(self, message):
        chosen = []
        for item in message.get("voucher_types") or []:
            text = str(item or "").strip()
            if text and text not in chosen:
                chosen.append(text)
        return chosen

    def _compare(self, message):
        if self._busy:
            self.emit({"event": "error", "message": "A compare is already running."})
            return
        start = as_date(message.get("from"))
        end = as_date(message.get("to"))
        if start is None or end is None:
            self.emit({"event": "error", "message": "Choose a From date and a To date."})
            return
        if start > end:
            self.emit({"event": "error", "message": "From date is after To date."})
            return
        branch = (message.get("branch") or ALL_BRANCHES).strip() or ALL_BRANCHES
        voucher_types = self._chosen_voucher_types(message)
        if not voucher_types:
            self.emit(
                {
                    "event": "error",
                    "message": (
                        "Choose the voucher types for this company in Settings "
                        "and save them before comparing."
                    ),
                }
            )
            return
        self._busy = True
        started = time.perf_counter()
        phase = {"tracksheet_s": 0.0, "tally_s": 0.0, "extra_jc_s": 0.0, "compare_s": 0.0}
        try:
            name = current_company()
            self._last_company_name = name
            self._last_company = name
            self._last_online = True
            self.emit({"event": "tally.status", "online": True, "company": name})
            if not name:
                raise RuntimeError(
                    "Tally is online, but no company is loaded. Open a company in Tally first."
                )

            t0 = time.perf_counter()
            loaded = []
            seen_track = 0
            for chunk_start, chunk_end in date_slices(start, end):
                def track_progress(day, count, base=seen_track):
                    self.emit(
                        {
                            "event": "progress",
                            "source": "Tracksheet",
                            "day": day.isoformat(),
                            "label": format_date(day),
                            "count": base + count,
                            "elapsed_s": round(time.perf_counter() - started, 1),
                        }
                    )

                chunk = job_cards(chunk_start, chunk_end, progress=track_progress)
                seen_track += len(chunk)
                loaded.extend(chunk)
            phase["tracksheet_s"] = round(time.perf_counter() - t0, 2)
            names = branches_in(loaded)
            used = branch if branch and branch != ALL_BRANCHES else company_branch(name, names)

            t0 = time.perf_counter()
            tally_records = []
            seen_tally = 0
            for chunk_start, chunk_end in date_slices(start, end):
                def tally_progress(day, count, base=seen_tally):
                    self.emit(
                        {
                            "event": "progress",
                            "source": "Tally",
                            "day": day.isoformat(),
                            "label": format_date(day),
                            "count": base + count,
                            "elapsed_s": round(time.perf_counter() - started, 1),
                        }
                    )

                chunk = hirise_vouchers(
                    chunk_start,
                    chunk_end,
                    progress=tally_progress,
                    voucher_types=voucher_types,
                )
                seen_tally += len(chunk)
                tally_records.extend(chunk)
            for index, record in enumerate(tally_records, start=1):
                record.row_number = index
            phase["tally_s"] = round(time.perf_counter() - t0, 2)
            for record in tally_records:
                record.branch = used
            track_records = filter_records(loaded, start, end, used or branch)

            def jc_progress(card, count):
                self.emit(
                    {
                        "event": "progress",
                        "source": "Tracksheet",
                        "day": start.isoformat(),
                        "label": "JC " + card,
                        "count": count,
                        "elapsed_s": round(time.perf_counter() - started, 1),
                    }
                )

            t0 = time.perf_counter()
            track_records = merge_tracksheet_for_tally_jcs(
                track_records,
                tally_records,
                used or branch,
                lambda numbers: job_cards_by_numbers(numbers, progress=jc_progress),
            )
            phase["extra_jc_s"] = round(time.perf_counter() - t0, 2)

            t0 = time.perf_counter()
            service_types = [
                name for name in voucher_types if not is_hirise_invoice_service(name)
            ]
            result = compare(
                track_records, tally_records, service_types=service_types
            )
            phase["compare_s"] = round(time.perf_counter() - t0, 2)
            total_s = round(time.perf_counter() - started, 2)
            phase["total_s"] = total_s
            print(
                "COMPARE_TIMING "
                f"from={start.isoformat()} to={end.isoformat()} "
                f"tracksheet={phase['tracksheet_s']}s "
                f"tally={phase['tally_s']}s "
                f"extra_jc={phase['extra_jc_s']}s "
                f"compare={phase['compare_s']}s "
                f"total={total_s}s "
                f"track_rows={result.track_rows} tally_rows={result.tally_rows}",
                file=sys.stderr,
                flush=True,
            )
            self._last_result = result
            self._last_tally_records = tally_records
            self._skipped = 0
            self.emit(
                {
                    "event": "compare.result",
                    "company": name,
                    "branch": used or branch,
                    "from": start.isoformat(),
                    "to": end.isoformat(),
                    "track_rows": result.track_rows,
                    "tally_rows": result.tally_rows,
                    "uncovered_rows": result.uncovered_rows,
                    "added": result.count(ADDED),
                    "removed": result.count(REMOVED),
                    "check": result.count(CHECK),
                    "keep": result.count(KEEP),
                    "both_match": result.count_category(BOTH_MATCH),
                    "one_match": result.count_category(ONE_MATCH),
                    "not_matching": result.count_category(NOT_MATCHING),
                    "hirise_bills": len(tally_records),
                    "voucher_rows": len(result.vouchers),
                    "branches": [ALL_BRANCHES, *sorted(set(names))],
                    "rows": [_outcome_row(outcome) for outcome in result.outcomes],
                    "vouchers": [_voucher_row(row) for row in result.vouchers],
                    "timing": phase,
                }
            )
        finally:
            self._busy = False

    def _write_cards(self, message):
        if self._busy:
            self.emit({"event": "error", "message": "Wait until the current compare finishes."})
            return
        self._busy = True
        try:
            if message.get("website"):
                apply_website(message.get("website"))
                confirm_site()
            allow = bool(message.get("allow_practice_save")) and can_save_site()
            self._allow_practice_save = allow
            if not can_save_site():
                raise RuntimeError(save_blocked_reason())
            if not allow:
                raise RuntimeError("Turn on saving for the Tracksheet in Settings.")
            rows = message.get("rows") or []
            cards = []
            for row in rows:
                if not isinstance(row, dict):
                    continue
                job = str(row.get("job_card") or "").strip()
                if not job:
                    continue
                cards.append(
                    {
                        "key": str(row.get("key") or ""),
                        "job_card": job,
                        "vehicle": _sheet_vehicle(row),
                        "bill": _write_bill(row),
                        "labour": row.get("labour") or "",
                        "spares": row.get("spares") or "",
                        "total": row.get("total") or "",
                        "vas": row.get("vas") or "",
                        "items": row.get("items") or "",
                        "sheet_row_id": _sheet_row_id(row.get("sheet_row_id")),
                    }
                )
            if not cards:
                raise RuntimeError("Choose a job card to write.")
            summary = write_practice_cards(cards)
        except Exception as error:
            self.emit({"event": "error", "message": str(error)})
            return
        finally:
            self._busy = False
        written = []
        failed = []
        for item in summary.get("results") or []:
            if item.get("ok"):
                written.append(item.get("key") or item.get("job_card") or "")
            else:
                failed.append(
                    {
                        "job_card": item.get("job_card") or "",
                        "error": item.get("error") or "Could not write that job card.",
                    }
                )
        self.emit(
            {
                "event": "tracksheet.written",
                "updated": summary.get("updated") or 0,
                "written": written,
                "failed": failed,
            }
        )

    def _save(self, message):
        path = (message.get("path") or "").strip()
        if not path:
            self.emit({"event": "error", "message": "Choose a path for the Excel file."})
            return
        snapshot = message.get("snapshot")
        if isinstance(snapshot, dict):
            outcomes = [_outcome_from_dict(row) for row in (snapshot.get("rows") or [])]
            vouchers = [_voucher_from_dict(row) for row in (snapshot.get("vouchers") or [])]
            lines = [
                "Aryabhangy Tracksheet compare (history export)",
                f"Company: {snapshot.get('company') or ''}",
                f"Branch: {snapshot.get('branch') or ''}",
                f"From: {snapshot.get('from') or ''}  To: {snapshot.get('to') or ''}",
                f"Saved at: {snapshot.get('saved_at') or ''}",
            ]
            write_report(path, lines, outcomes, vouchers=vouchers)
            self.emit({"event": "report.saved", "path": path})
            return
        if self._last_result is None:
            self.emit({"event": "error", "message": "Run compare before saving Excel."})
            return
        lines = summary_lines(
            self._last_result,
            SITE,
            self._last_company_name or self._last_company,
            self._last_tally_records,
            self._skipped,
        )
        write_report(
            path,
            lines,
            self._last_result.outcomes,
            vouchers=self._last_result.vouchers,
        )
        self.emit({"event": "report.saved", "path": path})


def _sheet_vehicle(row):
    """Write onto the Tracksheet registration when the bill's vehicle differs."""
    vehicle = str(row.get("vehicle") or "").strip()
    reason = str(row.get("reason") or "")
    if "vehicle numbers do not match" in reason and " / " in vehicle:
        sheet = vehicle.split(" / ", 1)[0].strip()
        if sheet and " and " not in sheet:
            return sheet
    return vehicle


def _sheet_row_id(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _write_bill(row):
    """Bill # to save. A vehicle mismatch keeps the sheet bill empty for display."""
    bill = str(row.get("bill") or "").strip()
    reason = str(row.get("reason") or "")
    if "vehicle numbers do not match" not in reason:
        return bill
    keys = []
    seen = set()
    for part in str(row.get("tally_bills") or "").split(";"):
        key = bill_compare_key(part)
        if key and key not in seen:
            seen.add(key)
            keys.append(key)
    return "; ".join(keys) if keys else bill


def _outcome_row(outcome):
    return {
        "mark": outcome.mark,
        "category": outcome.category,
        "job_card": outcome.job_card,
        "vehicle": outcome.vehicle,
        "customer": outcome.customer,
        "when": outcome.when,
        "adviser": outcome.adviser,
        "branch": outcome.branch,
        "reason": outcome.reason,
        "tally_bills": outcome.tally_bills,
        "track_bill": outcome.track_bill,
        "amount": outcome.amount,
        "status": outcome.status,
        "service": outcome.service,
        "phone": outcome.phone,
        "model": outcome.model,
        "booking": outcome.booking,
        "technician": outcome.technician,
        "labour": outcome.labour,
        "spares": outcome.spares,
        "vas": outcome.vas,
        "payment": outcome.payment,
        "items": outcome.items,
        "tally_labour": outcome.tally_labour,
        "tally_spares": outcome.tally_spares,
        "tally_vas": outcome.tally_vas,
        "tally_total": outcome.tally_total,
        "tally_when": outcome.tally_when,
        "sheet_bill": outcome.sheet_bill,
        "sheet_labour": outcome.sheet_labour,
        "sheet_spares": outcome.sheet_spares,
        "sheet_total": outcome.sheet_total,
        "sheet_vas": outcome.sheet_vas,
        "sheet_when": outcome.sheet_when,
        "sheet_row_id": outcome.sheet_row_id,
    }


def _voucher_row(row):
    return {
        "voucher_number": row.voucher_number,
        "when": row.when,
        "branch": row.branch,
        "registration": row.registration,
        "job_card": row.job_card,
        "has_job_card": row.has_job_card,
        "labour": row.labour,
        "spares": row.spares,
        "vas": row.vas,
        "items": row.items,
        "note": row.note,
    }


def _outcome_from_dict(data):
    data = data or {}
    return Outcome(
        mark=str(data.get("mark") or ""),
        reason=str(data.get("reason") or ""),
        job_card=str(data.get("job_card") or ""),
        vehicle=str(data.get("vehicle") or ""),
        customer=str(data.get("customer") or ""),
        when=str(data.get("when") or ""),
        branch=str(data.get("branch") or ""),
        tally_bills=str(data.get("tally_bills") or ""),
        track_bill=str(data.get("track_bill") or ""),
        adviser=str(data.get("adviser") or ""),
        status=str(data.get("status") or ""),
        service=str(data.get("service") or ""),
        amount=str(data.get("amount") or ""),
        category=str(data.get("category") or ""),
        phone=str(data.get("phone") or ""),
        model=str(data.get("model") or ""),
        booking=str(data.get("booking") or ""),
        technician=str(data.get("technician") or ""),
        labour=str(data.get("labour") or ""),
        spares=str(data.get("spares") or ""),
        vas=str(data.get("vas") or ""),
        payment=str(data.get("payment") or ""),
        items=str(data.get("items") or ""),
        tally_labour=str(data.get("tally_labour") or ""),
        tally_spares=str(data.get("tally_spares") or ""),
        tally_vas=str(data.get("tally_vas") or ""),
        tally_total=str(data.get("tally_total") or ""),
        tally_when=str(data.get("tally_when") or ""),
        sheet_bill=str(data.get("sheet_bill") or ""),
        sheet_labour=str(data.get("sheet_labour") or ""),
        sheet_spares=str(data.get("sheet_spares") or ""),
        sheet_total=str(data.get("sheet_total") or ""),
        sheet_vas=str(data.get("sheet_vas") or ""),
        sheet_when=str(data.get("sheet_when") or ""),
        sheet_row_id=_sheet_row_id(data.get("sheet_row_id")),
    )


def _voucher_from_dict(data):
    data = data or {}
    return VoucherRow(
        voucher_number=str(data.get("voucher_number") or ""),
        when=str(data.get("when") or ""),
        branch=str(data.get("branch") or ""),
        registration=str(data.get("registration") or ""),
        job_card=str(data.get("job_card") or ""),
        labour=str(data.get("labour") or ""),
        spares=str(data.get("spares") or ""),
        vas=str(data.get("vas") or ""),
        items=str(data.get("items") or ""),
        has_job_card=bool(data.get("has_job_card", True)),
        note=str(data.get("note") or ""),
    )


def main():
    Worker().run()


if __name__ == "__main__":
    main()
