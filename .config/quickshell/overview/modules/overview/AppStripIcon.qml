pragma ComponentBehavior: Bound

import QtQuick
import "../../../"
import "../../services"

Item {
    id: root

    required property var appData
    required property bool selected

    signal clicked()

    property int iconSize: 44
    property bool hovered: false
    property int instanceIndex: -1

    readonly property int windowCount: root.appData?.windowCount ?? 1

    readonly property bool lifted: root.selected || root.hovered
    readonly property int ringSize: root.iconSize + (root.lifted ? 8 : 4)

    width: iconSize + 8
    height: iconSize + 8
    clip: false

    Rectangle {
        id: selectionRing

        anchors.centerIn: parent
        width: root.ringSize
        height: root.ringSize
        radius: 12
        visible: root.lifted
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
        border.width: 1.5

        Behavior on width {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(140); easing.type: Easing.OutCubic }
        }

        Behavior on height {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(140); easing.type: Easing.OutCubic }
        }

        Behavior on color {
            enabled: Perf.animationsEnabled
            ColorAnimation { duration: Perf.msHalf(140) }
        }

        Behavior on border.color {
            enabled: Perf.animationsEnabled
            ColorAnimation { duration: Perf.msHalf(140) }
        }
    }

    Item {
        id: iconLayer

        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        scale: root.lifted ? 1.08 : 1
        y: root.lifted ? -2 : 0

        Behavior on scale {
            enabled: Perf.animationsEnabled
            NumberAnimation {
                duration: Perf.msHalf(140)
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            enabled: Perf.animationsEnabled
            NumberAnimation {
                duration: Perf.msHalf(140)
                easing.type: Easing.OutCubic
            }
        }

        AppIcon {
            anchors.fill: parent
            iconSize: root.iconSize
            appData: root.appData
        }

        Rectangle {
            visible: root.windowCount > 1
            width: badgeLabel.implicitWidth + 8
            height: 16
            radius: 8
            color: Theme.accent
            anchors {
                top: parent.top
                right: parent.right
                topMargin: -4
                rightMargin: -4
            }

            Text {
                id: badgeLabel
                anchors.centerIn: parent
                text: root.selected && root.instanceIndex >= 0
                    ? `${root.instanceIndex + 1}/${root.windowCount}`
                    : `${root.windowCount}`
                color: Theme.accentText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.weight: Font.Bold
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onClicked: root.clicked()
    }
}
