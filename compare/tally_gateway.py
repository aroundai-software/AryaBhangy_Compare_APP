"""Read-only requests to a Tally company that is already open.

These requests export data. They do not import, alter, or close the company.
"""

import urllib.request
import xml.etree.ElementTree as ET
from datetime import date, timedelta

from compare.money import classify_voucher
from compare.normalize import (
    as_date,
    as_text,
    bill_number,
    financial_year,
    is_hirise_invoice_service,
    is_service_bill,
    job_card,
    vehicle_cell,
    vehicle_in_text,
)
from compare.records import Record

GATEWAY = "http://127.0.0.1:9000"


def apply_tally_port(port):
    """Point later Tally reads at this port on this computer."""
    global GATEWAY
    try:
        number = int(str(port).strip())
    except (TypeError, ValueError) as error:
        raise ValueError("Tally port must be a number.") from error
    if number < 1 or number > 65535:
        raise ValueError("Tally port must be from 1 to 65535.")
    GATEWAY = f"http://127.0.0.1:{number}"
    return number
HIRISE = "Hirise Invoice Service"
# The open company uses the hyphenated name. The underscore spelling is kept
# so an export that still carries it is not dropped.
SERVICE_BILL_NAMES = ("SERVICE BILL -GST", "SERVICE BILL_GST")


def _post(xml, timeout=12):
    request = urllib.request.Request(
        GATEWAY,
        data=xml.encode("utf-8"),
        headers={"Content-Type": "text/xml"},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def _function_xml(name):
    return f"""<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export</TALLYREQUEST>
  <TYPE>Function</TYPE>
  <ID>{name}</ID>
 </HEADER>
 <BODY><DESC><FUNCPARAMLIST></FUNCPARAMLIST></DESC></BODY>
</ENVELOPE>"""


def _result_text(text):
    """Value of RESULT, or empty when Tally answered without one."""
    if "<ERRORMSG>" in text:
        return ""
    root = ET.fromstring(text)
    result = root.find(".//RESULT")
    if result is None or not (result.text or "").strip():
        return ""
    return result.text.strip()


def _function(name, timeout=8):
    text = _post(_function_xml(name), timeout=timeout)
    value = _result_text(text)
    if not value:
        if "<ERRORMSG>" in text:
            raise RuntimeError(_error_text(text))
        raise RuntimeError("Tally did not return " + name)
    return value


def current_company(timeout=8):
    """Open company name. Empty string when Tally answers but no company is loaded."""
    status = tally_status(timeout=timeout)
    if not status["online"]:
        raise RuntimeError("Tally is offline.")
    return status["name"]


def active_company(timeout=3):
    """The company Tally is using now. Empty when offline or no company is loaded."""
    status = tally_status(timeout=timeout)
    return status["name"] if status["online"] else ""


def tally_status(timeout=3):
    """Online when the gateway answers; company name when one is loaded.

    Offline only when Tally does not answer (closed, wrong port, timeout).
    Online with an empty name means Tally is up but no company is selected.
    """
    try:
        text = _post(_function_xml("$$CurrentCompany"), timeout=timeout)
    except Exception:
        return {"online": False, "name": "", "period": None}
    try:
        name = _result_text(text)
    except ET.ParseError:
        name = ""
    period = None
    try:
        period = current_period(timeout=timeout)
    except Exception:
        period = None
    return {"online": True, "name": name or "", "period": period}


def current_period(timeout=8):
    """The period Tally is showing on the gateway. This is not the year in the company name."""
    xml = """<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export</TALLYREQUEST>
  <TYPE>Data</TYPE>
  <ID>Open Period</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <REPORT NAME="Open Period">
      <FORMS>Open Period</FORMS>
     </REPORT>
     <FORM NAME="Open Period">
      <TOPPARTS>Open Period</TOPPARTS>
      <XMLTAG>PERIOD</XMLTAG>
     </FORM>
     <PART NAME="Open Period">
      <TOPLINES>Open Period</TOPLINES>
      <SCROLLED>Vertical</SCROLLED>
     </PART>
     <LINE NAME="Open Period">
      <FIELDS>Period From, Period To</FIELDS>
     </LINE>
     <FIELD NAME="Period From">
      <SET>$$String:##SVFromDate</SET>
      <XMLTAG>FROM</XMLTAG>
     </FIELD>
     <FIELD NAME="Period To">
      <SET>$$String:##SVToDate</SET>
      <XMLTAG>TO</XMLTAG>
     </FIELD>
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>"""
    return period_from_xml(_post(xml, timeout=timeout))


def period_from_xml(text):
    root = ET.fromstring(text)
    start = as_date(_tag_text(root, "FROM"))
    end = as_date(_tag_text(root, "TO"))
    if start is None or end is None:
        raise RuntimeError("Tally did not return the current period.")
    return start, end


def period_covers(period_start, period_end, start, end):
    values = (period_start, period_end, start, end)
    if not all(isinstance(value, date) for value in values):
        return False
    return period_start <= start <= end <= period_end


def _tag_text(root, tag):
    for node in root.iter(tag):
        if node.text and node.text.strip():
            return node.text.strip()
    return ""


def current_date(timeout=8):
    from compare.normalize import as_date as parse_date

    return parse_date(_function("$$SystemDate", timeout=timeout)) or parse_date(_function("$$MachineDate", timeout=timeout))


def _error_text(text):
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        return "Tally could not answer. Leave the company open and try again."
    messages = [node.text.strip() for node in root.iter("ERRORMSG") if node.text]
    return " ".join(messages) or "Tally could not answer. Leave the company open and try again."


def voucher_type_names(timeout=12):
    xml = """<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export</TALLYREQUEST>
  <TYPE>Collection</TYPE>
  <ID>Voucher Types</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <COLLECTION NAME="Voucher Types" ISMODIFY="No">
      <TYPE>VoucherType</TYPE>
      <FETCH>Name</FETCH>
     </COLLECTION>
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>"""
    text = _post(xml, timeout=timeout)
    if "<ERRORMSG>" in text and "<VOUCHERTYPE" not in text.upper():
        raise RuntimeError(_error_text(text))
    root = ET.fromstring(text)
    names = []
    for node in root.iter():
        if node.tag.upper() in {"VOUCHERTYPE", "NAME"} and node.text and node.text.strip():
            value = node.text.strip()
            if value not in names and node.tag.upper() == "NAME":
                names.append(value)
    if not names:
        for node in root.iter("VOUCHERTYPE"):
            name = node.get("NAME") or _child(node, "NAME")
            if name and name not in names:
                names.append(name)
    return names


def hirise_on_day(day, timeout=8, voucher_types=None):
    """Read one day of the chosen voucher types."""
    return hirise_between(day, day, timeout=timeout, voucher_types=voucher_types)


def _voucher_type_formula(name):
    safe = as_text(name).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    safe = safe.replace('"', "")
    return f'$$IsEqual:$VoucherTypeName:"{safe}"'


def hirise_between(start, end, timeout=45, voucher_types=None):
    """Read the chosen voucher types for a date range in one Tally export.

    Belongsto keeps the walk inside SVFromDate–SVToDate, instead of every
    voucher of this type in the company. With no list, Hirise Invoice Service
    and SERVICE BILL -GST are read.
    """
    names = [as_text(name) for name in (voucher_types or (HIRISE, *SERVICE_BILL_NAMES)) if as_text(name)]
    if not names:
        names = [HIRISE, *SERVICE_BILL_NAMES]
    stamp_from = start.strftime("%Y%m%d")
    stamp_to = end.strftime("%Y%m%d")
    shown_from = start.strftime("%d-%b-%Y")
    shown_to = end.strftime("%d-%b-%Y")
    keep_type = " OR ".join(_voucher_type_formula(name) for name in names)
    # A cancelled bill stays in Tally after a new one is created. Leave it out.
    keep = f"({keep_type}) AND NOT $IsCancelled"
    xml = f"""<ENVELOPE>
 <HEADER>
  <VERSION>1</VERSION>
  <TALLYREQUEST>Export</TALLYREQUEST>
  <TYPE>Data</TYPE>
  <ID>Hirise Lines</ID>
 </HEADER>
 <BODY>
  <DESC>
   <STATICVARIABLES>
    <SVEXPORTFORMAT>$$SysName:XML</SVEXPORTFORMAT>
    <SVFROMDATE>{stamp_from}</SVFROMDATE>
    <SVTODATE>{stamp_to}</SVTODATE>
   </STATICVARIABLES>
   <TDL>
    <TDLMESSAGE>
     <REPORT NAME="Hirise Lines">
      <FORMS>Hirise Lines</FORMS>
      <SET>SVFromDate : $$Date:"{shown_from}"</SET>
      <SET>SVToDate : $$Date:"{shown_to}"</SET>
     </REPORT>
     <FORM NAME="Hirise Lines">
      <TOPPARTS>Hirise Lines</TOPPARTS>
      <XMLTAG>BILLS</XMLTAG>
     </FORM>
     <PART NAME="Hirise Lines">
      <TOPLINES>Hirise Lines</TOPLINES>
      <REPEAT>Hirise Lines : Hirise Lines Coll</REPEAT>
      <SCROLLED>Vertical</SCROLLED>
     </PART>
     <LINE NAME="Hirise Lines">
      <FIELDS>HLDate, HLNo, HLParty, HLNarr, HLItems, HLLedges, HLLedAmts, HLType, HLCancelled</FIELDS>
      <XMLTAG>BILL</XMLTAG>
     </LINE>
     <FIELD NAME="HLDate"><SET>$Date</SET><XMLTAG>DATE</XMLTAG></FIELD>
     <FIELD NAME="HLNo"><SET>$VoucherNumber</SET><XMLTAG>VCHNO</XMLTAG></FIELD>
     <FIELD NAME="HLParty"><SET>$PartyLedgerName</SET><XMLTAG>PARTY</XMLTAG></FIELD>
     <FIELD NAME="HLNarr"><SET>$Narration</SET><XMLTAG>NARR</XMLTAG></FIELD>
     <!-- FullList (not EXPLODE — EXPLODE crashed Tally TDL). Plain $StockItemName:
          custom #formula inside FullList returned blank ITEMS. Comma-in-name
          stock (RUBBER, MOUNT) is repaired in split_item_list rejoin logic. -->
     <FIELD NAME="HLItems"><SET>$$FullList:AllInventoryEntries:$StockItemName</SET><XMLTAG>ITEMS</XMLTAG></FIELD>
     <FIELD NAME="HLLedges"><SET>$$FullList:AllLedgerEntries:$LedgerName</SET><XMLTAG>LEDGERS</XMLTAG></FIELD>
     <FIELD NAME="HLLedAmts"><SET>$$FullList:AllLedgerEntries:$Amount</SET><XMLTAG>LEDAMTS</XMLTAG></FIELD>
     <FIELD NAME="HLType"><SET>$VoucherTypeName</SET><XMLTAG>VCHTYPE</XMLTAG></FIELD>
     <FIELD NAME="HLCancelled"><SET>$IsCancelled</SET><XMLTAG>CANCELLED</XMLTAG></FIELD>
     <COLLECTION NAME="Hirise Lines Coll" ISMODIFY="No">
      <TYPE>Voucher</TYPE>
      <BELONGSTO>Yes</BELONGSTO>
      <FILTER>HLKeep</FILTER>
      <FETCH>PartyLedgerName, Narration, VoucherTypeName, IsCancelled, AllInventoryEntries, AllInventoryEntries.StockItemName, AllLedgerEntries, AllLedgerEntries.LedgerName, AllLedgerEntries.Amount</FETCH>
     </COLLECTION>
     <SYSTEM TYPE="Formulae" NAME="HLKeep">{keep}</SYSTEM>
    </TDLMESSAGE>
   </TDL>
  </DESC>
 </BODY>
</ENVELOPE>"""
    text = _post(xml, timeout=timeout)
    if "ERRORMSG" in text and "<BILL" not in text.upper() and "<VOUCHER" not in text.upper():
        raise RuntimeError(_error_text(text))
    return _vouchers_from_xml(text, names)


_STILL_READING = (
    "Tally is still reading the bills. Wait until Tally responds, "
    "then run Compare again."
)


def _tally_still_reading(error):
    """True when the app stopped waiting but Tally may still be building the list."""
    if isinstance(error, OSError):
        return True
    return isinstance(getattr(error, "reason", None), OSError)


def hirise_vouchers(start, end, timeout=8, progress=None, voucher_types=None):
    """Read Hirise Invoice Service one day at a time.

    A whole-range export keeps Tally's screen busy until every bill in the
    dates is built. One day answers quickly, and the next day is not sent
    until this day has answered. If a day does not answer, stop.
    """
    if not isinstance(start, date) or not isinstance(end, date) or end < start:
        raise RuntimeError("Choose a From date and a To date.")
    if (end - start).days > 31:
        raise RuntimeError("Choose 31 days or fewer.")

    if progress is not None:
        progress(start, 0)
    day_timeout = max(int(timeout or 8), 30)
    return _hirise_by_day(
        start, end, timeout=day_timeout, progress=progress, voucher_types=voucher_types
    )


def _hirise_by_day(start, end, timeout, progress=None, voucher_types=None):
    """Read each day only after Tally has answered for that day."""
    records = []
    day = start
    number = 1
    while day <= end:
        if progress is not None:
            progress(day, len(records))
        try:
            found = hirise_on_day(day, timeout=timeout, voucher_types=voucher_types)
        except Exception as error:
            if _tally_still_reading(error):
                raise RuntimeError(_STILL_READING) from error
            raise
        for record in found:
            record.row_number = number
            records.append(record)
            number += 1
        day += timedelta(days=1)
    if progress is not None:
        progress(end, len(records))
    return records


def _vouchers_from_xml(text, allowed=None):
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        raise RuntimeError("Tally sent a reply that could not be read.") from error
    bills = [node for node in root.iter("BILL") if _child(node, "PARTY") or _child(node, "NARR") or _child(node, "VCHNO")]
    bills = [
        node
        for node in bills
        if _keep_voucher_type(_child(node, "VCHTYPE"), allowed) and not _is_cancelled(_child(node, "CANCELLED"))
    ]
    if bills:
        return [_record_from_bill(node, index) for index, node in enumerate(bills, start=1)]
    records = []
    for index, node in enumerate(root.iter("VOUCHER"), start=1):
        voucher_type = _child(node, "VOUCHERTYPENAME")
        if voucher_type and not _keep_voucher_type(voucher_type, allowed):
            continue
        if _is_cancelled(_child(node, "ISCANCELLED")):
            continue
        on = as_date(_child(node, "DATE"))
        reference = _child(node, "REFERENCE")
        party = _child(node, "PARTYLEDGERNAME")
        narration = _child(node, "NARRATION")
        vehicle = vehicle_in_text(party) or vehicle_in_text(narration) or vehicle_in_text(reference)
        if not vehicle:
            vehicle = vehicle_cell(party)
        records.append(
            Record(
                source="tally",
                branch="",
                on=on,
                financial_year=financial_year(on),
                job_card=job_card(narration) or job_card(reference),
                vehicle=vehicle,
                customer=as_text(party).split("-")[0].strip(),
                bill=bill_number(_child(node, "VOUCHERNUMBER")),
                amount=_amount(_child(node, "AMOUNT")),
                voucher_type=voucher_type or HIRISE,
                status="",
                service=voucher_type or HIRISE,
                adviser="",
                row_number=index,
            )
        )
    return records


def _record_from_bill(node, index):
    party = _child(node, "PARTY")
    narration = _child(node, "NARR")
    on = as_date(_child(node, "DATE"))
    vehicle = vehicle_in_text(party) or vehicle_in_text(narration)
    if not vehicle:
        vehicle = vehicle_cell(party)
    items = _items_from_bill(node)
    ledgers = _list_text(_child(node, "LEDGERS"))
    # Do NOT run _list_text on LEDAMTS — it splits "1,413.48" into "1" and "413.48".
    ledamts = _amount_list_text(_child(node, "LEDAMTS"))
    classified = classify_voucher(items, ledgers, ledamts)
    voucher_type = _child(node, "VCHTYPE") or HIRISE
    return Record(
        source="tally",
        branch="",
        on=on,
        financial_year=financial_year(on),
        job_card=job_card(narration),
        vehicle=vehicle,
        customer=as_text(party).split("-")[0].strip(),
        bill=bill_number(_child(node, "VCHNO")),
        amount=classified.get("grand_total")
        or classified["labour"]
        or classified["spares"],
        voucher_type=voucher_type,
        status="",
        service=voucher_type,
        adviser="",
        row_number=index,
        items=classified["items"] or items,
        labour=classified["labour"],
        spares=classified["spares"],
        vas=classified["vas"],
        ledgers=ledgers,
        ledamts=ledamts,
    )


def _items_from_bill(node):
    """Stock item names from ITEMS FullList (tagged or legacy); stored newline-joined."""
    from compare.money import join_name_list, split_item_list

    # Optional ITEM tags if present; otherwise FullList text.
    names = []
    for item in node.findall("ITEM"):
        name = as_text(_child(item, "NAME"))
        if not name:
            name = as_text(item.text)
        if name:
            names.append(name)
    if names:
        return join_name_list(names)
    return join_name_list(split_item_list(_child(node, "ITEMS")))


def _list_text(value):
    """Normalise a Tally FullList string of ledger/VAS-style names."""
    from compare.money import join_name_list, split_name_list

    return join_name_list(split_name_list(value))


def _amount_list_text(value):
    """Keep Tally amount FullList intact (thousand commas must stay with the number)."""
    from compare.money import split_amount_list

    text = as_text(value)
    if not text:
        return ""
    # Normalise newlines to commas, then re-tokenise amounts safely.
    compact = text.replace("\r", ",").replace("\n", ",")
    amounts = split_amount_list(compact)
    return ",".join(amounts) if amounts else compact


def _is_cancelled(value):
    """Tally exports a cancelled voucher as Yes. A blank flag is a live voucher."""
    return as_text(value).lower() in {"yes", "true", "1"}


def _keep_voucher_type(voucher_type, allowed=None):
    """Old exports omit the type and are Hirise. Receipts and journals are dropped."""
    names = [as_text(name) for name in (allowed or (HIRISE, *SERVICE_BILL_NAMES)) if as_text(name)]
    if not as_text(voucher_type):
        return any(is_hirise_invoice_service(name) for name in names)
    return as_text(voucher_type) in names


def _child(node, name):
    found = node.find(name)
    if found is None or found.text is None:
        return ""
    return found.text.strip()


def _amount(value):
    text = as_text(value).replace(",", "")
    if not text:
        return ""
    try:
        number = abs(float(text))
    except ValueError:
        return as_text(value)
    if number.is_integer():
        return f"{int(number):,}"
    return f"{number:,.2f}"
