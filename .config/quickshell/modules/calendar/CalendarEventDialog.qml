pragma ComponentBehavior: Bound

// modules/calendar/CalendarEventDialog.qml
import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root
    visible: open

    // ── Public API ────────────────────────────────────────────────────────────
    property bool open: false
    property string editId: ""          // "" → add mode; set to event id → edit mode
    property string prefillDate: CalendarService.today()

    signal accepted()
    signal cancelled()

    function _cancel() {
        root.open = false;
        root.cancelled();
    }

    function _focusables() {
        const items = [_titleField, _dateField, _allDayCheck];
        if (!_allDayCheck.checked)
            items.push(_startField, _endField);
        for (let i = 0; i < colorRepeater.count; i++)
            items.push(colorRepeater.itemAt(i));
        items.push(_descField, cancelButton, saveButton);
        return items;
    }

    function _moveFocus(delta) {
        const items = _focusables();
        let current = -1;
        for (let i = 0; i < items.length; i++) {
            if (items[i] && items[i].activeFocus) {
                current = i;
                break;
            }
        }
        const next = ((current + delta) % items.length + items.length) % items.length;
        items[next].forceActiveFocus();
    }

    function openAdd(date) {
        root.editId = ""
        _titleField.text      = ""
        _dateField.text       = date || CalendarService.today()
        _startField.text      = ""
        _endField.text        = ""
        _descField.text       = ""
        _allDayCheck.checked  = false
        _selectedColor        = "primary"
        root.open = true
        _titleField.forceActiveFocus()
    }

    function openEdit(event) {
        root.editId           = event.id
        _titleField.text      = event.title      || ""
        _dateField.text       = event.date        || CalendarService.today()
        _startField.text      = event.startTime   || ""
        _endField.text        = event.endTime     || ""
        _descField.text       = event.description || ""
        _allDayCheck.checked  = event.allDay      || false
        _selectedColor        = event.color       || "primary"
        root.open = true
        _titleField.forceActiveFocus()
    }

    function _commit() {
        const ev = {
            title:       _titleField.text.trim(),
            date:        _dateField.text.trim(),
            allDay:      _allDayCheck.checked,
            startTime:   _allDayCheck.checked ? "" : _startField.text.trim(),
            endTime:     _allDayCheck.checked ? "" : _endField.text.trim(),
            color:       root._selectedColor,
            description: _descField.text.trim()
        }
        if (!ev.title || !ev.date) return
        if (root.editId)
            CalendarService.updateEvent(root.editId, ev)
        else
            CalendarService.addEvent(ev)
        root.open = false
        root.accepted()
    }

    // ── Internal state ────────────────────────────────────────────────────────
    property string _selectedColor: "primary"

    readonly property var _colorOptions: [
        { tag: "primary",   color: Theme.accent   },
        { tag: "secondary", color: Theme.accentAlt  },
        { tag: "tertiary",  color: Theme.info   },
        { tag: "error",     color: Theme.error      }
    ]

    // ── Slide animation ───────────────────────────────────────────────────────
    anchors.fill: parent
    focus: open
    Keys.priority: Keys.BeforeItem
    Keys.onTabPressed: event => {
        root._moveFocus(1);
        event.accepted = true;
    }
    Keys.onBacktabPressed: event => {
        root._moveFocus(-1);
        event.accepted = true;
    }
    Keys.onEscapePressed: event => {
        root._cancel();
        event.accepted = true;
    }

    Rectangle {
        id: overlay
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Perf.opacityMs(200) } }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root._cancel()
            }
        }
    }

    Rectangle {
        id: sheet
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: sheetContent.implicitHeight + 32
        radius: 20
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.97)
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.3)
        border.width: 1

        y: root.open ? 0 : height
        Behavior on y { NumberAnimation { duration: Perf.geometryMs(280); easing.type: Easing.OutCubic } }

        // Swallow clicks so overlay close doesn't fire
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: sheetContent
            anchors {
                fill: parent
                margins: 16
            }
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: root.editId ? "Edit Event" : "New Event"
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    renderType: Text.NativeRendering
                    Layout.fillWidth: true
                }

                Text {
                    text: "󰅖"
                    color: Theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                    renderType: Text.NativeRendering
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._cancel()
                    }
                }
            }

            // Title field
            StyledField {
                id: _titleField
                Layout.fillWidth: true
                placeholderText: "Event title"
                onAccepted: root._commit()
            }

            // Date + All-day row
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StyledField {
                    id: _dateField
                    Layout.fillWidth: true
                    placeholderText: "Date (YYYY-MM-DD)"
                    inputMethodHints: Qt.ImhDate
                }

                // All-day toggle
                RowLayout {
                    spacing: 6
                    Text {
                        text: "All day"
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        renderType: Text.NativeRendering
                    }
                    Rectangle {
                        id: _allDayCheck
                        property bool checked: false
                        implicitWidth: 22; implicitHeight: 22
                        radius: 6
                        color: checked
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                            : Theme.surfaceRaised
                        border.color: activeFocus ? Theme.islandFocus
                            : checked ? Theme.accent
                            : Qt.rgba(Theme.border.r,
                                Theme.border.g, Theme.border.b, 0.5)
                        border.width: activeFocus ? 2 : 1.5
                        activeFocusOnTab: true

                        Text {
                            anchors.centerIn: parent
                            visible: _allDayCheck.checked
                            text: "󰄬"
                            color: Theme.accent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
                            renderType: Text.NativeRendering
                        }

                        Keys.onReturnPressed: event => {
                            _allDayCheck.checked = !_allDayCheck.checked;
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: event => {
                            _allDayCheck.checked = !_allDayCheck.checked;
                            event.accepted = true;
                        }
                        Keys.onSpacePressed: event => {
                            _allDayCheck.checked = !_allDayCheck.checked;
                            event.accepted = true;
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: _allDayCheck.checked = !_allDayCheck.checked
                        }
                    }
                }
            }

            // Time row (hidden when all-day)
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: !_allDayCheck.checked

                StyledField {
                    id: _startField
                    Layout.fillWidth: true
                    placeholderText: "Start (HH:MM)"
                    inputMethodHints: Qt.ImhTime
                }

                Text {
                    text: "–"
                    color: Theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    renderType: Text.NativeRendering
                }

                StyledField {
                    id: _endField
                    Layout.fillWidth: true
                    placeholderText: "End (HH:MM)"
                    inputMethodHints: Qt.ImhTime
                }
            }

            // Color picker
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "Color"
                    color: Theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    renderType: Text.NativeRendering
                }

                Repeater {
                    id: colorRepeater
                    model: root._colorOptions
                    delegate: Rectangle {
                        id: colorOption
                        required property var modelData
                        width: 22; height: 22
                        radius: 11
                        color: modelData.color
                        border.width: root._selectedColor === modelData.tag ? 3 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.7)
                        activeFocusOnTab: true

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -3
                            radius: width / 2
                            color: "transparent"
                            border.width: parent.activeFocus ? 2 : 0
                            border.color: Theme.text
                        }

                        Keys.onReturnPressed: event => {
                            root._selectedColor = modelData.tag;
                            event.accepted = true;
                        }
                        Keys.onEnterPressed: event => {
                            root._selectedColor = modelData.tag;
                            event.accepted = true;
                        }
                        Keys.onSpacePressed: event => {
                            root._selectedColor = modelData.tag;
                            event.accepted = true;
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._selectedColor = colorOption.modelData.tag
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Description
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 72
                radius: 10
                color: Theme.surfaceRaised
                border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.35)
                border.width: 1

                TextEdit {
                    id: _descField
                    anchors { fill: parent; margins: 10 }
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    renderType: TextEdit.NativeRendering
                    activeFocusOnTab: true
                    wrapMode: TextEdit.WordWrap
                    selectedTextColor: Theme.accentText
                    selectionColor: Theme.accent

                    Text {
                        visible: _descField.text.length === 0
                        anchors.fill: parent
                        text: "Description (optional)"
                        color: Theme.textMuted
                        font: _descField.font
                        opacity: 0.6
                        renderType: Text.NativeRendering
                    }
                }
            }

            // Action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: cancelButton
                    implicitWidth: cancelText.implicitWidth + 24
                    implicitHeight: 34
                    radius: 10
                    color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.2)
                    border.color: activeFocus ? Theme.islandFocus
                        : Qt.rgba(Theme.border.r,
                            Theme.border.g, Theme.border.b, 0.4)
                    border.width: activeFocus ? 2 : 1
                    activeFocusOnTab: true

                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: event => {
                        root._cancel();
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        root._cancel();
                        event.accepted = true;
                    }
                    Keys.onSpacePressed: event => {
                        root._cancel();
                        event.accepted = true;
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._cancel()
                    }
                }

                Rectangle {
                    id: saveButton
                    implicitWidth: saveText.implicitWidth + 24
                    implicitHeight: 34
                    radius: 10
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                    border.color: activeFocus ? Theme.islandFocus
                        : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5)
                    border.width: activeFocus ? 2 : 1
                    activeFocusOnTab: true

                    Text {
                        id: saveText
                        anchors.centerIn: parent
                        text: root.editId ? "Save" : "Add"
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: event => {
                        root._commit();
                        event.accepted = true;
                    }
                    Keys.onEnterPressed: event => {
                        root._commit();
                        event.accepted = true;
                    }
                    Keys.onSpacePressed: event => {
                        root._commit();
                        event.accepted = true;
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._commit()
                    }
                }
            }
        }
    }

    // ── Inline styled text field component ───────────────────────────────────
    component StyledField: FocusScope {
        id: sfRoot
        property alias text: sfInput.text
        property alias placeholderText: sfPlaceholder.text
        property alias inputMethodHints: sfInput.inputMethodHints
        signal accepted()

        implicitHeight: 36
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Theme.surfaceRaised
            border.color: sfRoot.activeFocus
                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.35)
            border.width: sfRoot.activeFocus ? 1.5 : 1
        }

        TextInput {
            id: sfInput
            focus: true
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            renderType: TextInput.NativeRendering
            selectedTextColor: Theme.accentText
            selectionColor: Theme.accent
            onAccepted: sfRoot.accepted()

            Text {
                id: sfPlaceholder
                visible: sfInput.text.length === 0
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                color: Theme.textMuted
                font: sfInput.font
                opacity: 0.6
                renderType: Text.NativeRendering
            }
        }
    }
}
