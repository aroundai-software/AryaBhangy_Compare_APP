from datetime import date

from openpyxl import Workbook

# AMC and extended warranty are real Aluva invoices, and they are not the
# voucher type the compare uses. Only HiRise Invoice Service is compared.
KNOWN_INVOICES = [
    {
        "Branch": "Aluva",
        "Date": date(2026, 10, 31),
        "Voucher Type": "AMC",
        "Voucher No": "HO/SS1690/26-27",
        "Reference": "6908/26",
        "Vehicle": "KL 41W 2782",
        "Customer": "MATHAI",
        "Amount": 1180,
        "Particulars": "MATHAI - KL 41W 2782",
    },
    {
        "Branch": "Aluva",
        "Date": date(2026, 10, 31),
        "Voucher Type": "Extended warranty",
        "Voucher No": "HO/SS1696/26-27",
        "Reference": "6908/26",
        "Vehicle": "KL 41W 2782",
        "Customer": "MATHAI",
        "Amount": 1386,
        "Particulars": "MATHAI - KL 41W 2782",
    },
]


def write_sample(path):
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Tally"
    headers = list(KNOWN_INVOICES[0].keys())
    sheet.append(headers)
    for invoice in KNOWN_INVOICES:
        sheet.append([invoice[header] for header in headers])
    workbook.save(path)
    return path
