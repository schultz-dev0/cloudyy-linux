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

    readonly property bool lifted: root.selected || root.hovered

    width: iconSize + 8
    height: iconSize + 8

    Item {
        id: visualLayer

        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize

        scale: root.lifted ? 1.1 : 1
        y: root.lifted ? -3 : 0

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

        Rectangle {
            anchors.centerIn: parent
            width: root.iconSize + 6
            height: root.iconSize + 6
            radius: 12
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, root.lifted ? 0.14 : 0)
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, root.lifted ? 0.5 : 0)
            border.width: 1.5

            Behavior on color {
                enabled: Perf.animationsEnabled
                ColorAnimation { duration: Perf.msHalf(140) }
            }

            Behavior on border.color {
                enabled: Perf.animationsEnabled
                ColorAnimation { duration: Perf.msHalf(140) }
            }
        }

        AppIcon {
            anchors.centerIn: parent
            width: root.iconSize
            height: root.iconSize
            iconSize: root.iconSize
            appData: root.appData
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
