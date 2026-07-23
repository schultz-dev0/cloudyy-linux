import QtQuick
import QtTest
import "../../../../.config/quickshell/cloud-center/components/BluetoothState.js" as BluetoothState

TestCase {
    name: "BluetoothState"

    function test_sort_devices_connected_then_paired_then_name() {
        const devices = [
            { address: "1", display_name: "Zebra", paired: true, connected: false },
            { address: "2", display_name: "Alpha", paired: true, connected: true },
            { address: "3", display_name: "beta", paired: false, connected: false },
            { address: "4", display_name: "Apple", paired: true, connected: false },
        ];
        const ordered = BluetoothState.sortDevices(devices);
        compare(ordered.map(item => item.display_name), ["Alpha", "Apple", "Zebra", "beta"]);
    }

    function test_stable_selection_prefers_existing_then_connected() {
        const devices = [
            { address: "one", connected: false },
            { address: "two", connected: true },
        ];
        compare(BluetoothState.stableSelection(devices, "one", "address"), "one");
        compare(BluetoothState.stableSelection(devices, "missing", "address"), "two");
    }

    function test_stale_completion_does_not_clear_newer_pending_value() {
        const pending = { "device:aa:trusted": { generation: 4, value: true } };
        compare(BluetoothState.clearCompleted(pending, "device:aa:trusted", 3)["device:aa:trusted"].value, true);
        verify(BluetoothState.clearCompleted(pending, "device:aa:trusted", 4)["device:aa:trusted"] === undefined);
    }

    function test_status_and_empty_copy() {
        compare(BluetoothState.statusSummary({ powered: false }), "Bluetooth is off");
        compare(
            BluetoothState.statusSummary({ powered: true, scanning: true, devices: [] }),
            "Scanning for nearby devices…"
        );
        compare(
            BluetoothState.emptyListMessage({ powered: false }),
            "Turn Bluetooth on to see devices"
        );
        compare(
            BluetoothState.emptyListMessage({ powered: true, scanning: false, devices: [] }),
            "No devices found — try Scan"
        );
    }

    function test_device_subtitle() {
        compare(
            BluetoothState.deviceSubtitle({ connected: true, device_type: "phone" }),
            "Connected · phone"
        );
        compare(
            BluetoothState.deviceSubtitle({ paired: true, connected: false }),
            "Paired"
        );
        compare(
            BluetoothState.deviceSubtitle({ paired: false, connected: false }),
            "Available"
        );
    }
}
