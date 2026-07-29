from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[2]
COMPONENTS = REPO_ROOT / ".config/quickshell/cloud-center/components"
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/WifiEditor.qml"
STATE = COMPONENTS / "WifiState.js"
ROW = COMPONENTS / "WifiNetworkRow.qml"
PANEL = COMPONENTS / "WifiDetailPanel.qml"
PASSWORD = COMPONENTS / "WifiPasswordDialog.qml"


class WifiPageContractTests(unittest.TestCase):
    def test_wifi_qml_files_exist(self):
        for path in (PAGE, STATE, ROW, PANEL, PASSWORD):
            self.assertTrue(path.is_file(), path)

    def test_page_uses_fixed_wifi_protocol_surface(self):
        source = PAGE.read_text(encoding="utf-8")
        for method in (
            "get_wifi_snapshot",
            "start_wifi_watch",
            "stop_wifi_watch",
            "run_wifi_action",
        ):
            self.assertIn(method, source)
        for signal in ("onWifiSnapshotEvent", "onWifiActionDoneEvent"):
            self.assertIn(signal, source)
        for action in (
            '"set_radio"',
            '"rescan"',
            '"connect"',
            '"connect_enterprise"',
            '"disconnect"',
            '"forget"',
        ):
            self.assertIn(action, source)
        self.assertNotIn("nmcli", source)
        # Never accept frontend-provided shell strings.
        self.assertNotIn("exec(", source)
        self.assertNotIn("Process {", source)

    def test_page_correlates_actions_and_lifecycle(self):
        source = PAGE.read_text(encoding="utf-8")
        for fragment in (
            "function allocateGeneration()",
            "function handleActionReply(actionId, result)",
            "function handleActionError(actionId, error)",
            "function rejectAction(actionId, staleTarget, message)",
            "function finishAction(actionId, target, generation, ok, staleTarget, message)",
            "Component.onCompleted",
            "Component.onDestruction",
            "stop_wifi_watch",
            "generation: actionGeneration",
        ):
            self.assertIn(fragment, source)

    def test_password_dialog_supports_psk_and_enterprise(self):
        source = PASSWORD.read_text(encoding="utf-8")
        for fragment in (
            "property bool enterprise",
            "property string identity",
            "property string password",
            "echoMode",
            "TextInput.Password",
            "user@university.edu",
            "function openFor(network, prefillIdentity)",
            "signal submitted(string ssid, string identity, string password)",
        ):
            self.assertIn(fragment, source)

    def test_detail_and_row_use_newbie_friendly_copy(self):
        panel = PANEL.read_text(encoding="utf-8")
        row = ROW.read_text(encoding="utf-8")
        page = PAGE.read_text(encoding="utf-8")
        state = STATE.read_text(encoding="utf-8")
        for fragment in (
            "Select a network",
            'text: "Disconnect"',
            'text: "Connect"',
            'text: "Forget"',
            "CloudButton",
        ):
            self.assertIn(fragment, panel)
        self.assertIn("WifiState.networkSubtitle", row)
        self.assertIn("SelectableRow", row)
        for fragment in (
            "Turn Wi-Fi on to see nearby networks",
            "No networks found — try Rescan",
            "Wi-Fi is turned off",
            "Open network",
        ):
            self.assertIn(fragment, state)
        self.assertIn("Search networks", page)
        self.assertIn("Rescan", page)
        self.assertIn("CloudSwitch", page)
        # Stacked layout — no side-by-side master/detail Row.
        self.assertNotIn("parent.width - 354", page)
        self.assertIn('section: ({ title: "Networks" })', page)
        self.assertIn('section: ({ title: "Details" })', page)


if __name__ == "__main__":
    unittest.main()
