import tempfile
import unittest
from pathlib import Path
from unittest import mock

from lib import battery_core


class BatteryCoreTests(unittest.TestCase):
    def test_absent_snapshot_reports_no_battery(self):
        missing = Path("/tmp/cloudyy-no-bat-does-not-exist")
        snap = battery_core.build_battery_snapshot(
            bat_path=missing, upower=False,
        )
        self.assertFalse(snap["present"])
        self.assertFalse(snap["capabilities"]["threshold"])
        self.assertIsNone(snap["info"])

    def test_present_snapshot_reads_sysfs(self):
        with tempfile.TemporaryDirectory() as tmp:
            bat = Path(tmp) / "BAT0"
            bat.mkdir()
            (bat / "capacity").write_text("72\n")
            (bat / "status").write_text("Discharging\n")
            (bat / "voltage_now").write_text("12000000\n")
            (bat / "current_now").write_text("1000000\n")
            (bat / "charge_full").write_text("5000000\n")
            (bat / "charge_full_design").write_text("5500000\n")
            (bat / "cycle_count").write_text("312\n")
            (bat / "manufacturer").write_text("SMP\n")
            (bat / "model_name").write_text("C41\n")
            (bat / "technology").write_text("Li-ion\n")
            (bat / "serial_number").write_text("ABC\n")
            snap = battery_core.build_battery_snapshot(
                bat_path=bat,
                threshold_path=bat / "missing_threshold",
                asus_path=bat / "missing_asus",
                upower=False,
            )
            self.assertTrue(snap["present"])
            self.assertEqual(snap["info"]["percentage"], 72)
            self.assertEqual(snap["display"]["percentage_label"], "72%")
            self.assertIn("Health", snap["display"]["health_label"] + "Health")
            self.assertAlmostEqual(snap["info"]["health_pct"], 5000000 / 5500000 * 100)

    def test_set_threshold_writes_and_validates(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "charge_control_end_threshold"
            path.write_text("100\n")
            result = battery_core.set_charge_threshold(80, threshold_path=path)
            self.assertTrue(result["ok"])
            self.assertEqual(path.read_text().strip(), "80")
            with self.assertRaisesRegex(ValueError, "between 40 and 100"):
                battery_core.set_charge_threshold(20, threshold_path=path)

    def test_set_charge_mode_writes(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "charge_mode"
            path.write_text("0\n")
            result = battery_core.set_charge_mode(2, asus_path=path)
            self.assertTrue(result["ok"])
            self.assertEqual(path.read_text().strip(), "2")
            self.assertIn("Battery Care", result["message"])


if __name__ == "__main__":
    unittest.main()
