// modules/controlcenter/tiles/DarkModeTile.qml
import QtQuick
import Quickshell
import Quickshell.Io

BaseTile {
    id: root

    icon:       active ? "󰖔" : "󰖙"
    label:      "Dark Mode"
    statusText: active ? "Dark" : "Light"
    active:     false

    onClicked: toggleProc.running = true

    function refresh() {
        readProc.running = false
        readProc.running = true
    }

    Component.onCompleted: refresh()

    Process {
        id: readProc
        command: ["bash", "-c",
            "grep THEME_MODE ~/.config/hypr/theme_state/state.conf | cut -d= -f2 | tr -d '\"'"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => { root.active = line.trim() === "dark" }
        }
    }

    Process {
        id: toggleProc
        command: ["bash", "-lc", "~/cloudyy_scripts/theme_controller.sh toggle"]
        running: false
        onRunningChanged: if (!running) root.refresh()
    }
}
