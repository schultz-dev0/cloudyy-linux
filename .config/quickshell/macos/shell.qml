// cloudyyOS — Quickshell macOS Preset
// Segmented "Floating Glass Pills" layout × Frutiger Aero gloss

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
            margins { top: Style.barMarginTop; left: Style.barMarginSide; right: Style.barMarginSide }
            implicitHeight: Style.barHeight

            color: "transparent"
            exclusiveZone: Style.barExclusiveZone

            RowLayout {
                anchors.fill: parent
                spacing: Style.pillSpacing

                // LEFT — cloud + workspaces
                GlassPill {
                    Layout.alignment: Qt.AlignLeft
                    content: RowLayout {
                        spacing: Style.barContentSpacing - 4
                        CloudButton {}
                        Workspaces {}
                    }
                }

                Item { Layout.fillWidth: true }

                // CENTER — clock
                GlassPill {
                    Layout.alignment: Qt.AlignCenter
                    content: Clock {}
                }

                Item { Layout.fillWidth: true }

                // RIGHT — status tray
                GlassPill {
                    Layout.alignment: Qt.AlignRight
                    content: RowLayout {
                        spacing: Style.popupSpacing
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
