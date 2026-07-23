from pathlib import Path
import unittest


REPO_ROOT = Path(__file__).resolve().parents[3]
PAGE = REPO_ROOT / ".config/quickshell/cloud-center/pages/BluetoothEditor.qml"
PANEL = REPO_ROOT / ".config/quickshell/cloud-center/components/BluetoothDevicePanel.qml"
ROW = REPO_ROOT / ".config/quickshell/cloud-center/components/BluetoothDeviceRow.qml"
STATE = REPO_ROOT / ".config/quickshell/cloud-center/components/BluetoothState.js"


class BluetoothPageContractTests(unittest.TestCase):
    def test_bluetooth_qml_files_exist(self):
        for path in (PAGE, PANEL, ROW, STATE):
            self.assertTrue(path.is_file(), path)

    def test_native_page_uses_bluetooth_snapshot_lifecycle_and_events(self):
        source = PAGE.read_text(encoding="utf-8")
        for method in (
            "get_bluetooth_snapshot",
            "start_bluetooth_watch",
            "stop_bluetooth_watch",
            "run_bluetooth_action",
        ):
            self.assertIn(method, source)
        for signal in (
            "onBluetoothSnapshotEvent",
            "onBluetoothActionDoneEvent",
        ):
            self.assertIn(signal, source)
        for fragment in (
            "function allocateGeneration()",
            "function handleActionReply(actionId, result)",
            "function handleActionError(actionId, error)",
            "function rejectAction(actionId, staleTarget, message)",
            "generation: actionGeneration",
            "actions[String(actionId)] = true",
            "delete actions[String(actionId)]",
            "Component.onDestruction: S.Backend.request(\"stop_bluetooth_watch\"",
        ):
            self.assertIn(fragment, source)

    def test_page_actions_are_fixed_allowlist(self):
        source = PAGE.read_text(encoding="utf-8")
        panel = PANEL.read_text(encoding="utf-8")
        for action in (
            '"set_power"',
            '"start_scan"',
            '"connect"',
            '"disconnect"',
            '"remove"',
            '"trust"',
        ):
            self.assertTrue(
                action in source or action in panel,
                f"missing fixed action {action}",
            )
        combined = source + panel
        self.assertNotIn("bluetoothctl", combined)
        self.assertNotIn("rm -rf", combined)
        self.assertNotIn("subprocess", combined)

    def test_page_has_parity_controls_and_newbie_copy(self):
        source = PAGE.read_text(encoding="utf-8")
        panel = PANEL.read_text(encoding="utf-8")
        state = STATE.read_text(encoding="utf-8")
        for fragment in (
            'text: "Scan"',
            'text: "Refresh"',
            'text: "Bluetooth"',
            "CloudSwitch",
            "Turn Bluetooth on to see devices",
            "No devices found — try Scan",
            "Scanning for nearby devices",
        ):
            self.assertTrue(
                fragment in source or fragment in state,
                f"missing copy/control {fragment}",
            )
        for fragment in (
            'text: "Auto-connect"',
            "CloudSwitch",
            "Right-click or press Enter",
            "Select a device for details",
        ):
            self.assertIn(fragment, panel)
        source = PAGE.read_text(encoding="utf-8")
        for fragment in (
            "openDeviceMenu",
            "deviceActionOptions",
            "runDeviceAction",
            "toggleDeviceConnection",
            "Qt.Key_Return",
            "Qt.RightButton",
            "contextMenuRequested",
            "doubleClicked",
            'label: "Connect"',
            'label: "Disconnect"',
            'label: "Remove"',
        ):
            self.assertTrue(
                fragment in source or fragment in ROW.read_text(encoding="utf-8")
                or fragment in PANEL.read_text(encoding="utf-8")
                or fragment in (
                    Path(__file__).resolve().parents[3]
                    / ".config/quickshell/cloud-center/components/SelectableRow.qml"
                ).read_text(encoding="utf-8"),
                f"missing interaction {fragment}",
            )

    def test_device_panel_and_row_use_state_helpers(self):
        panel = PANEL.read_text(encoding="utf-8")
        row = ROW.read_text(encoding="utf-8")
        state = STATE.read_text(encoding="utf-8")
        self.assertIn("BluetoothState.js", panel)
        self.assertIn("BluetoothState.js", row)
        self.assertIn("BluetoothState.js", PAGE.read_text(encoding="utf-8"))
        for helper in (
            "function sortDevices",
            "function stableSelection",
            "function statusSummary",
            "function emptyListMessage",
            "function deviceSubtitle",
            "function setPending",
            "function clearCompleted",
        ):
            self.assertIn(helper, state)

    def test_master_detail_section_layout(self):
        source = PAGE.read_text(encoding="utf-8")
        for fragment in (
            'section: ({ title: "Adapter" })',
            'section: ({ title: "Devices" })',
            'section: ({ title: "Details" })',
            "BluetoothDeviceRow",
            "BluetoothDevicePanel",
        ):
            self.assertIn(fragment, source)


if __name__ == "__main__":
    unittest.main()
