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

    function focusInitial() {
        const firstEvent = eventRepeater.itemAt(0);
        if (firstEvent)
            firstEvent.forceActiveFocus();
        else
            addButton.forceActiveFocus();
    }

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
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            font.weight: Font.Medium
            renderType: Text.NativeRendering
            Layout.fillWidth: true
        }

        // Add event FAB
        Rectangle {
            id: addButton
            implicitWidth: 28; implicitHeight: 28
            radius: 14
            color: activeFocus ? Theme.islandAccent
                : Qt.rgba(Theme.islandAccent.r, Theme.islandAccent.g, Theme.islandAccent.b, 0.18)
            border.color: Qt.rgba(Theme.islandAccent.r, Theme.islandAccent.g, Theme.islandAccent.b, 0.4)
            border.width: 1
            activeFocusOnTab: true

            Text {
                anchors.centerIn: parent
                text: "󰐕"
                color: addButton.activeFocus ? Theme.islandOnAccent : Theme.islandAccent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                renderType: Text.NativeRendering
            }

            Keys.onReturnPressed: event => {
                root.addEventRequested(root.selectedDate);
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.addEventRequested(root.selectedDate);
                event.accepted = true;
            }
            Keys.onSpacePressed: event => {
                root.addEventRequested(root.selectedDate);
                event.accepted = true;
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
                color: Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 22
                renderType: Text.NativeRendering
                Layout.alignment: Qt.AlignHCenter
            }
            Text {
                text: "No events"
                color: Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                renderType: Text.NativeRendering
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
        spacing: 0

        Repeater {
            id: eventRepeater
            model: root._events
            delegate: CalendarEventCard {
                required property var modelData
                Layout.fillWidth: true
                event: modelData
                onEditRequested: ev => root.editEventRequested(ev)
                onDeleteRequested: id => {
                    root.deleteEventRequested(id);
                    Qt.callLater(() => root.focusInitial());
                }
            }
        }
    }
}
