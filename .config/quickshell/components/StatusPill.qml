import QtQuick
import ".."

Item {
    id: pill
    property string icon: ""
    property string text: ""
    property bool accent: false
    signal clicked()

    implicitWidth: row.implicitWidth + 16
    implicitHeight: Style.barHeight - 8
    
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: hover.containsMouse ? Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.1) : "transparent"
        Behavior on color { ColorAnimation { duration: Style.hoverAnimMs } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            text: pill.icon
            color: pill.accent ? Theme.primary : Theme.textPrimary
            font.family: Style.fontFamily
            font.pixelSize: Style.pillIconSize
            font.weight: Font.Bold
            visible: pill.icon.length > 0
            style: Text.Outline
            styleColor: Style.textShadowColor
        }
        Text {
            text: pill.text
            color: Theme.textPrimary
            font.family: Style.fontFamily
            font.pixelSize: Style.pillTextSize
            font.weight: Font.Bold
            visible: pill.text.length > 0
            style: Text.Outline
            styleColor: Style.textShadowColor
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
