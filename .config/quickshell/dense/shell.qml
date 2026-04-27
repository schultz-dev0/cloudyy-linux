// cloudyyOS — Quickshell Dense Preset
// High-density layout, minimal padding

import QtQuick
import QtQuick.Layouts
import Quickshell
import "."
import "./components"

Scope {
    id: root

    // ---- notifications & control center ---------------------------------
    Notifications {}

    // ---- battery probe --------------------------------------------------
    BatteryProbe { id: batteryProbe }

    // ---- Bar window, one per monitor -------------------------------------
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true }
            margins { top: 0; left: 0; right: 0 }
            implicitHeight: 32

            color: "transparent"
            exclusiveZone: 32

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.95)
                border.width: 1
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.1)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 4

                    // LEFT — cloud + workspaces
                    RowLayout {
                        spacing: 2
                        CloudButton { implicitWidth: 28; implicitHeight: 24 }
                        Workspaces {}
                    }

                    Item { Layout.fillWidth: true }

                    // CENTER — clock
                    Clock {
                        // Dense specific overrides
                    }

                    Item { Layout.fillWidth: true }

                    // RIGHT — status tray
                    RowLayout {
                        spacing: 0
                        StatusPill { 
                            icon: "󰂯"
                            onClicked: Quickshell.execDetached(["/home/schultz/cloudyy_scripts/cloud-center", "--bluetooth"]) 
                        }
                        StatusPill { 
                            icon: batteryProbe.icon
                            text: batteryProbe.percent + "%"
                            visible: batteryProbe.present 
                        }
                        StatusPill { 
                            icon: "󰖩"
                            onClicked: Quickshell.execDetached(["nm-connection-editor"]) 
                        }
                        StatusPill { 
                            icon: "󰂚"
                            onClicked: Quickshell.execDetached(["qs", "ipc", "call", "notifs", "toggle"]) 
                        }
                        StatusPill { 
                            icon: "󰐥"
                            accent: true
                            onClicked: Quickshell.execDetached(["wlogout"]) 
                        }
                    }
                }
            }
        }
    }
}
