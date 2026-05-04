pragma ComponentBehavior: Bound

// modules/calendar/CalendarEventDialog.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
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
        { tag: "primary",   color: Theme.primary   },
        { tag: "secondary", color: Theme.secondary  },
        { tag: "tertiary",  color: Theme.tertiary   },
        { tag: "error",     color: Theme.error      }
    ]

    // ── Slide animation ───────────────────────────────────────────────────────
    anchors.fill: parent

    Rectangle {
        id: overlay
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.4)
        opacity: root.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.open = false
                root.cancelled()
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
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1

        y: root.open ? 0 : height
        Behavior on y { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

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
                    color: Theme.on_surface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                }

                Text {
                    text: "󰅖"
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 18
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.open = false; root.cancelled() }
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
                        color: Theme.on_surface_variant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                    Rectangle {
                        id: _allDayCheck
                        property bool checked: false
                        width: 22; height: 22
                        radius: 6
                        color: checked
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                            : Theme.surface_container
                        border.color: checked ? Theme.primary : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.5)
                        border.width: 1.5

                        Text {
                            anchors.centerIn: parent
                            visible: _allDayCheck.checked
                            text: "󰄬"
                            color: Theme.primary
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 13
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
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
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
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                Repeater {
                    model: root._colorOptions
                    delegate: Rectangle {
                        required property var modelData
                        width: 22; height: 22
                        radius: 11
                        color: modelData.color
                        border.width: root._selectedColor === modelData.tag ? 3 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.7)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root._selectedColor = modelData.tag
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
                color: Theme.surface_container
                border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
                border.width: 1

                TextEdit {
                    id: _descField
                    anchors { fill: parent; margins: 10 }
                    color: Theme.on_surface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    wrapMode: TextEdit.WordWrap
                    selectedTextColor: Theme.on_primary
                    selectionColor: Theme.primary

                    Text {
                        visible: _descField.text.length === 0
                        anchors.fill: parent
                        text: "Description (optional)"
                        color: Theme.on_surface_variant
                        font: _descField.font
                        opacity: 0.6
                    }
                }
            }

            // Action buttons
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: cancelText.implicitWidth + 24
                    implicitHeight: 34
                    radius: 10
                    color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.2)
                    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)
                    border.width: 1

                    Text {
                        id: cancelText
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: Theme.on_surface_variant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.open = false; root.cancelled() }
                    }
                }

                Rectangle {
                    implicitWidth: saveText.implicitWidth + 24
                    implicitHeight: 34
                    radius: 10
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                    border.width: 1

                    Text {
                        id: saveText
                        anchors.centerIn: parent
                        text: root.editId ? "Save" : "Add"
                        color: Theme.primary
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.Medium
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
    component StyledField: Rectangle {
        id: sfRoot
        property alias text: sfInput.text
        property alias placeholderText: sfPlaceholder.text
        property alias inputMethodHints: sfInput.inputMethodHints
        signal accepted()

        implicitHeight: 36
        radius: 10
        color: Theme.surface_container
        border.color: sfInput.activeFocus
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
            : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
        border.width: sfInput.activeFocus ? 1.5 : 1

        TextInput {
            id: sfInput
            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            selectedTextColor: Theme.on_primary
            selectionColor: Theme.primary
            onAccepted: sfRoot.accepted()

            Text {
                id: sfPlaceholder
                visible: sfInput.text.length === 0
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                color: Theme.on_surface_variant
                font: sfInput.font
                opacity: 0.6
            }
        }
    }
}
