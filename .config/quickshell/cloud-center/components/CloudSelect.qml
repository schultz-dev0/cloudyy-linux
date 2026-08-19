pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import ".."

FocusScope {
    id: select

    property var options: []
    property int currentIndex: -1
    property string textRole: ""
    property string placeholderText: "Choose…"
    property bool compact: false
    signal activated(int index)

    implicitWidth: 180
    implicitHeight: compact ? 32 : 36
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.42

    function labelFor(item) {
        if (item === undefined || item === null) return "";
        if (textRole !== "" && typeof item === "object") return String(item[textRole] ?? "");
        return String(item);
    }

    function choose(index) {
        currentIndex = index;
        activated(index);
        menu.close();
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: 2
        color: disclosureHover.hovered || menu.opened
            ? Theme.surface_container_highest
            : Theme.surface_container_high
        border {
            width: menu.opened || select.activeFocus ? 2 : 1
            color: menu.opened || select.activeFocus ? Theme.primary : Theme.hairline
        }

        Rectangle {
            anchors { left: parent.left; right: disclosure.left; top: parent.top; bottom: parent.bottom
                      margins: 1; rightMargin: 0 }
            radius: 1
            color: selectHover.hovered
                ? Theme.surface_container
                : Theme.surface_container_lowest

            Rectangle {
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: parent.radius
                color: parent.color
            }
        }

        Text {
            anchors { left: parent.left; leftMargin: 10; right: disclosure.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            text: select.currentIndex >= 0 && select.currentIndex < select.options.length
                ? select.labelFor(select.options[select.currentIndex]) : select.placeholderText
            elide: Text.ElideRight
            color: select.currentIndex >= 0 ? Theme.textPrimary : Theme.textMuted
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: select.compact ? 10 : 11
                   hintingPreference: Font.PreferVerticalHinting }
        }

        Rectangle {
            id: disclosure
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 1 }
            width: 32
            color: "transparent"

            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 1
                color: Theme.hairline
            }
            Text {
                anchors.centerIn: parent
                text: menu.opened ? "⌃" : "⌄"
                color: menu.opened ? Theme.accent : Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13
                       hintingPreference: Font.PreferVerticalHinting }
            }
            HoverHandler { id: disclosureHover }
        }

        Rectangle {
            anchors { fill: parent; margins: 2 }
            visible: menu.opened || select.activeFocus
            radius: 1
            color: "transparent"
            border { width: 1; color: Theme.glass(Theme.primary, 0.22) }
        }
        HoverHandler { id: selectHover }
        TapHandler {
            enabled: select.enabled
            onTapped: {
                select.forceActiveFocus();
                menu.opened ? menu.close() : menu.open();
            }
        }
    }

    Popup {
        id: menu
        y: select.height + 6
        width: select.width
        padding: 5
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: null; exit: null

        background: Rectangle {
            radius: 2
            color: Theme.surface_container_high
            border { width: 1; color: Theme.hairline }
        }
        contentItem: ListView {
            id: optionList
            clip: true
            implicitHeight: Math.min(217, contentHeight)
            boundsBehavior: Flickable.StopAtBounds
            model: menu.opened ? select.options : []
            delegate: Rectangle {
                id: optionRow
                required property var modelData
                required property int index
                width: optionList.width; height: 31; radius: 2
                color: optionHover.hovered || index === select.currentIndex
                    ? Theme.glass(Theme.primary, 0.12) : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: 9; right: selectedMark.left; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    text: select.labelFor(optionRow.modelData)
                    elide: Text.ElideRight
                    color: index === select.currentIndex ? Theme.accent : Theme.textPrimary
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           weight: index === select.currentIndex ? Font.Medium : Font.Normal
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Text {
                    id: selectedMark
                    anchors { right: parent.right; rightMargin: 9; verticalCenter: parent.verticalCenter }
                    visible: optionRow.index === select.currentIndex
                    text: "✓"
                    color: Theme.accent
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                }
                HoverHandler { id: optionHover }
                TapHandler { onTapped: select.choose(optionRow.index) }
            }
        }
    }

    Keys.onSpacePressed: if (enabled) menu.open()
    Keys.onReturnPressed: if (enabled) menu.open()
    Keys.onDownPressed: if (enabled) menu.open()
}
