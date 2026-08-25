pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."
import "../systemmonitor"

Item {
    id: sectionRoot

    readonly property var bat: BatteryService

    property int labelFont: 14
    property int valueFont: 16
    property int bodyFont: 11
    property int sparklineHeight: 36

    visible: bat.available
    implicitHeight: visible ? sectionCol.implicitHeight : 0

    ColumnLayout {
        id: sectionCol
        anchors { left: parent.left; right: parent.right }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "󰁹 Battery"
                color: Theme.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.labelFont
                font.weight: Font.Bold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.6
                Layout.fillWidth: true
            }
            Text {
                text: Math.round(bat.percent) + "%"
                color: bat.charging || bat.full ? Theme.info : Theme.accent
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.valueFont
                font.weight: Font.Bold
            }
            Text {
                text: bat.usageLabel
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
        }

        MetricSparkline {
            Layout.fillWidth: true
            values: bat.percentHistory
            barHeight: sectionRoot.sparklineHeight
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 4

            Text {
                text: "Status"
                color: Theme.border
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
            Text {
                text: bat.statusLabel
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }

            Text {
                text: bat.charging ? "Time to full" : "Time to empty"
                color: Theme.border
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
            Text {
                text: bat.full ? "—" : bat.formatDuration(bat.charging ? bat.timeToFullSec : bat.timeToEmptySec)
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }

            Text {
                visible: bat.healthPercent > 0
                text: "Health"
                color: Theme.border
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
            Text {
                visible: bat.healthPercent > 0
                text: Math.round(bat.healthPercent) + "%"
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }
        }
    }
}
