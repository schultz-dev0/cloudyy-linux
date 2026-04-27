// cloudyyOS — Quickshell Compact Preset
// Single continuous floating bar, polished hierarchy

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
            margins { top: 6; left: 8; right: 8 }
            implicitHeight: 40

            color: "transparent"
            exclusiveZone: 44

            Rectangle {
                anchors.fill: parent
                radius: 14
                color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.82)
                border.width: 1
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.15)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 6

                    // LEFT — cloud + workspaces
                    RowLayout {
                        spacing: 4
                        CompactModule { content: CloudButton {} }
                        
                        Rectangle {
                            implicitWidth: wsRow.implicitWidth + 12
                            implicitHeight: 32
                            radius: 12
                            color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.82)
                            border.width: 1
                            border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.18)
                            
                            Workspaces {
                                id: wsRow
                                anchors.centerIn: parent
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // CENTER — clock
                    CompactModule {
                        content: Clock {}
                    }

                    Item { Layout.fillWidth: true }

                    // RIGHT — status tray
                    RowLayout {
                        spacing: 2
                        CompactModule {
                            content: StatusPill { 
                                icon: "󰂯"
                                onClicked: Quickshell.execDetached(["/home/schultz/cloudyy_scripts/cloud-center", "--bluetooth"]) 
                            }
                        }
                        CompactModule {
                            content: StatusPill { 
                                icon: batteryProbe.icon
                                text: batteryProbe.percent + "%"
                                visible: batteryProbe.present 
                            }
                        }
                        CompactModule {
                            content: StatusPill { 
                                icon: "󰖩"
                                onClicked: Quickshell.execDetached(["nm-connection-editor"]) 
                            }
                        }
                        CompactModule {
                            content: StatusPill { 
                                icon: "󰂚"
                                onClicked: Quickshell.execDetached(["qs", "ipc", "call", "notifs", "toggle"]) 
                            }
                        }
                        CompactModule {
                            content: StatusPill { 
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

    // ---- Compact Module Component ---------------------------------------
    component CompactModule: Rectangle {
        property alias content: container.data
        implicitWidth: container.implicitWidth + 12
        implicitHeight: 32
        radius: 10
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.22)
        border.width: 1
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.18)

        Item {
            id: container
            anchors.centerIn: parent
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
