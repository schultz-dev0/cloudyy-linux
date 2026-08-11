pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../systemmonitor" as QuickSystemMonitor
import "." as QuickIsland

Item {
    id: root

    signal activateRequested

    readonly property var service: QuickSystemMonitor.SystemMonitorService

    QuickIsland.IslandPageFrame {
        anchors.fill: parent

        leftContent: Item {
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 12
                spacing: 7

                Text {
                    width: parent.width
                    text: "System Overview"
                    color: Theme.islandOnSurface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                }

                Text {
                    width: parent.width
                    text: root.service.hasSnapshot && !root.service.stale
                        ? "Live system snapshot" : "Metrics unavailable"
                    color: Theme.islandOnSurfaceVariant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: "Enter to open full monitor"
                    color: Theme.islandOnSurfaceVariant
                    opacity: 0.72
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    renderType: Text.NativeRendering
                }
            }

            TapHandler {
                onTapped: root.activateRequested()
            }
        }

        rightContent: Item {
            Column {
                anchors.centerIn: parent
                width: parent.width - 20
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 12

                    Repeater {
                        model: [
                            { label: "CPU", value: root.service.cpuPercent,
                                available: root.service.cpuAvailable
                                    && !root.service.stale },
                            { label: "RAM", value: root.service.ramPercent,
                                available: root.service.ramAvailable
                                    && !root.service.stale },
                            { label: "GPU", value: root.service.gpuPercent,
                                available: root.service.hasSnapshot
                                    && root.service.gpuMetricAvailable
                                    && !root.service.stale },
                        ]

                        delegate: Column {
                            id: metric

                            required property var modelData

                            width: (parent.width - 24) / 3
                            spacing: 4

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: metric.modelData.available
                                    ? metric.modelData.value + "%" : "--"
                                color: metric.modelData.available ? Theme.islandOnSurface
                                    : Theme.islandOnSurfaceVariant
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                renderType: Text.NativeRendering
                            }

                            Rectangle {
                                width: parent.width
                                height: 3
                                radius: 2
                                color: Theme.islandBorder

                                Rectangle {
                                    width: metric.modelData.available
                                        ? parent.width * Math.max(0,
                                            Math.min(100, metric.modelData.value)) / 100
                                        : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.islandAccent
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: metric.modelData.label
                                color: Theme.islandOnSurfaceVariant
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 8
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 32

                    Column {
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.service.uptimeLabel
                            color: root.service.uptimeSeconds > 0
                                ? Theme.islandOnSurface : Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "UPTIME"
                            color: Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8
                            renderType: Text.NativeRendering
                        }
                    }

                    Column {
                        spacing: 2

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.service.temperatureAvailable
                                && !root.service.stale
                                ? root.service.cpuTempC + "°C" : "--"
                            color: root.service.temperatureAvailable
                                && !root.service.stale
                                ? Theme.islandOnSurface : Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "TEMP"
                            color: Theme.islandOnSurfaceVariant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 8
                            renderType: Text.NativeRendering
                        }
                    }
                }
            }

            TapHandler {
                onTapped: root.activateRequested()
            }
        }
    }
}
