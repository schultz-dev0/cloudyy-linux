pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/BluetoothTile.qml — launcher cell into Cloud Center.
import QtQuick
import Quickshell.Io
import "../../.."

BaseTile {
    id: root

    function refresh() {
        btProc.running = false;
        btProc.running = true;
    }

    icon:  "󰂯"
    label: "Bluetooth"

    onClicked: launchProc.running = true

    Process {
        id: btProc
        command: ["bash", "-c", "bluetoothctl show | awk '/Powered:/{print $2}'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.active = line.trim() === "yes"
        }
    }

    Process { id: launchProc; command: ["cloudyy-center", "bluetooth"] }

    Component.onCompleted: refresh()
}
