pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../.."

PanelWindow {
    id: timerWindow

    readonly property int panelWidth:  340
    readonly property int panelRadius: 20
    readonly property int padding:     16

    anchors { bottom: true; left: true }
    margins { bottom: 16; left: 16 }
    implicitWidth:  panelWidth
    implicitHeight: panelRect.implicitHeight
    color:          "transparent"
    visible:        TimerService.open

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell:timer"
    WlrLayershell.keyboardFocus: TimerService.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Keys.onEscapePressed: TimerService.open = false

    Rectangle {
        id: panelRect
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        implicitHeight: 120
        radius: timerWindow.panelRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.9)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        opacity: TimerService.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        scale: TimerService.open ? 1.0 : 0.88
        transformOrigin: Item.BottomLeft
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

        Text {
            anchors.centerIn: parent
            text: "⏱ Timer panel (stub)"
            color: Theme.on_surface
            font.pixelSize: 13
        }
    }
}
