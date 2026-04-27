import QtQuick
import Quickshell
import ".."

Rectangle {
    id: cb
    property string label: "󰅟"
    signal clicked()
    implicitWidth: Style.cloudButtonWidth
    implicitHeight: Style.cloudButtonHeight
    radius: Style.cloudButtonRadius
    color: hover.containsMouse
        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Style.accentTintIcon)
        : "transparent"
    Behavior on color { ColorAnimation { duration: Style.hoverAnimMs } }

    Text {
        anchors.centerIn: parent
        text: cb.label
        color: Theme.textPrimary
        font.pixelSize: Style.cloudButtonIconSize
        font.family: Style.fontFamily
        font.weight: Font.Bold
        style: Text.Outline
        styleColor: Style.textShadowColor
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (cb.clicked.count > 0) {
                cb.clicked();
            } else {
                Quickshell.execDetached(["sh", "-c", "rofi -show drun || wofi --show drun"]);
            }
        }
    }
}
