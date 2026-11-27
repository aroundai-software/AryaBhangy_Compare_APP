import sqlite3
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "z_trackdemo"))

import server  # noqa: E402

from compare import tracksheet_site  # noqa: E402


def _db():
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.execute(
        """
        CREATE TABLE job_cards (
            id INTEGER PRIMARY KEY,
            jc_number TEXT NOT NULL,
            registration TEXT NOT NULL,
            status TEXT NOT NULL,
            bill_number TEXT NOT NULL DEFAULT '',
            labour REAL,
            spares REAL,
            bill_amount REAL,
            vas TEXT NOT NULL DEFAULT '[]',
            items TEXT NOT NULL DEFAULT '',
            updated_at TEXT NOT NULL DEFAULT ''
        )
        """
    )
    return con


class FillCardsTests(unittest.TestCase):
    def test_fill_matches_job_card_and_registration(self):
        con = _db()
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status) VALUES (?, ?, ?)",
            ("007362", "KL41R4406", "Received"),
        )
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status) VALUES (?, ?, ?)",
            ("007362", "KL07CU4294", "Received"),
        )
        summary = server.fill_cards(
            con,
            [
                {
                    "key": "007362|KL41R4406",
                    "job_card": "7362",
                    "vehicle": "KL 41R 4406",
                    "bill": "6526",
                    "labour": "3,366",
                    "spares": "3622.94",
                    "total": "8246.79",
                    "vas": "ANTI RUST COATING",
                    "items": "ENGINE OIL\nWASHER, RUBBER",
                }
            ],
        )
        self.assertEqual(summary["updated"], 1)
        self.assertTrue(summary["results"][0]["ok"])
        self.assertEqual(summary["results"][0]["key"], "007362|KL41R4406")
        matched = con.execute(
            "SELECT * FROM job_cards WHERE registration = ?",
            ("KL41R4406",),
        ).fetchone()
        other = con.execute(
            "SELECT * FROM job_cards WHERE registration = ?",
            ("KL07CU4294",),
        ).fetchone()
        self.assertEqual(matched["bill_number"], "6526")
        self.assertEqual(matched["labour"], 3366)
        self.assertEqual(matched["spares"], 3622.94)
        self.assertEqual(matched["bill_amount"], 8246.79)
        self.assertEqual(matched["vas"], '["ANTI RUST COATING"]')
        self.assertEqual(matched["items"], "ENGINE OIL\nWASHER, RUBBER")
        self.assertEqual(other["bill_number"], "")
        self.assertEqual(other["items"], "")
        self.assertIsNone(other["labour"])

    def test_short_district_matches_the_padded_plate(self):
        con = _db()
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status) VALUES (?, ?, ?)",
            ("002236", "KL7DC1448", "Received"),
        )
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status) VALUES (?, ?, ?)",
            ("002236", "KL42U9189", "Received"),
        )
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status) VALUES (?, ?, ?)",
            ("002236", "KL70DC1448", "Received"),
        )
        summary = server.fill_cards(
            con,
            [{"job_card": "002236", "vehicle": "KL07DC1448", "bill": "2016", "labour": "4268", "spares": "3898.90", "total": "9000"}],
        )
        self.assertTrue(summary["results"][0]["ok"])
        self.assertEqual(summary["updated"], 1)
        matched = con.execute(
            "SELECT bill_number, registration FROM job_cards WHERE registration = ?",
            ("KL7DC1448",),
        ).fetchone()
        other = con.execute(
            "SELECT bill_number FROM job_cards WHERE registration = ?",
            ("KL42U9189",),
        ).fetchone()
        nearby = con.execute(
            "SELECT bill_number FROM job_cards WHERE registration = ?",
            ("KL70DC1448",),
        ).fetchone()
        self.assertEqual(matched["bill_number"], "2016")
        self.assertEqual(matched["registration"], "KL7DC1448")
        self.assertEqual(other["bill_number"], "")
        self.assertEqual(nearby["bill_number"], "")

    def test_delivered_row_is_not_written(self):
        con = _db()
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status, bill_number) VALUES (?, ?, ?, ?)",
            ("006932", "KL41X6864", "Delivered", "keep"),
        )
        summary = server.fill_cards(
            con,
            [{"job_card": "006932", "vehicle": "KL41X6864", "bill": "6140", "labour": "10700", "spares": "21413.17", "total": "37893.55", "vas": []}],
        )
        self.assertFalse(summary["results"][0]["ok"])
        self.assertIn("delivered", summary["results"][0]["error"])
        row = con.execute("SELECT bill_number FROM job_cards").fetchone()
        self.assertEqual(row["bill_number"], "keep")

    def test_blank_vehicle_does_not_guess_between_registrations(self):
        con = _db()
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status) VALUES (?, ?, ?)",
            ("005216", "KL07CU4294", "Received"),
        )
        con.execute(
            "INSERT INTO job_cards (jc_number, registration, status) VALUES (?, ?, ?)",
            ("005216", "KL41R4406", "Received"),
        )
        summary = server.fill_cards(con, [{"job_card": "005216", "vehicle": "", "bill": "5274", "total": "1"}])
        self.assertFalse(summary["results"][0]["ok"])
        self.assertIn("more than one vehicle", summary["results"][0]["error"])

    def test_live_site_is_never_written(self):
        previous_site = tracksheet_site.SITE
        previous_database = tracksheet_site.DATABASE
        try:
            tracksheet_site.apply_website("https://track.aryabhangymotors.com")
            with self.assertRaises(tracksheet_site.SiteError) as caught:
                tracksheet_site.write_practice_cards([{"job_card": "007362"}])
            self.assertIn("token", str(caught.exception).lower())
        finally:
            tracksheet_site.SITE = previous_site
            tracksheet_site.DATABASE = previous_database
            tracksheet_site.LIVE_WRITE_TOKEN = ""


def _editable_card():
    con = sqlite3.connect(":memory:")
    con.row_factory = sqlite3.Row
    con.execute(
        """
        CREATE TABLE job_cards (
            id INTEGER PRIMARY KEY,
            jc_number TEXT,
            on_date TEXT,
            registration TEXT,
            customer_name TEXT,
            model TEXT,
            branch TEXT,
            serviced_at TEXT,
            service_type TEXT,
            booking_source TEXT,
            adviser TEXT,
            technician TEXT,
            status TEXT,
            final_inspection TEXT,
            claim TEXT,
            bill_number TEXT,
            labour REAL,
            spares REAL,
            bill_amount REAL,
            payment_mode TEXT,
            vas TEXT,
            items TEXT,
            remarks TEXT,
            repeat_complaint INTEGER,
            day_serial INTEGER,
            delivered_on TEXT
        )
        """
    )
    con.execute(
        """
        INSERT INTO job_cards VALUES (
            1, '005744', '2026-09-25', 'KL41W4558', 'Customer', 'Dio', 'Aluva', '',
            'PAID', '', 'Roshan', 'Achu', 'Received', '', '', '5240',
            NULL, 924.71, 1091.16, '', '[]', '', '', 0, 1, NULL
        )
        """
    )
    return con, con.execute("SELECT * FROM job_cards WHERE id = 1").fetchone()


class CellEditTests(unittest.TestCase):
    def test_money_keeps_paise(self):
        self.assertEqual(server.money("924.71"), 924.71)
        self.assertEqual(server.money("1,091.16"), 1091.16)

    def test_clicking_another_cell_keeps_the_gst_total(self):
        con, current = _editable_card()
        item = server.clean_payload(con, {"status": "Pending"}, current)
        self.assertEqual(item["status"], "Pending")
        self.assertIsNone(item["labour"])
        self.assertEqual(item["spares"], 924.71)
        self.assertEqual(item["bill_amount"], 1091.16)

    def test_opening_spares_without_a_new_figure_keeps_the_total(self):
        con, current = _editable_card()
        item = server.clean_payload(con, {"spares": 924.71}, current)
        self.assertEqual(item["spares"], 924.71)
        self.assertEqual(item["bill_amount"], 1091.16)

    def test_a_new_spare_figure_does_not_replace_the_stored_total(self):
        con, current = _editable_card()
        item = server.clean_payload(con, {"spares": 1000}, current)
        self.assertEqual(item["spares"], 1000)
        self.assertEqual(item["bill_amount"], 1091.16)

    def test_an_empty_total_is_still_labour_plus_spares(self):
        self.assertEqual(server.kept_bill_amount(None, 100, 50.5), 150.5)
        self.assertIsNone(server.kept_bill_amount(None, None, None))


if __name__ == "__main__":
    unittest.main()
