"""Labour / spares totals from Tally ledgers and Tracksheet compare."""

from __future__ import annotations

import re

from compare.normalize import as_text

MONEY_TOLERANCE = 0.0  # exact L/S match (paise); no ₹1 slack
TOTAL_TOLERANCE = 2.0  # bill total may differ by rounding / Adjust A/C

_VAS_NAME_HINTS = (
    "CHAIN LUB",
    "CHAINLUBE",
    "QUICK DC",
    "INJECTOR",
    "AMC",
    "RSA",
    "PAID SERVICE",
    "EXTENDED WARRANTY",
    "EW ",
    " CANVAS",
    "POLISH",
    "COATING",
)

_SKIP_LEDGERS = (
    "SERVICE-GST",
    "SERVICE GST",
    "ADJUST",
    "ROUND",
)


def _amount_text(value) -> str:
    text = as_text(value).replace(",", "").replace(" ", "")
    return text.replace("(-)", "-").replace("(", "-").replace(")", "")


def parse_amount(value) -> float:
    text = _amount_text(value)
    if not text or text == "-":
        return 0.0
    try:
        return abs(float(text))
    except ValueError:
        return 0.0


def signed_amount(value) -> float:
    """Keep a leading minus. Discounts must reduce labour; other totals stay positive via abs."""
    text = _amount_text(value)
    if not text or text == "-":
        return 0.0
    try:
        return float(text)
    except ValueError:
        return 0.0


def format_money(value: float) -> str:
    if abs(value - round(value)) < 0.005:
        return f"{int(round(value)):,}"
    return f"{value:,.2f}"


def money_matches(track_value, tally_value, tolerance=MONEY_TOLERANCE) -> bool:
    left = round(parse_amount(track_value), 2)
    right = round(parse_amount(tally_value), 2)
    if left == 0 and right == 0:
        return True
    return abs(left - right) <= tolerance


def totals_match(track_total, tally_total, tolerance=TOTAL_TOLERANCE) -> bool:
    """True when full bill totals agree (allows small rounding)."""
    left = round(float(track_total), 2)
    right = round(float(tally_total), 2)
    if left == 0 and right == 0:
        return True
    return abs(left - right) <= tolerance


def track_bill_total(record) -> float:
    """Tracksheet total = Labour + Spares when present, else Bill Amount."""
    labour_spares = parse_amount(getattr(record, "labour", "")) + parse_amount(
        getattr(record, "spares", "")
    )
    if labour_spares > 0:
        return round(labour_spares, 2)
    return round(parse_amount(getattr(record, "amount", "")), 2)


def tally_bill_total(rows) -> float:
    """Tally bill total: voucher amount (grand/party) when set, else Labour+Spares."""
    total = 0.0
    for record in rows or []:
        voucher_amount = parse_amount(getattr(record, "amount", ""))
        if voucher_amount > 0:
            total += voucher_amount
            continue
        total += parse_amount(getattr(record, "labour", "")) + parse_amount(
            getattr(record, "spares", "")
        )
    return round(total, 2)


# Appended to each stock name in Tally $$FullList so commas inside names
# (e.g. RUBBER, MOUNT) are not treated as item separators.
ITEM_FULLLIST_MARK = "##AB##"

# Legacy FullList has no tags. Fragments with no digits are almost always an
# unfinished stock name head (RUBBER / BULB / NUT, SPECIAL) — rejoin the next
# comma piece. These rare full names have no digits and must NOT rejoin.
_COMPLETE_NO_DIGIT_ITEMS = frozenset(
    {
        "CHAIN LUBRICATION",
        "CHAIN LUBE",
        "CHAINLUBE",
        "RSA",
        "AMC",
        "PAID SERVICE",
        "QUICK DC",
        "EXTENDED WARRANTY",
        "POLISH",
        "COATING",
        "CANVAS",
        "INJECTOR CLEAN",
        "FORK OIL CHANGE",
        "DECARBONISING",
    }
)


def _needs_comma_rejoin(fragment: str) -> bool:
    folded = " ".join(as_text(fragment).upper().split())
    if not folded:
        return True
    if folded in _COMPLETE_NO_DIGIT_ITEMS:
        return False
    # Honda comma-names put the part number after the comma; a piece with no
    # digit is still the name head (e.g. "RUBBER" before "MOUNT 90543…").
    return re.search(r"\d", folded) is None


def _split_legacy_item_full_list(text: str) -> list:
    """Split untagged Tally FullList on ', ' / ';' without breaking comma names."""
    if ";" in text and "," not in text:
        parts = re.split(r";+", text)
        return [" ".join(part.split()) for part in parts if part.strip()]

    parts = re.split(r",\s+", text)
    if len(parts) <= 1:
        cleaned = " ".join(text.split())
        return [cleaned] if cleaned else []

    out = []
    i = 0
    while i < len(parts):
        cur = parts[i].strip()
        while i + 1 < len(parts) and _needs_comma_rejoin(cur):
            i += 1
            nxt = parts[i].strip()
            cur = f"{cur}, {nxt}" if cur else nxt
        cleaned = " ".join(cur.split())
        if cleaned:
            out.append(cleaned)
        i += 1
    return out


def split_item_list(value) -> list:
    """Split stock item lists into individual names.

    Priority:
    1. Tagged Tally FullList (``name##AB##, name##AB##``) — commas in names safe
    2. Newlines (stored / joined form)
    3. Legacy untagged FullList / older History: ``, `` with comma-name rejoin
    """
    text = as_text(value)
    if not text:
        return []
    if ITEM_FULLLIST_MARK in text:
        parts = []
        for chunk in text.split(ITEM_FULLLIST_MARK):
            cleaned = " ".join(chunk.strip().strip(",").split())
            if cleaned:
                parts.append(cleaned)
        return parts
    if "\n" in text or "\r" in text:
        chunks = re.split(r"[\r\n]+", text)
        return [" ".join(part.split()) for part in chunks if part.strip()]
    return _split_legacy_item_full_list(text)


def split_name_list(value) -> list:
    """Split Tally FullList name lists (ledgers/VAS).

    Prefer newlines. Else ``;`` / ``|``, else comma+space (ledger FullList).
    """
    text = as_text(value)
    if not text:
        return []
    if "\n" in text or "\r" in text:
        chunks = re.split(r"[\r\n]+", text)
    elif ";" in text or "|" in text:
        chunks = re.split(r"[;|]+", text)
    else:
        chunks = re.split(r",\s+", text)
    return [" ".join(part.split()) for part in chunks if part.strip()]


def split_csv_list(value) -> list:
    """Backward-compatible name splitter (ledger-style)."""
    return split_name_list(value)


def join_name_list(names) -> str:
    """Join stock/ledger display names with newlines (safe for commas in names)."""
    parts = []
    seen = set()
    for name in names or []:
        text = " ".join(as_text(name).split())
        if text and text not in seen:
            seen.add(text)
            parts.append(text)
    return "\n".join(parts)


# Tally FullList amounts may use thousand commas ("1,413.48"). Do not split those
# on every comma — that mis-aligns ledger names and invents wrong Labour/Spares.
_AMOUNT_TOKEN = re.compile(
    r"\(\s*-\s*\d+(?:\.\d+)?\s*\)|"
    r"\s*-\d{1,3}(?:,\d{3})+(?:\.\d+)?|"
    r"\s*-\d+(?:\.\d+)?|"
    r"\d{1,3}(?:,\d{3})+(?:\.\d+)?|"
    r"\d+(?:\.\d+)?"
)


def split_amount_list(value) -> list:
    text = as_text(value)
    if not text:
        return []
    return [match.group(0).strip() for match in _AMOUNT_TOKEN.finditer(text)]


def pair_ledgers(names_text, amounts_text) -> list:
    names = split_csv_list(names_text)
    amounts = split_amount_list(amounts_text)
    pairs = []
    for index, name in enumerate(names):
        amount = parse_amount(amounts[index]) if index < len(amounts) else 0.0
        pairs.append((name, amount))
    return pairs


def party_voucher_total(ledgers_text, amounts_text) -> float:
    """Party line with a vehicle token is usually the voucher grand total."""
    for name, amount in pair_ledgers(ledgers_text, amounts_text):
        folded = " ".join(as_text(name).upper().split())
        if re.search(r"\bKL\s?\d", folded) and amount > 0:
            return round(amount, 2)
    return 0.0


def _folded_ledger(name) -> str:
    return " ".join(as_text(name).upper().split())


def _is_gst_line(name) -> bool:
    folded = _folded_ledger(name)
    if "OUTPUT" in folded and ("GST" in folded or "SGST" in folded or "CGST" in folded or "IGST" in folded):
        return True
    if re.search(r"\b(CGST|SGST|IGST)\b", folded):
        return True
    return False


def _is_service_gst_line(name) -> bool:
    folded = _folded_ledger(name)
    return "SERVICE-GST" in folded or "SERVICE GST" in folded


def _is_round_or_adjust(name) -> bool:
    folded = _folded_ledger(name)
    return "ROUND" in folded or "ADJUST" in folded


def _is_discount(name) -> bool:
    return "DISCOUNT" in _folded_ledger(name)


def _is_paid_service(name) -> bool:
    return "PAID SERVICE" in _folded_ledger(name)


def _is_labour_charge(name) -> bool:
    folded = _folded_ledger(name)
    if "GST" in folded or "OUTPUT" in folded or "DISCOUNT" in folded:
        return False
    return "LABOUR" in folded or "LABOR" in folded


def _party_line(name) -> bool:
    return re.search(r"\bKL\s?\d", _folded_ledger(name)) is not None


def _is_named_party(name, party_name) -> bool:
    party = _folded_ledger(party_name)
    if not party:
        return False
    return _folded_ledger(name) == party


def ledger_fill_parts(ledgers_text, ledamts_text, service_bill=False, party_name="") -> dict:
    """Pre-tax labour and spares, with-tax total, and VAS names for one bill.

    Labour excludes GST. A discount reduces labour. A charge that is not parts,
    GST, a discount, or round-off is labour (for example Accidental Repairs).
    Spares are the SERVICE-GST base (parts before tax). Total is the party-line
    amount, tax included, including when the party is an insurer with no vehicle.
    Paid Service is a labour amount; its name is kept only when that amount
    is not zero. Other charge lines on a service bill become VAS names.
    """
    labour = 0.0
    spares = 0.0
    total = 0.0
    vas_names = []
    seen = set()

    def add_vas(name):
        text = " ".join(as_text(name).split())
        key = text.upper()
        if text and key not in seen:
            seen.add(key)
            vas_names.append(text)

    names = split_name_list(ledgers_text)
    amounts = split_amount_list(ledamts_text)
    for index, name in enumerate(names):
        amount = signed_amount(amounts[index]) if index < len(amounts) else 0.0
        if _is_service_gst_line(name):
            if amount:
                spares += abs(amount)
            continue
        if _party_line(name) or _is_named_party(name, party_name):
            if amount:
                total = max(total, abs(amount))
            continue
        if _is_gst_line(name) or _is_round_or_adjust(name):
            continue
        if _is_discount(name):
            labour += amount
            continue
        if _is_paid_service(name):
            labour += amount
            if amount:
                add_vas(name)
            continue
        if _is_labour_charge(name):
            labour += amount
            continue
        if not amount:
            continue
        if service_bill or is_vas_name(name):
            labour += amount
            add_vas(name)
            continue
        labour += amount

    if not total:
        total = party_voucher_total(ledgers_text, ledamts_text)
    return {
        "labour": round(labour, 2),
        "spares": round(spares, 2),
        "total": round(total, 2),
        "vas": vas_names,
    }


def is_vas_name(name: str) -> bool:
    folded = " ".join(as_text(name).upper().split())
    if not folded:
        return False
    return any(hint in folded for hint in _VAS_NAME_HINTS)


def is_labour_ledger(name: str) -> bool:
    folded = " ".join(as_text(name).upper().split())
    if "LABOUR" in folded or "LABOR" in folded:
        return True
    if "OUTPUT-" in folded and "LABOUR" in folded:
        return True
    return False


def is_parts_gst_ledger(name: str) -> bool:
    folded = " ".join(as_text(name).upper().split())
    if "OUTPUT-" not in folded:
        return False
    if "LABOUR" in folded or "LABOR" in folded:
        return False
    return "SGST" in folded or "CGST" in folded or "IGST" in folded


def is_party_or_sales(name: str) -> bool:
    folded = " ".join(as_text(name).upper().split())
    if not folded:
        return True
    if any(skip in folded for skip in _SKIP_LEDGERS):
        return True
    # Party lines usually contain a vehicle token or are the first receivable
    if re.search(r"\bKL\s?\d", folded):
        return True
    return False


def classify_voucher(items_text, ledgers_text, ledamts_text) -> dict:
    """Split one Tally voucher into items, VAS names, labour and spares totals.

    Spares = inventory/service-gst stock total + parts GST ledgers (not x1.18).
    Labour = labour/labor charge ledgers + labour GST ledgers.
    VAS names = only matching **ledger** lines (Paid Service, AMC, …).
    Stock item names stay in ITEMS even if they contain VAS-like words
    (e.g. ``INJECTOR ASSY,FUEL …`` must not become VAS).
    """
    item_names = split_item_list(items_text)
    pairs = pair_ledgers(ledgers_text, ledamts_text)

    labour = 0.0
    spares = 0.0
    stock_total = 0.0
    vas_names = []

    for name, amount in pairs:
        folded = " ".join(name.upper().split())
        if is_labour_ledger(name):
            labour += amount
            continue
        if is_parts_gst_ledger(name):
            spares += amount
            continue
        if folded.startswith("SERVICE-GST") or folded == "SERVICE GST":
            stock_total = max(stock_total, amount)
            continue
        if is_vas_name(name) and not is_party_or_sales(name):
            if name not in vas_names:
                vas_names.append(name)
            # Paid Service etc. often sit with labour/VAS value — add to labour side
            labour += amount
            continue
        # other ledgers ignored for money (party, adjust, sales)

    if stock_total:
        spares += stock_total
    else:
        # fallback: no SERVICE-GST line — cannot reliably sum broken item amounts
        pass

    classified_total = round(labour + spares, 2)
    party_total = party_voucher_total(ledgers_text, ledamts_text)
    # Prefer party total when present (true voucher total); else Labour+Spares.
    grand = party_total if party_total > 0 else classified_total
    return {
        "items": join_name_list(item_names),
        "vas": ", ".join(vas_names),
        "labour": format_money(labour) if labour else "",
        "spares": format_money(spares) if spares else "",
        "labour_value": labour,
        "spares_value": spares,
        "grand_total": format_money(grand) if grand else "",
        "grand_total_value": grand,
    }


def vas_keys(value) -> set:
    keys = set()
    for part in split_csv_list(value):
        folded = " ".join(part.upper().split())
        if not folded:
            continue
        # light normalisation for Chain Lube / CHAIN LUBRICATION
        folded = folded.replace("CHAIN LUBRICATION", "CHAIN LUBE").replace("CHAINLUBE", "CHAIN LUBE")
        keys.add(folded)
    return keys


def vas_missing(track_vas, tally_vas) -> list:
    track = vas_keys(track_vas)
    tally = vas_keys(tally_vas)
    missing = []
    for part in split_csv_list(tally_vas):
        key = " ".join(part.upper().split())
        key = key.replace("CHAIN LUBRICATION", "CHAIN LUBE").replace("CHAINLUBE", "CHAIN LUBE")
        if key and key not in track and part not in missing:
            missing.append(part)
    return missing


def vas_extra(track_vas, tally_vas) -> list:
    track = vas_keys(track_vas)
    tally = vas_keys(tally_vas)
    extras = []
    for part in split_csv_list(track_vas):
        key = " ".join(part.upper().split())
        key = key.replace("CHAIN LUBRICATION", "CHAIN LUBE").replace("CHAINLUBE", "CHAIN LUBE")
        if key and key not in tally and part not in extras:
            extras.append(part)
    return extras
