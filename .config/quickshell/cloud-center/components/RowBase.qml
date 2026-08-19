import QtQuick
import ".."

Rectangle {
    id: row
    required property var item
    default property alias contentSlot: slot.data

    // Whole-row click surface. A TapHandler passed as a default child would be
    // reparented into the small right-side slot Row and only that corner would
    // be clickable — consumers use onClicked instead.
    // Caveat: inner control TapHandlers (toggle knob, button) also co-fire
    // clicked() — don't connect onClicked on rows that carry a control.
    signal clicked()

    property bool showDivider: true
    property int dividerInset: 46

    width: parent ? parent.width : 0
    height: Math.max(46, contentColumn.implicitHeight + 18)
    radius: 2
    color: hover.hovered ? Theme.glass(Theme.primary, 0.08) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: glyph
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        text: row.item.icon ?? ""
        color: Theme.accent
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 16 }
    }
    Column {
        id: contentColumn
        anchors { left: glyph.right; leftMargin: 12; right: slot.left; rightMargin: 12
                  verticalCenter: parent.verticalCenter }
        Text { text: row.item.title ?? ""; color: Theme.textPrimary
               renderType: Text.NativeRendering
               font { family: "JetBrainsMono Nerd Font"; pixelSize: 14; weight: Font.Medium
                      hintingPreference: Font.PreferVerticalHinting } }
        Text { visible: text !== ""; text: row.item.description ?? ""
               color: Theme.textMuted; width: parent.width; elide: Text.ElideRight
               renderType: Text.NativeRendering
               font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                      hintingPreference: Font.PreferVerticalHinting } }
    }
    Row { id: slot
         anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
         spacing: 8 }
    Rectangle {
        visible: row.showDivider
        anchors {
            left: parent.left
            leftMargin: row.dividerInset
            right: parent.right
            rightMargin: 14
            bottom: parent.bottom
        }
        height: 1
        color: Theme.hairline
    }

    HoverHandler { id: hover }
    TapHandler { onTapped: row.clicked() }
}
