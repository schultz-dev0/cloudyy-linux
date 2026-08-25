pragma ComponentBehavior: Bound

// modules/calendar/CalendarGrid.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property int displayYear: new Date().getFullYear()
    property int displayMonth: new Date().getMonth()
    property string selectedDate: CalendarService.today()
    property string keyboardDate: selectedDate

    signal dateSelected(string date)
    signal requestPrevMonth()
    signal requestNextMonth()

    readonly property int _offset: CalendarService.firstWeekday(displayYear, displayMonth)
    readonly property int _numDays: CalendarService.daysInMonth(displayYear, displayMonth)
    readonly property int _cellCount: Math.ceil((_offset + _numDays) / 7) * 7

    activeFocusOnTab: true
    implicitHeight: headerRow.implicitHeight + dowRow.implicitHeight + grid.implicitHeight + 8

    function _dateForCell(idx) {
        const dayNum = idx - _offset + 1;
        if (dayNum < 1 || dayNum > _numDays)
            return "";
        return CalendarService.dateKey(displayYear, displayMonth, dayNum);
    }

    function _syncKeyboardDate() {
        const parts = keyboardDate.split("-");
        if (parts.length !== 3
                || parseInt(parts[0], 10) !== displayYear
                || parseInt(parts[1], 10) - 1 !== displayMonth) {
            keyboardDate = CalendarService.dateKey(displayYear, displayMonth, 1);
        }
    }

    function _moveKeyboardDate(delta) {
        const base = keyboardDate || selectedDate || CalendarService.today();
        const next = new Date(base + "T12:00:00");
        next.setDate(next.getDate() + delta);
        displayYear = next.getFullYear();
        displayMonth = next.getMonth();
        keyboardDate = CalendarService.dateKey(
            next.getFullYear(), next.getMonth(), next.getDate());
    }

    function _selectKeyboardDate() {
        if (keyboardDate)
            root.dateSelected(keyboardDate);
    }

    function focusInitial() {
        keyboardDate = selectedDate;
        _syncKeyboardDate();
        forceActiveFocus();
    }

    onDisplayYearChanged: _syncKeyboardDate()
    onDisplayMonthChanged: _syncKeyboardDate()
    onSelectedDateChanged: {
        if (!activeFocus)
            keyboardDate = selectedDate;
    }
    onActiveFocusChanged: {
        if (activeFocus)
            _syncKeyboardDate();
    }

    Keys.onLeftPressed: event => {
        root._moveKeyboardDate(-1);
        event.accepted = true;
    }
    Keys.onRightPressed: event => {
        root._moveKeyboardDate(1);
        event.accepted = true;
    }
    Keys.onUpPressed: event => {
        root._moveKeyboardDate(-7);
        event.accepted = true;
    }
    Keys.onDownPressed: event => {
        root._moveKeyboardDate(7);
        event.accepted = true;
    }
    Keys.onReturnPressed: event => {
        root._selectKeyboardDate();
        event.accepted = true;
    }
    Keys.onEnterPressed: event => {
        root._selectKeyboardDate();
        event.accepted = true;
    }
    Keys.onSpacePressed: event => {
        root._selectKeyboardDate();
        event.accepted = true;
    }

    RowLayout {
        id: headerRow
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 8

        Rectangle {
            id: prevButton
            Layout.leftMargin: 2
            implicitWidth: 28
            implicitHeight: 28
            radius: 8
            color: activeFocus ? Theme.islandFocus : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Theme.islandFocus
            activeFocusOnTab: true

            Text {
                anchors.centerIn: parent
                text: "󰍞"
                color: prevButton.activeFocus ? Theme.accentText : Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
                renderType: Text.NativeRendering
            }

            Keys.onReturnPressed: event => {
                root.requestPrevMonth();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.requestPrevMonth();
                event.accepted = true;
            }
            Keys.onSpacePressed: event => {
                root.requestPrevMonth();
                event.accepted = true;
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestPrevMonth()
            }
        }

        Text {
            text: CalendarService.monthLabel(root.displayYear, root.displayMonth)
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            font.weight: Font.Bold
            renderType: Text.NativeRendering
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            id: nextButton
            Layout.rightMargin: 2
            implicitWidth: 28
            implicitHeight: 28
            radius: 8
            color: activeFocus ? Theme.islandFocus : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Theme.islandFocus
            activeFocusOnTab: true

            Text {
                anchors.centerIn: parent
                text: "󰍟"
                color: nextButton.activeFocus ? Theme.accentText : Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 16
                renderType: Text.NativeRendering
            }

            Keys.onReturnPressed: event => {
                root.requestNextMonth();
                event.accepted = true;
            }
            Keys.onEnterPressed: event => {
                root.requestNextMonth();
                event.accepted = true;
            }
            Keys.onSpacePressed: event => {
                root.requestNextMonth();
                event.accepted = true;
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestNextMonth()
            }
        }
    }

    Row {
        id: dowRow
        anchors {
            top: headerRow.bottom
            left: parent.left
            right: parent.right
            topMargin: 6
        }

        Repeater {
            model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
            delegate: Text {
                required property string modelData
                width: root.width / 7
                text: modelData
                color: Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                renderType: Text.NativeRendering
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Grid {
        id: grid
        anchors {
            top: dowRow.bottom
            left: parent.left
            right: parent.right
            topMargin: 2
        }
        columns: 7

        Repeater {
            model: root._cellCount

            delegate: Item {
                id: cellItem
                required property int index
                readonly property string cellDate: root._dateForCell(index)
                readonly property bool isCurrentMonth: cellDate !== ""
                readonly property bool isToday: cellDate === CalendarService.today()
                readonly property bool isSelected: cellDate === root.selectedDate
                readonly property bool isKeyboardFocused:
                    cellDate === root.keyboardDate && root.activeFocus
                readonly property bool isMarked:
                    cellDate !== "" && !!CalendarService.markedDays[cellDate]
                readonly property var markedInfo:
                    isMarked ? CalendarService.markedDays[cellDate] : null
                readonly property var dots:
                    cellDate !== "" ? CalendarService.dotsForDate(cellDate) : []

                width: root.width / 7
                height: 48

                Rectangle {
                    anchors.centerIn: parent
                    width: 38
                    height: 38
                    radius: 19
                    color: "transparent"
                    border.width: cellItem.isKeyboardFocused ? 2
                        : (cellItem.isMarked && !cellItem.isSelected ? 2 : 0)
                    border.color: cellItem.isKeyboardFocused ? Theme.islandFocus
                        : (cellItem.markedInfo
                            ? Theme._minLightness(
                                CalendarService.tagColor(cellItem.markedInfo.color), 0.55)
                            : "transparent")
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 34
                    height: 34
                    radius: 17
                    color: cellItem.isSelected
                        ? Qt.rgba(Theme.islandAccent.r, Theme.islandAccent.g, Theme.islandAccent.b, 0.28)
                        : "transparent"
                    border.width: cellItem.isToday ? 2 : 0
                    border.color: Theme.islandAccent
                }

                Text {
                    anchors.centerIn: parent
                    text: {
                        const n = cellItem.index - root._offset + 1;
                        return n >= 1 && n <= root._numDays ? n.toString() : "";
                    }
                    color: cellItem.isToday ? Theme.islandAccent
                        : cellItem.isCurrentMonth ? Theme.islandOnSurface
                        : Theme.islandOnSurfaceVariant
                    opacity: cellItem.isCurrentMonth ? 1.0 : 0.35
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.weight: cellItem.isToday ? Font.Bold : Font.Normal
                    renderType: Text.NativeRendering
                }

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
                            width: 5
                            height: 5
                            radius: 3
                            color: CalendarService.tagColor(modelData)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: cellItem.isCurrentMonth
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.keyboardDate = cellItem.cellDate;
                        root.dateSelected(cellItem.cellDate);
                    }
                }
            }
        }
    }
}
