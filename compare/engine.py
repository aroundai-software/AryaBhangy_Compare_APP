from collections import defaultdict
from dataclasses import replace

from compare.money import (
    format_money,
    join_name_list,
    ledger_fill_parts,
    money_matches,
    parse_amount,
    split_item_list,
    tally_bill_total,
    track_bill_total,
    vas_keys,
)
from compare.normalize import bill_compare_key, format_date, is_service_bill
from compare.records import CompareResult, Outcome, VoucherRow

ADDED = "Added to track"
REMOVED = "Removed from tracksheet"
CHECK = "Check manually"
KEEP = "No change"

BOTH_MATCH = "Both match"
ONE_MATCH = "Only one match"
NOT_MATCHING = "Not matching"


def _key(record):
    return (record.financial_year, record.job_card, record.vehicle)


def _join(values):
    seen = []
    for value in values:
        text = (value or "").strip()
        if text and text not in seen:
            seen.append(text)
    return " and ".join(seen)


def _bills(records):
    pairs = []
    seen = set()
    for record in records:
        if not record.bill or record.bill in seen:
            continue
        seen.add(record.bill)
        pairs.append(record.bill)
    return "; ".join(pairs)


def _last4_bills(records):
    """Tracksheet-style Bill # (last 4) from Tally voucher numbers."""
    pairs = []
    seen = set()
    for record in records:
        key = bill_compare_key(record.bill)
        if not key or key in seen:
            continue
        seen.add(key)
        pairs.append(key)
    return "; ".join(pairs)


def _bill_set(records):
    keys = set()
    for record in records:
        key = bill_compare_key(record.bill)
        if key:
            keys.add(key)
    return keys


def _set_category(outcome, category):
    outcome.category = category
    return outcome


def _incomplete_card_reason(record):
    """Name the blank field. A shown job card is not described as missing."""
    if record.job_card and not record.vehicle:
        return f"Job Card {record.job_card} has no vehicle number. Nothing was changed."
    if record.vehicle and not record.job_card:
        return f"Vehicle {record.vehicle} has no job card number. Nothing was changed."
    return "This row has no job card number and no vehicle number. Nothing was changed."


def _stamp_sheet(outcome, track_rows):
    """Keep the amounts and bill already stored on the Tracksheet.

    Fill display overwrites labour, spares, total, and Bill # with the Tally
    values that Write will save. These fields stay the sheet's own values.
    """
    rows = list(track_rows or [])
    outcome.sheet_bill = _bills(rows)
    outcome.sheet_labour = _join(row.labour for row in rows if row.labour)
    outcome.sheet_spares = _join(row.spares for row in rows if row.spares)
    outcome.sheet_vas = _join(row.vas for row in rows if row.vas)
    outcome.sheet_when = _join(format_date(row.on) for row in rows if row.on)
    totals = []
    for row in rows:
        total = track_bill_total(row)
        if not total:
            continue
        text = format_money(total)
        if text and text not in totals:
            totals.append(text)
    outcome.sheet_total = "; ".join(totals)
    for row in rows:
        if row.sheet_row_id:
            outcome.sheet_row_id = row.sheet_row_id
            break
    return outcome


def _stamp_tally(outcome, tally_rows):
    """Bill date and voucher amounts, before a ledger fill replaces them."""
    rows = list(tally_rows or [])
    if not rows:
        return outcome
    outcome.tally_when = _join(format_date(row.on) for row in rows if row.on)
    labour, spares, vas = _tally_money(rows)
    outcome.tally_labour = labour
    outcome.tally_spares = spares
    outcome.tally_vas = vas
    total = tally_bill_total(rows)
    outcome.tally_total = format_money(total) if total else ""
    return outcome


def _copy_job_fields(outcome, records):
    ordered = sorted(
        records,
        key=lambda record: (0 if record.source == "tracksheet" else 1, record.on or "", record.row_number),
    )
    if not ordered:
        return outcome
    primary = ordered[0]
    for record in ordered:
        if record.source == "tracksheet":
            primary = record
            break
    outcome.phone = primary.phone or _join(r.phone for r in ordered)
    outcome.model = primary.model or _join(r.model for r in ordered)
    outcome.booking = primary.booking or _join(r.booking for r in ordered)
    outcome.technician = primary.technician or _join(r.technician for r in ordered)
    outcome.labour = primary.labour or _join(r.labour for r in ordered)
    outcome.spares = primary.spares or _join(r.spares for r in ordered)
    outcome.vas = primary.vas or _join(r.vas for r in ordered)
    outcome.payment = primary.payment or _join(r.payment for r in ordered)
    # Items come from Tally bill stock lines when present (newline-safe join).
    tally_items = []
    for record in ordered:
        if record.source == "tally" and record.items:
            tally_items.extend(split_item_list(record.items))
    if tally_items:
        outcome.items = join_name_list(tally_items)
    else:
        other_items = []
        for record in ordered:
            if record.items:
                other_items.extend(split_item_list(record.items))
        outcome.items = join_name_list(other_items)
    if not outcome.status:
        outcome.status = primary.status or _join(r.status for r in ordered)
    if primary.source == "tracksheet" and primary.sheet_row_id:
        outcome.sheet_row_id = primary.sheet_row_id
    return outcome


def _describe(records):
    ordered = sorted(records, key=lambda record: (record.on or "", record.row_number))
    outcome = Outcome(
        mark="",
        reason="",
        job_card=_join(record.job_card for record in ordered),
        vehicle=_join(record.vehicle for record in ordered),
        customer=_join(record.customer for record in ordered),
        when=_join(format_date(record.on) for record in ordered),
        branch=_join(record.branch for record in ordered),
        adviser=_join(record.adviser for record in ordered),
        status=_join(record.status for record in ordered),
        service=_join(record.service or record.voucher_type for record in ordered),
        amount=_join(record.amount for record in ordered if record.amount and record.amount != "0"),
    )
    return _copy_job_fields(outcome, ordered)


def _span(records):
    dates = sorted(record.on for record in records if record.on)
    if not dates:
        return "", ""
    return format_date(dates[0]), format_date(dates[-1])


def _tally_money(rows):
    labour = _join(r.labour for r in rows if r.labour)
    spares = _join(r.spares for r in rows if r.spares)
    vas = _join(r.vas for r in rows if r.vas)
    return labour, spares, vas


def _item_name_keys(value):
    """Item names compared without regard to order or capital letters."""
    return {
        " ".join(name.upper().split())
        for name in split_item_list(value)
        if " ".join(name.upper().split())
    }


def _tally_items(rows):
    names = []
    for record in rows:
        if record.items:
            names.extend(split_item_list(record.items))
    return join_name_list(names)


def _vas_from_all_jc_bills(tally_by_jc, job_card):
    rows = tally_by_jc.get(job_card, [])
    return _join(r.vas for r in rows if r.vas)


def _has_ledger_lines(record):
    return bool((getattr(record, "ledgers", "") or "").strip() or (getattr(record, "ledamts", "") or "").strip())


def _service_matches(bill, hirise_rows):
    """Hirise bills this service bill belongs with.

    A job card on the service bill wins. Otherwise the same vehicle and the
    same bill date, because most service bills have an empty narration.
    """
    if bill.job_card:
        rows = [
            row
            for row in hirise_rows
            if row.job_card == bill.job_card and (not bill.vehicle or row.vehicle == bill.vehicle)
        ]
        if rows:
            return rows
    if bill.vehicle and bill.on:
        return [row for row in hirise_rows if row.vehicle == bill.vehicle and row.on == bill.on]
    return []


def link_service_bills(tally_groups, service_bills):
    """Attach each service bill to one Hirise job, or mark the day ambiguous.

    Returns (attached, ambiguous_keys, unassigned, notes).
    attached maps (year, job card, vehicle) to service-bill records.
    """
    hirise_rows = [row for rows in tally_groups.values() for row in rows]
    attached = defaultdict(list)
    ambiguous = set()
    unassigned = []
    notes = {}
    for bill in service_bills:
        matches = _service_matches(bill, hirise_rows)
        jobs = []
        seen = set()
        for row in matches:
            key = _key(row)
            if key[1] and key[2] and key not in seen:
                seen.add(key)
                jobs.append(key)
        if len(jobs) == 1:
            attached[jobs[0]].append(bill)
            notes[id(bill)] = "Service bill joined to the Hirise job on this day"
        elif len(jobs) > 1:
            ambiguous.update(jobs)
            notes[id(bill)] = (
                "Service bill not joined: two Hirise bills share this customer and date"
            )
        else:
            unassigned.append(bill)
            notes[id(bill)] = "Service bill not joined: no single Hirise bill on this day"
    return attached, ambiguous, unassigned, notes


def combine_fill(hirise_rows, service_rows):
    """Sum pre-tax labour and spares and the with-tax total. None without ledger lines."""
    rows = [(row, False) for row in hirise_rows or []] + [(row, True) for row in service_rows or []]
    if not any(_has_ledger_lines(row) for row, _service in rows):
        return None
    labour = 0.0
    spares = 0.0
    total = 0.0
    names = []
    seen = set()
    for row, service in rows:
        if not _has_ledger_lines(row):
            if service:
                total += parse_amount(row.amount)
            continue
        parts = ledger_fill_parts(
            row.ledgers,
            row.ledamts,
            service_bill=service,
            party_name=row.customer,
        )
        labour += parts["labour"]
        spares += parts["spares"]
        bill_total = parts["total"] or parse_amount(row.amount)
        total += bill_total
        for name in parts["vas"]:
            key = name.upper()
            if key not in seen:
                seen.add(key)
                names.append(name)
    return {
        "labour": round(labour, 2),
        "spares": round(spares, 2),
        "total": round(total, 2),
        "vas": names,
    }


_FILL_NOTE = (
    "Labour and spares are before GST. Nothing is written until you press Write."
)
_AMBIGUOUS_NOTE = (
    "A service bill on this day was left out because two Hirise bills "
    "are for this vehicle on the same day. Please check which job it belongs to."
)


def _apply_fill_display(outcome, fill, hirise_rows, ambiguous):
    """Show the Tally fill in the columns the app would otherwise copy from Tracksheet."""
    if ambiguous:
        outcome.mark = CHECK
        outcome.category = ONE_MATCH
        if _AMBIGUOUS_NOTE not in (outcome.reason or ""):
            outcome.reason = ((outcome.reason or "").rstrip() + " " + _AMBIGUOUS_NOTE).strip()
    if not fill:
        return outcome
    last4 = _last4_bills(hirise_rows)
    if last4:
        outcome.track_bill = last4
    outcome.labour = format_money(fill["labour"]) if fill["labour"] else ""
    outcome.spares = format_money(fill["spares"]) if fill["spares"] else ""
    if fill["total"]:
        outcome.amount = format_money(fill["total"])
    outcome.vas = ", ".join(fill["vas"])
    outcome.tally_labour = outcome.labour
    outcome.tally_spares = outcome.spares
    outcome.tally_vas = outcome.vas
    if fill["total"]:
        outcome.tally_total = outcome.amount
    if outcome.mark != KEEP and _FILL_NOTE not in (outcome.reason or ""):
        outcome.reason = ((outcome.reason or "").rstrip() + " " + _FILL_NOTE).strip()
    return outcome


def _unassigned_service_outcome(bill):
    fill = combine_fill([], [bill])
    outcome = Outcome(
        mark=CHECK,
        reason=(
            f"Service bill {bill.bill or '—'} on {format_date(bill.on)} for "
            f"{bill.vehicle or bill.customer or 'this customer'} could not be joined to one job. "
            "There was no single Hirise bill for this vehicle on that day. "
            "Nothing was written."
        ),
        vehicle=bill.vehicle,
        customer=bill.customer,
        when=format_date(bill.on),
        branch=bill.branch,
        tally_bills=bill.bill,
        service=bill.voucher_type or "SERVICE BILL -GST",
        amount=bill.amount,
    )
    _stamp_tally(outcome, [bill])
    _apply_fill_display(outcome, fill, [], False)
    outcome.mark = CHECK
    outcome.category = ONE_MATCH
    return outcome


def _voucher_rows(tally_records, notes=None):
    notes = notes or {}
    rows = []
    for record in tally_records:
        has_jc = bool(record.job_card)
        note = notes.get(id(record), "")
        if not note and not has_jc:
            note = "No job card on this bill"
        labour = record.labour
        spares = record.spares
        vas = record.vas
        if _has_ledger_lines(record):
            parts = ledger_fill_parts(
                record.ledgers,
                record.ledamts,
                service_bill=is_service_bill(record.voucher_type),
                party_name=record.customer,
            )
            labour = format_money(parts["labour"]) if parts["labour"] else ""
            spares = format_money(parts["spares"]) if parts["spares"] else ""
            vas = ", ".join(parts["vas"])
        rows.append(
            VoucherRow(
                voucher_number=record.bill,
                when=format_date(record.on),
                branch=record.branch,
                registration=record.vehicle,
                job_card=record.job_card,
                labour=labour,
                spares=spares,
                vas=vas,
                items=record.items,
                has_job_card=has_jc,
                note=note,
            )
        )
    return rows


def compare(track_records, tally_records, service_types=None):
    chosen = None
    if service_types is not None:
        chosen = {str(name).strip() for name in service_types if str(name).strip()}

    def _service(record):
        if chosen is None:
            return is_service_bill(record.voucher_type)
        return str(record.voucher_type or "").strip() in chosen

    service_bills = [record for record in tally_records if _service(record)]
    tally_records = [record for record in tally_records if not _service(record)]
    track_groups = defaultdict(list)
    tally_groups = defaultdict(list)
    tally_by_jc = defaultdict(list)
    outcomes = []
    # Keys where Tally had JC but no vehicle; vehicle taken from the only
    # Tracksheet row for that FY + job-card in this compare set.
    inferred_vehicle_keys = set()

    for record in track_records:
        if not record.job_card or not record.vehicle:
            outcome = Outcome(
                mark=CHECK,
                reason=_incomplete_card_reason(record),
                job_card=record.job_card,
                vehicle=record.vehicle,
                customer=record.customer,
                when=format_date(record.on),
                branch=record.branch,
                track_bill=record.bill,
                adviser=record.adviser,
                status=record.status,
                service=record.service,
            )
            _copy_job_fields(outcome, [record])
            _stamp_sheet(outcome, [record])
            outcomes.append(_set_category(outcome, ONE_MATCH))
            continue
        track_groups[_key(record)].append(record)

    vehicles_for_card = defaultdict(set)
    for year, card, vehicle in track_groups:
        vehicles_for_card[(year, card)].add(vehicle)

    for record in tally_records:
        if record.job_card:
            tally_by_jc[record.job_card].append(record)

        if not record.job_card:
            outcome = Outcome(
                mark=CHECK,
                reason="This Tally bill has no job card number or no vehicle number. Nothing was changed.",
                job_card=record.job_card,
                vehicle=record.vehicle,
                customer=record.customer,
                when=format_date(record.on),
                branch=record.branch,
                tally_bills=_bills([record]),
                service=record.voucher_type,
                amount=record.amount,
            )
            _copy_job_fields(outcome, [record])
            _stamp_tally(outcome, [record])
            outcomes.append(_set_category(outcome, ONE_MATCH))
            continue

        if not record.vehicle:
            vehicles = vehicles_for_card.get(
                (record.financial_year, record.job_card), set()
            )
            if len(vehicles) == 1:
                only_vehicle = next(iter(vehicles))
                record = replace(record, vehicle=only_vehicle)
                inferred_vehicle_keys.add(_key(record))
            else:
                if len(vehicles) > 1:
                    reason = (
                        "This Tally bill has a job card but no vehicle number, and that "
                        "job card is on more than one vehicle on the Tracksheet. Please check it."
                    )
                else:
                    reason = (
                        "This Tally bill has a job card but no vehicle number, and that "
                        "job card was not found on the Tracksheet. Nothing was changed."
                    )
                outcome = Outcome(
                    mark=CHECK,
                    reason=reason,
                    job_card=record.job_card,
                    vehicle=record.vehicle,
                    customer=record.customer,
                    when=format_date(record.on),
                    branch=record.branch,
                    tally_bills=_bills([record]),
                    service=record.voucher_type,
                    amount=record.amount,
                )
                _copy_job_fields(outcome, [record])
                _stamp_tally(outcome, [record])
                outcomes.append(_set_category(outcome, ONE_MATCH))
                continue

        tally_groups[_key(record)].append(record)

    attached, ambiguous_keys, unassigned, service_notes = link_service_bills(
        tally_groups, service_bills
    )

    uncovered = 0
    handled = set()

    for (year, card), vehicles in sorted(vehicles_for_card.items()):
        if len(vehicles) < 2:
            continue
        members = _card_rows(track_groups, year, card, vehicles)
        tally_members = _card_rows(tally_groups, year, card, vehicles)
        described = _describe(members + tally_members)
        described.mark = CHECK
        described.reason = (
            "This job card number is used for different vehicles. "
            "They were kept apart. Nothing was changed."
        )
        described.track_bill = _bills(members)
        described.tally_bills = _bills(tally_members)
        _stamp_sheet(described, members)
        _stamp_tally(described, tally_members)
        outcomes.append(_set_category(described, ONE_MATCH))
        for vehicle in vehicles:
            handled.add((year, card, vehicle))

    for key in sorted(set(track_groups) | set(tally_groups)):
        if key in handled:
            continue
        track_rows = track_groups.get(key, [])
        tally_rows = tally_groups.get(key, [])

        if len(track_rows) > 1:
            described = _describe(track_rows)
            described.mark = CHECK
            described.reason = (
                "This job card and vehicle are on the Tracksheet more than once. "
                "Nothing was changed."
            )
            described.track_bill = _bills(track_rows)
            described.tally_bills = _bills(tally_rows)
            _stamp_sheet(described, track_rows)
            _stamp_tally(described, tally_rows)
            outcomes.append(_set_category(described, ONE_MATCH))
            continue

        if track_rows and tally_rows:
            track_bills = _bill_set(track_rows)
            tally_bills = _bill_set(tally_rows)
            described = _describe(track_rows + tally_rows)
            _stamp_sheet(described, track_rows)
            _stamp_tally(described, tally_rows)
            described.track_bill = _bills(track_rows)
            described.tally_bills = _bills(tally_rows)
            # No Bill # on Tracksheet: show Tally last-4 in the list (with Items from Tally).
            if not described.track_bill:
                described.track_bill = _last4_bills(tally_rows)
            tally_labour, tally_spares, _ = _tally_money(tally_rows)
            # VAS from every Tally bill for this JC (incl. other bills / T bills for same JC)
            jc = track_rows[0].job_card
            tally_vas = _vas_from_all_jc_bills(tally_by_jc, jc) or _join(r.vas for r in tally_rows if r.vas)
            described.tally_labour = tally_labour
            described.tally_spares = tally_spares
            described.tally_vas = tally_vas
            described.items = _tally_items(tally_rows)
            date_note = ""
            track_on = track_rows[0].on
            tally_on = next((row.on for row in tally_rows if row.on), None)
            if track_on and tally_on and track_on != tally_on:
                date_note = (
                    f" The job card date {format_date(track_on)} differs from bill date "
                    f"{format_date(tally_on)}."
                )
            if key in inferred_vehicle_keys:
                date_note += (
                    " Tally had no vehicle number, so this was matched to the only "
                    "Tracksheet row for this job card."
                )

            ambiguous = key in ambiguous_keys
            services = [] if ambiguous else attached.get(key, [])
            fill = combine_fill(tally_rows, services)
            # Ledger fill is the with-tax total of Hirise plus the service bill.
            if fill and not ambiguous:
                tally_total = fill["total"]
                fill_labour = format_money(fill["labour"]) if fill["labour"] else ""
                fill_spares = format_money(fill["spares"]) if fill["spares"] else ""
            else:
                tally_total = tally_bill_total(tally_rows)
                fill_labour = tally_labour
                fill_spares = tally_spares

            def _emit(outcome, category):
                _apply_fill_display(outcome, fill if not ambiguous else combine_fill(tally_rows, []), tally_rows, ambiguous)
                if not outcome.category:
                    _set_category(outcome, category)
                outcomes.append(outcome)

            if not tally_bills and track_bills:
                # Provisional — client may change Removed meaning later.
                described.mark = REMOVED
                described.reason = (
                    "Job card and vehicle match, but bill "
                    f"{described.track_bill or '—'} on the Tracksheet was not found in Tally "
                    "for these dates. Nothing was removed."
                    + date_note
                )
                _emit(described, NOT_MATCHING)
            else:
                written_vas = ", ".join(fill["vas"]) if fill and not ambiguous else tally_vas
                sheet = track_rows[0]
                bills_same = track_bills == tally_bills
                labour_same = money_matches(sheet.labour, fill_labour)
                spares_same = money_matches(sheet.spares, fill_spares)
                total_same = money_matches(track_bill_total(sheet), tally_total)
                vas_same = vas_keys(sheet.vas) == vas_keys(written_vas)
                items_same = _item_name_keys(sheet.items) == _item_name_keys(described.items)
                if fill_labour:
                    described.labour = fill_labour
                if fill_spares:
                    described.spares = fill_spares
                if tally_total:
                    described.amount = format_money(tally_total)
                if written_vas:
                    described.vas = written_vas
                if (
                    bills_same
                    and labour_same
                    and spares_same
                    and total_same
                    and vas_same
                    and items_same
                ):
                    described.mark = KEEP
                    described.reason = (
                        "Job card, vehicle, bill number, labour, spares, total, "
                        "VAS, and items match."
                        + date_note
                    )
                    _emit(described, BOTH_MATCH)
                else:
                    described.mark = ADDED
                    if not bills_same:
                        tally_bill = _last4_bills(tally_rows)
                        if tally_bill:
                            described.track_bill = tally_bill
                    differ = []
                    if not bills_same:
                        differ.append("Bill #")
                    if not labour_same:
                        differ.append("Labour")
                    if not spares_same:
                        differ.append("Spares")
                    if not total_same:
                        differ.append("Total")
                    if not vas_same:
                        differ.append("VAS")
                    if not items_same:
                        differ.append("Items")
                    bits = []
                    if described.track_bill:
                        bits.append(f"Bill # {described.track_bill}")
                    if fill_labour:
                        bits.append(f"Labour ₹{fill_labour}")
                    if fill_spares:
                        bits.append(f"Spares ₹{fill_spares}")
                    if tally_total:
                        bits.append(f"Total ₹{format_money(tally_total)}")
                    ready = (" Ready to fill: " + ", ".join(bits) + ".") if bits else ""
                    described.reason = (
                        "Job card and vehicle match. "
                        + ", ".join(differ)
                        + (" differs." if len(differ) == 1 else " differ.")
                        + ready
                        + date_note
                    )
                    _emit(described, NOT_MATCHING)
            continue

        if tally_rows and not track_rows:
            year, card, tally_vehicle = key
            other_vehicles = sorted(
                {
                    vehicle
                    for (group_year, group_card, vehicle) in track_groups
                    if group_year == year and group_card == card and vehicle
                }
            )
            if other_vehicles:
                track_members = []
                for vehicle in other_vehicles:
                    track_members.extend(track_groups[(year, card, vehicle)])
                described = _describe(track_members + tally_rows)
                described.mark = CHECK
                sheet_list = " and ".join(other_vehicles)
                described.reason = (
                    f"Job Card {card} is on the Tracksheet for {sheet_list}. "
                    f"The Tally bill is for {tally_vehicle}. "
                    "The vehicle numbers do not match, so nothing was written. "
                    "Check which number is correct."
                )
                described.customer = track_members[0].customer or described.customer
                described.vehicle = f"{sheet_list} / {tally_vehicle}"
                _stamp_sheet(described, track_members)
                _stamp_tally(described, tally_rows)
                described.track_bill = _bills(track_members)
                described.tally_bills = _bills(tally_rows)
                services = [] if key in ambiguous_keys else attached.get(key, [])
                fill = combine_fill(tally_rows, services)
                _apply_fill_display(
                    described,
                    fill if key not in ambiguous_keys else combine_fill(tally_rows, []),
                    tally_rows,
                    key in ambiguous_keys,
                )
                described.track_bill = _bills(track_members)
                described.mark = CHECK
                if not described.category:
                    _set_category(described, ONE_MATCH)
                outcomes.append(described)
                continue
            described = _describe(tally_rows)
            described.mark = CHECK
            described.reason = (
                "This bill is in Tally, but it is not on the Tracksheet. "
                "Check it before adding a job card."
            )
            _stamp_tally(described, tally_rows)
            described.tally_bills = _bills(tally_rows)
            services = [] if key in ambiguous_keys else attached.get(key, [])
            fill = combine_fill(tally_rows, services)
            _apply_fill_display(
                described,
                fill if key not in ambiguous_keys else combine_fill(tally_rows, []),
                tally_rows,
                key in ambiguous_keys,
            )
            if not described.category:
                _set_category(described, NOT_MATCHING)
            outcomes.append(described)
            continue

        if track_rows and not tally_rows:
            # The job card is in the dates, but no Hirise bill for it was read.
            # The bill may be on a later day, outside this compare. Leave it out.
            # A Tally bill for this job card under another vehicle is already
            # explained on that bill's Check row.
            year, card, _vehicle = key
            explained = any(
                group_year == year and group_card == card
                for (group_year, group_card, _group_vehicle) in tally_groups
            )
            if not explained:
                uncovered += 1

    for bill in unassigned:
        outcomes.append(_unassigned_service_outcome(bill))

    track_from, track_to = _span(track_records)
    tally_from, tally_to = _span(tally_records)
    return CompareResult(
        outcomes=outcomes,
        vouchers=_voucher_rows(list(tally_records) + list(service_bills), service_notes),
        track_rows=len(track_records),
        tally_rows=len(tally_records),
        uncovered_rows=uncovered,
        track_from=track_from,
        track_to=track_to,
        tally_from=tally_from,
        tally_to=tally_to,
    )


def _card_rows(groups, year, card, vehicles):
    rows = []
    for vehicle in sorted(vehicles):
        rows.extend(groups.get((year, card, vehicle), []))
    return rows
