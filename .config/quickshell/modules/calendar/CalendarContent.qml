pragma ComponentBehavior: Bound

// modules/calendar/CalendarContent.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../.."

FocusScope {
    id: root

    signal closeNestedRequested

    readonly property bool dialogOpen: dialogLayer.open
    property Item _focusBeforeDialog: null

    implicitHeight: Math.min(820, contentColumn.implicitHeight)
    clip: true

    function nextMonth() {
        if (calGrid.displayMonth === 11) {
            calGrid.displayYear += 1;
            calGrid.displayMonth = 0;
        } else {
            calGrid.displayMonth++;
        }
    }

    function prevMonth() {
        if (calGrid.displayMonth === 0) {
            calGrid.displayYear -= 1;
            calGrid.displayMonth = 11;
        } else {
            calGrid.displayMonth--;
        }
    }

    function jumpToToday() {
        const now = new Date();
        calGrid.displayYear = now.getFullYear();
        calGrid.displayMonth = now.getMonth();
        calGrid.selectedDate = CalendarService.today();
        calGrid.keyboardDate = calGrid.selectedDate;
    }

    function focusInitial() {
        calGrid.focusInitial();
    }

    function _rememberFocus() {
        _focusBeforeDialog = root.Window.window
            ? root.Window.window.activeFocusItem : calGrid;
    }

    function _restoreFocus() {
        const target = _focusBeforeDialog;
        _focusBeforeDialog = null;
        Qt.callLater(() => {
            if (target)
                target.forceActiveFocus();
            else
                calGrid.focusInitial();
        });
    }

    function _openAdd(date) {
        _rememberFocus();
        dialogLayer.openAdd(date);
    }

    function _openEdit(event) {
        _rememberFocus();
        dialogLayer.openEdit(event);
    }

    Keys.onEscapePressed: event => {
        if (dialogLayer.open)
            dialogLayer._cancel();
        else
            root.closeNestedRequested();
        event.accepted = true;
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        ColumnLayout {
            id: contentColumn
            width: flick.width
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                Layout.rightMargin: 2
                visible: todayButton.visible

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: todayButton
                    implicitWidth: 28
                    implicitHeight: 28
                    radius: 14
                    color: activeFocus ? Theme.accent
                        : Qt.rgba(Theme.selection.r,
                            Theme.selection.g,
                            Theme.selection.b, 0.45)
                    border.color: activeFocus ? Theme.accent
                        : Qt.rgba(Theme.border.r,
                            Theme.border.g,
                            Theme.border.b, 0.3)
                    border.width: activeFocus ? 2 : 1
                    activeFocusOnTab: visible
                    visible: calGrid.selectedDate !== CalendarService.today()
                        || calGrid.displayYear !== new Date().getFullYear()
                        || calGrid.displayMonth !== new Date().getMonth()

                    Text {
                        anchors.centerIn: parent
                        text: "󰋙"
                        color: todayButton.activeFocus
                            ? Theme.accentText : Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 14
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: event => {
                        root.jumpToToday();
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        root.jumpToToday();
                        event.accepted = true;
                    }
                    Keys.onSpacePressed: event => {
                        root.jumpToToday();
                        event.accepted = true;
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.jumpToToday()
                    }
                }
            }

            GridLayout {
                id: calendarBody

                readonly property bool sideBySide: root.width >= 520

                Layout.fillWidth: true
                columns: sideBySide ? 3 : 1
                columnSpacing: sideBySide ? 12 : 0
                rowSpacing: sideBySide ? 0 : 10

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: calendarBody.sideBySide
                    Layout.preferredWidth: 286
                    implicitHeight: calGrid.implicitHeight

                    CalendarGrid {
                        id: calGrid
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        onDateSelected: date => calGrid.selectedDate = date
                        onRequestPrevMonth: root.prevMonth()
                        onRequestNextMonth: root.nextMonth()
                    }
                }

                Rectangle {
                    id: bodyDivider
                    Layout.fillWidth: !calendarBody.sideBySide
                    Layout.fillHeight: calendarBody.sideBySide
                    Layout.preferredWidth: calendarBody.sideBySide ? 1 : -1
                    Layout.preferredHeight: calendarBody.sideBySide ? -1 : 1
                    color: Theme.islandBorder
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: calendarBody.sideBySide
                    Layout.preferredWidth: 244
                    implicitHeight: agendaColumn.implicitHeight

                    ColumnLayout {
                        id: agendaColumn
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        spacing: 8

                        CalendarDayView {
                            id: dayView
                            Layout.fillWidth: true
                            selectedDate: calGrid.selectedDate
                            onAddEventRequested: date => root._openAdd(date)
                            onEditEventRequested: event => root._openEdit(event)
                            onDeleteEventRequested: id => CalendarService.removeEvent(id)
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Theme.islandBorder
                        }

                        RowLayout {
                            id: markRow
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 8

                            Text {
                                text: CalendarService.markedDays[calGrid.selectedDate]
                                    ? "󰊰" : "󰃄"
                                color: CalendarService.markedDays[calGrid.selectedDate]
                                    ? Theme.islandAccent : Theme.islandOnSurfaceVariant
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                                renderType: Text.NativeRendering
                            }

                            Text {
                                text: CalendarService.markedDays[calGrid.selectedDate]
                                    ? "Day marked" + (CalendarService.markedDays[calGrid.selectedDate].note
                                        ? " · " + CalendarService.markedDays[calGrid.selectedDate].note : "")
                                    : "Mark this day"
                                color: Theme.islandOnSurfaceVariant
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                renderType: Text.NativeRendering
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Rectangle {
                                id: markButton
                                implicitWidth: 28
                                implicitHeight: 28
                                radius: 14
                                color: activeFocus ? Theme.accent : "transparent"
                                border.color: activeFocus ? Theme.islandFocus
                                    : CalendarService.markedDays[calGrid.selectedDate]
                                        ? Theme.error : Theme.islandAccent
                                border.width: activeFocus ? 2 : 1
                                activeFocusOnTab: true

                                function toggleMarked() {
                                    if (CalendarService.markedDays[calGrid.selectedDate])
                                        CalendarService.clearMarkedDay(calGrid.selectedDate);
                                    else
                                        CalendarService.setMarkedDay(
                                            calGrid.selectedDate, "primary", "");
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: CalendarService.markedDays[calGrid.selectedDate]
                                        ? "󰅗" : "󰃅"
                                    color: markButton.activeFocus ? Theme.accentText
                                        : CalendarService.markedDays[calGrid.selectedDate]
                                            ? Theme.error : Theme.islandAccent
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 13
                                    renderType: Text.NativeRendering
                                }

                                Keys.onReturnPressed: event => {
                                    markButton.toggleMarked();
                                    event.accepted = true;
                                }
                                Keys.onEnterPressed: event => {
                                    markButton.toggleMarked();
                                    event.accepted = true;
                                }
                                Keys.onSpacePressed: event => {
                                    markButton.toggleMarked();
                                    event.accepted = true;
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: markButton.toggleMarked()
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: CalendarService.persistenceError !== ""
                text: CalendarService.persistenceError
                color: Theme.error
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                renderType: Text.NativeRendering
                wrapMode: Text.WordWrap
            }

            Item {
                implicitHeight: 2
            }
        }
    }

    CalendarEventDialog {
        id: dialogLayer
        anchors.fill: parent
        z: 50
        open: false
        onAccepted: root._restoreFocus()
        onCancelled: root._restoreFocus()
    }
}
