pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "." as QuickToast

Rectangle {
    id: root

    required property var toast   // {id, serial, data, expiresAt}
    readonly property bool isOsd: toast.data?.activityType === "osd"

    width: 320
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
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                border.width: 1
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                Text {
                    anchors.centerIn: parent
                    text: root.isOsd ? (root.toast.data?.icon ?? "") : "󰂚"
                    color: Theme.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                }
            }

            Column {
                width: parent.width - 28 - 10 - (closeBtn.visible ? closeBtn.width + 6 : 0)
                spacing: 2

                Text {
                    width: parent.width
                    text: root.isOsd ? (root.toast.data?.kind ?? "") : (root.toast.data?.appName ?? "")
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    visible: !root.isOsd
                    width: parent.width
                    text: root.toast.data?.summary ?? ""
                    color: Theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    visible: !root.isOsd && (root.toast.data?.body ?? "") !== ""
                    width: parent.width
                    text: root.toast.data?.body ?? ""
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
                        width: parent.width * Math.max(0, Math.min(1, root.toast.data?.progress ?? 0))
                        color: Theme.accent
                    }
                }

                Text {
                    visible: root.isOsd
                    text: root.toast.data?.valueLabel ?? ""
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
            root.toast.data?.notification?.dismiss();
            QuickToast.ToastQueueService.remove(root.toast.id);
        }
    }
}
