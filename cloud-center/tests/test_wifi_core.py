import importlib
import json
import sys
import unittest
from unittest import mock


MULTILINE_LIST = """\
SSID: Campus
BSSID: AA:BB:CC:DD:EE:01
SIGNAL: 40
SECURITY: WPA2 802.1X
ACTIVE: no
FREQ: 2437 MHz
SSID: Home
BSSID: 11:22:33:44:55:66
SIGNAL: 70
SECURITY: WPA2
ACTIVE: yes
FREQ: 5180 MHz
SSID: Campus
BSSID: AA:BB:CC:DD:EE:02
SIGNAL: 88
SECURITY: WPA2 802.1X
ACTIVE: no
FREQ: 5500 MHz
SSID: OpenCafe
BSSID: DE:AD:BE:EF:00:01
SIGNAL: 55
SECURITY: --
ACTIVE: no
FREQ: 2412 MHz
SSID: --
BSSID: 00:00:00:00:00:00
SIGNAL: 10
SECURITY: WPA2
ACTIVE: no
FREQ: 2412 MHz
"""


class WifiCoreTests(unittest.TestCase):
    def test_import_does_not_load_gtk(self):
        sys.modules.pop("lib.wifi_core", None)
        before = set(sys.modules)
        importlib.import_module("lib.wifi_core")
        loaded = set(sys.modules) - before
        self.assertFalse(any(name == "gi" or name.startswith("gi.") for name in loaded))

    def test_parse_network_list_dedupes_by_strongest_and_sorts(self):
        from lib import wifi_core

        networks = wifi_core.parse_network_list(MULTILINE_LIST)
        self.assertEqual([n.ssid for n in networks], ["Home", "Campus", "OpenCafe"])
        campus = networks[1]
        self.assertEqual(campus.signal, 88)
        self.assertEqual(campus.bssid, "AA:BB:CC:DD:EE:02")
        self.assertTrue(campus.is_enterprise)
        self.assertTrue(networks[0].connected)
        self.assertTrue(networks[2].is_open)

    def test_parse_marks_saved_connections(self):
        from lib import wifi_core

        networks = wifi_core.parse_network_list(MULTILINE_LIST)
        wifi_core.apply_saved_flags(networks, "Home\nGuest\n")
        self.assertTrue(networks[0].saved)
        self.assertFalse(networks[1].saved)

    def test_snapshot_is_json_serializable(self):
        from lib import wifi_core

        network = wifi_core.WifiNetwork(
            ssid="Home", bssid="11:22:33:44:55:66", signal=70,
            security="WPA2", connected=True, saved=True, frequency="5180 MHz",
        )
        with mock.patch.object(wifi_core, "get_wifi_enabled", return_value=True), \
             mock.patch.object(wifi_core, "get_active_ssid", return_value="Home"), \
             mock.patch.object(wifi_core, "list_networks", return_value=[network]), \
             mock.patch.object(wifi_core, "get_wifi_device", return_value="wlan0"):
            snapshot = wifi_core.build_wifi_snapshot()
        json.dumps(snapshot)
        self.assertTrue(snapshot["enabled"])
        self.assertEqual(snapshot["active_ssid"], "Home")
        self.assertEqual(snapshot["device"], "wlan0")
        self.assertEqual(snapshot["networks"][0]["ssid"], "Home")
        self.assertTrue(snapshot["networks"][0]["is_open"] is False)
        self.assertIn("signal_icon", snapshot["networks"][0])

    def test_unknown_action_is_rejected(self):
        from lib import wifi_core

        with self.assertRaisesRegex(ValueError, "unknown wifi action"):
            wifi_core.execute_wifi_action("shell", "target", "rm -rf /")

    def test_set_radio_and_connect_dispatch(self):
        from lib import wifi_core

        with mock.patch.object(wifi_core, "set_wifi_enabled", return_value=True) as radio, \
             mock.patch.object(wifi_core, "connect_network", return_value=(True, "")) as connect, \
             mock.patch.object(
                 wifi_core, "connect_enterprise_network", return_value=(True, ""),
             ) as enterprise:
            wifi_core.execute_wifi_action("set_radio", "wifi", True)
            wifi_core.execute_wifi_action("connect", "Home", "secret")
            wifi_core.execute_wifi_action(
                "connect_enterprise", "Campus",
                {"identity": "user@edu", "password": "secret"},
            )
        radio.assert_called_once_with(True)
        connect.assert_called_once_with("Home", "secret")
        enterprise.assert_called_once_with("Campus", "user@edu", "secret")

    def test_connect_enterprise_requires_identity_and_password(self):
        from lib import wifi_core

        with self.assertRaisesRegex(ValueError, "identity"):
            wifi_core.execute_wifi_action(
                "connect_enterprise", "Campus", {"password": "x"},
            )
        with self.assertRaisesRegex(ValueError, "password"):
            wifi_core.execute_wifi_action(
                "connect_enterprise", "Campus", {"identity": "user"},
            )


if __name__ == "__main__":
    unittest.main()
