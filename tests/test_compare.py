import tempfile
import unittest
from datetime import date
from pathlib import Path

from compare.engine import (
    ADDED,
    BOTH_MATCH,
    CHECK,
    KEEP,
    NOT_MATCHING,
    ONE_MATCH,
    REMOVED,
    compare,
)

# Human-facing action labels used in Excel / UI.
assert ADDED == "Added to track"
assert REMOVED == "Removed from tracksheet"
from compare.load import load_tally
from compare.normalize import bill_compare_key, is_service_bill, job_card, vehicle_cell, vehicle_in_text
from compare.tally_gateway import _vouchers_from_xml
from compare.records import Record
from compare.sample_tally import write_sample


def record(**kwargs):
    values = dict(
        source="tracksheet",
        branch="Aluva",
        on=date(2026, 11, 10),
        financial_year="2026-27",
        job_card="002846",
        vehicle="KL63L4643",
        customer="Basil Baby",
        bill="",
        amount="",
        voucher_type="",
        status="Received",
        service="FREE 02",
        adviser="Delsy Anil",
        row_number=2,
    )
    values.update(kwargs)
    return Record(**values)


class NormalizeTests(unittest.TestCase):
    def test_job_card_from_the_forms_we_have_seen(self):
        self.assertEqual(job_card("JC-KL100001-02-2627-007063"), "007063")
        self.assertEqual(
            job_card("Jobcard No : JC-KL100001-02-2627-007050, Jobcard Date : 5-Nov-26, Customer Name : ANWAR SADATH V S"),
            "007050",
        )
        self.assertEqual(job_card("6908/26"), "006908")
        self.assertEqual(job_card("6908/26 dt. 31-Oct-26"), "006908")
        self.assertEqual(job_card("2846"), "002846")
        self.assertEqual(job_card("HO/SS1690/26-27"), "")

    def test_vehicle_cleanup(self):
        self.assertEqual(vehicle_cell("KL 41W 2782"), "KL41W2782")
        self.assertEqual(vehicle_in_text("MATHAI - KL 41W 2782"), "KL41W2782")
        self.assertEqual(vehicle_in_text("Anwar SADATH - KL 41X 9816"), "KL41X9816")
        self.assertEqual(vehicle_in_text("MOHANAN -KL07DE2963"), "KL07DE2963")
        self.assertEqual(vehicle_in_text("JAIN KL 07 CT 7306"), "KL07CT7306")
        self.assertEqual(vehicle_cell("KL07DE5812"), "KL07DE5812")
        # Tally often spaces letter series: "KA 19 H J 0759" (JC 7089 case).
        self.assertEqual(
            vehicle_in_text("RAINA - KA 19 H J 0759"),
            "KA19HJ0759",
        )
        self.assertEqual(vehicle_cell("RAINA - KA 19 H J 0759"), "KA19HJ0759")
        self.assertEqual(vehicle_in_text("KA 19 H J 0759"), "KA19HJ0759")
        self.assertEqual(vehicle_in_text("KL 07 D G 8234"), "KL07DG8234")
        self.assertEqual(vehicle_in_text("KA-19-HJ-0759"), "KA19HJ0759")
        # Tally party ledgers use a semicolon or colon before the plate.
        self.assertEqual(vehicle_in_text("MANAGING PARTNER - KL; 42Z 3312"), "KL42Z3312")
        self.assertEqual(vehicle_in_text("MANAGING PARTNER - KL: 42Z 3312"), "KL42Z3312")
        self.assertEqual(vehicle_cell("MANAGING PARTNER - KL; 42Z 3312"), "KL42Z3312")
        # Must not keep party name stuck to the reg.
        self.assertEqual(vehicle_cell("RAINAKA19HJ0759"), "KA19HJ0759")
        self.assertNotEqual(vehicle_cell("RAINA - KA 19 H J 0759"), "RAINAKA19HJ0759")

    def test_tally_bill_line_uses_narration_and_party_name(self):
        text = """<BILLS><BILL>
          <DATE>5-Nov-26</DATE>
          <VCHNO>KL10000126006234</VCHNO>
          <PARTY>Anwar SADATH - KL 41X 9816</PARTY>
          <NARR>Jobcard No : JC-KL100001-02-2627-007050, Jobcard Date : 5-Nov-26</NARR>
          <ITEMS>3M CARBON CLEANER  08307-3M
RUBBER, MOUNT 90543MV9670
WASHER,12MM DRAIN 9410912000</ITEMS>
        </BILL></BILLS>"""
        records = _vouchers_from_xml(text)
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0].job_card, "007050")
        self.assertEqual(records[0].vehicle, "KL41X9816")
        self.assertEqual(records[0].bill, "KL10000126006234")
        self.assertEqual(
            records[0].items,
            "3M CARBON CLEANER 08307-3M\n"
            "RUBBER, MOUNT 90543MV9670\n"
            "WASHER,12MM DRAIN 9410912000",
        )


class EngineTests(unittest.TestCase):
    def test_matching_job_with_a_missing_tracksheet_bill_is_added(self):
        track = [record(bill="")]
        tally = [record(source="tally", bill="HO/SS1690/26-27", amount="1,180", voucher_type="AMC")]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count(REMOVED), 0)
        self.assertEqual(result.count(CHECK), 0)

    def test_matching_job_with_a_tracksheet_bill_missing_in_tally_is_removed(self):
        track = [record(bill="2419")]
        tally = [record(source="tally", bill="")]
        result = compare(track, tally)
        self.assertEqual(result.count(REMOVED), 1)
        self.assertEqual(result.count(ADDED), 0)

    def test_one_different_column_is_added_and_the_same_columns_are_no_change(self):
        same = compare(
            [record(bill="6400", labour="259.60", spares="1,293.83", amount="1,553.43", vas="RSA, Chain Lube", items="ENGINE OIL\nO RING")],
            [record(source="tally", bill="KL10000126006400", labour="259.60", spares="1293.83", amount="1553.43", vas="CHAIN LUBE, RSA", items="O RING\nENGINE OIL")],
        )
        self.assertEqual(same.count(KEEP), 1)
        changed = compare(
            [record(bill="6400", labour="259.60", spares="1,293.83", amount="1,553.43", vas="RSA", items="ENGINE OIL")],
            [record(source="tally", bill="KL10000126006400", labour="259.60", spares="1,293.83", amount="1,553.43", vas="RSA", items="ENGINE OIL\nO RING")],
        )
        self.assertEqual(changed.count(ADDED), 1)
        self.assertIn("Items differs", changed.outcomes[0].reason)

    def test_items_saved_on_the_tracksheet_are_read_back(self):
        from compare.tracksheet_site import _record

        saved = _record(
            {
                "JC Number": "006719",
                "Date": "2026-10-26",
                "Registration": "TN99Q1580",
                "Bill Number": "5973",
                "Labour": 3341,
                "Spares": 2681.08,
                "Bill Amount": 6784.74,
                "VAS Canvassed": [{"id": 1, "value": "Silencer Coating"}],
                "Items": "SCOOTER OIL\nWASHER,12MM DRAIN 9410912000",
            },
            1,
        )
        self.assertEqual(saved.items, "SCOOTER OIL\nWASHER,12MM DRAIN 9410912000")
        tally = record(
            source="tally",
            job_card="006719",
            vehicle="TN99Q1580",
            on=date(2026, 10, 27),
            bill="KL10000126005973",
            labour="3,341",
            spares="2,681.08",
            amount="6,784.74",
            vas="Silencer Coating",
            items="WASHER,12MM DRAIN 9410912000\nSCOOTER OIL",
        )
        result = compare([saved], [tally])
        self.assertEqual(result.count(KEEP), 1)
        self.assertEqual(result.count(ADDED), 0)

    def test_different_bill_numbers_are_added(self):
        track = [record(bill="2419")]
        tally = [record(source="tally", bill="HO/SS1690/26-27")]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count(CHECK), 0)
        self.assertEqual(result.count(REMOVED), 0)
        self.assertIn("Bill #", result.outcomes[0].reason)

    def test_same_bill_is_kept(self):
        track = [record(bill="HO/SS1690/26-27")]
        tally = [record(source="tally", bill="HO/SS1690/26-27")]
        result = compare(track, tally)
        self.assertEqual(result.count(KEEP), 1)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.count_category(BOTH_MATCH), 1)

    def test_hirise_voucher_last_four_matches_tracksheet_bill(self):
        self.assertEqual(bill_compare_key("KL10000126006515"), "6515")
        track = [record(bill="6515")]
        tally = [record(source="tally", bill="KL10000126006515", amount="2,500")]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count(CHECK), 0)
        self.assertEqual(result.count_category(NOT_MATCHING), 1)

    def test_bill_match_missing_vas_is_added(self):
        track = [record(bill="6400", vas="Chain Lube", labour="259", spares="1293")]
        tally = [
            record(
                source="tally",
                bill="KL10000126006400",
                vas="CHAIN LUBRICATION, RSA",
                labour="259.60",
                spares="1,293.83",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertIn("RSA", result.outcomes[0].vas)

    def test_bill_match_extra_tracksheet_vas_is_ignored_for_now(self):
        track = [record(bill="6400", vas="Chain Lube, RSA", labour="259.60", spares="1,293.83")]
        tally = [
            record(
                source="tally",
                bill="KL10000126006400",
                vas="CHAIN LUBRICATION",
                labour="259.60",
                spares="1,293.83",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count(CHECK), 0)
        self.assertIn("CHAIN LUBRICATION", result.outcomes[0].vas.upper())

    def test_bill_totals_match_keeps_despite_labour_spares_split(self):
        # Same full bill (~1412 vs ~1413), different L/S packaging (e.g. Chain Lube in labour).
        track = [record(bill="6484", labour="914", spares="498", vas="Chain Lube")]
        tally = [
            record(
                source="tally",
                bill="KL10000126006484",
                labour="914.50",
                spares="498.99",
                vas="CHAIN LUBRICATION",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count(CHECK), 0)
        self.assertIn("Ready to fill", result.outcomes[0].reason)

    def test_rerun_after_write_is_no_change(self):
        # Write stored pretax labour and spares, and the with-GST total in Bill Amount.
        track = [
            record(
                job_card="005721",
                bill="5241",
                labour="600",
                spares="1,400.70",
                amount="2,360.82",
            )
        ]
        tally = [
            record(
                source="tally",
                job_card="005721",
                bill="KL10000125005241",
                amount="2,360.82",
                voucher_type="Hirise Invoice Service",
                ledgers="CUSTOMER - KL 63L 4643, SERVICE-GST, LABOUR CHARGE, Output-SGST 9%, Output-CGST 9%",
                ledamts="2360.82, 1400.70, 600, 180.06, 180.06",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(KEEP), 1)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.outcomes[0].sheet_total, "2,360.82")
        self.assertEqual(result.outcomes[0].amount, "2,360.82")

    def test_parts_only_rerun_after_write_is_no_change(self):
        track = [
            record(
                job_card="005905",
                bill="5230",
                labour="",
                spares="723.06",
                amount="853.21",
            )
        ]
        tally = [
            record(
                source="tally",
                job_card="005905",
                bill="KL10000125005230",
                amount="853.21",
                voucher_type="Hirise Invoice Service",
                ledgers="CUSTOMER - KL 63L 4643, SERVICE-GST, Output-SGST 9%, Output-CGST 9%",
                ledamts="853.21, 723.06, 65.07, 65.08",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(KEEP), 1)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.outcomes[0].sheet_total, "853.21")
        self.assertEqual(result.outcomes[0].amount, "853.21")

    def test_bill_totals_differ_is_check(self):
        track = [record(bill="6400", labour="914", spares="498")]
        tally = [
            record(
                source="tally",
                bill="KL10000126006400",
                labour="500",
                spares="400",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count(CHECK), 0)
        self.assertIn("Ready to fill", result.outcomes[0].reason)
        row = result.outcomes[0]
        self.assertEqual(row.sheet_labour, "914")
        self.assertEqual(row.sheet_spares, "498")
        self.assertEqual(row.sheet_total, "1,412")
        self.assertEqual(row.sheet_bill, "6400")
        self.assertEqual(row.tally_labour, "500")
        self.assertEqual(row.tally_spares, "400")
        self.assertEqual(row.tally_total, "900")
        self.assertEqual(row.sheet_when, "10 Nov 2026")
        self.assertEqual(row.tally_when, "10 Nov 2026")

    def test_vouchers_table_built(self):
        tally = [
            record(source="tally", bill="KL10000126006400", items="ENGINE OIL 1", labour="100", spares="200")
        ]
        result = compare([record(bill="6400", labour="100", spares="200")], tally)
        self.assertEqual(len(result.vouchers), 1)
        self.assertEqual(result.vouchers[0].voucher_number, "KL10000126006400")
        self.assertTrue(result.vouchers[0].has_job_card)
        self.assertEqual(result.outcomes[0].items, "ENGINE OIL 1")

    def test_categories_for_partial_and_one_sided(self):
        track = [record(bill="2419")]
        tally = [record(source="tally", bill="HO/SS1690/26-27")]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count_category(NOT_MATCHING), 1)

        only_tally = compare([], [record(source="tally", bill="KL10000126006234")])
        self.assertEqual(only_tally.count_category(NOT_MATCHING), 1)

        missing_bill = compare(
            [record(bill="")],
            [record(source="tally", bill="KL10000126006234", items="ENGINE OIL 1")],
        )
        self.assertEqual(missing_bill.count_category(NOT_MATCHING), 1)
        self.assertEqual(missing_bill.count(ADDED), 1)
        self.assertEqual(missing_bill.outcomes[0].track_bill, "6234")
        self.assertEqual(missing_bill.outcomes[0].items, "ENGINE OIL 1")
        self.assertIn("Bill # 6234", missing_bill.outcomes[0].reason)

    def test_same_job_card_on_two_vehicles_is_not_added_or_removed(self):
        track = [
            record(vehicle="KL63L4643", customer="Basil Baby", on=date(2026, 11, 16)),
            record(vehicle="KL63L4673", customer="Naity Joseph", adviser="Akhil", on=date(2026, 11, 10), row_number=3),
        ]
        tally = [record(source="tally", vehicle="KL63L4643", bill="HO/SS1690/26-27", on=date(2026, 11, 16))]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.count(REMOVED), 0)
        self.assertEqual(result.count(CHECK), 1)
        self.assertIn("different vehicle", result.outcomes[0].reason)

    def test_tally_jc_without_vehicle_matches_unique_tracksheet_jc(self):
        """JC 007254-style: Tally has JC in narration but no reg → unique Tracksheet JC."""
        track = [
            record(
                job_card="007254",
                vehicle="KL41T0914",
                bill="6401",
                labour="239",
                spares="459",
                customer="MARTIN K V",
            )
        ]
        tally = [
            record(
                source="tally",
                job_card="007254",
                vehicle="",
                bill="KL10000126006401",
                labour="239.54",
                spares="459.14",
                amount="698.68",
                customer="MARTIN K V",
                items="ENGINE OIL\nO RING\nWASHER",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 1)
        self.assertEqual(result.count(CHECK), 0)
        self.assertEqual(result.outcomes[0].vehicle, "KL41T0914")
        self.assertIn("only Tracksheet row", result.outcomes[0].reason)
        self.assertIn("ENGINE OIL", result.outcomes[0].items)

    def test_tally_jc_without_vehicle_stays_check_if_jc_on_two_track_vehicles(self):
        track = [
            record(job_card="007254", vehicle="KL41T0914", bill="6401", row_number=2),
            record(
                job_card="007254",
                vehicle="KL41T9999",
                bill="6402",
                customer="Other",
                row_number=3,
            ),
        ]
        tally = [
            record(
                source="tally",
                job_card="007254",
                vehicle="",
                bill="KL10000126006401",
                amount="698.68",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.count(KEEP), 0)
        self.assertGreaterEqual(result.count(CHECK), 1)
        self.assertTrue(
            any("more than one vehicle" in o.reason for o in result.outcomes)
        )

    def test_tally_jc_without_vehicle_stays_check_if_no_tracksheet_jc(self):
        tally = [
            record(
                source="tally",
                job_card="007254",
                vehicle="",
                bill="KL10000126006401",
                amount="698.68",
            )
        ]
        result = compare([], tally)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.count(CHECK), 1)
        self.assertIn("no vehicle number", result.outcomes[0].reason)

    def test_a_job_only_in_tally_is_not_added(self):
        tally = [record(source="tally", job_card="006908", vehicle="KL41W2782", bill="HO/SS1690/26-27", on=date(2026, 10, 31))]
        result = compare([], tally)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.count(CHECK), 1)

    def test_empty_tally_leaves_tracksheet_rows_out(self):
        track = [record()]
        result = compare(track, [])
        self.assertEqual(result.count(CHECK), 0)
        self.assertEqual(result.uncovered_rows, 1)
        self.assertEqual(result.count(REMOVED), 0)

    def test_job_card_with_no_bill_inside_the_dates_is_left_out(self):
        track = [
            record(
                job_card="006400",
                vehicle="KL07AB1234",
                on=date(2026, 11, 5),
                bill="",
                labour="",
                spares="",
            )
        ]
        other = record(
            source="tally",
            job_card="006401",
            vehicle="KL07AB9999",
            on=date(2026, 11, 6),
            bill="KL10000126007001",
            amount="500",
            voucher_type="Hirise Invoice Service",
        )
        result = compare(track, [other])
        self.assertFalse(any(outcome.job_card == "006400" for outcome in result.outcomes))
        self.assertEqual(result.uncovered_rows, 1)
        self.assertEqual(result.count(CHECK), 1)

    def test_bill_on_a_later_day_inside_the_compare_is_matched(self):
        track = [
            record(
                job_card="006400",
                vehicle="KL07AB1234",
                on=date(2026, 11, 5),
                bill="",
                labour="",
                spares="",
            )
        ]
        bill = record(
            source="tally",
            job_card="006400",
            vehicle="KL07AB1234",
            on=date(2026, 11, 18),
            bill="KL10000126007018",
            amount="1,500",
            voucher_type="Hirise Invoice Service",
            ledgers="CUSTOMER - KL 07AB 1234, SERVICE-GST, LABOUR CHARGE",
            ledamts="1500, 800, 500",
        )
        result = compare(track, [bill])
        row = next(outcome for outcome in result.outcomes if outcome.job_card == "006400")
        self.assertEqual(row.mark, ADDED)
        self.assertEqual(row.track_bill, "7018")
        self.assertIn("05 Nov 2026", row.reason)
        self.assertIn("18 Nov 2026", row.reason)
        self.assertNotIn("Check manually", row.reason)

    def test_duplicate_tracksheet_rows_are_not_changed(self):
        track = [record(row_number=2), record(row_number=3, customer="Basil")]
        tally = [record(source="tally", bill="HO/SS1690/26-27")]
        result = compare(track, tally)
        self.assertEqual(result.count(CHECK), 1)
        self.assertEqual(result.count(ADDED), 0)

    def test_dates_outside_the_tally_file_are_left_unchanged(self):
        track = [record(on=date(2026, 11, 16), job_card="002100", vehicle="KL63L1111")]
        tally = [record(source="tally", on=date(2026, 10, 31), job_card="006908", vehicle="KL41W2782", bill="HO/SS1/26-27")]
        result = compare(track, tally)
        self.assertEqual(result.uncovered_rows, 1)
        self.assertEqual(result.count(REMOVED), 0)
        self.assertEqual(result.count(CHECK), 1)

    def test_service_bill_on_the_same_day_is_included_in_the_fill(self):
        day = date(2026, 11, 13)
        track = [
            record(
                job_card="007362",
                vehicle="KL41R4406",
                customer="SULAIMAN",
                on=day,
                bill="6526",
                labour="3971",
                spares="4275",
                vas="Anti Rust, Injector Cleaning, Quick DC",
            )
        ]
        hirise = record(
            source="tally",
            job_card="007362",
            vehicle="KL41R4406",
            customer="SULAIMAN",
            on=day,
            bill="KL10000126006526",
            amount="7,524.79",
            voucher_type="Hirise Invoice Service",
            items="O RING DS-5058",
            ledgers=(
                "SULAIMAN - KL 41R 4406, SERVICE-GST, LABOUR CHARGE, Paid Service, "
                "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C"
            ),
            ledamts="7524.79, 3622.94, 2754, 0, 326.07, 326.07, 247.86, 247.86, -30.01",
        )
        service = record(
            source="tally",
            job_card="",
            vehicle="KL41R4406",
            customer="SULAIMAN",
            on=day,
            bill="HO/SS1819/26-27",
            amount="722",
            voucher_type="SERVICE BILL_GST",
            ledgers="SULAIMAN - KL 41R 4406, ANTI RUST COATING, DISCOUNT ON LABOUR, CGST, SGST, ROUNDOFF",
            ledamts="722, 680, -68, 55, 55, -0.10",
        )
        result = compare(track, [hirise, service])
        row = next(outcome for outcome in result.outcomes if outcome.job_card == "007362")
        self.assertEqual(row.mark, ADDED)
        self.assertEqual(row.track_bill, "6526")
        self.assertEqual(row.labour, "3,366")
        self.assertEqual(row.spares, "3,622.94")
        self.assertEqual(row.amount, "8,246.79")
        self.assertEqual(row.vas, "ANTI RUST COATING")
        self.assertEqual(row.items, "O RING DS-5058")
        self.assertIn("Nothing is written until you press Write", row.reason)
        self.assertIn("before GST", row.reason)

    def test_tamil_nadu_party_total_is_not_added_to_labour(self):
        day = date(2026, 10, 27)
        track = [
            record(
                job_card="006719",
                vehicle="TN99Q1580",
                customer="KANNAN V",
                on=date(2026, 10, 26),
                bill="",
                labour="",
                spares="",
            )
        ]
        hirise = record(
            source="tally",
            job_card="006719",
            vehicle="TN99Q1580",
            customer="KANNAN",
            on=day,
            bill="KL10000126005973",
            amount="5,340.74",
            voucher_type="Hirise Invoice Service",
            ledgers=(
                "KANNAN-TN 99 Q 1580, SERVICE-GST, LABOUR CHARGE, Paid Service, "
                "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour"
            ),
            ledamts="5340.74, 2681.08, 1845, 0, 241.28, 241.28, 166.05, 166.05",
        )
        service = record(
            source="tally",
            job_card="",
            vehicle="TN99Q1580",
            customer="KANNAN",
            on=day,
            bill="HO/SS1636/26-27",
            amount="1444",
            voucher_type="SERVICE BILL -GST",
            ledgers="KANNAN-TN 99 Q 1580, Silencer Coating, TEFLON COATING, CGST, SGST",
            ledamts="1444, 700, 524.40, 109.80, 109.80",
        )
        result = compare(track, [hirise, service])
        row = next(outcome for outcome in result.outcomes if outcome.job_card == "006719")
        self.assertEqual(row.labour, "3,069.40")
        self.assertEqual(row.spares, "2,681.08")
        self.assertEqual(row.amount, "6,784.74")
        self.assertEqual(row.vas, "Silencer Coating, TEFLON COATING")
        self.assertNotIn("KANNAN", row.vas)

    def test_service_bills_on_different_days_stay_on_their_own_job(self):
        first = date(2026, 11, 9)
        second = date(2026, 11, 13)
        track = [
            record(job_card="007208", vehicle="KL42V4885", on=first, bill="0389", labour="1", spares="1"),
            record(job_card="007362", vehicle="KL41R4406", on=second, bill="6526", labour="1", spares="1"),
        ]
        bills = [
            record(
                source="tally",
                job_card="007208",
                vehicle="KL42V4885",
                on=first,
                bill="KL10000126006389",
                amount="6449.67",
                voucher_type="Hirise Invoice Service",
                ledgers="SRUTHY - KL 42V 4885, SERVICE-GST, LABOUR CHARGE, Paid Service",
                ledamts="6449.67, 3350.84, 2115, 0",
            ),
            record(
                source="tally",
                job_card="",
                vehicle="KL42V4885",
                on=first,
                bill="HO/SS1780/26-27",
                amount="1180",
                voucher_type="SERVICE BILL_GST",
                ledgers="SRUTHY - KL 42V 4885, AMC(SERVICE), CGST, SGST",
                ledamts="1180, 1000, 90, 90",
            ),
            record(
                source="tally",
                job_card="007362",
                vehicle="KL41R4406",
                on=second,
                bill="KL10000126006526",
                amount="7524.79",
                voucher_type="Hirise Invoice Service",
                ledgers="SULAIMAN - KL 41R 4406, SERVICE-GST, LABOUR CHARGE",
                ledamts="7524.79, 3622.94, 2754",
            ),
            record(
                source="tally",
                job_card="",
                vehicle="KL41R4406",
                on=second,
                bill="HO/SS1819/26-27",
                amount="722",
                voucher_type="SERVICE BILL_GST",
                ledgers="SULAIMAN - KL 41R 4406, ANTI RUST COATING, DISCOUNT ON LABOUR",
                ledamts="722, 680, -68",
            ),
        ]
        result = compare(track, bills)
        sruthy = next(outcome for outcome in result.outcomes if outcome.job_card == "007208")
        sulaiman = next(outcome for outcome in result.outcomes if outcome.job_card == "007362")
        self.assertEqual(sruthy.labour, "3,115")
        self.assertEqual(sruthy.spares, "3,350.84")
        self.assertEqual(sruthy.amount, "7,629.67")
        self.assertEqual(sruthy.vas, "AMC(SERVICE)")
        self.assertEqual(sruthy.track_bill, "6389")
        self.assertEqual(sulaiman.labour, "3,366")
        self.assertEqual(sulaiman.vas, "ANTI RUST COATING")
        self.assertNotIn("AMC", sulaiman.vas)

    def test_two_hirise_bills_on_one_day_leave_the_service_bill_out(self):
        day = date(2026, 11, 13)
        track = [
            record(job_card="007362", vehicle="KL41R4406", on=day, bill="6526", labour="2754", spares="3622.94"),
            record(job_card="007400", vehicle="KL41R4406", on=day, bill="6600", labour="100", spares="50", row_number=3),
        ]
        bills = [
            record(
                source="tally",
                job_card="007362",
                vehicle="KL41R4406",
                on=day,
                bill="KL10000126006526",
                amount="1000",
                voucher_type="Hirise Invoice Service",
                ledgers="SULAIMAN - KL 41R 4406, SERVICE-GST, LABOUR CHARGE",
                ledamts="1000, 400, 500",
            ),
            record(
                source="tally",
                job_card="007400",
                vehicle="KL41R4406",
                on=day,
                bill="KL10000126006600",
                amount="200",
                voucher_type="Hirise Invoice Service",
                ledgers="SULAIMAN - KL 41R 4406, SERVICE-GST, LABOUR CHARGE",
                ledamts="200, 50, 100",
                row_number=4,
            ),
            record(
                source="tally",
                job_card="",
                vehicle="KL41R4406",
                on=day,
                bill="HO/SS1819/26-27",
                amount="722",
                voucher_type="SERVICE BILL_GST",
                ledgers="SULAIMAN - KL 41R 4406, ANTI RUST COATING",
                ledamts="722, 680",
            ),
        ]
        result = compare(track, bills)
        jobs = [outcome for outcome in result.outcomes if outcome.job_card in {"007362", "007400"}]
        self.assertEqual(len(jobs), 2)
        self.assertTrue(all(outcome.mark == CHECK for outcome in jobs))
        self.assertTrue(all("left out" in outcome.reason for outcome in jobs))
        by_card = {outcome.job_card: outcome for outcome in jobs}
        self.assertEqual(by_card["007362"].labour, "500")
        self.assertEqual(by_card["007400"].labour, "100")
        self.assertNotIn("ANTI RUST", by_card["007362"].vas)
        self.assertFalse(any(outcome.job_card == "" and "HO/SS1819" in outcome.reason for outcome in result.outcomes))

    def test_insurance_party_total_includes_accidental_repairs(self):
        day = date(2026, 10, 31)
        track = [
            record(
                job_card="006932",
                vehicle="KL41X6864",
                customer="KUMARAN V P",
                on=date(2026, 10, 14),
                bill="",
                labour="",
                spares="",
            )
        ]
        hirise = record(
            source="tally",
            job_card="006932",
            vehicle="",
            customer="SHIRIRAM GENERAL INSURANCE CO.LTD",
            on=day,
            bill="KL10000126006140",
            amount="27,193.57",
            voucher_type="Hirise Invoice Service",
            ledgers=(
                "SHIRIRAM GENERAL INSURANCE CO.LTD, SERVICE-GST, ACCIDENTAL REPAIRS, "
                "Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C"
            ),
            ledamts="37893.55, 21413.17, 10700, 1927.20, 1927.20, 963, 963, -0.02",
        )
        result = compare(track, [hirise])
        row = result.outcomes[0]
        self.assertEqual(row.vehicle, "KL41X6864")
        self.assertEqual(row.labour, "10,700")
        self.assertEqual(row.spares, "21,413.17")
        self.assertEqual(row.amount, "37,893.55")
        self.assertEqual(row.track_bill, "6140")

    def test_hyphenated_service_bill_type_is_included(self):
        self.assertTrue(is_service_bill("SERVICE BILL -GST"))
        self.assertTrue(is_service_bill("SERVICE BILL_GST"))
        self.assertFalse(is_service_bill("SERVICE BILL - GST MARAMPILLY"))
        self.assertFalse(is_service_bill("Service GST"))
        self.assertFalse(is_service_bill("RECEIPT  -SERVICE"))
        day = date(2026, 10, 3)
        track = [
            record(
                job_card="005216",
                vehicle="KL07CU4294",
                customer="SILVY VARGHESE",
                on=date(2026, 9, 11),
                bill="5274",
                labour="6,065",
                spares="15,942",
                amount="22,007",
            )
        ]
        hirise = record(
            source="tally",
            job_card="005216",
            vehicle="KL07CU4294",
            customer="SILVY",
            on=day,
            bill="KL10000126005274",
            amount="20,828.10",
            voucher_type="Hirise Invoice Service",
            ledgers="SILVY - KL 07CU 4294, SERVICE-GST, LABOUR CHARGE, Output-SGST 9%, Output-CGST 9%, Output-SGST 9%-Labour, Output-CGST 9%-Labour, Adjust A/C",
            ledamts="20828.10, 13510.93, 4140, 1215.99, 1215.99, 372.60, 372.60, -0.01",
        )
        service = record(
            source="tally",
            vehicle="KL07CU4294",
            customer="SILVY",
            on=day,
            bill="HO/SS1447/26-27",
            amount="1,180.00",
            voucher_type="SERVICE BILL -GST",
            ledgers="SILVY - KL 07CU 4294, AMC(SERVICE), CGST, SGST",
            ledamts="1180, 1000, 90, 90",
        )
        result = compare(track, [hirise, service])
        row = result.outcomes[0]
        self.assertEqual(row.labour, "5,140")
        self.assertEqual(row.spares, "13,510.93")
        self.assertEqual(row.amount, "22,008.10")
        self.assertEqual(row.vas, "AMC(SERVICE)")
        self.assertEqual(row.mark, ADDED)

    def test_a_saved_extra_voucher_type_joins_as_a_service_bill(self):
        day = date(2026, 10, 3)
        track = [
            record(
                job_card="002232",
                vehicle="KL63L7316",
                customer="ANU MATHEW",
                on=day,
                bill="",
            )
        ]
        hirise = record(
            source="tally",
            job_card="002232",
            vehicle="KL63L7316",
            customer="ANU",
            on=day,
            bill="KL10BB01260002002",
            amount="609.13",
            voucher_type="Hirise Invoice Service",
            ledgers="ANU-KL 63 L 7316, SERVICE-GST",
            ledamts="609.13, 516.21",
        )
        extra = record(
            source="tally",
            vehicle="KL63L7316",
            customer="ANU",
            on=day,
            bill="AG/L/449/26-27",
            amount="800",
            voucher_type="SERVICE BILL (NEW)",
            ledgers="ANU-KL 63 L 7316, ANTI RUST COTTING, CGST, SGST",
            ledamts="800, 677.97, 61.02, 61.01",
        )
        left_out = compare(track, [hirise, extra])
        alone = next(row for row in left_out.outcomes if row.job_card == "002232")
        self.assertEqual(alone.amount, "609.13")
        joined = compare(track, [hirise, extra], service_types=["SERVICE BILL (NEW)"])
        row = next(item for item in joined.outcomes if item.job_card == "002232")
        self.assertEqual(row.spares, "516.21")
        self.assertEqual(row.labour, "677.97")
        self.assertEqual(row.amount, "1,409.13")
        self.assertEqual(row.vas, "ANTI RUST COTTING")

    def test_cancelled_hirise_bill_is_dropped_and_the_new_bill_is_kept(self):
        text = """<BILLS>
          <BILL>
            <DATE>3-Oct-2026</DATE>
            <VCHNO>KL10000126005274</VCHNO>
            <PARTY>SILVY - KL 07CU 4294</PARTY>
            <NARR>Jobcard No : JC-KL100001-02-2627-005216</NARR>
            <VCHTYPE>Hirise Invoice Service</VCHTYPE>
            <CANCELLED>Yes</CANCELLED>
            <LEDGERS>SILVY - KL 07CU 4294, SERVICE-GST, LABOUR CHARGE</LEDGERS>
            <LEDAMTS>20828.10, 13510.93, 4140</LEDAMTS>
          </BILL>
          <BILL>
            <DATE>3-Oct-2026</DATE>
            <VCHNO>KL10000126005999</VCHNO>
            <PARTY>SILVY - KL 07CU 4294</PARTY>
            <NARR>Jobcard No : JC-KL100001-02-2627-005216</NARR>
            <VCHTYPE>Hirise Invoice Service</VCHTYPE>
            <CANCELLED>No</CANCELLED>
            <LEDGERS>SILVY - KL 07CU 4294, SERVICE-GST, LABOUR CHARGE</LEDGERS>
            <LEDAMTS>15000, 10000, 3000</LEDAMTS>
          </BILL>
          <BILL>
            <DATE>3-Oct-2026</DATE>
            <VCHNO>HO/SS1447/26-27</VCHNO>
            <PARTY>SILVY - KL 07CU 4294</PARTY>
            <VCHTYPE>SERVICE BILL -GST</VCHTYPE>
            <LEDGERS>SILVY - KL 07CU 4294, AMC(SERVICE), CGST, SGST</LEDGERS>
            <LEDAMTS>1180, 1000, 90, 90</LEDAMTS>
          </BILL>
          <BILL>
            <DATE>3-Oct-2026</DATE>
            <VCHNO>HO/SS1448/26-27</VCHNO>
            <PARTY>SILVY - KL 07CU 4294</PARTY>
            <VCHTYPE>SERVICE BILL -GST</VCHTYPE>
            <CANCELLED>Yes</CANCELLED>
            <LEDGERS>SILVY - KL 07CU 4294, ANTI RUST COATING</LEDGERS>
            <LEDAMTS>722, 680</LEDAMTS>
          </BILL>
        </BILLS>"""
        bills = _vouchers_from_xml(text)
        self.assertEqual([bill.bill for bill in bills], ["KL10000126005999", "HO/SS1447/26-27"])
        track = [
            record(
                job_card="005216",
                vehicle="KL07CU4294",
                customer="SILVY VARGHESE",
                on=date(2026, 9, 11),
                bill="",
                labour="",
                spares="",
            )
        ]
        result = compare(track, bills)
        row = next(outcome for outcome in result.outcomes if outcome.job_card == "005216")
        self.assertEqual(row.track_bill, "5999")
        self.assertEqual(row.labour, "4,000")
        self.assertEqual(row.spares, "10,000")
        self.assertEqual(row.amount, "16,180")
        self.assertEqual(row.vas, "AMC(SERVICE)")
        self.assertNotIn("5274", row.track_bill)
        self.assertNotIn("ANTI RUST", row.vas)

    def test_same_job_card_with_a_different_vehicle_names_both_numbers(self):
        track = [
            record(
                job_card="006279",
                vehicle="KL07AW0728",
                customer="ANEEZYA S",
                on=date(2026, 10, 12),
                bill="",
            )
        ]
        tally = [
            record(
                source="tally",
                job_card="006279",
                vehicle="KL04AW0728",
                customer="ANEEZYA S KL04AW0728",
                on=date(2026, 10, 12),
                bill="KL10000126005550",
                amount="2868.11",
                labour="1650",
                spares="780.60",
            )
        ]
        result = compare(track, tally)
        self.assertEqual(result.count(CHECK), 1)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.uncovered_rows, 0)
        row = result.outcomes[0]
        self.assertEqual(row.job_card, "006279")
        self.assertEqual(row.vehicle, "KL07AW0728 / KL04AW0728")
        self.assertEqual(row.customer, "ANEEZYA S")
        self.assertEqual(row.track_bill, "")
        self.assertEqual(row.sheet_bill, "")
        self.assertEqual(row.sheet_when, "12 Oct 2026")
        self.assertEqual(row.tally_when, "12 Oct 2026")
        self.assertEqual(row.tally_labour, "1650")
        self.assertEqual(row.tally_spares, "780.60")
        self.assertEqual(row.tally_total, "2,868.11")
        self.assertIn("KL10000126005550", row.tally_bills)
        self.assertIn("KL07AW0728", row.reason)
        self.assertIn("KL04AW0728", row.reason)
        self.assertIn("vehicle numbers do not match", row.reason)
        self.assertNotIn("not on the Tracksheet", row.reason)


class SampleFileTests(unittest.TestCase):
    def test_sample_invoices_load_as_one_job(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tally.xlsx"
            write_sample(path)
            loaded = load_tally(path)
        self.assertEqual(loaded.skipped, 2)
        self.assertEqual(loaded.records, [])
        self.assertEqual(job_card("HO/SS1690/26-27"), "")

    def test_only_hirise_invoice_service_is_kept(self):
        from openpyxl import Workbook

        from compare.normalize import is_hirise_invoice_service

        self.assertTrue(is_hirise_invoice_service("HiRise Invoice Service"))
        self.assertFalse(is_hirise_invoice_service("AMC"))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tally.xlsx"
            workbook = Workbook()
            sheet = workbook.active
            sheet.append(["Date", "Voucher Type", "Voucher No", "Reference", "Vehicle", "Customer", "Amount", "Branch"])
            sheet.append(["2026-11-10", "HiRise Invoice Service", "KL10000126006116", "6908/26", "KL41W2782", "MATHAI", 1292, "Aluva"])
            sheet.append(["2026-11-10", "Sales Spares GST", "ANG/SP972/26-27", "6908/26", "KL41W2782", "MATHAI", 500, "Aluva"])
            workbook.save(path)
            loaded = load_tally(path)
        self.assertEqual(loaded.skipped, 1)
        self.assertEqual(len(loaded.records), 1)
        self.assertEqual(loaded.records[0].job_card, "006908")
        self.assertEqual(loaded.records[0].voucher_type, "HiRise Invoice Service")


class SuppliedTracksheetTests(unittest.TestCase):
    def test_real_export_has_no_automatic_changes(self):
        track_path = Path(r"C:\Users\admin\Downloads\JobCards_2026-11-16_1127rows.xlsx")
        if not track_path.exists():
            self.skipTest("tracksheet export is not on this machine")
        from compare.load import load_tracksheet

        with tempfile.TemporaryDirectory() as folder:
            tally_path = Path(folder) / "tally.xlsx"
            write_sample(tally_path)
            loaded = load_tally(tally_path)
            result = compare(load_tracksheet(track_path), loaded.records)
        self.assertEqual(loaded.skipped, 2)
        self.assertEqual(result.track_rows, 1127)
        self.assertEqual(result.count(ADDED), 0)
        self.assertEqual(result.count(REMOVED), 0)
        self.assertGreaterEqual(result.count(CHECK), 32)
        self.assertEqual(result.uncovered_rows, 1057)


if __name__ == "__main__":
    unittest.main()
