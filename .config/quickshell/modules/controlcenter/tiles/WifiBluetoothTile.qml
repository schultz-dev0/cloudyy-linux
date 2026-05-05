pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/WifiBluetoothTile.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../.."

Rectangle {
    id: root

    // ── Public ────────────────────────────────────────────────────────────
    property string networkName:  "..."
    property bool   wifiActive:   false
    property bool   btActive:     false
    property string btStatusText: "Off"

    function refresh() {
        wifiProc.running = false
        wifiProc.running = true
        btProc.running   = false
        btProc.running   = true
    }

    // ── Tunables ──────────────────────────────────────────────────────────
    readonly property int tileRadius: 12

    // ── Layout ────────────────────────────────────────────────────────────
    // Height matches two BaseTiles plus one row gap: 68 + 6 + 68 = 142.
    // This is set explicitly so ElevatedEffect can cache the shadow at the
    // correct size, and so no GridLayout rowSpan / z-fighting is needed.
    implicitHeight: 142
    implicitWidth:  170
    Layout.fillWidth: true

    radius:       tileRadius
    color:        Theme.surface_container
    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
    border.width: 1

    ElevatedEffect { target: root }

    // ── Content ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing:      0

        // ── Wi-Fi row ─────────────────────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // Hover highlight
            Rectangle {
                anchors { fill: parent; margins: 3 }
                radius: root.tileRadius - 3
                color: wifiHover.containsMouse
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.09)
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 10

                Text {
                    text:           root.wifiActive ? "󰖩" : "󰖪"
                    color:          root.wifiActive
                        ? Theme.primary
                        : Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 20

                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                ColumnLayout {
                    spacing:          1
                    Layout.fillWidth: true

                    Text {
                        text:           "Wi-Fi"
                        color:          Theme.on_surface
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.weight:    Font.Bold
                    }

                    Text {
                        text:             root.networkName
                        color:            root.wifiActive
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                            : Theme.on_surface_variant
                        font.family:      "JetBrainsMono Nerd Font"
                        font.pixelSize:   9
                        elide:            Text.ElideRight
                        Layout.fillWidth: true

                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            MouseArea {
                id:           wifiHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked:    wifiLaunchProc.running = true
            }
        }

        // ── Divider ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height:           1
            color:            Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        }

        // ── Bluetooth row ─────────────────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // Hover highlight
            Rectangle {
                anchors { fill: parent; margins: 3 }
                radius: root.tileRadius - 3
                color: btHover.containsMouse
                    ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.09)
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                spacing: 10

                Text {
                    text:           root.btActive ? "󰂯" : "󰂲"
                    color:          root.btActive
                        ? Theme.primary
                        : Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 20

                    Behavior on color { ColorAnimation { duration: 150 } }
                }

                ColumnLayout {
                    spacing:          1
                    Layout.fillWidth: true

                    Text {
                        text:           "Bluetooth"
                        color:          Theme.on_surface
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.weight:    Font.Bold
                    }

                    Text {
                        text:           root.btStatusText
                        color:          root.btActive
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.9)
                            : Theme.on_surface_variant
                        font.family:    "JetBrainsMono Nerd Font"
                        font.pixelSize: 9

                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            MouseArea {
                id:           btHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked:    btLaunchProc.running = true
            }
        }
    }

    // ── Processes ─────────────────────────────────────────────────────────
    Process {
        id:      wifiProc
        command: ["bash", "-c", "nmcli -t -f active,ssid dev wifi | awk -F: '/^yes/{print $2}'"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const name = line.trim()
                root.wifiActive  = name !== ""
                root.networkName = name !== "" ? name : "Not connected"
            }
        }
    }

    Process {
        id:      btProc
        command: ["bash", "-c", "bluetoothctl show | awk '/Powered:/{print $2}'"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const on          = line.trim() === "yes"
                root.btActive     = on
                root.btStatusText = on ? "On" : "Off"
            }
        }
    }

    Process { id: wifiLaunchProc; command: ["uwsm-app", "--", "nm-connection-editor"]; running: false }
    Process { id: btLaunchProc;   command: ["cloud-center", "bluetooth"];               running: false }

    Component.onCompleted: refresh()
}
