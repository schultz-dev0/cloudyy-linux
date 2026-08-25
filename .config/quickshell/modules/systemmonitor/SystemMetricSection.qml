pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Item {
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

    implicitHeight: sectionCol.implicitHeight

    ColumnLayout {
        id: sectionCol
        anchors { left: parent.left; right: parent.right }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: sectionRoot.title
                color: Theme.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.labelFont
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
                Layout.fillWidth: true
            }
            Text {
                visible: sectionRoot.valueText !== ""
                text: sectionRoot.valueText
                color: Theme.accent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.valueFont
                font.weight: Font.Bold
            }
            Text {
                visible: sectionRoot.subValueText !== ""
                text: sectionRoot.subValueText
                color: Theme.textMuted
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
            color: Theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: sectionRoot.bodyFont
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
    }
}
