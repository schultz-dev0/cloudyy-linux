import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string appName: ""
    property string summary: ""

    anchors.fill: parent

    RowLayout {
        anchors.fill: parent
        spacing: 11

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            radius: 9
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.92)

            Text {
                anchors.centerIn: parent
                text: "󰂚"
                color: Qt.rgba(0, 0, 0, 0.82)
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: {
                    const name = root.appName || "";
                    return name || "Notification";
                }
                color: Qt.rgba(1, 1, 1, 0.52)
                font.family: "sans-serif"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                maximumLineCount: 1
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.summary
                color: Qt.rgba(1, 1, 1, 0.94)
                font.family: "sans-serif"
                font.pixelSize: 13
                font.weight: Font.Medium
                maximumLineCount: 1
                elide: Text.ElideRight
            }
        }
    }
}
