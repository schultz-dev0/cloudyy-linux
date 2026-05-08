pragma ComponentBehavior: Bound

import QtQuick
import "../.."

Rectangle {
    implicitWidth: 80; implicitHeight: 28
    radius: 14
    color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.8)

    Text {
        anchors.centerIn: parent
        text: "⏱ Timer"
        color: Theme.on_surface_variant
        font.pixelSize: 12
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: TimerService.open = !TimerService.open
    }
}
