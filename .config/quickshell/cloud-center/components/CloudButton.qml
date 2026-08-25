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
        radius: 2
        clip: true
        color: {
            if (button.primary)
                return hover.hovered ? Theme.accent : Theme.accentMuted;
            if (button.danger)
                return Theme.glass(Theme.error, hover.hovered ? 0.20 : 0.12);
            if (button.subtle)
                return hover.hovered ? Theme.glass(Theme.accent, 0.11) : "transparent";
            return hover.hovered ? Theme.surfaceOverlay : Theme.surfaceRaised;
        }
        border {
            width: button.primary || button.subtle ? 0 : 1
            color: Theme.hairline
        }

        // Dots material — faint texture on the fill, text stays fully opaque.
        DotTexture {
            anchors.fill: parent
            visible: !button.subtle || hover.hovered
            tint: button.danger ? Theme.error
                : button.primary ? Theme.accentText : Theme.accent
            dotAlpha: 0.16
            cell: 5
            dotRadius: 0.7
        }

        Row {
            id: labelRow
            anchors.centerIn: parent
            spacing: button.glyph === "" ? 0 : 6
            Text {
                visible: button.glyph !== ""
                text: button.glyph
                color: button.danger ? Theme.error
                    : button.primary ? Theme.accentText : Theme.accent
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: button.compact ? 11 : 12
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                text: button.text
                color: button.danger ? Theme.error
                    : button.primary ? Theme.accentText
                    : button.subtle ? Theme.accent : Theme.text
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
            border { width: button.activeFocus ? 1 : 0; color: Theme.accent }
        }
        HoverHandler { id: hover }
        TapHandler { enabled: button.enabled; onTapped: button.clicked() }
    }

    Keys.onSpacePressed: if (enabled) clicked()
    Keys.onReturnPressed: if (enabled) clicked()
}
