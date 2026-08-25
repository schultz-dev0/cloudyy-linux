pragma ComponentBehavior: Bound

import QtQuick
import "../../.."

Item {
    id: root

    required property string icon
    required property string value
    required property string label
    property string detail: ""

    width: 88
    height: 56

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: Theme.surfaceOverlay
        border.color: Theme.hairline
        border.width: 1
    }

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon + "  " + root.value
            color: Theme.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 8
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            color: Theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            elide: Text.ElideRight
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 8
            horizontalAlignment: Text.AlignHCenter
            visible: root.detail.length > 0
            text: root.detail
            color: Theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 8
            elide: Text.ElideRight
        }
    }
}
