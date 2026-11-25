import io
import json
import unittest
from datetime import date, timedelta
from unittest import mock

from compare.engine import ADDED, CHECK, REMOVED, compare
from compare.records import Outcome, Record
from compare.worker import Worker, date_slices, _outcome_row, _sheet_vehicle, _write_bill


class FakeIO:
    def __init__(self, lines):
        self.stdin = io.StringIO("\n".join(lines) + "\n")
        self.stdout = io.StringIO()

    def events(self):
        return [json.loads(line) for line in self.stdout.getvalue().splitlines() if line.strip()]


class DateSliceTests(unittest.TestCase):
    def test_short_range_is_one_piece(self):
        slices = date_slices(date(2026, 10, 15), date(2026, 10, 30))
        self.assertEqual(slices, [(date(2026, 10, 15), date(2026, 10, 30))])

    def test_sync_past_31_days_is_split_without_a_gap(self):
        slices = date_slices(date(2026, 10, 31), date(2026, 12, 15))
        self.assertEqual(slices[0], (date(2026, 10, 31), date(2026, 12, 1)))
        self.assertEqual(slices[1][0], date(2026, 12, 2))
        self.assertEqual(slices[-1][1], date(2026, 12, 15))
        for index in range(1, len(slices)):
            self.assertEqual(slices[index][0], slices[index - 1][1] + timedelta(days=1))
            self.assertLessEqual((slices[index][1] - slices[index][0]).days, 31)


class WorkerProtocolTests(unittest.TestCase):
    def test_ping_and_shutdown(self):
        fake = FakeIO(['{"cmd":"ping"}', '{"cmd":"shutdown"}'])
        worker = Worker(stdin=fake.stdin, stdout=fake.stdout)
        with mock.patch.object(worker, "_watch_tally", lambda: None):
            worker.run()
        events = fake.events()
        self.assertEqual(events[0]["event"], "pong")
        self.assertEqual(events[-1]["event"], "shutdown")

    def test_unknown_command(self):
        fake = FakeIO(['{"cmd":"nope"}', '{"cmd":"shutdown"}'])
        worker = Worker(stdin=fake.stdin, stdout=fake.stdout)
        with mock.patch.object(worker, "_watch_tally", lambda: None):
            worker.run()
        events = fake.events()
        self.assertEqual(events[0]["event"], "error")
        self.assertIn("Unknown", events[0]["message"])

    def test_bad_json(self):
        fake = FakeIO(["{", '{"cmd":"shutdown"}'])
        worker = Worker(stdin=fake.stdin, stdout=fake.stdout)
        with mock.patch.object(worker, "_watch_tally", lambda: None):
            worker.run()
        events = fake.events()
        self.assertEqual(events[0]["event"], "error")

    def test_branches_load(self):
        fake = FakeIO(['{"cmd":"branches.load"}', '{"cmd":"shutdown"}'])
        worker = Worker(stdin=fake.stdin, stdout=fake.stdout)
        worker._last_company = "Arya Bhangy Motors, Aluva - (2025-2026)"
        with mock.patch.object(worker, "_watch_tally", lambda: None):
            with mock.patch("compare.worker.branch_names", return_value=["Aluva", "Angamaly"]):
                worker.run()
        events = [event for event in fake.events() if event["event"] == "branches.loaded"]
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["names"], ["Aluva", "Angamaly"])
        self.assertEqual(events[0]["preferred"], "Aluva")

    def test_compare_run_emits_result(self):
        fake = FakeIO(
            [
                '{"cmd":"compare.run","from":"2026-11-16","to":"2026-11-16","branch":"Aluva"}',
                '{"cmd":"shutdown"}',
            ]
        )
        worker = Worker(stdin=fake.stdin, stdout=fake.stdout)
        track = [
            Record(
                source="tracksheet",
                branch="Aluva",
                on=date(2026, 11, 16),
                financial_year="2026-27",
                job_card="007050",
                vehicle="KL41X9816",
                customer="Anwar",
                bill="",
                amount="",
                voucher_type="",
                status="Delivered",
                service="Paid",
                adviser="Akhil",
                row_number=1,
            )
        ]
        tally = [
            Record(
                source="tally",
                branch="Aluva",
                on=date(2026, 11, 16),
                financial_year="2026-27",
                job_card="007050",
                vehicle="KL41X9816",
                customer="Anwar",
                bill="KL10000126006234",
                amount="736",
                voucher_type="Hirise Invoice Service",
                status="",
                service="Hirise Invoice Service",
                adviser="",
                row_number=1,
            )
        ]
        with mock.patch.object(worker, "_watch_tally", lambda: None):
            with mock.patch("compare.worker.current_company", return_value="Arya Bhangy Motors, Aluva - (2025-2026)"):
                with mock.patch("compare.worker.job_cards", return_value=track):
                    with mock.patch("compare.worker.hirise_vouchers", return_value=tally):
                        with mock.patch("compare.worker.job_cards_by_numbers", return_value=[]):
                            worker.run()
        result_events = [event for event in fake.events() if event["event"] == "compare.result"]
        self.assertEqual(len(result_events), 1)
        payload = result_events[0]
        self.assertEqual(payload["added"], 1)
        self.assertEqual(payload["removed"], 0)
        self.assertEqual(payload["branch"], "Aluva")
        self.assertEqual(payload["rows"][0]["mark"], ADDED)

    def test_outcome_row_shape(self):
        outcome = Outcome(
            mark=CHECK,
            reason="Check this",
            job_card="007050",
            vehicle="KL41X9816",
            category="Only one match",
        )
        row = _outcome_row(outcome)
        self.assertEqual(row["mark"], CHECK)
        self.assertEqual(row["category"], "Only one match")
        self.assertEqual(row["job_card"], "007050")
        self.assertEqual(row["reason"], "Check this")
        self.assertIn("sheet_bill", row)
        self.assertIn("tally_when", row)


class WriteVehicleMismatchTests(unittest.TestCase):
    def test_write_uses_the_tracksheet_vehicle_and_the_tally_bill(self):
        row = {
            "vehicle": "KL07AW0728 / KL04AW0728",
            "reason": "The vehicle numbers do not match, so nothing was written.",
            "bill": "",
            "tally_bills": "KL10000126005550",
        }
        self.assertEqual(_sheet_vehicle(row), "KL07AW0728")
        self.assertEqual(_write_bill(row), "5550")

    def test_two_sheet_vehicles_are_not_guessed(self):
        row = {
            "vehicle": "KL07AW0728 and KL08AW0728 / KL04AW0728",
            "reason": "The vehicle numbers do not match.",
            "bill": "",
            "tally_bills": "KL10000126005550",
        }
        self.assertEqual(_sheet_vehicle(row), row["vehicle"])

    def test_a_normal_row_keeps_its_bill(self):
        row = {"vehicle": "KL07AW0728", "reason": "Ready to fill.", "bill": "5550"}
        self.assertEqual(_sheet_vehicle(row), "KL07AW0728")
        self.assertEqual(_write_bill(row), "5550")


if __name__ == "__main__":
    unittest.main()
