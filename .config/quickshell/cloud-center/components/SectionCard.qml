import QtQuick
import ".."

Column {
    id: card
    required property var section
    default property alias rows: inner.data
    spacing: 5

    Text {
        visible: card.section.title !== ""
        text: card.section.title.toUpperCase()
        color: Theme.textMuted
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11; weight: Font.Medium
               letterSpacing: 1; hintingPreference: Font.PreferVerticalHinting }
        leftPadding: 4
    }
    Rectangle {
        id: body
        width: card.width
        height: inner.implicitHeight + 8
        radius: 12
        clip: true
        color: Theme.surface_container_lowest
        border { width: 1; color: Theme.glass(Theme.outline_variant, 0.55) }

        Column {
            id: inner
            x: 4
            y: 4
            width: body.width - 8
        }
    }
}
