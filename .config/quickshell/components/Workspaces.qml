import QtQuick
import Quickshell.Hyprland
import ".."

Row {
    spacing: Style.workspaceSpacing

    Repeater {
        model: Style.workspaceCount
        Rectangle {
            required property int index
            readonly property int wsId: index + 1
            readonly property bool active: Hyprland.focusedWorkspace
                                           ? Hyprland.focusedWorkspace.id === wsId
                                           : false
            readonly property var ws: {
                for (let i = 0; i < Hyprland.workspaces.values.length; i++)
                    if (Hyprland.workspaces.values[i].id === wsId) return Hyprland.workspaces.values[i]
                return null
            }
            readonly property bool occupied: ws !== null

            width: active ? Style.workspaceDotActiveWidth : Style.workspaceDotSize
            height: Style.workspaceDotSize
            radius: Style.workspaceDotRadius
            Behavior on width { NumberAnimation { duration: Style.workspaceAnimMs; easing.type: Easing.OutCubic } }

            color: active
                ? Theme.accent
                : occupied
                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.workspaceOccupiedAlpha)
                    : Qt.rgba(1, 1, 1, 0.3)
            
            border.width: active ? 1 : 0
            border.color: Theme.glassEdge

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + parent.wsId)
            }
        }
    }
}
