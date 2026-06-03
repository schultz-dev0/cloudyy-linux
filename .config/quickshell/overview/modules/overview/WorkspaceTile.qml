pragma ComponentBehavior: Bound

import QtQuick
import "../../../"

Item {
    id: root

    required property int workspaceId
    required property var windows
    required property bool active
    required property bool selected
    required property bool overviewActive
    property var monitorData: null
    property int tileWidth: 220
    property int tileHeight: 132

    signal requestWorkspace(int workspaceId)
    signal requestFocusWindow(var windowData)
    signal requestCloseWindow(var windowData)

    width: tileWidth
    height: tileHeight

    Rectangle {
        id: tile

        anchors.fill: parent
        radius: 16
        color: root.selected
            ? Qt.tint(Theme.surface_container, Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18))
            : root.active
                ? Theme.surface_container_high
                : Theme.surface_container
        border.color: root.selected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
            : root.active
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.26)
                : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
        border.width: 1
        antialiasing: true

        ElevatedEffect { target: tile }

        Behavior on color {
            ColorAnimation { duration: 140 }
        }

        Behavior on border.color {
            ColorAnimation { duration: 140 }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.requestWorkspace(root.workspaceId)
    }

    Text {
        anchors {
            left: parent.left
            top: parent.top
            leftMargin: 12
            topMargin: 12
        }
        text: "Workspace " + root.workspaceId
        color: Theme.on_surface
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
        font.weight: Font.Bold
    }

    Rectangle {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 11
            rightMargin: 12
        }
        width: countText.implicitWidth + 16
        height: 22
        radius: 11
        color: root.active
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            : Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.72)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.25)
        border.width: 1

        Text {
            id: countText
            anchors.centerIn: parent
            text: (root.windows ?? []).length + " open"
            color: root.active ? Theme.primary : Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 10
            rightMargin: 10
            bottomMargin: 10
        }
        height: 28
        radius: 14
        color: Qt.rgba(Theme.surface_container_high.r, Theme.surface_container_high.g, Theme.surface_container_high.b, 0.68)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.16)
        border.width: 1
        visible: (root.windows ?? []).length > 0
    }

    Text {
        visible: (root.windows ?? []).length === 0
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 18
        }
        text: root.active ? "active empty" : "empty"
        color: Theme.on_surface_variant
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 10
    }

    WorkspaceIconStrip {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 14
            rightMargin: 14
            bottomMargin: 15
        }
        windows: root.windows ?? []
        iconSize: 14
    }
}
