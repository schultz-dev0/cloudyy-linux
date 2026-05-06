pragma ComponentBehavior: Bound

// modules/calendar/CalendarPanel.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../.."

PanelWindow {
    id: panel

    // ── Tunables ──────────────────────────────────────────────────────────────
    readonly property int panelWidth:     380
    readonly property int panelMaxHeight: 860
    readonly property int bottomGap:      10
    readonly property int rightGap:       20
    readonly property int panelRadius:    24
    readonly property int panelPadding:   18
    readonly property int sectionRadius:  16

    // ── Public ────────────────────────────────────────────────────────────────
    property bool open: false

    // Expose navigation functions for IPC
    function nextMonth()    { calGrid.displayMonth === 11 ? (calGrid.displayYear += 1, calGrid.displayMonth = 0) : calGrid.displayMonth++ }
    function prevMonth()    { calGrid.displayMonth === 0  ? (calGrid.displayYear -= 1, calGrid.displayMonth = 11) : calGrid.displayMonth-- }
    function jumpToToday()  {
        calGrid.displayYear  = new Date().getFullYear()
        calGrid.displayMonth = new Date().getMonth()
        calGrid.selectedDate = CalendarService.today()
    }

    // ── Window ────────────────────────────────────────────────────────────────
    anchors { bottom: true; right: true }
    margins { bottom: bottomGap; right: rightGap }
    implicitWidth:  panelWidth
    implicitHeight: Math.min(panelMaxHeight, outerCol.implicitHeight + panelPadding * 2)
    color: "transparent"
    visible: open
    WlrLayershell.keyboardFocus: dialogLayer.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ── Panel shell ───────────────────────────────────────────────────────────
    Rectangle {
        id: panelRect
        anchors.fill: parent
        radius: panel.panelRadius
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.72)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        // ── Popout animation: scale from bottom-right + fade ─────────────────
        opacity: panel.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        scale: panel.open ? 1.0 : 0.88
        transformOrigin: Item.BottomRight
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.5 } }

        Flickable {
            id: flick
            anchors.fill: parent
            contentHeight: outerCol.implicitHeight + panel.panelPadding * 2
            clip: true
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
                id: outerCol
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    margins: panel.panelPadding
                }
                spacing: 14

                // ── Calendar header ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "󰃭  Calendar"
                        color: Theme.on_surface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        Layout.fillWidth: true
                    }

                    // Jump to today
                    Rectangle {
                        width: 28; height: 28
                        radius: 14
                        color: Qt.rgba(Theme.secondary_container.r, Theme.secondary_container.g, Theme.secondary_container.b, 0.45)
                        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
                        border.width: 1
                        visible: calGrid.selectedDate !== CalendarService.today()
                            || calGrid.displayYear  !== new Date().getFullYear()
                            || calGrid.displayMonth !== new Date().getMonth()

                        Text {
                            anchors.centerIn: parent
                            text: "󰋙"
                            color: Theme.on_surface_variant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.jumpToToday()
                        }
                    }
                }

                // ── Month grid section ────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: calGrid.implicitHeight + 20
                    radius: panel.sectionRadius
                    color: Theme.surface_container
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.22)
                    border.width: 1

                    ElevatedEffect { target: parent }

                    CalendarGrid {
                        id: calGrid
                        anchors { fill: parent; margins: 10 }
                        onDateSelected: date => calGrid.selectedDate = date
                        onRequestPrevMonth: panel.prevMonth()
                        onRequestNextMonth: panel.nextMonth()
                    }
                }

                // ── Day view section ──────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: dayView.implicitHeight + 24
                    radius: panel.sectionRadius
                    color: Theme.surface_container
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.22)
                    border.width: 1

                    ElevatedEffect { target: parent }

                    CalendarDayView {
                        id: dayView
                        anchors { fill: parent; margins: 12 }
                        selectedDate: calGrid.selectedDate
                        onAddEventRequested:    date    => dialogLayer.openAdd(date)
                        onEditEventRequested:   event   => dialogLayer.openEdit(event)
                        onDeleteEventRequested: id      => CalendarService.removeEvent(id)
                    }
                }

                // ── Mark day section ──────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: markRow.implicitHeight + 20
                    radius: panel.sectionRadius
                    color: Theme.surface_container
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.22)
                    border.width: 1
                    visible: true

                    RowLayout {
                        id: markRow
                        anchors { fill: parent; margins: 12 }
                        spacing: 8

                        Text {
                            text: CalendarService.markedDays[calGrid.selectedDate] ? "󰊰" : "󰃄"
                            color: CalendarService.markedDays[calGrid.selectedDate]
                                ? Theme.primary
                                : Theme.on_surface_variant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 16
                        }

                        Text {
                            text: CalendarService.markedDays[calGrid.selectedDate]
                                ? "Day marked" + (CalendarService.markedDays[calGrid.selectedDate].note
                                    ? " · " + CalendarService.markedDays[calGrid.selectedDate].note : "")
                                : "Mark this day"
                            color: Theme.on_surface_variant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        // Mark / unmark toggle
                        Rectangle {
                            width: 28; height: 28
                            radius: 14
                            color: CalendarService.markedDays[calGrid.selectedDate]
                                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15)
                                : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                            border.color: CalendarService.markedDays[calGrid.selectedDate]
                                ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.4)
                                : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: CalendarService.markedDays[calGrid.selectedDate] ? "󰅗" : "󰃅"
                                color: CalendarService.markedDays[calGrid.selectedDate] ? Theme.error : Theme.primary
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (CalendarService.markedDays[calGrid.selectedDate])
                                        CalendarService.clearMarkedDay(calGrid.selectedDate)
                                    else
                                        CalendarService.setMarkedDay(calGrid.selectedDate, "primary", "")
                                }
                            }
                        }
                    }
                }

                // Bottom spacer so last card doesn't sit flush
                Item { implicitHeight: 2 }
            }
        }

        // ── Event dialog overlay ──────────────────────────────────────────────
        CalendarEventDialog {
            id: dialogLayer
            anchors.fill: parent
            open: false
            onAccepted:  { /* grid + day view auto-update via CalendarService bindings */ }
            onCancelled: { }
        }

        Keys.onEscapePressed: panel.open = false
        focus: true
    }
}
