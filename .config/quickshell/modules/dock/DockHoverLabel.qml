pragma ComponentBehavior: Bound

import QtQuick
import "../.."

Item {
    id: root

    required property Item anchorItem
    required property bool active
    required property string label
    required property real labelLiftPx

    visible: root.active && root.label.length > 0
    enabled: false
    z: 20
    anchors.horizontalCenter: anchorItem.horizontalCenter
    anchors.bottom: anchorItem.top
    anchors.bottomMargin: 16 + root.labelLiftPx
    width: Math.min(220, labelText.implicitWidth + 16)
    height: labelText.implicitHeight + 12

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.94)
        border.color: Theme.hairline
        border.width: 1
    }

    Text {
        id: labelText
        anchors.centerIn: parent
        width: parent.width - 12
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: root.label
        color: Theme.on_surface
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
    }
}
