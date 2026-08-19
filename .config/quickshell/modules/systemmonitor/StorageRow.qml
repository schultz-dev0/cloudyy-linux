import QtQuick
import QtQuick.Layouts
import "../.."

ColumnLayout {
    id: root

    property string mount: "/"
    property int percent: 0
    property real usedGb: 0
    property real totalGb: 0
    property int labelFont: 14
    property int bodyFont: 11

    spacing: 4
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: root.mount
            color: Theme.on_surface
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.labelFont
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Text {
            text: root.percent + "% · " + root.usedGb + " / " + root.totalGb + " GB"
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.bodyFont
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 6
        radius: 0
        color: Theme.hairline

        Rectangle {
            height: parent.height
            width: parent.width * Math.min(1, root.percent / 100)
            radius: 0
            color: root.percent >= 85 ? Theme.error : Theme.accent
        }
    }
}
