// modules/controlcenter/tiles/BluetoothTile.qml
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

BaseTile {
    id: root

    icon:       "󰂯"
    label:      "Bluetooth"
    statusText: "Off"
    active:     false

    function refresh() {
        btProc.running = false
        btProc.running = true
    }

    onClicked: launchProc.running = true

    Process {
        id: btProc
        command: ["bash", "-c", "bluetoothctl show | awk '/Powered:/{print $2}'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const on = line.trim() === "yes"
                root.active     = on
                root.statusText = on ? "On" : "Off"
            }
        }
    }

    Process {
        id: launchProc
        command: ["bash", "-c", "cloud-center bluetooth"]
        running: false
    }

    Component.onCompleted: refresh()
}
