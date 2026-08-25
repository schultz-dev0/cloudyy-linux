pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/BaseTile.qml
import QtQuick
import QtQuick.Layouts
import "../../.."

Rectangle {
    id: root

    property string icon:       ""
    property string label:      ""
    property string statusText: ""
    property bool   active:     false

    signal clicked()
    signal rightClicked()

    implicitHeight: 68
    implicitWidth: 170
    radius: 2
    color: hover.containsMouse ? Theme.hairline : "transparent"
    border.width: 0
    Behavior on color { ColorAnimation { duration: 90 } }

    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text:        root.icon
                color:       Theme.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 18
            }

            Item { Layout.fillWidth: true }

            // LED indicator — state lives here, not in the tile's fill, so
            // the label stays legible in both states instead of flashing
            // the whole card a solid color.
            Rectangle {
                width: 7
                height: 7
                radius: 0
                color: root.active ? Theme.accent : "transparent"
                border.width: 1
                border.color: Theme.accent
            }
        }

        Text {
            text:           root.label
            color:          Theme.text
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.weight:    Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
            Layout.fillWidth: true
            elide:          Text.ElideRight
        }

        Text {
            text:           root.statusText
            color:          Theme.textMuted
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            visible:        root.statusText !== ""
        }
    }

    MouseArea {
        id: hover
        anchors.fill:    parent
        hoverEnabled:    true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked()
            else
                root.clicked()
        }
    }
}
