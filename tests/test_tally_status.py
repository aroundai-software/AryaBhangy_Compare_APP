import unittest
from unittest import mock

from compare import tally_gateway, tracksheet_site
from compare.tally_gateway import current_company, tally_status


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

    def test_tally_port_stays_on_this_computer(self):
        tally_gateway.apply_tally_port("9001")
        self.assertEqual(tally_gateway.GATEWAY, "http://127.0.0.1:9001")
        with self.assertRaises(ValueError):
            tally_gateway.apply_tally_port("0")

    def test_practice_website_is_used_for_job_cards(self):
        tracksheet_site.apply_website("http://127.0.0.1:8765/")
        self.assertEqual(tracksheet_site.SITE, "http://127.0.0.1:8765")
        self.assertEqual(tracksheet_site.DATABASE, "http://127.0.0.1:8765")
        self.assertTrue(tracksheet_site.is_practice_site())

    def test_live_website_keeps_the_job_card_host(self):
        tracksheet_site.apply_website("https://track.aryabhangymotors.com")
        self.assertEqual(tracksheet_site.SITE, tracksheet_site.LIVE_SITE)
        self.assertEqual(tracksheet_site.DATABASE, tracksheet_site.LIVE_DATABASE)
        self.assertFalse(tracksheet_site.is_practice_site())


if __name__ == "__main__":
    unittest.main()
