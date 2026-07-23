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
    implicitHeight: compact ? 30 : 36
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
        anchors.fill: parent
        radius: select.compact ? 8 : 10
        color: menu.opened || select.activeFocus
            ? Theme.glass(Theme.surface_container_lowest, 0.96)
            : selectHover.hovered
                ? Theme.glass(Theme.surface_container_high, 0.88)
                : Theme.glass(Theme.surface_container_low, 0.82)
        border {
            width: menu.opened || select.activeFocus ? 1.5 : 1
            color: menu.opened || select.activeFocus ? Theme.primary
                : Theme.glass(Theme.outline_variant, 0.56)
        }

        Text {
            anchors { left: parent.left; leftMargin: 11; right: chevron.left; rightMargin: 8
                      verticalCenter: parent.verticalCenter }
            text: select.currentIndex >= 0 && select.currentIndex < select.options.length
                ? select.labelFor(select.options[select.currentIndex]) : select.placeholderText
            elide: Text.ElideRight
            color: select.currentIndex >= 0 ? Theme.textPrimary : Theme.textMuted
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: select.compact ? 10 : 11
                   hintingPreference: Font.PreferVerticalHinting }
        }
        Text {
            id: chevron
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: menu.opened ? "\u{f0143}" : "\u{f0140}"
            color: Theme.textMuted
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                   hintingPreference: Font.PreferVerticalHinting }
        }
        HoverHandler { id: selectHover }
        TapHandler { enabled: select.enabled; onTapped: menu.opened ? menu.close() : menu.open() }
    }

    Popup {
        id: menu
        y: select.height + 5
        width: select.width
        padding: 5
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        enter: null; exit: null

        background: Rectangle {
            radius: 11
            color: Theme.glass(Theme.surface_container, 0.98)
            border { width: 1; color: Theme.glass(Theme.outline_variant, 0.62) }
        }
        contentItem: ListView {
            id: optionList
            clip: true
            implicitHeight: Math.min(240, contentHeight)
            model: menu.opened ? select.options : []
            delegate: Rectangle {
                id: optionRow
                required property var modelData
                required property int index
                width: optionList.width; height: 32; radius: 8
                color: optionHover.hovered || index === select.currentIndex
                    ? Theme.glass(Theme.primary, 0.12) : "transparent"
                Text {
                    anchors { left: parent.left; leftMargin: 9; right: parent.right; rightMargin: 9
                              verticalCenter: parent.verticalCenter }
                    text: select.labelFor(optionRow.modelData)
                    elide: Text.ElideRight
                    color: index === select.currentIndex ? Theme.accent : Theme.textPrimary
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           weight: index === select.currentIndex ? Font.Medium : Font.Normal
                           hintingPreference: Font.PreferVerticalHinting }
                }
                HoverHandler { id: optionHover }
                TapHandler { onTapped: select.choose(optionRow.index) }
            }
        }
    }

    Keys.onSpacePressed: if (enabled) menu.open()
    Keys.onReturnPressed: if (enabled) menu.open()
}
