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
        radius: 12
        color: Qt.rgba(Theme.surface_variant.r, Theme.surface_variant.g, Theme.surface_variant.b, 0.28)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.2)
        border.width: 1
    }

    Column {
        anchors.centerIn: parent
        spacing: 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon + "  " + root.value
            color: Theme.textPrimary
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 8
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            color: Theme.on_surface_variant
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
