import unittest
from pathlib import Path

from compare.engine import ADDED, CHECK, REMOVED
from compare.normalize import as_date
from compare.session import run_compare


class SessionTests(unittest.TestCase):
    def test_window_dates_are_read(self):
        self.assertEqual(as_date("09 Nov 2026").isoformat(), "2026-11-09")
        self.assertEqual(as_date("1-11-26").isoformat(), "2026-11-01")
        self.assertEqual(as_date("18-11-26").isoformat(), "2026-11-18")

    def test_known_files_mark_nothing_to_add_or_remove(self):
        track = Path(r"C:\Users\admin\Downloads\JobCards_2026-11-16_1127rows.xlsx")
        tally = Path(__file__).resolve().parents[1] / "samples" / "tally_known_invoices.xlsx"
        if not track.exists() or not tally.exists():
            self.skipTest("sample files are not on this machine")
        result, _tally_records, skipped = run_compare(
            track, tally, "09 Nov 2026", "16 Nov 2026", "All branches"
        )
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.count(REMOVED), 0)
        self.assertGreater(result.count(CHECK), 0)
        self.assertEqual(skipped, 2)


class WindowTests(unittest.TestCase):
    def test_branch_names_come_from_the_site(self):
        from compare.tracksheet_site import branch_names

        try:
            names = branch_names()
        except Exception as error:
            self.skipTest("tracksheet site is not reachable: " + str(error))
        self.assertIn("Aluva", names)
        self.assertIn("Angamaly", names)

    def test_window_reads_the_open_company_and_the_site(self):
        from app import CompareApp
        from compare.tally_gateway import period_covers, period_from_xml
        from compare.tracksheet_site import _record

        period_start, period_end = period_from_xml("<PERIOD><FROM>1-Apr-26</FROM><TO>31-Mar-27</TO></PERIOD>")
        self.assertEqual(period_start.isoformat(), "2026-04-01")
        self.assertEqual(period_end.isoformat(), "2027-03-31")
        self.assertTrue(period_covers(period_start, period_end, as_date("09 Nov 2026"), as_date("16 Nov 2026")))
        from compare.session import company_branch

        self.assertEqual(
            company_branch("Arya Bhangy Motors, Aluva - (2025-2026)", ["Aluva", "Bigwing Aluva", "Angamaly"]),
            "Aluva",
        )
        self.assertFalse(period_covers(period_start, period_end, as_date("09 Nov 2025"), as_date("16 Nov 2025")))
        record = _record(
            {
                "JC Number": "7063",
                "Date": "2026-11-06",
                "Registration": "KL 39 G 3555",
                "Customer Name": "Nimish",
                "Branch": {"id": 1, "value": "Aluva"},
                "Bill Number": "KL10000126006293",
                "Bill Amount": 1292,
                "Status": {"id": 2, "value": "Delivered"},
                "Service Type": {"id": 3, "value": "Paid Service"},
                "Adviser": "Akhil",
            },
            1,
        )
        self.assertEqual(record.job_card, "007063")
        self.assertEqual(record.vehicle, "KL39G3555")
        self.assertEqual(record.branch, "Aluva")
        self.assertEqual(record.bill, "KL10000126006293")

        window = CompareApp(visible=False)
        try:
            labels = []

            def walk(widget):
                try:
                    labels.append(widget.cget("text"))
                except (tk.TclError, AttributeError, KeyError):
                    pass
                for child in widget.winfo_children():
                    walk(child)

            import tkinter as tk

            walk(window)
            shown = " ".join(labels)
            self.assertIn("https://track.aryabhangymotors.com", shown)
            self.assertNotIn("Browse", shown)
            self.assertNotIn("Read open company", shown)
            self.assertTrue(hasattr(window, "from_picker"))
            self.assertTrue(hasattr(window, "to_picker"))
            window.from_picker.set_date(as_date("09 Nov 2026"))
            window.to_picker.set_date(as_date("16 Nov 2026"))
            start, end = window._dates()
            self.assertEqual(start.isoformat(), "2026-11-09")
            self.assertEqual(end.isoformat(), "2026-11-16")
            self.assertEqual(window.company.get(), "Tally: Checking")
            self.assertEqual(window.tally_line.get(), "Waiting for Tally")
            self.assertFalse(hasattr(window, "track_path"))
            self.assertFalse(hasattr(window, "tally_path"))
            window._remember_company(True, "Arya Bhangy Motors, Aluva - (2025-2026)", None)
            self.assertIn("Online", window.company.get())
            self.assertIn("Aluva", window.company.get())
            self.assertNotIn("Period", window.company.get())
            self.assertTrue(hasattr(window.tree, "xview"))
            window._set_branches(["Aluva", "Angamaly", "Cherai"])
            self.assertIn("Angamaly", window.branch_list["values"])
            self.assertEqual(window.branch_list["values"][0], "All branches")
            window._remember_company(False, "", None)
            self.assertEqual(window.company.get(), "Tally: Offline")
        finally:
            window.destroy()


if __name__ == "__main__":
    unittest.main()
