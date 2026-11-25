from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

from compare.engine import ADDED, CHECK, KEEP, REMOVED

# Hand-update columns only.
JOB_HEADERS = [
    "Action Status",
    "JC Number",
    "Date",
    "Registration",
    "Customer Name",
    "Service Type",
    "Adviser",
    "Technician",
    "VAS Canvassed",
    "Items",
    "Bill Number",
    "Labour (before GST)",
    "Spares (before GST)",
    "Total (with GST)",
    "Reason",
]

VOUCHER_HEADERS = [
    "Voucher Number",
    "Date",
    "Branch",
    "Registration",
    "JC Number",
    "Has Job Card",
    "Labour",
    "Spares",
    "VAS",
    "Item Lines",
    "Note",
]

HEADER_FILL = PatternFill("solid", fgColor="1F4D3A")
HEADER_FONT = Font(color="FFFFFF", bold=True, name="Calibri", size=11)
BODY_FONT = Font(name="Calibri", size=11)
THIN = Border(
    left=Side(style="thin", color="D6D3D1"),
    right=Side(style="thin", color="D6D3D1"),
    top=Side(style="thin", color="D6D3D1"),
    bottom=Side(style="thin", color="D6D3D1"),
)

FILLS = {
    ADDED: PatternFill("solid", fgColor="166534"),
    REMOVED: PatternFill("solid", fgColor="9B2C2C"),
    CHECK: PatternFill("solid", fgColor="B45309"),
    KEEP: PatternFill("solid", fgColor="57534E"),
}
ROW_FILLS = {
    ADDED: PatternFill("solid", fgColor="ECFDF5"),
    REMOVED: PatternFill("solid", fgColor="FEF2F2"),
    CHECK: PatternFill("solid", fgColor="FFFBEB"),
    KEEP: PatternFill("solid", fgColor="FFFFFF"),
}


def summary_lines(result, track_path, tally_path, tally_records, skipped=0):
    """Kept for CLI/log use. Not written into the Excel workbook."""
    return [
        "Aryabhangy Tracksheet compare",
        f"Tracksheet: {track_path}",
        f"Tally: {tally_path}",
        f"{ADDED}: {result.count(ADDED)}",
        f"{REMOVED}: {result.count(REMOVED)}",
        f"{CHECK}: {result.count(CHECK)}",
        f"{KEEP}: {result.count(KEEP)}",
    ]


def _job_cells(outcome):
    return [
        outcome.mark,
        outcome.job_card,
        outcome.when,
        outcome.vehicle,
        outcome.customer,
        outcome.service,
        outcome.adviser,
        outcome.technician,
        outcome.vas,
        outcome.items,
        outcome.track_bill,
        outcome.labour,
        outcome.spares,
        outcome.amount,
        outcome.reason,
    ]


def _voucher_cells(row):
    return [
        row.voucher_number,
        row.when,
        row.branch,
        row.registration,
        row.job_card,
        "Yes" if row.has_job_card else "No",
        row.labour,
        row.spares,
        row.vas,
        row.items,
        row.note,
    ]


def _style_header(sheet):
    for cell in sheet[1]:
        cell.fill = HEADER_FILL
        cell.font = HEADER_FONT
        cell.alignment = Alignment(vertical="center", wrap_text=True)
        cell.border = THIN


def _style_row(sheet, fill=None, status_fill=None):
    row_idx = sheet.max_row
    for col in range(1, sheet.max_column + 1):
        cell = sheet.cell(row_idx, col)
        cell.font = BODY_FONT
        cell.alignment = Alignment(wrap_text=True, vertical="center")
        cell.border = THIN
        if fill:
            cell.fill = fill
    if status_fill:
        status_cell = sheet.cell(row_idx, 1)
        status_cell.fill = status_fill
        status_cell.font = Font(color="FFFFFF", bold=True, name="Calibri", size=11)


def _autosize(sheet, widths):
    for index, width in enumerate(widths, start=1):
        sheet.column_dimensions[get_column_letter(index)].width = width
    sheet.row_dimensions[1].height = 28
    sheet.freeze_panes = "B2"
    sheet.auto_filter.ref = f"A1:{get_column_letter(sheet.max_column)}{max(sheet.max_row, 1)}"


JOB_WIDTHS = [18, 12, 14, 14, 24, 14, 12, 12, 22, 40, 12, 10, 10, 48]
VOUCHER_WIDTHS = [22, 14, 12, 14, 12, 12, 10, 10, 22, 40, 28]


def write_report(path, lines, outcomes, vouchers=None):
    """Write Job Cards + Vouchers + status sheets. `lines` is ignored (no Summary sheet)."""
    vouchers = vouchers or []
    workbook = Workbook()

    jobs = workbook.active
    jobs.title = "Job Cards"
    jobs.append(JOB_HEADERS)
    _style_header(jobs)
    for outcome in outcomes:
        jobs.append(_job_cells(outcome))
        _style_row(jobs, ROW_FILLS.get(outcome.mark), FILLS.get(outcome.mark))
    _autosize(jobs, JOB_WIDTHS)

    vouchers_sheet = workbook.create_sheet("Vouchers")
    vouchers_sheet.append(VOUCHER_HEADERS)
    _style_header(vouchers_sheet)
    for row in vouchers:
        vouchers_sheet.append(_voucher_cells(row))
        _style_row(vouchers_sheet)
    _autosize(vouchers_sheet, VOUCHER_WIDTHS)

    for title, marks in (
        (ADDED, {ADDED}),
        (REMOVED, {REMOVED}),
        (CHECK, {CHECK}),
        (KEEP, {KEEP}),
    ):
        sheet = workbook.create_sheet(title[:31])
        sheet.append(JOB_HEADERS)
        _style_header(sheet)
        for outcome in outcomes:
            if outcome.mark not in marks:
                continue
            sheet.append(_job_cells(outcome))
            _style_row(sheet, ROW_FILLS.get(outcome.mark), FILLS.get(outcome.mark))
        _autosize(sheet, JOB_WIDTHS)

    workbook.save(path)
    return path
