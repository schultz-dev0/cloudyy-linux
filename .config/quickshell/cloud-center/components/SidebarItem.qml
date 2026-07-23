import QtQuick
import ".."

Rectangle {
    id: item
    required property string pageId
    required property string title
    required property string glyph
    property bool badge: false
    property bool selected: false
    signal clicked()

    height: 34
    radius: 8
    color: selected ? Theme.primary
         : hover.hovered ? Theme.glass(Theme.primary, 0.08)
         : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }  // hover tint only

    Row {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 9
        Text { text: item.glyph; color: item.selected ? Theme.on_primary : Theme.accent
               font { family: "JetBrainsMono Nerd Font"; pixelSize: 14 } }
        Text { text: item.title; color: item.selected ? Theme.on_primary : Theme.textPrimary
               renderType: Text.NativeRendering
               font { family: "JetBrainsMono Nerd Font"; pixelSize: 14; weight: Font.Medium
                      hintingPreference: Font.PreferVerticalHinting } }
    }
    Text {
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        visible: item.badge
        text: "⤴"
        color: item.selected ? Theme.on_primary : Theme.textMuted
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
    }
    HoverHandler { id: hover }
    TapHandler { onTapped: item.clicked() }
}
