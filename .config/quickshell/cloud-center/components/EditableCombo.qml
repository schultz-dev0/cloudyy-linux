pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
    id: combo

    property var options: []
    property string value: ""
    property string placeholderText: ""
    property string popupHint: ""
    property color backgroundColor: "#eef3f1"
    property color hoverColor: "#e2ece8"
    property color borderColor: "#bdcbc6"
    property color textColor: "#22332e"
    property color mutedColor: "#6e817b"
    property color accentColor: "#087b68"
    property string filterQuery: ""
    property bool editorDirty: false
    readonly property var visibleOptions: filteredOptions(filterQuery)

    signal optionSelected(var value)
    signal textAccepted(string text)
    signal editorBlurred(string text)

    implicitWidth: 210
    implicitHeight: 34

    function filteredOptions(query) {
        const needle = String(query ?? "").trim().toLowerCase();
        if (needle === "") return combo.options.slice();
        return combo.options.filter(option => String(option).toLowerCase().includes(needle));
    }

    function open() {
        // Opening the picker should always reveal every advertised mode. Once
        // the user types, the menu switches to filtering that new input.
        combo.filterQuery = "";
        input.forceActiveFocus();
        popup.open();
    }

    onValueChanged: {
        if (input.text !== value)
            input.text = value;
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: 8
        color: disclosureHover.hovered || popup.opened
            ? combo.hoverColor : Qt.lighter(combo.backgroundColor, 1.08)
        border {
            width: input.activeFocus || popup.opened ? 2 : 1
            color: input.activeFocus || popup.opened ? combo.accentColor : combo.borderColor
        }

        Rectangle {
            id: editorWell
            anchors { left: parent.left; right: disclosure.left; top: parent.top; bottom: parent.bottom
                      margins: 1; rightMargin: 0 }
            radius: 7
            color: editorHover.hovered
                ? Qt.lighter(combo.backgroundColor, 1.04)
                : Qt.darker(combo.backgroundColor, 1.12)

            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: parent.radius
                color: parent.color
            }

            TextInput {
                id: input
                anchors { fill: parent; leftMargin: 9; rightMargin: 8 }
                text: combo.value
                color: combo.textColor
                verticalAlignment: TextInput.AlignVCenter
                selectByMouse: true
                clip: true
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 10
                    hintingPreference: Font.PreferVerticalHinting
                }
                onTextEdited: {
                    combo.editorDirty = true;
                    combo.value = text;
                    combo.filterQuery = text;
                    if (!popup.opened) popup.open();
                }
                onAccepted: {
                    popup.close();
                    if (combo.editorDirty)
                        combo.textAccepted(text);
                    combo.editorDirty = false;
                }
                onActiveFocusChanged: {
                    if (!activeFocus)
                        blurTimer.restart();
                }
                Keys.onDownPressed: popup.open()

                Text {
                    visible: input.text === ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: combo.placeholderText
                    color: combo.mutedColor
                    renderType: Text.NativeRendering
                    font: input.font
                }
            }

            HoverHandler { id: editorHover }
        }

        Rectangle {
            id: disclosure
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 1 }
            width: 32
            color: "transparent"

            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 1
                color: combo.borderColor
            }
            Text {
                anchors.centerIn: parent
                text: popup.opened ? "⌃" : "⌄"
                color: popup.opened ? combo.accentColor : combo.mutedColor
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
            }
            HoverHandler { id: disclosureHover }
            TapHandler { onTapped: popup.opened ? popup.close() : combo.open() }
        }

        Rectangle {
            anchors { fill: parent; margins: 2 }
            visible: input.activeFocus || popup.opened
            radius: 6
            color: "transparent"
            border {
                width: 1
                color: Qt.rgba(combo.accentColor.r, combo.accentColor.g,
                    combo.accentColor.b, 0.22)
            }
        }
    }

    Timer {
        id: blurTimer
        interval: 0
        onTriggered: {
            if (!input.activeFocus && combo.editorDirty) {
                combo.editorBlurred(input.text);
                combo.editorDirty = false;
            }
        }
    }

    Popup {
        id: popup
        y: combo.height + 6
        width: combo.width
        padding: 5
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: null
        exit: null

        contentItem: Column {
            ListView {
                id: optionList
                width: parent.width
                height: Math.min(217, contentHeight)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: popup.opened ? combo.visibleOptions : []
                currentIndex: -1

                delegate: Rectangle {
                    id: optionDelegate
                    required property var modelData
                    width: optionList.width
                    height: 31
                    radius: 7
                    color: optionHover.hovered
                        || String(optionDelegate.modelData) === combo.value
                        ? Qt.rgba(combo.accentColor.r, combo.accentColor.g,
                            combo.accentColor.b, 0.13)
                        : "transparent"
                    Text {
                        anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                        text: String(optionDelegate.modelData)
                        color: String(optionDelegate.modelData) === combo.value
                            ? combo.accentColor : combo.textColor
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                        visible: String(optionDelegate.modelData) === combo.value
                        text: "✓"
                        color: combo.accentColor
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                    }
                    HoverHandler { id: optionHover }
                    TapHandler {
                        onTapped: {
                            combo.value = String(optionDelegate.modelData);
                            input.text = combo.value;
                            combo.filterQuery = "";
                            combo.editorDirty = false;
                            popup.close();
                            combo.optionSelected(optionDelegate.modelData);
                        }
                    }
                }
            }

            Rectangle {
                visible: combo.popupHint !== ""
                width: parent.width
                height: visible ? 1 : 0
                color: combo.borderColor
            }
            Item {
                visible: combo.popupHint !== ""
                width: parent.width
                height: visible ? 27 : 0
                Text {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: combo.popupHint
                    color: combo.mutedColor
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 8 }
                }
            }
        }

        background: Rectangle {
            radius: 10
            color: Qt.lighter(combo.backgroundColor, 1.04)
            border { width: 1; color: combo.borderColor }
        }
    }
}
