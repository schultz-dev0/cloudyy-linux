pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../.."
import "." as QuickToast

PanelWindow {
    id: root

    readonly property var activity: QuickToast.ToastQueueService.currentActivity
    readonly property bool isOsd: activity?.data?.activityType === "osd"
    readonly property bool panelActive: activity !== null

    anchors { top: true; right: true }
    margins { top: 16; right: 16 }
    implicitWidth: panelActive ? 230 : 0
    implicitHeight: panelActive ? card.implicitHeight : 0
    visible: panelActive
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:toast"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    Connections {
        target: QuickToast.ToastQueueService
        function onCurrentActivityUpdated() {
            // currentActivity mutated in place (OSD revive) — force the
            // bindings below to re-evaluate since the property reference
            // itself didn't change.
            root.activityRevision++;
        }
    }
    property int activityRevision: 0

    Rectangle {
        id: card
        width: parent.width
        implicitHeight: contentCol.implicitHeight + 22
        radius: 0
        color: Theme.resin(Theme.resinFillAlpha)
        border.width: 1
        border.color: Theme.resinBorder
        antialiasing: true

        Column {
            id: contentCol
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                margins: 11
            }
            spacing: 4

            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: 28; height: 28
                    radius: 0
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.3)
                    Text {
                        anchors.centerIn: parent
                        // Comma-operator read of activityRevision forces this
                        // binding to re-evaluate on OSD revive (currentActivity
                        // is mutated in place, not reassigned, so the value
                        // itself isn't a sufficient dependency — see ToastQueueService.showOsdBurst()).
                        text: root.isOsd ? (root.activityRevision, root.activity?.data?.icon ?? "") : "󰂚"
                        color: Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                    }
                }

                Column {
                    width: parent.width - 28 - 10 - (closeBtn.visible ? closeBtn.width + 6 : 0)
                    spacing: 2

                    Row {
                        width: parent.width
                        Text {
                            width: parent.width - (closeBtn.visible ? 0 : 0)
                            text: root.isOsd ? (root.activity?.data?.kind ?? "") : (root.activity?.data?.appName ?? "")
                            color: Theme.textPrimary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        visible: !root.isOsd
                        width: parent.width
                        text: root.activity?.data?.summary ?? ""
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: !root.isOsd && (root.activity?.data?.body ?? "") !== ""
                        width: parent.width
                        text: root.activity?.data?.body ?? ""
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    Item {
                        visible: root.isOsd
                        width: parent.width
                        height: 4
                        Rectangle {
                            anchors.fill: parent
                            radius: 0
                            color: Qt.rgba(1, 1, 1, 0.08)
                        }
                        Rectangle {
                            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                            radius: 0
                            width: parent.width * Math.max(0, Math.min(1, (root.activityRevision, root.activity?.data?.progress ?? 0)))
                            color: Theme.primary
                        }
                    }

                    Text {
                        visible: root.isOsd
                        text: (root.activityRevision, root.activity?.data?.valueLabel ?? "")
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                }
            }
        }

        Text {
            id: closeBtn
            visible: !root.isOsd && closeHover.containsMouse
            anchors { top: parent.top; right: parent.right; margins: 8 }
            text: "×"
            color: Theme.textMuted
            font.pixelSize: 14
        }

        MouseArea {
            id: closeHover
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (root.activity) {
                    root.activity.data?.notification?.dismiss();
                    QuickToast.ToastQueueService.remove(root.activity.id);
                }
            }
        }
    }
}
