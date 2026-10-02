pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/WifiTile.qml — launcher cell; SSID lives in
// nm-connection-editor, one click away (VISUAL-LANGUAGE.md §7).
import QtQuick
import Quickshell.Io
import "../../.."

BaseTile {
    id: root

    function refresh() {
        wifiProc.running = false;
        wifiProc.running = true;
    }

    icon:    active ? "󰖩" : "󰖪"
    iconDim: !active
    label:   "Wi-Fi"

    onClicked: launchProc.running = true

    Process {
        id: wifiProc
        command: ["bash", "-c", "nmcli -t -f active,ssid dev wifi | awk -F: '/^yes/{print $2}'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => root.active = line.trim() !== ""
        }
    }

    Process { id: launchProc; command: ["uwsm-app", "--", "nm-connection-editor"] }

    Component.onCompleted: refresh()
}
