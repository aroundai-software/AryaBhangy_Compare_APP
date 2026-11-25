import tempfile
import unittest
from pathlib import Path

from compare.engine import ADDED
from compare.records import Outcome, VoucherRow
from compare.report import JOB_HEADERS, VOUCHER_HEADERS, write_report


class ReportTests(unittest.TestCase):
    def test_excel_has_job_cards_and_vouchers_sheets(self):
        self.assertEqual(
            JOB_HEADERS,
            [
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
            ],
        )
        self.assertNotIn("Tally VAS", JOB_HEADERS)
        self.assertIn("Voucher Number", VOUCHER_HEADERS)
        outcomes = [
            Outcome(
                mark=ADDED,
                reason="Add VAS",
                job_card="007194",
                vehicle="KL41W6899",
                track_bill="6400",
                vas="Chain Lube",
                items="ENGINE OIL 1",
                labour="259",
                spares="1,293",
            )
        ]
        vouchers = [
            VoucherRow(
                voucher_number="KL10000126006400",
                when="10 Nov 2026",
                registration="KL41W6899",
                job_card="007194",
                labour="259.60",
                spares="1,293.83",
                vas="CHAIN LUBRICATION",
                items="ENGINE OIL 1",
                has_job_card=True,
            )
        ]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "out.xlsx"
            write_report(str(path), ["Aryabhangy Tracksheet compare"], outcomes, vouchers)
            from openpyxl import load_workbook

            book = load_workbook(path)
            self.assertEqual(
                book.sheetnames,
                [
                    "Job Cards",
                    "Vouchers",
                    "Added to track",
                    "Removed from tracksheet",
                    "Check manually",
                    "No change",
                ],
            )
            self.assertNotIn("Summary", book.sheetnames)
            self.assertEqual([c.value for c in book["Job Cards"][1]], JOB_HEADERS)
            self.assertEqual(book["Job Cards"]["J2"].value, "ENGINE OIL 1")
            self.assertEqual(book["Vouchers"]["A2"].value, "KL10000126006400")
            self.assertEqual(book["Vouchers"]["J2"].value, "ENGINE OIL 1")


if __name__ == "__main__":
    unittest.main()
