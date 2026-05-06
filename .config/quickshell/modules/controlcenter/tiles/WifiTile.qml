pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/WifiTile.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../.."

Rectangle {
    id: root

    Layout.columnSpan: 2
    Layout.fillWidth:  true
    implicitHeight:    52
    radius:            12
    color:  Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.13)
    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
    border.width: 1

    property string networkName: "..."

    function refresh() {
        wifiProc.running = false
        wifiProc.running = true
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
        spacing: 10

        Text {
            text:        "󰖩"
            color:       Theme.primary
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 20
        }

        ColumnLayout {
            spacing: 1
            Layout.fillWidth: true

            Text {
                text:           "Wi-Fi"
                color:          Theme.on_surface
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                font.weight:    Font.Bold
            }

            Text {
                text:           root.networkName
                color:          Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                elide:          Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked:    launchProc.running = true
    }

    Process {
        id: wifiProc
        command: ["bash", "-c", "nmcli -t -f active,ssid dev wifi | awk -F: '/^yes/{print $2}'"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const name = line.trim()
                root.networkName = name !== "" ? name : "Not connected"
            }
        }
    }

    Process {
        id: launchProc
        command: ["uwsm-app", "--", "nm-connection-editor"]
        running: false
    }

    Component.onCompleted: refresh()
}
