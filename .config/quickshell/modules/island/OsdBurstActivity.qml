import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root
    property string kind: "volume"
    property string icon: "󰕾"
    property string valueLabel: "50%"
    property real progress: 0

    anchors.fill: parent

    RowLayout {
        id: iconRow
        anchors.fill: parent
        spacing: 12

        Text {
            text: root.icon
            color: "#ffffff"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 17
            renderType: Text.NativeRendering
            Layout.alignment: Qt.AlignVCenter
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: 120
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: 6

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 5
                radius: 2.5
                color: Qt.rgba(1, 1, 1, 0.16)

                Rectangle {
                    id: fill
                    height: parent.height
                    radius: parent.radius
                    color: Qt.rgba(1, 1, 1, 0.9)
                    width: track.width * Math.max(0, Math.min(1, root.progress))
                }
            }
        }

        Text {
            text: root.valueLabel
            color: Qt.rgba(1, 1, 1, 0.68)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
            font.weight: Font.DemiBold
            renderType: Text.NativeRendering
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
        }
    }
}
