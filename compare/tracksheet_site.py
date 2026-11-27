"""Read and update job cards on the Aryabhangy tracksheet site.

The website address chooses the site. The hosted demo uses its own save.
The original Tracksheet updates table 561 when LIVE_WRITE_TOKEN is set.
That token stays empty until it is placed here. Do not commit a real token.
"""

import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import timedelta

from compare.normalize import as_date, as_text, bill_number, financial_year, format_amount, job_card, vehicle_cell
from compare.records import Record

LIVE_SITE = "https://track.aryabhangymotors.com"
LIVE_DATABASE = "https://tracksheet.aryabhangymotors.com"
DEMO_TOKEN = "local-trackdemo-token"
# Paste the original Tracksheet update token here when it is available.
LIVE_WRITE_TOKEN = ""
LIVE_HOSTS = frozenset({"track.aryabhangymotors.com", "tracksheet.aryabhangymotors.com"})
LOCAL_HOSTS = frozenset({"127.0.0.1", "localhost"})
SITE = LIVE_SITE
DATABASE = LIVE_DATABASE
_demo_confirmed = False
TABLE_ID = 561
DATE_FIELD = 5256
JC_FIELD = 5253
MAX_DAYS = 31
MAX_PAGES = 20
# Parallel HTTP reads — most compare time is waiting on the site.
_DAY_WORKERS = 8
_JC_WORKERS = 10


class SiteError(RuntimeError):
    pass


def apply_website(website):
    """Point later Tracksheet reads at this address.

    The hosted demo serves its own job cards. The original Tracksheet keeps
    its database address. An address on this computer is not a Tracksheet.
    """
    global SITE, DATABASE, _demo_confirmed
    origin = _origin(website)
    SITE = origin
    _demo_confirmed = False
    if _is_live_host(origin):
        SITE = LIVE_SITE
        DATABASE = LIVE_DATABASE
    elif _is_local_host(origin):
        DATABASE = origin
    else:
        DATABASE = LIVE_DATABASE
    return origin


def confirm_site(timeout=8):
    """True when Write may save on the website that is selected."""
    global DATABASE, _demo_confirmed
    _demo_confirmed = False
    if _is_local_host(SITE):
        return False
    if _is_live_host(SITE):
        DATABASE = LIVE_DATABASE
        return _original_write_ready()
    try:
        token = _token(timeout, attempts=1)
    except SiteError:
        DATABASE = SITE
        return False
    if token == DEMO_TOKEN and not _is_live_host(SITE):
        DATABASE = SITE
        _demo_confirmed = True
        return True
    DATABASE = LIVE_DATABASE
    return False


def can_save_site():
    """True for the hosted demo, or the original site when its token is set."""
    if _is_local_host(SITE):
        return False
    if _is_live_host(SITE):
        return _original_write_ready()
    return _demo_confirmed


def save_blocked_reason():
    if _is_local_host(SITE):
        return "Use the demo Tracksheet or the original Tracksheet address."
    if _is_live_host(SITE):
        return "Write stays off for the original Tracksheet until the update token is in the app."
    return "Saving is only allowed on the hosted demo or the original Tracksheet."


def is_practice_site(website=None):
    origin = _origin(website) if website else SITE
    return _is_local_host(origin)


def _original_write_ready():
    return bool(str(LIVE_WRITE_TOKEN).strip())


def _is_live_host(website):
    return _host(website) in LIVE_HOSTS


def _is_local_host(website):
    return _host(website) in LOCAL_HOSTS


def _refuse_local():
    if _is_local_host(SITE):
        raise SiteError(save_blocked_reason())


def _host(website):
    return (urllib.parse.urlparse(website).hostname or "").lower()


def write_practice_cards(cards, timeout=60):
    """Save Bill #, Labour, Spares, Total, VAS, and Items on the selected site."""
    if _is_local_host(SITE):
        raise SiteError(save_blocked_reason())
    if _is_live_host(SITE):
        return _write_original_cards(cards, timeout)
    if not can_save_site() or _is_live_host(DATABASE):
        raise SiteError(save_blocked_reason())
    target = SITE.rstrip("/")
    payload = json.dumps({"cards": cards}, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        target + "/api/local/fill",
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "AryabhangyCompare",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        message = "The practice copy refused the update."
        try:
            parsed = json.loads(detail)
            if isinstance(parsed, dict) and parsed.get("error"):
                message = str(parsed["error"])
        except json.JSONDecodeError:
            if detail.strip():
                message = detail.strip()
        raise SiteError(message) from error
    except SiteError:
        raise
    except Exception as error:
        raise SiteError(
            "The Tracksheet did not answer. Start it, then try again."
        ) from error
    if not isinstance(body, dict):
        raise SiteError("The Tracksheet returned an unexpected reply.")
    return body


def _write_original_cards(cards, timeout):
    """Update the read row on the original Tracksheet table."""
    if not _original_write_ready():
        raise SiteError(save_blocked_reason())
    results = []
    updated = 0
    for card in cards or []:
        job = str(card.get("job_card") or "")
        key = str(card.get("key") or job)
        try:
            row_id = int(card.get("sheet_row_id") or 0)
        except (TypeError, ValueError):
            row_id = 0
        if row_id <= 0:
            results.append(
                {
                    "ok": False,
                    "key": key,
                    "job_card": job,
                    "error": "This job card has no row to update.",
                }
            )
            continue
        payload = json.dumps(
            {
                "Bill Number": card.get("bill") or "",
                "Labour": card.get("labour") or "",
                "Spares": card.get("spares") or "",
                "Bill Amount": card.get("total") or "",
                "VAS Canvassed": card.get("vas") or "",
                "Items": card.get("items") or "",
            },
            ensure_ascii=False,
        ).encode("utf-8")
        request = urllib.request.Request(
            f"{DATABASE.rstrip('/')}/api/database/rows/table/{TABLE_ID}/{row_id}/?user_field_names=true",
            data=payload,
            headers={
                "Authorization": "Token " + str(LIVE_WRITE_TOKEN).strip(),
                "Content-Type": "application/json",
                "User-Agent": "AryabhangyCompare",
            },
            method="PATCH",
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                response.read()
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace").strip()
            results.append(
                {
                    "ok": False,
                    "key": key,
                    "job_card": job,
                    "error": detail or "The original Tracksheet refused the update.",
                }
            )
            continue
        except Exception:
            results.append(
                {
                    "ok": False,
                    "key": key,
                    "job_card": job,
                    "error": "The original Tracksheet did not answer.",
                }
            )
            continue
        updated += 1
        results.append({"ok": True, "key": key, "job_card": job})
    return {"updated": updated, "results": results}


def probe_website(timeout=8):
    """True when the chosen website returns its Tracksheet config. Read-only."""
    if _is_local_host(SITE):
        return False, save_blocked_reason()
    request = urllib.request.Request(
        SITE + "/config.js",
        headers={"User-Agent": "AryabhangyCompare"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            text = response.read().decode("utf-8", "replace")
    except Exception:
        return False, "Unable to reach the Tracksheet website."
    if "TRACKSHEET_TOKEN" not in text:
        return False, "The website is reachable, but it is not a Tracksheet."
    return True, "Tracksheet website is reachable."


def _origin(website):
    text = as_text(website).rstrip("/")
    parsed = urllib.parse.urlparse(text)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Enter a website address starting with http:// or https://.")
    return f"{parsed.scheme}://{parsed.netloc}"


def branch_names(timeout=30):
    """Branch names from the tracksheet Branch field. Read-only."""
    _refuse_local()
    token = _token(timeout)
    data = _get(f"/api/database/fields/table/{TABLE_ID}/", token, timeout)
    if not isinstance(data, list):
        raise SiteError("The tracksheet site did not return the branch list.")
    for field in data:
        if as_text(field.get("name")) != "Branch":
            continue
        names = []
        for option in field.get("select_options") or []:
            value = as_text(option.get("value"))
            if value and value not in names:
                names.append(value)
        if not names:
            raise SiteError("The tracksheet site has no branches.")
        return names
    raise SiteError("The tracksheet site has no Branch field.")


def job_cards(start, end, timeout=30, progress=None):
    _refuse_local()
    if start is None or end is None:
        raise SiteError("Choose a From date and a To date.")
    if end < start:
        raise SiteError("From date is after To date.")
    if (end - start).days > MAX_DAYS:
        raise SiteError("Choose 31 days or fewer.")
    token = _token(timeout)
    days = []
    day = start
    while day <= end:
        days.append(day)
        day += timedelta(days=1)

    def fetch_day(on):
        return on, _rows_on(on, token, timeout)

    by_day = {}
    workers = max(1, min(_DAY_WORKERS, len(days)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(fetch_day, on) for on in days]
        for future in as_completed(futures):
            on, rows = future.result()
            by_day[on] = rows
            if progress is not None:
                progress(on, sum(len(by_day[d]) for d in by_day))

    records = []
    number = 1
    for on in days:
        for row in by_day.get(on, []):
            records.append(_record(row, number))
            number += 1
    return records


def job_cards_by_numbers(numbers, timeout=30, progress=None):
    """Fetch Tracksheet rows for these JC numbers on any date. Read-only.

    Used when a Hirise bill falls in From–To but the Job Card Date is outside
    that window (open-date vs bill-date).
    """
    _refuse_local()
    wanted = []
    seen = set()
    for value in numbers or []:
        card = job_card(value)
        if card and card not in seen:
            seen.add(card)
            wanted.append(card)
    if not wanted:
        return []
    token = _token(timeout)

    def fetch_card(card):
        return card, _rows_for_jc(card, token, timeout)

    by_card = {}
    workers = max(1, min(_JC_WORKERS, len(wanted)))
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(fetch_card, card) for card in wanted]
        for future in as_completed(futures):
            card, rows = future.result()
            by_card[card] = rows
            if progress is not None:
                progress(card, sum(len(by_card[c]) for c in by_card))

    records = []
    number = 1
    for card in wanted:
        for row in by_card.get(card, []):
            records.append(_record(row, number))
            number += 1
    return records


def _token(timeout, attempts=3):
    request = urllib.request.Request(
        SITE + "/config.js", headers={"User-Agent": "AryabhangyCompare"}
    )
    last_error = None
    text = ""
    for attempt in range(attempts):
        try:
            text = urllib.request.urlopen(request, timeout=timeout).read().decode(
                "utf-8", "replace"
            )
            break
        except (TimeoutError, urllib.error.URLError, OSError) as error:
            last_error = error
            if attempt + 1 >= attempts:
                raise SiteError("The tracksheet site could not be reached.") from error
            time.sleep(0.6 * (attempt + 1))
        except Exception as error:
            raise SiteError("The tracksheet site could not be reached.") from error
    else:
        raise SiteError("The tracksheet site could not be reached.") from last_error
    match = re.search(r'TRACKSHEET_TOKEN\s*=\s*"([^"]+)"', text)
    if not match or match.group(1) in {"", "PASTE_DB_TOKEN_HERE", "MISSING_CONFIG_JS"}:
        raise SiteError("The tracksheet site did not allow this read.")
    return match.group(1)


def _rows_on(day, token, timeout):
    query = (
        f"/api/database/rows/table/{TABLE_ID}/"
        f"?user_field_names=true&size=200&page=1"
        f"&filter__field_{DATE_FIELD}__date_equal={day.isoformat()}"
    )
    return _paged_rows(query, token, timeout)


def _rows_for_jc(card, token, timeout):
    query = (
        f"/api/database/rows/table/{TABLE_ID}/"
        f"?user_field_names=true&size=200&page=1"
        f"&filter__field_{JC_FIELD}__equal={card}"
    )
    return _paged_rows(query, token, timeout)


def _paged_rows(query, token, timeout):
    rows = []
    for _page in range(MAX_PAGES):
        data = _get(query, token, timeout)
        rows.extend(data.get("results") or [])
        nxt = data.get("next") or ""
        if not nxt:
            return rows
        if not nxt.startswith(DATABASE):
            raise SiteError("The tracksheet site returned an unexpected next page.")
        query = nxt[len(DATABASE) :]
    raise SiteError("The tracksheet site returned more pages than this read allows.")


def _get(path, token, timeout, attempts=3):
    request = urllib.request.Request(
        DATABASE + path,
        headers={"Authorization": "Token " + token, "User-Agent": "AryabhangyCompare"},
    )
    last_error = None
    for attempt in range(attempts):
        try:
            raw = urllib.request.urlopen(request, timeout=timeout).read().decode(
                "utf-8", "replace"
            )
            break
        except (TimeoutError, urllib.error.URLError, OSError) as error:
            last_error = error
            if attempt + 1 >= attempts:
                raise SiteError(
                    "The tracksheet site did not return the job cards."
                ) from error
            time.sleep(0.6 * (attempt + 1))
        except Exception as error:
            raise SiteError(
                "The tracksheet site did not return the job cards."
            ) from error
    else:
        raise SiteError(
            "The tracksheet site did not return the job cards."
        ) from last_error
    try:
        return json.loads(raw)
    except json.JSONDecodeError as error:
        raise SiteError(
            "The tracksheet site returned a reply that could not be read."
        ) from error


def _record(row, number):
    on = as_date(row.get("Date"))
    return Record(
        source="tracksheet",
        branch=_choice(row.get("Branch")),
        on=on,
        financial_year=financial_year(on),
        job_card=job_card(row.get("JC Number")),
        vehicle=vehicle_cell(row.get("Registration")),
        customer=as_text(row.get("Customer Name")),
        bill=bill_number(row.get("Bill Number")),
        amount=format_amount(row.get("Bill Amount")),
        voucher_type="",
        status=_choice(row.get("Status")),
        service=_choice(row.get("Service Type")),
        adviser=as_text(row.get("Adviser")),
        row_number=number,
        phone=as_text(row.get("Customer Phone")),
        model=as_text(row.get("Model")),
        booking=_choice(row.get("Booking Source")),
        technician=as_text(row.get("Technician")),
        labour=format_amount(row.get("Labour")),
        spares=format_amount(row.get("Spares")),
        vas=_multi(row.get("VAS Canvassed")),
        payment=_choice(row.get("Payment Mode")),
        items=_items(row.get("Items")),
        sheet_row_id=_row_id(row),
    )


def _row_id(row):
    try:
        return int(row.get("id") or 0)
    except (TypeError, ValueError):
        return 0


def _choice(value):
    if isinstance(value, dict):
        return as_text(value.get("value"))
    return as_text(value)


def _items(value):
    """Item names as stored. Newlines stay so a comma inside a name is one item."""
    if isinstance(value, list):
        lines = []
        for item in value:
            if isinstance(item, dict):
                text = as_text(item.get("value"))
            else:
                text = as_text(item)
            if text and text not in lines:
                lines.append(text)
        return "\n".join(lines)
    return as_text(value)


def _multi(value):
    if isinstance(value, list):
        names = []
        for item in value:
            if isinstance(item, dict):
                text = as_text(item.get("value"))
            else:
                text = as_text(item)
            if text and text not in names:
                names.append(text)
        return ", ".join(names)
    return as_text(value)
