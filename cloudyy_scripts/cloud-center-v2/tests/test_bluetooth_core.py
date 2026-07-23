import importlib
import json
import sys
import unittest
from unittest import mock


class BluetoothCoreTests(unittest.TestCase):
    def test_import_does_not_load_gtk(self):
        sys.modules.pop("lib.bluetooth_core", None)
        before = set(sys.modules)
        importlib.import_module("lib.bluetooth_core")
        loaded = set(sys.modules) - before
        self.assertFalse(any(name == "gi" or name.startswith("gi.") for name in loaded))

    def test_parse_device_list_lines(self):
        from lib import bluetooth_core

        lines = bluetooth_core.parse_device_list(
            "Device AA:BB:CC:DD:EE:FF Headphones\n"
            "Device 11:22:33:44:55:66 Phone Name\n"
            "noise\n"
        )
        self.assertEqual(
            lines,
            [
                ("AA:BB:CC:DD:EE:FF", "Headphones"),
                ("11:22:33:44:55:66", "Phone Name"),
            ],
        )

    def test_parse_paired_addresses(self):
        from lib import bluetooth_core

        addrs = bluetooth_core.parse_paired_addresses(
            "Device AA:BB:CC:DD:EE:FF Headphones\nDevice 00:11:22:33:44:55 Other\n"
        )
        self.assertEqual(addrs, {"AA:BB:CC:DD:EE:FF", "00:11:22:33:44:55"})

    def test_parse_device_info(self):
        from lib import bluetooth_core

        info = bluetooth_core.parse_device_info(
            "Device AA:BB:CC:DD:EE:FF (public)\n"
            "\tName: Buds\n"
            "\tConnected: yes\n"
            "\tPaired: yes\n"
            "\tTrusted: no\n"
            "\tIcon: audio-headset\n"
        )
        self.assertTrue(info["connected"])
        self.assertTrue(info["paired"])
        self.assertFalse(info["trusted"])
        self.assertEqual(info["device_type"], "audio-headset")

    def test_devices_sort_connected_then_paired_then_name(self):
        from lib import bluetooth_core

        devices = [
            bluetooth_core.BluetoothDevice("A1", "Zebra", paired=True),
            bluetooth_core.BluetoothDevice("A2", "Alpha", connected=True, paired=True),
            bluetooth_core.BluetoothDevice("A3", "beta", paired=False),
            bluetooth_core.BluetoothDevice("A4", "Apple", paired=True),
        ]
        ordered = bluetooth_core.sort_devices(devices)
        self.assertEqual([d.name for d in ordered], ["Alpha", "Apple", "Zebra", "beta"])

    def test_snapshot_is_json_serializable(self):
        from lib import bluetooth_core

        device = bluetooth_core.BluetoothDevice(
            "AA:BB:CC:DD:EE:FF", "Buds",
            paired=True, connected=True, trusted=True, device_type="audio-headset",
        )
        with mock.patch.object(bluetooth_core, "get_bt_powered", return_value=True), \
             mock.patch.object(bluetooth_core, "get_devices", return_value=[device]):
            snapshot = bluetooth_core.build_bluetooth_snapshot(scanning=False)
        json.dumps(snapshot)
        self.assertTrue(snapshot["powered"])
        self.assertFalse(snapshot["scanning"])
        self.assertEqual(snapshot["devices"][0]["address"], "AA:BB:CC:DD:EE:FF")
        self.assertEqual(snapshot["devices"][0]["display_name"], "Buds")
        self.assertEqual(snapshot["devices"][0]["icon"], "audio-headset-symbolic")

    def test_snapshot_clears_devices_when_powered_off(self):
        from lib import bluetooth_core

        with mock.patch.object(bluetooth_core, "get_bt_powered", return_value=False), \
             mock.patch.object(bluetooth_core, "get_devices") as getter:
            snapshot = bluetooth_core.build_bluetooth_snapshot()
        getter.assert_not_called()
        self.assertFalse(snapshot["powered"])
        self.assertEqual(snapshot["devices"], [])

    def test_unknown_action_is_rejected(self):
        from lib import bluetooth_core

        with self.assertRaisesRegex(ValueError, "unknown bluetooth action"):
            bluetooth_core.execute_bluetooth_action("shell", "target", "rm -rf /")

    def test_connect_uses_fixed_argv(self):
        from lib import bluetooth_core

        with mock.patch.object(
            bluetooth_core, "_run_bt", return_value=(True, "ok"),
        ) as runner:
            ok, _ = bluetooth_core.execute_bluetooth_action(
                "connect", "AA:BB:CC:DD:EE:FF", None,
            )
        self.assertTrue(ok)
        runner.assert_called_once_with(["connect", "AA:BB:CC:DD:EE:FF"], timeout=18)

    def test_set_power_and_trust_dispatch(self):
        from lib import bluetooth_core

        with mock.patch.object(bluetooth_core, "set_bt_power", return_value=True) as power, \
             mock.patch.object(
                 bluetooth_core, "trust_device", return_value=(True, ""),
             ) as trust:
            bluetooth_core.execute_bluetooth_action("set_power", "adapter", True)
            bluetooth_core.execute_bluetooth_action(
                "trust", "AA:BB:CC:DD:EE:FF", False,
            )
        power.assert_called_once_with(True)
        trust.assert_called_once_with("AA:BB:CC:DD:EE:FF", False)

    def test_icon_for_type_has_defaults(self):
        from lib import bluetooth_core

        self.assertEqual(
            bluetooth_core.icon_for_type("audio-headset"),
            "audio-headset-symbolic",
        )
        self.assertEqual(
            bluetooth_core.icon_for_type("mystery"),
            "bluetooth-active-symbolic",
        )


if __name__ == "__main__":
    unittest.main()
