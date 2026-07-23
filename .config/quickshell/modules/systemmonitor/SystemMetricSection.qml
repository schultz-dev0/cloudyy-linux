pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Rectangle {
    id: sectionRoot

    property string title: ""
    property string valueText: ""
    property string subValueText: ""
    property string detailLine: ""
    property var history: []
    property int labelFont: 14
    property int valueFont: 16
    property int bodyFont: 11
    property int sparklineHeight: 36

    implicitHeight: sectionCol.implicitHeight + 28
    radius: 14
    color: Theme.glassSection
    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.25)
    border.width: 1

    ColumnLayout {
        id: sectionCol
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: sectionRoot.title
                color: Theme.on_surface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.labelFont
                font.weight: Font.Bold
                Layout.fillWidth: true
            }
            Text {
                visible: sectionRoot.valueText !== ""
                text: sectionRoot.valueText
                color: Theme.primary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.valueFont
                font.weight: Font.Bold
            }
            Text {
                visible: sectionRoot.subValueText !== ""
                text: sectionRoot.subValueText
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
        }

        MetricSparkline {
            Layout.fillWidth: true
            values: sectionRoot.history
            barHeight: sectionRoot.sparklineHeight
        }

        Text {
            visible: sectionRoot.detailLine !== ""
            text: sectionRoot.detailLine
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: sectionRoot.bodyFont
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
