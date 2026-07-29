from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/BatteryEditor.qml"
STATE = REPO_ROOT / ".config/quickshell/cloud-center/components/BatteryState.js"
SHELL = REPO_ROOT / ".config/quickshell/cloud-center/shell.qml"
BACKEND = REPO_ROOT / ".config/quickshell/cloud-center/services/Backend.qml"


class BatteryPageContractTests(unittest.TestCase):
    def test_files_exist(self):
        for path in (PAGE, STATE):
            self.assertTrue(path.is_file(), path)

    def test_page_uses_battery_protocol(self):
        source = PAGE.read_text(encoding="utf-8")
        for method in (
            "get_battery_snapshot",
            "start_battery_watch",
            "stop_battery_watch",
            "run_battery_action",
        ):
            self.assertIn(method, source)
        for signal in ("onBatterySnapshotEvent", "onBatteryActionDoneEvent"):
            self.assertIn(signal, source)
        self.assertIn("No battery", source)
        self.assertIn("Battery Status", source)
        self.assertIn("Battery Health", source)
        self.assertIn("Device Information", source)
        self.assertIn("set_threshold", source)
        self.assertIn("set_charge_mode", source)

    def test_shell_and_backend_wire_battery(self):
        shell = SHELL.read_text(encoding="utf-8")
        backend = BACKEND.read_text(encoding="utf-8")
        self.assertIn('page.kind === "battery"', shell)
        self.assertIn("BatteryEditor", shell)
        self.assertIn("batterySnapshotEvent", backend)
        self.assertIn('case "battery_snapshot"', backend)


if __name__ == "__main__":
    unittest.main()
