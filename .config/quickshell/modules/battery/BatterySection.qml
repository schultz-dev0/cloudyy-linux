pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."
import "../systemmonitor"

Rectangle {
    id: sectionRoot

    readonly property var bat: BatteryService

    property int labelFont: 14
    property int valueFont: 16
    property int bodyFont: 11
    property int sparklineHeight: 36

    visible: bat.available
    implicitHeight: visible ? sectionCol.implicitHeight + 28 : 0
    radius: 14
    color: Theme.glassSection
    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.25)
    border.width: 1

    ElevatedEffect { target: sectionRoot }

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
                text: "󰁹 Battery"
                color: Theme.on_surface
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.labelFont
                font.weight: Font.Bold
                Layout.fillWidth: true
            }
            Text {
                text: Math.round(bat.percent) + "%"
                color: bat.charging || bat.full ? Theme.tertiary : Theme.primary
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.valueFont
                font.weight: Font.Bold
            }
            Text {
                text: bat.usageLabel
                color: Theme.on_surface_variant
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
                color: Theme.outline_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
            Text {
                text: bat.statusLabel
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }

            Text {
                text: bat.charging ? "Time to full" : "Time to empty"
                color: Theme.outline_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
            Text {
                text: bat.full ? "—" : bat.formatDuration(bat.charging ? bat.timeToFullSec : bat.timeToEmptySec)
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }

            Text {
                visible: bat.healthPercent > 0
                text: "Health"
                color: Theme.outline_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
            }
            Text {
                visible: bat.healthPercent > 0
                text: Math.round(bat.healthPercent) + "%"
                color: Theme.on_surface_variant
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: sectionRoot.bodyFont
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
            }
        }
    }
}
