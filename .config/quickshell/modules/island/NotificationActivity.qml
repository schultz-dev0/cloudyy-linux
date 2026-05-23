import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    // Set by DynamicIsland after Loader is ready (not via item.data — bindings break).
    property string appName: ""
    property string summary: ""

    implicitWidth:  320
    implicitHeight: 32

    RowLayout {
        anchors.fill: parent
        spacing: 10

        Rectangle {
            width:  28
            height: 28
            radius: 8
            color:  Qt.rgba(Theme.surface_container_high.r,
                            Theme.surface_container_high.g,
                            Theme.surface_container_high.b, 0.6)
            Layout.alignment: Qt.AlignVCenter

            Text {
                anchors.centerIn: parent
                text:             "󰂚"
                color:            Theme.on_surface_variant
                font.family:      "JetBrainsMono Nerd Font"
                font.pixelSize:   15
            }
        }

        ColumnLayout {
            Layout.fillWidth:   true
            Layout.alignment:   Qt.AlignVCenter
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: {
                    const name = root.appName || "";
                    return name ? name.toUpperCase() : "NOTIFICATION";
                }
                color:            Theme.on_surface_variant
                font.family:      "JetBrainsMono Nerd Font"
                font.pixelSize:   9
                font.letterSpacing: 0.8
                elide:            Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text:             root.summary
                color:            Theme.on_surface
                font.family:      "JetBrainsMono Nerd Font"
                font.pixelSize:   12
                font.weight:      Font.Bold
                elide:            Text.ElideRight
            }
        }
    }
}
