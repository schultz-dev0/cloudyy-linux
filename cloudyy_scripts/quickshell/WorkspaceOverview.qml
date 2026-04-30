import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Hyprland

// A floating glass workspace overview overlay
Window {
    id: root
    visible: true
    width: Screen.width
    height: Screen.height
    color: "transparent"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool

    // Configurable toggle for window previews
    property bool showPreview: false

    // Close on Escape
    Shortcut {
        sequence: "Esc"
        onActivated: root.visible = false
    }

    // Optional dimmed background overlay
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.4

        MouseArea {
            anchors.fill: parent
            onClicked: root.visible = false
        }
    }

    // Centered layout for workspace cards
    Row {
        id: workspacesRow
        anchors.centerIn: parent
        spacing: 16

        Repeater {
            // Iterate over all available workspaces from Hyprland
            model: Hyprland.workspaces

            delegate: Rectangle {
                id: wsCard

                // Each card has a 16:9 aspect ratio
                width: 240
                height: width * (9 / 16)

                // Active state check
                property bool isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData.id

                // Glassmorphism styling
                color: "rgba(255, 255, 255, 0.06)"
                border.color: isActive ? "rgba(160, 130, 255, 0.5)" : "rgba(255, 255, 255, 0.12)"
                border.width: 1
                radius: 12

                // Drop shadow placeholder (Quickshell doesn't always support native shadow, but we can simulate with border/opacity)

                Behavior on border.color { ColorAnimation { duration: 150 } }

                // Hover state logic
                MouseArea {
                    id: cardMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Hyprland.dispatch("workspace " + modelData.id)
                        root.visible = false
                    }
                }

                transform: Translate {
                    y: cardMouseArea.containsMouse ? -2 : 0
                    Behavior on y { NumberAnimation { duration: 150 } }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 5

                    // Workspace Label
                    Text {
                        text: (wsCard.isActive ? "● " : "") + "WS " + modelData.id
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.family: "JetBrains Mono"
                        color: wsCard.isActive ? "rgba(180, 150, 255, 0.8)" : "rgba(255, 255, 255, 0.35)"
                        font.letterSpacing: 1.2
                        Layout.alignment: Qt.AlignLeft
                    }

                    // Windows List
                    ListView {
                        id: windowsList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        model: modelData.windows

                        // Handle empty workspaces
                        Text {
                            anchors.centerIn: parent
                            visible: windowsList.count === 0
                            text: "empty"
                            font.pixelSize: 10
                            color: "rgba(255, 255, 255, 0.12)"
                            font.family: "JetBrains Mono"
                        }

                        delegate: Rectangle {
                            width: ListView.view.width
                            height: showPreview ? (isFocusedWindow ? 80 : 20) : 20
                            radius: 5

                            // Window focus check
                            property bool isFocusedWindow: modelData.address === (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.windows.length > 0 ? Hyprland.focusedWorkspace.windows[0].address : "")

                            color: isFocusedWindow ? "rgba(160, 130, 255, 0.12)" : "rgba(255, 255, 255, 0.05)"
                            border.color: isFocusedWindow ? "rgba(160, 130, 255, 0.2)" : "rgba(255, 255, 255, 0.06)"
                            border.width: 1

                            Behavior on height { NumberAnimation { duration: 150 } }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    Hyprland.dispatch("focuswindow address:" + modelData.address)
                                    root.visible = false
                                }
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 4

                                // Window Title Row
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: "󰖯" // Placeholder icon, replace with dynamic mapping if available
                                        font.pixelSize: 12
                                        color: isFocusedWindow ? "rgba(220, 210, 255, 0.9)" : "rgba(255, 255, 255, 0.6)"
                                    }

                                    Text {
                                        text: modelData.title || modelData.class || "Unknown"
                                        font.pixelSize: 10
                                        font.family: "JetBrains Mono"
                                        color: isFocusedWindow ? "rgba(220, 210, 255, 0.9)" : "rgba(255, 255, 255, 0.6)"
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        visible: isFocusedWindow
                                        text: "focused"
                                        font.pixelSize: 9
                                        color: "rgba(255, 255, 255, 0.4)"
                                        font.family: "JetBrains Mono"
                                    }
                                }

                                // Optional Preview Thumbnail (Mock)
                                Rectangle {
                                    visible: showPreview && isFocusedWindow
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "rgba(255, 255, 255, 0.04)"
                                    radius: 4
                                    border.color: "rgba(255, 255, 255, 0.06)"

                                    // Simulated lines of code/content
                                    Column {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 2

                                        Rectangle { width: parent.width; height: 4; color: "rgba(255,255,255,0.08)"; radius: 2 }
                                        Rectangle { width: parent.width * 0.9; height: 2; color: "rgba(120,180,255,0.15)"; radius: 1 }
                                        Rectangle { width: parent.width * 0.6; height: 2; color: "rgba(120,180,255,0.15)"; radius: 1 }
                                        Rectangle { width: parent.width * 0.8; height: 2; color: "rgba(120,180,255,0.15)"; radius: 1 }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
