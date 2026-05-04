pragma ComponentBehavior: Bound

// modules/calendar/CalendarGrid.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property int  displayYear:  new Date().getFullYear()
    property int  displayMonth: new Date().getMonth()   // 0-based
    property string selectedDate: CalendarService.today()

    signal dateSelected(string date)
    signal requestPrevMonth()
    signal requestNextMonth()

    // ── Helpers ───────────────────────────────────────────────────────────────
    readonly property int _offset:   CalendarService.firstWeekday(displayYear, displayMonth)
    readonly property int _numDays:  CalendarService.daysInMonth(displayYear, displayMonth)
    readonly property int _cellCount: Math.ceil((_offset + _numDays) / 7) * 7

    function _tagColor(tag) {
        return tag === "secondary" ? Theme.secondary
             : tag === "tertiary"  ? Theme.tertiary
             : tag === "error"     ? Theme.error
             : Theme.primary
    }

    function _dateForCell(idx) {
        const dayNum = idx - _offset + 1
        if (dayNum < 1 || dayNum > _numDays) return ""
        return CalendarService.dateKey(displayYear, displayMonth, dayNum)
    }

    implicitHeight: headerRow.implicitHeight + dowRow.implicitHeight + grid.implicitHeight + 8

    // ── Month navigation header ───────────────────────────────────────────────
    RowLayout {
        id: headerRow
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 8

        Text {
            text: "󰍞"
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            Layout.leftMargin: 4

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestPrevMonth()
            }
        }

        Text {
            text: CalendarService.monthLabel(root.displayYear, root.displayMonth)
            color: Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            font.weight: Font.Bold
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            text: "󰍟"
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            Layout.rightMargin: 4

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestNextMonth()
            }
        }
    }

    // ── Day-of-week headers ───────────────────────────────────────────────────
    Row {
        id: dowRow
        anchors {
            top: headerRow.bottom
            left: parent.left
            right: parent.right
            topMargin: 6
        }
        Repeater {
            model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
            delegate: Text {
                required property string modelData
                width: root.width / 7
                text: modelData
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // ── Day cells grid ────────────────────────────────────────────────────────
    Grid {
        id: grid
        anchors {
            top: dowRow.bottom
            left: parent.left
            right: parent.right
            topMargin: 2
        }
        columns: 7
        rowSpacing: 0
        columnSpacing: 0

        Repeater {
            model: root._cellCount

            delegate: Item {
                id: cellItem
                required property int index
                readonly property string cellDate: root._dateForCell(index)
                readonly property bool isCurrentMonth: cellDate !== ""
                readonly property bool isToday: cellDate === CalendarService.today()
                readonly property bool isSelected: cellDate === root.selectedDate
                readonly property bool isMarked: cellDate !== "" && !!CalendarService.markedDays[cellDate]
                readonly property var markedInfo: isMarked ? CalendarService.markedDays[cellDate] : null
                readonly property var dots: cellDate !== "" ? CalendarService.dotsForDate(cellDate) : []

                width: root.width / 7
                height: 48

                // Marked day ring
                Rectangle {
                    anchors.centerIn: parent
                    width: 36; height: 36
                    radius: 18
                    color: "transparent"
                    border.width: 2
                    border.color: cellItem.isMarked && cellItem.markedInfo
                        ? root._tagColor(cellItem.markedInfo.color)
                        : "transparent"
                    visible: cellItem.isMarked && !cellItem.isSelected
                }

                // Selected / today background
                Rectangle {
                    anchors.centerIn: parent
                    width: 34; height: 34
                    radius: 17
                    color: cellItem.isSelected
                        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.28)
                        : "transparent"
                    border.width: cellItem.isToday ? 2 : 0
                    border.color: Theme.primary
                }

                // Day number — centered to match the ring circles
                Text {
                    anchors.centerIn: parent
                    text: {
                        const n = cellItem.index - root._offset + 1
                        return (n >= 1 && n <= root._numDays) ? n.toString() : ""
                    }
                    color: cellItem.isToday        ? Theme.primary
                         : cellItem.isCurrentMonth ? Theme.on_surface
                         : Theme.on_surface_variant
                    opacity: cellItem.isCurrentMonth ? 1.0 : 0.35
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.weight:    cellItem.isToday ? Font.Bold : Font.Normal
                }

                // Event dots row
                Row {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                        bottomMargin: 4
                    }
                    spacing: 3
                    visible: cellItem.dots.length > 0

                    Repeater {
                        model: cellItem.dots
                        delegate: Rectangle {
                            required property string modelData
                            width: 5; height: 5
                            radius: 3
                            color: root._tagColor(modelData)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: cellItem.isCurrentMonth
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dateSelected(cellItem.cellDate)
                }
            }
        }
    }
}
