pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/BaseTile.qml — compact toggle cell: icon,
// LED (state lives here, never in the fill), short nameplate label.
import QtQuick
import QtQuick.Layouts
import "../../.."

Rectangle {
    id: root

    property string icon:    ""
    property string label:   ""
    property bool   active:  false
    property bool   iconDim: false

    signal clicked()
    signal rightClicked()

    Layout.fillWidth: true
    implicitHeight: 64
    radius: 2
    color: hover.containsMouse ? Theme.hairline : "transparent"
    Behavior on color { ColorAnimation { duration: 90 } }

    Rectangle {
        anchors { top: parent.top; right: parent.right; margins: 8 }
        width: 7; height: 7
        color: root.active ? Theme.accent : "transparent"
        border.width: 1
        border.color: Theme.accent
    }

    Column {
        anchors.centerIn: parent
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            color: root.iconDim ? Theme.textMuted : Theme.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 8
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
}
