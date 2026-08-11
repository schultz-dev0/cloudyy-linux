import QtQuick
import "../.."

Item {
    id: root

    property var notification: null
    readonly property var actions: notification ? notification.actions : []
    property string appName: ""
    property string summary: ""
    property string icon: ""
    property int urgency: 0

    implicitHeight: 40

    Rectangle {
        anchors.fill: parent
        color: Theme.islandHover
    }

    Rectangle {
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
        }
        width: 3
        color: Theme.error
        visible: root.urgency === 2
    }

    Row {
        anchors {
            fill: parent
            leftMargin: 12
            rightMargin: 12
        }
        spacing: 10

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: Theme.islandOnSurface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            renderType: Text.NativeRendering
            visible: text.length > 0
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width - x)
            spacing: 1

            Text {
                width: parent.width
                text: root.appName || "Activity"
                color: Theme.islandOnSurface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.summary
                color: Theme.islandOnSurfaceVariant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                renderType: Text.NativeRendering
                elide: Text.ElideRight
            }
        }
    }
}
