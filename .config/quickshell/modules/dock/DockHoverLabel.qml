pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../../ShellEdges.js" as ShellEdges

Item {
    id: root

    required property Item anchorItem
    required property bool active
    required property string label
    required property real labelLiftPx

    // On side edges the upright box's width runs into the screen; push it out
    // so its near side, not its centre, sits 16px + lift from the icon.
    readonly property bool sideways: ShellEdges.isVertical(ShellLayout.dockEdge)

    visible: root.active && root.label.length > 0
    enabled: false
    z: 20
    anchors.horizontalCenter: anchorItem.horizontalCenter
    anchors.bottom: anchorItem.top
    anchors.bottomMargin: 16 + root.labelLiftPx + (root.sideways ? (root.width - root.height) / 2 : 0)
    width: Math.min(220, labelText.implicitWidth + 16)
    height: labelText.implicitHeight + 12

    DockUpright {
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
            color: Theme.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
        }
    }
}
