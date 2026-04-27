import QtQuick
import Quickshell
import Quickshell.Io
import ".."

Item {
    id: batteryProbe
    property bool present: false
    property int percent: 0
    property string state: ""
    property string icon: "󰂑"

    function refresh() { batProc.running = true }
    Component.onCompleted: refresh()

    Timer {
        interval: Style.batteryPollMs; repeat: true; running: true
        onTriggered: batteryProbe.refresh()
    }

    Process {
        id: batProc
        command: ["sh", "-c",
            "upower -i $(upower -e | grep -m1 BAT) 2>/dev/null | " +
            "awk '/percentage/ {gsub(\"%\",\"\",$2); print \"P\"$2} /state/ {print \"S\"$2}'"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("P")) { batteryProbe.percent = parseInt(line.slice(1)); batteryProbe.present = true }
                else if (line.startsWith("S")) {
                    batteryProbe.state = line.slice(1)
                    const p = batteryProbe.percent
                    if (batteryProbe.state === "charging")    batteryProbe.icon = "󰂄"
                    else if (p >= 90) batteryProbe.icon = "󰁹"
                    else if (p >= 70) batteryProbe.icon = "󰂁"
                    else if (p >= 50) batteryProbe.icon = "󰁾"
                    else if (p >= 30) batteryProbe.icon = "󰁼"
                    else if (p >= 10) batteryProbe.icon = "󰁺"
                    else              batteryProbe.icon = "󰂎"
                }
            }
        }
    }
}
