pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
    id: combo

    property var options: []
    property string value: ""
    property string placeholderText: ""
    property color backgroundColor: "#eef3f1"
    property color hoverColor: "#e2ece8"
    property color borderColor: "#bdcbc6"
    property color textColor: "#22332e"
    property color mutedColor: "#6e817b"
    property color accentColor: "#087b68"
    property string filterQuery: ""
    readonly property var visibleOptions: filteredOptions(filterQuery)

    implicitWidth: 210
    implicitHeight: 28

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
        anchors.fill: parent
        radius: 7
        color: hover.hovered ? combo.hoverColor : combo.backgroundColor
        border { width: 1; color: combo.borderColor }

        TextInput {
            id: input
            anchors { left: parent.left; right: arrowDivider.left; top: parent.top; bottom: parent.bottom
                      leftMargin: 9; rightMargin: 7 }
            text: combo.value
            color: combo.textColor
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            clip: true
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
            onTextEdited: {
                combo.value = text;
                combo.filterQuery = text;
                if (!popup.opened) popup.open();
            }
            onAccepted: popup.close()
            Keys.onDownPressed: popup.open()

            Text {
                visible: input.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: combo.placeholderText
                color: combo.mutedColor
                font: input.font
            }
        }

        Rectangle {
            id: arrowDivider
            anchors { right: arrow.left; top: parent.top; bottom: parent.bottom }
            width: 1
            color: combo.borderColor
        }
        Text {
            id: arrow
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: popup.opened ? "󰅀" : "󰅂"
            color: combo.mutedColor
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
        }

        HoverHandler { id: hover }
        TapHandler { onTapped: combo.open() }
    }

    Popup {
        id: popup
        y: combo.height + 4
        width: combo.width
        padding: 4
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: null
        exit: null

        contentItem: ListView {
            id: optionList
            clip: true
            implicitHeight: Math.min(220, contentHeight)
            model: popup.opened ? combo.visibleOptions : []
            currentIndex: -1

            delegate: Rectangle {
                id: optionDelegate
                required property var modelData
                width: optionList.width
                height: 28
                radius: 6
                color: optionHover.hovered ? combo.hoverColor : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                    text: String(optionDelegate.modelData)
                    color: combo.textColor
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                }
                HoverHandler { id: optionHover }
                TapHandler {
                    onTapped: {
                        combo.value = String(optionDelegate.modelData);
                        input.text = combo.value;
                        combo.filterQuery = "";
                        popup.close();
                    }
                }
            }
        }

        background: Rectangle {
            radius: 8
            color: combo.backgroundColor
            border { width: 1; color: combo.borderColor }
        }
    }
}
