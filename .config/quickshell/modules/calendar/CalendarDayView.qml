pragma ComponentBehavior: Bound

// modules/calendar/CalendarDayView.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string selectedDate: CalendarService.today()
    signal addEventRequested(string date)
    signal editEventRequested(var event)
    signal deleteEventRequested(string id)

    readonly property var _events: CalendarService.eventsForDate(selectedDate)

    implicitHeight: dayHeader.implicitHeight + (root._events.length > 0 ? eventList.implicitHeight : emptyState.implicitHeight) + 32

    // ── Day header ────────────────────────────────────────────────────────────
    RowLayout {
        id: dayHeader
        anchors { top: parent.top; left: parent.left; right: parent.right }

        Text {
            text: CalendarService.dayOfWeekLabel(
                parseInt(root.selectedDate.split("-")[0]),
                parseInt(root.selectedDate.split("-")[1]) - 1,
                parseInt(root.selectedDate.split("-")[2])
            )
            color: Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            font.weight: Font.Medium
            Layout.fillWidth: true
        }

        // Add event FAB
        Rectangle {
            width: 28; height: 28
            radius: 14
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "󰐕"
                color: Theme.primary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addEventRequested(root.selectedDate)
            }
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────────
    Item {
        id: emptyState
        anchors {
            top: dayHeader.bottom
            left: parent.left
            right: parent.right
            topMargin: 8
        }
        visible: root._events.length === 0
        implicitHeight: 56

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            Text {
                text: "󰃰"
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 22
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "No events"
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // ── Event list ────────────────────────────────────────────────────────────
    ColumnLayout {
        id: eventList
        anchors {
            top: dayHeader.bottom
            left: parent.left
            right: parent.right
            topMargin: 8
        }
        visible: root._events.length > 0
        spacing: 6

        Repeater {
            model: root._events
            delegate: CalendarEventCard {
                required property var modelData
                Layout.fillWidth: true
                event: modelData
                onEditRequested: ev => root.editEventRequested(ev)
                onDeleteRequested: id => root.deleteEventRequested(id)
            }
        }
    }
}
