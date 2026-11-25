from openpyxl import load_workbook

from dataclasses import dataclass

from compare.normalize import (
    as_date,
    as_text,
    bill_number,
    financial_year,
    financial_year_from_reference,
    format_amount,
    is_hirise_invoice_service,
    job_card,
    vehicle_cell,
    vehicle_in_text,
)
from compare.records import Record


@dataclass
class TallyLoad:
    records: list
    skipped: int


def _header_map(header):
    return {as_text(name).lower(): index for index, name in enumerate(header) if as_text(name)}


def _cell(row, columns, *names):
    for name in names:
        index = columns.get(name.lower())
        if index is not None and index < len(row):
            return row[index]
    return None


def load_tracksheet(path):
    workbook = load_workbook(path, data_only=True, read_only=True)
    sheet = workbook.active
    rows = sheet.iter_rows(values_only=True)
    header = next(rows)
    columns = _header_map(header)
    records = []
    for number, row in enumerate(rows, start=2):
        if not row or not any(cell not in (None, "") for cell in row):
            continue
        on = as_date(_cell(row, columns, "Date"))
        reference = _cell(row, columns, "JC Number", "Job Card", "Job card")
        records.append(
            Record(
                source="tracksheet",
                branch=as_text(_cell(row, columns, "Branch")),
                on=on,
                financial_year=financial_year(on),
                job_card=job_card(reference),
                vehicle=vehicle_cell(_cell(row, columns, "Registration", "Vehicle", "Reg")),
                customer=as_text(_cell(row, columns, "Customer Name", "Customer")),
                bill=bill_number(_cell(row, columns, "Bill Number", "Bill")),
                amount=format_amount(_cell(row, columns, "Total", "Amount")),
                voucher_type="",
                status=as_text(_cell(row, columns, "Status")),
                service=as_text(_cell(row, columns, "Service Type", "Service")),
                adviser=as_text(_cell(row, columns, "Adviser", "Advisor")),
                row_number=number,
            )
        )
    workbook.close()
    return records


def load_tally(path):
    workbook = load_workbook(path, data_only=True, read_only=True)
    sheet = workbook.active
    rows = sheet.iter_rows(values_only=True)
    header = next(rows)
    columns = _header_map(header)
    records = []
    skipped = 0
    for number, row in enumerate(rows, start=2):
        if not row or not any(cell not in (None, "") for cell in row):
            continue
        on = as_date(_cell(row, columns, "Date"))
        reference = _cell(row, columns, "Reference", "Job Card", "JC Number", "Order Number")
        particulars = _cell(row, columns, "Particulars", "Customer")
        vehicle_value = _cell(row, columns, "Vehicle", "Registration")
        vehicle = vehicle_cell(vehicle_value) if as_text(vehicle_value) else ""
        if not vehicle:
            vehicle = vehicle_in_text(particulars)
        year = financial_year(on) or financial_year_from_reference(reference)
        voucher_type = as_text(_cell(row, columns, "Voucher Type", "Type"))
        if not is_hirise_invoice_service(voucher_type):
            skipped += 1
            continue
        records.append(
            Record(
                source="tally",
                branch=as_text(_cell(row, columns, "Branch")),
                on=on,
                financial_year=year,
                job_card=job_card(reference),
                vehicle=vehicle,
                customer=as_text(_cell(row, columns, "Customer"))
                or as_text(particulars).split("-")[0].strip(),
                bill=bill_number(_cell(row, columns, "Voucher No", "Voucher Number", "Invoice No", "Bill Number")),
                amount=format_amount(_cell(row, columns, "Amount", "Credit Amount", "Debit Amount")),
                voucher_type=voucher_type,
                status="",
                service=voucher_type,
                adviser="",
                row_number=number,
            )
        )
    workbook.close()
    return TallyLoad(records, skipped)
