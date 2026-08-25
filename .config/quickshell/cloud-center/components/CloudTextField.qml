import QtQuick
import ".."

FocusScope {
    id: field

    property alias text: input.text
    property string placeholderText: ""
    property bool readOnly: false
    property bool compact: false
    property string leadingGlyph: ""
    signal textEdited(string value)
    signal accepted()

    implicitHeight: compact ? 30 : 36
    implicitWidth: 220
    activeFocusOnTab: true

    Rectangle {
        anchors.fill: parent
        radius: 2
        color: field.activeFocus
            ? Theme.background
            : inputHover.hovered
                ? Theme.surfaceOverlay
                : Theme.surface
        border {
            width: field.activeFocus ? 1.5 : 1
            color: field.activeFocus ? Theme.accent : Theme.hairline
        }

        Text {
            id: glyphLabel
            visible: field.leadingGlyph !== ""
            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: field.leadingGlyph
            color: Theme.accent
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                   hintingPreference: Font.PreferVerticalHinting }
        }

        TextInput {
            id: input
            anchors {
                left: field.leadingGlyph === "" ? parent.left : glyphLabel.right
                right: parent.right; top: parent.top; bottom: parent.bottom
                leftMargin: field.leadingGlyph === "" ? 11 : 8; rightMargin: 11
            }
            readOnly: field.readOnly
            selectByMouse: true
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            renderType: TextInput.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: field.compact ? 10 : 11
                   hintingPreference: Font.PreferVerticalHinting }
            onTextEdited: field.textEdited(text)
            onAccepted: field.accepted()
            Text {
                visible: input.text === ""
                anchors.verticalCenter: parent.verticalCenter
                text: field.placeholderText
                color: Theme.textMuted
                opacity: 0.72
                renderType: Text.NativeRendering
                font: input.font
            }
        }
        HoverHandler { id: inputHover }
        TapHandler { onTapped: input.forceActiveFocus() }
    }
}
