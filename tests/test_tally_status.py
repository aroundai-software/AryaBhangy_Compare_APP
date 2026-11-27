import unittest
from datetime import date
from unittest import mock

from compare import tally_gateway, tracksheet_site
from compare.tally_gateway import current_company, hirise_vouchers, tally_status


def _company_envelope(result_text):
    return (
        "<ENVELOPE><HEADER><STATUS>1</STATUS></HEADER>"
        f"<BODY><DESC><RESULT>{result_text}</RESULT></DESC></BODY></ENVELOPE>"
    )


class TallyStatusTests(unittest.TestCase):
    def test_offline_when_gateway_does_not_answer(self):
        with mock.patch("compare.tally_gateway._post", side_effect=OSError("refused")):
            status = tally_status(timeout=1)
        self.assertEqual(status, {"online": False, "name": "", "period": None})

    def test_online_with_no_company_when_result_is_empty(self):
        with mock.patch(
            "compare.tally_gateway._post",
            return_value=_company_envelope(""),
        ):
            with mock.patch(
                "compare.tally_gateway.current_period",
                side_effect=RuntimeError("no period"),
            ):
                status = tally_status(timeout=1)
        self.assertTrue(status["online"])
        self.assertEqual(status["name"], "")
        self.assertIsNone(status["period"])

    def test_online_with_no_company_when_tally_returns_error(self):
        body = "<ERRORMSG>Could not find company</ERRORMSG>"
        with mock.patch("compare.tally_gateway._post", return_value=body):
            with mock.patch(
                "compare.tally_gateway.current_period",
                side_effect=RuntimeError("no period"),
            ):
                status = tally_status(timeout=1)
        self.assertTrue(status["online"])
        self.assertEqual(status["name"], "")

    def test_online_with_company_name(self):
        name = "Arya Bhangy Motors, Aluva - (2025-2026)"
        with mock.patch(
            "compare.tally_gateway._post",
            return_value=_company_envelope(name),
        ):
            with mock.patch(
                "compare.tally_gateway.current_period",
                return_value=None,
            ):
                status = tally_status(timeout=1)
        self.assertTrue(status["online"])
        self.assertEqual(status["name"], name)

    def test_current_company_raises_when_offline(self):
        with mock.patch(
            "compare.tally_gateway.tally_status",
            return_value={"online": False, "name": "", "period": None},
        ):
            with self.assertRaises(RuntimeError):
                current_company(timeout=1)

    def test_current_company_returns_empty_when_online_without_company(self):
        with mock.patch(
            "compare.tally_gateway.tally_status",
            return_value={"online": True, "name": "", "period": None},
        ):
            self.assertEqual(current_company(timeout=1), "")


class ConnectionSettingTests(unittest.TestCase):
    def tearDown(self):
        tally_gateway.GATEWAY = "http://127.0.0.1:9000"
        tracksheet_site.SITE = tracksheet_site.LIVE_SITE
        tracksheet_site.DATABASE = tracksheet_site.LIVE_DATABASE
        tracksheet_site._demo_confirmed = False
        tracksheet_site.LIVE_WRITE_TOKEN = ""

    def test_tally_port_stays_on_this_computer(self):
        tally_gateway.apply_tally_port("9001")
        self.assertEqual(tally_gateway.GATEWAY, "http://127.0.0.1:9001")
        with self.assertRaises(ValueError):
            tally_gateway.apply_tally_port("0")

    def test_this_computer_is_not_a_tracksheet(self):
        tracksheet_site.apply_website("http://127.0.0.1:8765/")
        self.assertTrue(tracksheet_site.is_practice_site())
        self.assertFalse(tracksheet_site.can_save_site())
        self.assertFalse(tracksheet_site.confirm_site())
        with self.assertRaises(tracksheet_site.SiteError) as caught:
            tracksheet_site.job_cards(date(2026, 11, 1), date(2026, 11, 1))
        self.assertIn("demo", str(caught.exception).lower())

    def test_live_website_keeps_the_job_card_host(self):
        tracksheet_site.apply_website("https://track.aryabhangymotors.com")
        self.assertEqual(tracksheet_site.SITE, tracksheet_site.LIVE_SITE)
        self.assertEqual(tracksheet_site.DATABASE, tracksheet_site.LIVE_DATABASE)
        self.assertFalse(tracksheet_site.is_practice_site())
        self.assertFalse(tracksheet_site.confirm_site())
        with self.assertRaises(tracksheet_site.SiteError) as caught:
            tracksheet_site.write_practice_cards([{"job_card": "002236"}])
        self.assertIn("original", str(caught.exception).lower())

    def test_hosted_demo_token_points_reads_and_writes_at_that_site(self):
        with mock.patch(
            "compare.tracksheet_site._token",
            return_value=tracksheet_site.DEMO_TOKEN,
        ):
            tracksheet_site.apply_website("https://demo.example.com/job-cards")
            self.assertTrue(tracksheet_site.confirm_site())
        self.assertEqual(tracksheet_site.SITE, "https://demo.example.com")
        self.assertEqual(tracksheet_site.DATABASE, "https://demo.example.com")
        self.assertTrue(tracksheet_site.can_save_site())
        self.assertFalse(tracksheet_site.is_practice_site())

        class _Response:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def read(self):
                return b'{"updated": 1, "results": []}'

        with mock.patch(
            "compare.tracksheet_site.urllib.request.urlopen",
            return_value=_Response(),
        ) as opened:
            body = tracksheet_site.write_practice_cards([{"job_card": "002236"}])
        self.assertEqual(body["updated"], 1)
        request = opened.call_args.args[0]
        self.assertEqual(request.full_url, "https://demo.example.com/api/local/fill")

    def test_original_write_updates_the_read_row(self):
        tracksheet_site.LIVE_WRITE_TOKEN = "test-write-token"
        tracksheet_site.apply_website("https://track.aryabhangymotors.com")
        self.assertTrue(tracksheet_site.confirm_site())
        self.assertTrue(tracksheet_site.can_save_site())

        class _Response:
            def __enter__(self):
                return self

            def __exit__(self, exc_type, exc, tb):
                return False

            def read(self):
                return b"{}"

        with mock.patch(
            "compare.tracksheet_site.urllib.request.urlopen",
            return_value=_Response(),
        ) as opened:
            body = tracksheet_site.write_practice_cards(
                [
                    {
                        "job_card": "002236",
                        "sheet_row_id": 42,
                        "bill": "2002",
                        "labour": "10",
                        "spares": "20",
                        "total": "30",
                        "vas": "Chain Lube",
                        "items": "OIL",
                    }
                ]
            )
        self.assertEqual(body["updated"], 1)
        request = opened.call_args.args[0]
        self.assertIn("/api/database/rows/table/561/42/", request.full_url)
        self.assertNotIn("/api/local/fill", request.full_url)
        self.assertEqual(request.get_method(), "PATCH")
        self.assertEqual(request.get_header("Authorization"), "Token test-write-token")
        sent = request.data.decode("utf-8")
        self.assertIn('"Bill Number": "2002"', sent)
        self.assertIn('"Bill Amount": "30"', sent)

    def test_original_write_without_a_row_does_not_call_the_site(self):
        tracksheet_site.LIVE_WRITE_TOKEN = "test-write-token"
        tracksheet_site.apply_website("https://tracksheet.aryabhangymotors.com")
        with mock.patch("compare.tracksheet_site.urllib.request.urlopen") as opened:
            body = tracksheet_site.write_practice_cards([{"job_card": "002236"}])
        opened.assert_not_called()
        self.assertEqual(body["updated"], 0)
        self.assertFalse(body["results"][0]["ok"])

    def test_other_website_token_does_not_become_writable(self):
        with mock.patch("compare.tracksheet_site._token", return_value="someone-else"):
            tracksheet_site.apply_website("https://example.com")
            self.assertFalse(tracksheet_site.confirm_site())
        self.assertEqual(tracksheet_site.DATABASE, tracksheet_site.LIVE_DATABASE)
        self.assertFalse(tracksheet_site.can_save_site())
        tracksheet_site.LIVE_WRITE_TOKEN = "test-write-token"
        with self.assertRaises(tracksheet_site.SiteError):
            tracksheet_site.write_practice_cards(
                [{"job_card": "002236", "sheet_row_id": 9}]
            )


class TallyExportTests(unittest.TestCase):
    def test_a_slow_day_does_not_ask_for_the_next_day(self):
        calls = []

        def one_day(day, timeout=8, voucher_types=None):
            calls.append(day)
            if day == date(2026, 10, 2):
                raise TimeoutError("timed out")
            return []

        with mock.patch("compare.tally_gateway.hirise_on_day", side_effect=one_day):
            with self.assertRaises(RuntimeError) as caught:
                hirise_vouchers(date(2026, 10, 1), date(2026, 10, 3))
        self.assertIn("still reading", str(caught.exception))
        self.assertEqual(calls, [date(2026, 10, 1), date(2026, 10, 2)])


if __name__ == "__main__":
    unittest.main()
