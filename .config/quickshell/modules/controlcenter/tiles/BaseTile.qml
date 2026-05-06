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
    radius: 12
    color: active
        ? Qt.tint(Theme.surface_container, Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18))
        : Theme.surface_container
    border.color: active
        ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
        : Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.35)
    border.width: 1

    ElevatedEffect {
        target: root
    }

    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 2

        Text {
            text:        root.icon
            color:       root.active ? Theme.primary : Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 18
        }

        Text {
            text:           root.label
            color:          Theme.on_surface
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            font.weight:    Font.Bold
            Layout.fillWidth: true
            elide:          Text.ElideRight
        }

        Text {
            text:           root.statusText
            color:          root.active
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)
                : Theme.on_surface_variant
            font.family:    "JetBrainsMono Nerd Font"
            font.pixelSize: 9
            visible:        root.statusText !== ""
        }
    }

    MouseArea {
        anchors.fill:    parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked()
            else
                root.clicked()
        }
    }
}
