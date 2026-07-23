import QtQuick
import ".."

FocusScope {
    id: button

    property string text: ""
    property string glyph: ""
    property bool primary: false
    property bool danger: false
    property bool subtle: false
    property bool compact: false
    signal clicked()

    implicitWidth: labelRow.implicitWidth + (compact ? 18 : 24)
    implicitHeight: compact ? 28 : 34
    opacity: enabled ? 1 : 0.42
    activeFocusOnTab: enabled

    Rectangle {
        anchors.fill: parent
        radius: button.compact ? 8 : 10
        color: {
            if (button.primary)
                return hover.hovered ? Theme.primary : Theme.primary_container;
            if (button.danger)
                return hover.hovered ? Theme.glass(Theme.error, 0.20) : Theme.glass(Theme.error_container, 0.55);
            if (button.subtle)
                return hover.hovered ? Theme.glass(Theme.primary, 0.11) : "transparent";
            return hover.hovered ? Theme.surface_container_high : Theme.glass(Theme.surface_container_high, 0.72);
        }
        border {
            width: button.primary || button.subtle ? 0 : 1
            color: Theme.glass(Theme.outline_variant, 0.52)
        }

        Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: button.glyph === "" ? 0 : 6
            Text {
                visible: button.glyph !== ""
                text: button.glyph
                color: button.danger ? Theme.error
                    : button.primary ? Theme.on_primary_container : Theme.accent
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: button.compact ? 11 : 12
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                text: button.text
                color: button.danger ? Theme.error
                    : button.primary ? Theme.on_primary_container
                    : button.subtle ? Theme.accent : Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: button.compact ? 10 : 11
                       weight: button.primary ? Font.Medium : Font.Normal
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Math.max(0, parent.radius - 2)
            color: "transparent"
            border { width: button.activeFocus ? 1 : 0; color: Theme.primary }
        }
        HoverHandler { id: hover }
        TapHandler { enabled: button.enabled; onTapped: button.clicked() }
    }

    Keys.onSpacePressed: if (enabled) clicked()
    Keys.onReturnPressed: if (enabled) clicked()
}
