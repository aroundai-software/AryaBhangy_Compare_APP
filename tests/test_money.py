import unittest

from compare.money import (
    classify_voucher,
    ledger_fill_parts,
    money_matches,
    split_amount_list,
    split_item_list,
    tally_bill_total,
    totals_match,
    track_bill_total,
    vas_extra,
    vas_missing,
)
from compare.records import Record
from datetime import date


class MoneyTests(unittest.TestCase):
    def test_labour_spares_from_gst_ledgers(self):
        items = "ENGINE OIL 1, CONSUMABLES CON-01"
        ledgers = (
            "SANEESH - KL 41W 6899, SERVICE-GST, CHAIN LUBRICATION, "
            "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C"
        )
        ledamts = "1553.43, 1096.47, 220.00, 98.67, 98.67, 19.80, 19.80, 0.02"
        classified = classify_voucher(items, ledgers, ledamts)
        self.assertEqual(classified["spares"], "1,293.81")
        self.assertEqual(classified["labour"], "259.60")
        self.assertTrue(money_matches("259.60", classified["labour"]))
        self.assertTrue(money_matches("1,293.81", classified["spares"]))
        self.assertIn("CHAIN LUBRICATION", classified["vas"].upper())

    def test_stock_name_with_internal_comma_stays_one_item(self):
        raw = (
            "ENGINE OIL MB 600ML\n"
            "CONSUMABLES CON-01\n"
            "RUBBER, MOUNT 90543MV9670\n"
            "WASHER,12MM DRAIN 9410912000\n"
            "BULB, TAIL LIGHT 34906GBG750"
        )
        names = split_item_list(raw)
        self.assertEqual(len(names), 5)
        self.assertEqual(names[2], "RUBBER, MOUNT 90543MV9670")
        self.assertEqual(names[3], "WASHER,12MM DRAIN 9410912000")
        self.assertEqual(names[4], "BULB, TAIL LIGHT 34906GBG750")

        # Tagged Tally FullList keeps commas inside names.
        tagged = (
            "ENGINE OIL MB 600ML##AB##, "
            "RUBBER, MOUNT 90543MV9670##AB##, "
            "WASHER,12MM DRAIN 9410912000##AB##"
        )
        self.assertEqual(
            split_item_list(tagged),
            [
                "ENGINE OIL MB 600ML",
                "RUBBER, MOUNT 90543MV9670",
                "WASHER,12MM DRAIN 9410912000",
            ],
        )

        # Legacy untagged FullList / older History: split on comma+space,
        # but keep comma-inside names like RUBBER, MOUNT.
        legacy = (
            "ENGINE OIL MB 600ML, CONSUMABLES CON-01, O RING DS-5058, "
            "RUBBER, MOUNT 90543MV9670, WASHER, 12MM DRAIN 9410912000, "
            "BULB, TAIL LIGHT 34906GBG750, NUT, SPECIAL, 28MM 90202KPL900"
        )
        legacy_names = split_item_list(legacy)
        self.assertEqual(
            legacy_names,
            [
                "ENGINE OIL MB 600ML",
                "CONSUMABLES CON-01",
                "O RING DS-5058",
                "RUBBER, MOUNT 90543MV9670",
                "WASHER, 12MM DRAIN 9410912000",
                "BULB, TAIL LIGHT 34906GBG750",
                "NUT, SPECIAL, 28MM 90202KPL900",
            ],
        )

        pipe_name = "RINGSET,PISTON O|S.13031-KRM-305"
        self.assertEqual(split_item_list(pipe_name), [pipe_name])
        self.assertEqual(
            split_item_list(f"ENGINE OIL\n{pipe_name}\nWASHER,12MM DRAIN"),
            ["ENGINE OIL", pipe_name, "WASHER,12MM DRAIN"],
        )

        classified = classify_voucher(raw, "SERVICE-GST", "100")
        self.assertIn("RUBBER, MOUNT 90543MV9670", classified["items"])
        self.assertEqual(len(split_item_list(classified["items"])), 5)

    def test_money_exact_match_no_rupee_slack(self):
        self.assertTrue(money_matches("259.60", "259.60"))
        self.assertTrue(money_matches("1,293.83", "1293.83"))
        self.assertFalse(money_matches("259", "259.60"))
        self.assertFalse(money_matches("1293", "1,293.83"))
        self.assertFalse(money_matches("259", "262"))

    def test_vas_add_and_extra(self):
        self.assertEqual(vas_missing("Chain Lube", "CHAIN LUBRICATION, RSA"), ["RSA"])
        self.assertEqual(vas_extra("Chain Lube, RSA", "CHAIN LUBRICATION"), ["RSA"])

    def test_vas_from_ledgers_only_not_stock_items(self):
        """Spare names with VAS-like words must stay in ITEMS, not VAS."""
        items = (
            "ENGINE OIL MB 600ML\n"
            "INJECTOR ASSY,FUEL 16450K0PD60\n"
            "WASHER,12MM DRAIN 9410912000"
        )
        ledgers = (
            "PARTY - KL 08BV 2237, Paid Service, SERVICE-GST, "
            "Output-SGST 9%-Labour, Output-CGST 9%-Labour"
        )
        ledamts = "2000, 500, 1000, 45, 45"
        classified = classify_voucher(items, ledgers, ledamts)
        self.assertEqual(classified["vas"], "Paid Service")
        self.assertIn("INJECTOR ASSY,FUEL 16450K0PD60", classified["items"])
        self.assertNotIn("INJECTOR ASSY", classified["vas"])

    def test_bill_totals_allow_small_rounding(self):
        self.assertTrue(totals_match(1412, 1413.48))
        self.assertFalse(totals_match(1412, 1500))

    def test_track_and_tally_bill_total_helpers(self):
        track = Record(
            source="tracksheet",
            branch="Aluva",
            on=date(2026, 11, 12),
            financial_year="2026-27",
            job_card="007357",
            vehicle="KL32Q5712",
            customer="Arun",
            bill="6484",
            amount="",
            voucher_type="",
            status="Delivered",
            service="Repair",
            adviser="",
            row_number=1,
            labour="914",
            spares="498",
        )
        tally = Record(
            source="tally",
            branch="Aluva",
            on=date(2026, 11, 12),
            financial_year="2026-27",
            job_card="007357",
            vehicle="KL32Q5712",
            customer="Arun",
            bill="KL10000126006484",
            amount="1,413.48",
            voucher_type="Hirise Invoice Service",
            status="",
            service="",
            adviser="",
            row_number=1,
            labour="914.50",
            spares="498.99",
        )
        self.assertEqual(track_bill_total(track), 1412.0)
        self.assertEqual(tally_bill_total([tally]), 1413.48)
        self.assertTrue(totals_match(track_bill_total(track), tally_bill_total([tally])))

    def test_classify_includes_grand_total(self):
        items = "CABLE A, CABLE B, BULB"
        ledgers = (
            "ARUN AC KL32Q5712, SERVICE-GST, LABOUR CHARGE, CHAIN LUBRICATION, "
            "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C"
        )
        ledamts = "1413.48, 422.87, 555.00, 220.00, 38.06, 38.06, 69.75, 69.75, 0.01"
        classified = classify_voucher(items, ledgers, ledamts)
        self.assertEqual(classified["spares"], "498.99")
        self.assertEqual(classified["labour"], "914.50")
        self.assertTrue(totals_match(1413.48, classified["grand_total_value"]))
        self.assertIn("CHAIN LUBRICATION", classified["vas"].upper())

    def test_classify_with_thousand_commas_in_ledamts(self):
        items = "CABLE A, CABLE B, BULB"
        ledgers = (
            "ARUN AC KL32Q5712, SERVICE-GST, LABOUR CHARGE, CHAIN LUBRICATION, "
            "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C"
        )
        # Real Tally FullList often includes thousand separators — must not break pairing.
        ledamts = "1,413.48,422.87,555.00,220.00,38.06,38.06,69.75,69.75,0.01"
        classified = classify_voucher(items, ledgers, ledamts)
        self.assertEqual(classified["labour"], "914.50")
        self.assertEqual(classified["spares"], "498.99")
        self.assertTrue(totals_match(1412, classified["grand_total_value"]))

    def test_spaced_negative_amounts_keep_their_sign(self):
        self.assertEqual(
            split_amount_list("722, 680, -68, 55, 55, -0.10"),
            ["722", "680", "-68", "55", "55", "-0.10"],
        )

    def test_service_bill_pretax_labour_and_vas_name(self):
        parts = ledger_fill_parts(
            "SULAIMAN - KL 41R 4406, ANTI RUST COATING, DISCOUNT ON LABOUR, CGST, SGST, ROUNDOFF",
            "722, 680, -68, 55, 55, -0.10",
            service_bill=True,
        )
        self.assertEqual(parts["labour"], 612)
        self.assertEqual(parts["spares"], 0)
        self.assertEqual(parts["total"], 722)
        self.assertEqual(parts["vas"], ["ANTI RUST COATING"])

    def test_paid_service_without_amount_is_not_vas(self):
        parts = ledger_fill_parts(
            "SULAIMAN - KL 41R 4406, SERVICE-GST, LABOUR CHARGE, Paid Service, "
            "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C",
            "7524.79, 3622.94, 2754, 0, 326.07, 326.07, 247.86, 247.86, -30.01",
        )
        self.assertEqual(parts["labour"], 2754)
        self.assertEqual(parts["spares"], 3622.94)
        self.assertEqual(parts["total"], 7524.79)
        self.assertEqual(parts["vas"], [])

    def test_insurance_bill_uses_party_total_and_accidental_repairs_as_labour(self):
        parts = ledger_fill_parts(
            "SHIRIRAM GENERAL INSURANCE CO.LTD, SERVICE-GST, ACCIDENTAL REPAIRS, "
            "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C",
            "37893.55, 21413.17, 10700, 1927.20, 1927.20, 963, 963, -0.02",
            party_name="SHIRIRAM GENERAL INSURANCE CO.LTD",
        )
        self.assertEqual(parts["spares"], 21413.17)
        self.assertEqual(parts["labour"], 10700)
        self.assertEqual(parts["total"], 37893.55)
        self.assertEqual(parts["vas"], [])


if __name__ == "__main__":
    unittest.main()
