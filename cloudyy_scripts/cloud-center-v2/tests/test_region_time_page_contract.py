from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/RegionTimeEditor.qml"
STATE = REPO_ROOT / ".config/quickshell/cloud-center/components/RegionTimeState.js"
SHELL = REPO_ROOT / ".config/quickshell/cloud-center/shell.qml"
BACKEND = REPO_ROOT / ".config/quickshell/cloud-center/services/Backend.qml"


class RegionTimePageContractTests(unittest.TestCase):
    def test_files_exist(self):
        for path in (PAGE, STATE):
            self.assertTrue(path.is_file(), path)

    def test_page_uses_region_protocol(self):
        source = PAGE.read_text(encoding="utf-8")
        for method in (
            "get_region_snapshot",
            "get_region_timezones",
            "start_region_watch",
            "stop_region_watch",
            "run_region_action",
        ):
            self.assertIn(method, source)
        for signal in ("onRegionSnapshotEvent", "onRegionActionDoneEvent"):
            self.assertIn(signal, source)
        self.assertIn("Date & Time", source)
        self.assertIn("Timezone", source)
        self.assertIn("Manual Date & Time", source)
        self.assertIn("Location", source)
        self.assertIn("set_ntp", source)
        self.assertIn("set_timezone", source)
        self.assertIn("set_time", source)
        self.assertIn("apply_location", source)

    def test_shell_and_backend_wire_region(self):
        shell = SHELL.read_text(encoding="utf-8")
        backend = BACKEND.read_text(encoding="utf-8")
        self.assertIn('page.kind === "region"', shell)
        self.assertIn("RegionTimeEditor", shell)
        self.assertIn("regionSnapshotEvent", backend)
        self.assertIn('case "region_snapshot"', backend)


if __name__ == "__main__":
    unittest.main()
