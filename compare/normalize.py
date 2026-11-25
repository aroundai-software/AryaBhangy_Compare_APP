import re
from datetime import date, datetime

_ORDER_JC = re.compile(r"JC(?:-[A-Z0-9]+)*-(\d{6})\b", re.IGNORECASE)
_LEADING_REFERENCE = re.compile(r"^\s*(\d{1,6})\s*/\s*(\d{2})\b")
# Allow spaces/hyphens inside the letter series (Tally often writes "KA 19 H J 0759").
_VEHICLE = re.compile(
    r"\b([A-Z]{2})\s*-?\s*(\d{1,2})\s*-?\s*([A-Z](?:\s*-?\s*[A-Z]){0,2})\s*-?\s*(\d{1,4})\b",
    re.IGNORECASE,
)
_COMPACT_VEHICLE = re.compile(r"^[A-Z]{2}\d{1,2}[A-Z]{1,3}\d{1,4}$")
_COMPACT_VEHICLE_FIND = re.compile(r"[A-Z]{2}\d{1,2}[A-Z]{1,3}\d{1,4}")
_EMPTY_BILL = {"", "0", "0.0", "00", "000", "-"}
# Only this Tally voucher type is compared. Receipts, journals, AMC, warranty, and spares are left out.
HIRISE_INVOICE_SERVICE = "hirise invoice service"


def as_text(value) -> str:
    if value is None:
        return ""
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    if isinstance(value, int):
        return str(value)
    return str(value).strip()


def as_date(value):
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    text = as_text(value)
    if not text:
        return None
    for fmt in (
        "%Y-%m-%d",
        "%d %b %Y",
        "%d-%b-%Y",
        "%d-%b-%y",
        "%d/%m/%Y",
        "%d-%m-%Y",
        "%d/%m/%y",
        "%d-%m-%y",
    ):
        try:
            return datetime.strptime(text, fmt).date()
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text).date()
    except ValueError:
        return None


def financial_year(value) -> str:
    current = as_date(value)
    if current is None:
        return ""
    start = current.year if current.month >= 4 else current.year - 1
    return f"{start}-{str(start + 1)[-2:]}"


def financial_year_from_reference(value) -> str:
    match = _LEADING_REFERENCE.search(as_text(value))
    if not match:
        return ""
    start = 2000 + int(match.group(2))
    return f"{start}-{str(start + 1)[-2:]}"


def job_card(value) -> str:
    """Job-card number from a tracksheet cell, a Tally reference, or a HiRise order number.

    An invoice number such as HO/SS1690/26-27 is not a job card.
    """
    text = as_text(value)
    if not text:
        return ""
    compact = re.sub(r"\s+", "", text)
    found = _ORDER_JC.search(compact)
    if found:
        return found.group(1)
    match = _LEADING_REFERENCE.search(text)
    if match:
        return match.group(1).zfill(6)
    if re.search(r"[A-Za-z]", text):
        return ""
    if re.fullmatch(r"\d{1,6}", text):
        return text.zfill(6)
    return ""


def vehicle_in_text(value) -> str:
    text = as_text(value).upper()
    if not text:
        return ""
    match = _VEHICLE.search(text)
    if not match:
        return ""
    state, district, letters, serial = match.groups()
    letters = re.sub(r"[^A-Z]", "", letters.upper())
    return f"{state.upper()}{district.zfill(2)}{letters}{serial}"


def vehicle_cell(value) -> str:
    parsed = vehicle_in_text(value)
    if parsed:
        return parsed
    compact = re.sub(r"[^A-Z0-9]", "", as_text(value).upper())
    if not compact:
        return ""
    if _COMPACT_VEHICLE.fullmatch(compact):
        return compact
    # Party name often prefixes the reg when separators are stripped
    # (e.g. RAINAKA19HJ0759). Prefer the last plate-shaped match.
    matches = list(_COMPACT_VEHICLE_FIND.finditer(compact))
    if matches:
        return matches[-1].group(0)
    return ""


def is_hirise_invoice_service(value) -> bool:
    return " ".join(as_text(value).lower().split()) == HIRISE_INVOICE_SERVICE


def is_service_bill(value) -> bool:
    """Aluva service bill (AMC, anti-rust, and similar). Not a receipt or journal.

    Tally's voucher type is "SERVICE BILL -GST". Older notes used "SERVICE BILL_GST".
    Branch types such as "SERVICE BILL - GST MARAMPILLY" are left out.
    """
    folded = as_text(value).upper().replace("_", " ").replace("-", " ")
    folded = " ".join(folded.split())
    return folded == "SERVICE BILL GST"


def bill_number(value) -> str:
    text = as_text(value).upper().replace(" ", "")
    if text in _EMPTY_BILL:
        return ""
    return text


def bill_compare_key(value) -> str:
    """Key used to decide whether Tally and tracksheet bills are the same.

    Hirise voucher numbers are long (e.g. KL10000126006515). The tracksheet
    Bill Number is the last four digits of that voucher (6515).
    """
    text = bill_number(value)
    if not text:
        return ""
    digits = re.sub(r"\D", "", text)
    if digits and (re.search(r"[A-Z]", text) or len(digits) > 4):
        return digits[-4:]
    return text


def item_keys(value) -> set:
    """Normalised item names for comparing Tracksheet Items vs Tally stock lines."""
    text = as_text(value)
    if not text:
        return set()
    keys = set()
    for chunk in text.replace(";", ",").replace("\n", ",").split(","):
        name = " ".join(chunk.upper().split())
        if name:
            keys.add(name)
    return keys


def items_missing(track_items, tally_items) -> list:
    """Tally item names that are not already on the tracksheet Items field."""
    track = item_keys(track_items)
    tally = item_keys(tally_items)
    missing = sorted(tally - track)
    return missing


def format_date(value) -> str:
    current = as_date(value)
    if current is None:
        return ""
    return current.strftime("%d %b %Y")


def format_amount(value) -> str:
    text = as_text(value).replace(",", "")
    if not text:
        return ""
    try:
        number = float(text)
    except ValueError:
        return as_text(value)
    if number.is_integer():
        return f"{int(number):,}"
    return f"{number:,.2f}"
