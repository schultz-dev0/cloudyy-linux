import unittest
from datetime import datetime
from unittest import mock

from lib import region_time_core


class RegionTimeCoreTests(unittest.TestCase):
    def test_allowed_actions(self):
        self.assertIn("set_ntp", region_time_core.ALLOWED_ACTIONS)
        self.assertIn("set_timezone", region_time_core.ALLOWED_ACTIONS)
        self.assertIn("set_time", region_time_core.ALLOWED_ACTIONS)
        self.assertIn("apply_location", region_time_core.ALLOWED_ACTIONS)

    @mock.patch("lib.region_time_core.offline_geocode.data_available", return_value=True)
    @mock.patch("lib.region_time_core.geo.get_location", return_value=None)
    @mock.patch("lib.region_time_core.geo.read_static_geolocation", return_value=None)
    @mock.patch("lib.region_time_core.geo.is_manual_mode", return_value=False)
    @mock.patch("lib.region_time_core.geo.service_active", return_value=True)
    @mock.patch("lib.region_time_core.utility.load_setting", side_effect=lambda k, d="": d)
    @mock.patch("lib.region_time_core.dt.ensure_polkit_agent", return_value=True)
    @mock.patch("lib.region_time_core.dt.get_ntp_enabled", return_value=True)
    @mock.patch("lib.region_time_core.dt.get_timezone", return_value="Europe/London")
    @mock.patch(
        "lib.region_time_core.dt.get_status_text",
        return_value={
            "timezone": "Europe/London",
            "ntp_sync": "yes",
            "ntp_service": "active",
        },
    )
    @mock.patch(
        "lib.region_time_core.dt.format_local_clock",
        return_value="Thursday, 23 Jul 2026  16:00:00",
    )
    def test_snapshot_shape(self, *_mocks):
        snap = region_time_core.build_region_snapshot(include_location=False)
        self.assertTrue(snap["polkit_ready"])
        self.assertEqual(snap["timezone"], "Europe/London")
        self.assertTrue(snap["ntp_enabled"])
        self.assertTrue(snap["geo_active"])
        self.assertIn("clock", snap)
        self.assertIn("year", snap["clock"])

    def test_timezone_offsets(self):
        offsets = region_time_core.timezone_offsets(["UTC", "Europe/London"])
        self.assertIn("UTC", offsets)
        self.assertTrue(offsets["UTC"].startswith("UTC"))

    @mock.patch("lib.region_time_core.dt.ensure_polkit_agent", return_value=True)
    @mock.patch("lib.region_time_core.dt.set_ntp", return_value=(True, ""))
    def test_set_ntp_action(self, set_ntp, _polkit):
        result = region_time_core.run_region_action("set_ntp", True)
        self.assertTrue(result["ok"])
        set_ntp.assert_called_once_with(True)

    @mock.patch("lib.region_time_core.dt.ensure_polkit_agent", return_value=True)
    @mock.patch("lib.region_time_core.dt.get_ntp_enabled", return_value=True)
    def test_set_time_blocked_when_ntp_on(self, *_mocks):
        result = region_time_core.run_region_action("set_time", {
            "year": 2026, "month": 7, "day": 23, "hour": 12, "minute": 0,
        })
        self.assertFalse(result["ok"])
        self.assertIn("NTP", result["message"])

    @mock.patch("lib.region_time_core.dt.ensure_polkit_agent", return_value=True)
    @mock.patch("lib.region_time_core.dt.get_ntp_enabled", return_value=False)
    @mock.patch("lib.region_time_core.dt.get_timezone", return_value="UTC")
    @mock.patch("lib.region_time_core.dt.set_manual_time", return_value=(True, ""))
    def test_set_time_when_ntp_off(self, set_time, *_mocks):
        result = region_time_core.run_region_action("set_time", {
            "year": 2026, "month": 7, "day": 23, "hour": 12, "minute": 30,
        })
        self.assertTrue(result["ok"])
        args = set_time.call_args[0][0]
        self.assertIsInstance(args, datetime)
        self.assertEqual(args.hour, 12)
        self.assertEqual(args.minute, 30)

    def test_unknown_action(self):
        with self.assertRaisesRegex(ValueError, "unknown region action"):
            region_time_core.run_region_action("nope", None)


if __name__ == "__main__":
    unittest.main()
