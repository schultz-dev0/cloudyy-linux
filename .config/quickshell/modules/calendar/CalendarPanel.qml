pragma ComponentBehavior: Bound

// modules/calendar/CalendarPanel.qml — standalone calendar overlay, opened
// from the bar's clock. Not part of the island; spawns top-center like
// Spotlight (same width/topMargin).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "." as QuickCalendar

PanelWindow {
    id: root

    readonly property var svc: QuickCalendar.CalendarPanelService
    readonly property int overlayWidth: 640
    readonly property int topMargin: 80

    anchors { top: true }
    margins { top: root.topMargin }

    implicitWidth: root.svc.visible ? root.overlayWidth : 0
    implicitHeight: root.svc.visible ? contentPanel.implicitHeight : 0
    visible: root.svc.visible
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:command"
    // Exclusive, not OnDemand: on_demand only grants focus on an actual
    // click, so opening via the SUPER+CTRL+C keybind (no click) would never
    // actually receive keyboard input for the grid/dialog navigation.
    WlrLayershell.keyboardFocus: root.svc.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    onVisibleChanged: {
        if (visible)
            Qt.callLater(() => calendarContent.focusInitial());
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.svc.close()
    }

    Item {
        id: contentPanel
        width: root.overlayWidth
        implicitHeight: calendarContent.implicitHeight + 24

        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            radius: 0
            color: Theme.glassShell
            border.width: 1
            border.color: Theme.glassPanelBorder
        }

        QuickCalendar.CalendarContent {
            id: calendarContent
            anchors {
                fill: parent
                margins: 12
            }
            onCloseNestedRequested: root.svc.close()
        }
    }

    IpcHandler {
        target: "calendar"
        function open() {
            root.svc.open();
        }
        function hide() {
            root.svc.close();
        }
        function toggle() {
            root.svc.toggle();
        }
    }
}
