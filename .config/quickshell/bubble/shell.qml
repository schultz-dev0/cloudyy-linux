// cloudyyOS — Quickshell Bubble Preset
// Three opaque "bubbles" (left, center, right)

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
            margins { top: 6; left: 6; right: 6 }
            implicitHeight: 44

            color: "transparent"
            exclusiveZone: 50

            RowLayout {
                anchors.fill: parent
                spacing: 12

                // LEFT — cloud + workspaces
                BubblePill {
                    Layout.alignment: Qt.AlignLeft
                    content: RowLayout {
                        spacing: 8
                        CloudButton {}
                        Workspaces {}
                    }
                }

                Item { Layout.fillWidth: true }

                // CENTER — clock
                BubblePill {
                    Layout.alignment: Qt.AlignCenter
                    content: Clock {}
                }

                Item { Layout.fillWidth: true }

                // RIGHT — status tray
                BubblePill {
                    Layout.alignment: Qt.AlignRight
                    content: RowLayout {
                        spacing: 8
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

    // ---- Bubble Pill Component (Opaque) ---------------------------------
    component BubblePill: Rectangle {
        property alias content: container.data
        implicitWidth: container.implicitWidth + 32
        implicitHeight: 36
        radius: 24
        antialiasing: true
        color: Qt.rgba(Theme.on_primary.r, Theme.on_primary.g, Theme.on_primary.b, 0.42)
        border.width: 1
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.15)

        Item {
            id: container
            anchors.centerIn: parent
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
