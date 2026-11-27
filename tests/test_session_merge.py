import unittest
from datetime import date

from compare.engine import ADDED, CHECK, compare
from compare.records import Record
from compare.session import merge_tracksheet_for_tally_jcs


def track(**kwargs):
    base = dict(
        source="tracksheet",
        branch="Aluva",
        on=date(2026, 10, 15),
        financial_year="2026-27",
        job_card="006422",
        vehicle="KL41X3684",
        customer="FAHAD",
        bill="5905",
        amount="609",
        voucher_type="",
        status="Delivered",
        service="FREE 02",
        adviser="Sathya",
        row_number=1,
        labour="0",
        spares="609",
    )
    base.update(kwargs)
    return Record(**base)


def tally(**kwargs):
    base = dict(
        source="tally",
        branch="Aluva",
        on=date(2026, 10, 24),
        financial_year="2026-27",
        job_card="006422",
        vehicle="KL41X3684",
        customer="FAHAD",
        bill="KL10000126005905",
        amount="609",
        voucher_type="Hirise Invoice Service",
        status="",
        service="Hirise Invoice Service",
        adviser="",
        row_number=1,
        labour="0",
        spares="609",
        items="ENGINE OIL MB 600ML",
    )
    base.update(kwargs)
    return Record(**base)


class MergeTracksheetForTallyJcsTests(unittest.TestCase):
    def test_fetches_jc_when_job_card_date_outside_window(self):
        # Date-window pull empty; Tally bill in range for JC 006422.
        window_track = []
        bills = [tally()]
        fetched = [track()]

        def fetch_by_jc(numbers):
            self.assertEqual(numbers, ["006422"])
            return fetched

        merged = merge_tracksheet_for_tally_jcs(window_track, bills, "Aluva", fetch_by_jc)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0].job_card, "006422")
        self.assertEqual(merged[0].on, date(2026, 10, 15))

        result = compare(merged, bills)
        self.assertEqual(result.count(ADDED), 1)
        self.assertIn("differs from bill date", result.outcomes[0].reason)

    def test_skips_fetch_when_jc_vehicle_already_in_window(self):
        window_track = [track(on=date(2026, 10, 24))]
        bills = [tally()]
        calls = []

        def fetch_by_jc(numbers):
            calls.append(numbers)
            return [track()]

        merged = merge_tracksheet_for_tally_jcs(window_track, bills, "Aluva", fetch_by_jc)
        self.assertEqual(calls, [])
        self.assertEqual(len(merged), 1)

    def test_without_merge_tally_only_is_check(self):
        result = compare([], [tally()])
        self.assertEqual(result.count(CHECK), 1)
        self.assertIn("not on the Tracksheet", result.outcomes[0].reason)


if __name__ == "__main__":
    unittest.main()
