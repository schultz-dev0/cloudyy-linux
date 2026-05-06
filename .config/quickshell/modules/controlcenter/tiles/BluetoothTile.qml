// modules/controlcenter/tiles/BluetoothTile.qml
import QtQuick
import Quickshell
import Quickshell.Io

BaseTile {
    id: root

    icon:       "󰂯"
    label:      "Bluetooth"
    statusText: "Off"
    active:     false

    onClicked: launchProc.running = true

    function refresh() {
        btProc.running = false
        btProc.running = true
    }

    Component.onCompleted: refresh()

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
        command: ["cloud-center", "bluetooth"]
        running: false
    }
}
