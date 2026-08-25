pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../battery" as QuickBattery

PanelWindow {
    id: panel

    readonly property var svc: SystemMonitorService

    // Larger layout for high-DPI / big monitors (34").
    readonly property int panelWidth: 560
    readonly property int panelRadius: 0
    readonly property int padding: 20
    readonly property int topGap: 10
    readonly property int rightGap: 20
    readonly property int sectionRadius: 0
    readonly property int bodyFont: 11
    readonly property int labelFont: 14
    readonly property int titleFont: 18
    readonly property int valueFont: 16
    readonly property int sparklineHeight: 36

    // Slide left when Control Center (notif panel) is open beside us.
    property bool notifOpen: false
    readonly property int notifPanelWidth: 380
    readonly property int notifPanelGap: 16
    property real notifShiftPx: 0

    anchors {
        top: true
        right: true
    }
    margins {
        top: 52
        right: rightGap + notifShiftPx
    }

    onNotifOpenChanged: syncNotifShift(true)

    Component.onCompleted: syncNotifShift(false)

    Connections {
        target: svc
        function onOpenChanged() {
            if (svc.open)
                syncNotifShift(true)
        }
    }

    function syncNotifShift(animate) {
        const target = notifOpen ? (notifPanelWidth + notifPanelGap) : 0
        if (animate) {
            notifShiftAnim.to = target
            notifShiftAnim.restart()
        } else {
            notifShiftPx = target
        }
    }

    NumberAnimation {
        id: notifShiftAnim
        target: panel
        property: "notifShiftPx"
        to: panel.notifOpen ? (panel.notifPanelWidth + panel.notifPanelGap) : 0
        duration: 320
        easing.type: Easing.OutCubic
    }
    width: panelWidth
    implicitWidth: panelWidth
    implicitHeight: Math.min(920, Math.max(320, contentCol.implicitHeight + panel.padding * 2))
    color: "transparent"
    visible: svc.open

    // Never Exclusive — on Hyprland that mode captures keyboard and pointer globally.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:system"
    WlrLayershell.keyboardFocus: svc.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: 0

    Component {
        id: procProto
        Process {}
    }

    function launch(cmd) {
        const p = procProto.createObject(panel, { command: cmd });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    Rectangle {
        id: panelRect
        anchors.fill: parent
        implicitWidth: panel.panelWidth
        implicitHeight: contentCol.implicitHeight + panel.padding * 2
        radius: panel.panelRadius
        color: Theme.glassShell
        border.width: 1
        border.color: Theme.glassPanelBorder
        focus: false

        Keys.onEscapePressed: svc.open = false

        // Background only — buttons stay above; focus panel for Escape without grabbing the session.
        MouseArea {
            z: -1
            anchors.fill: parent
            onPressed: panelRect.forceActiveFocus()
        }

        opacity: svc.open ? 1 : 0
        scale: svc.open ? 1.0 : 0.94
        transformOrigin: Item.TopRight
        Behavior on opacity {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(180); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(200); easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: contentCol
            anchors {
                fill: parent
                margins: panel.padding
            }
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "󰘚  System"
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: panel.titleFont
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 0.6
                    Layout.fillWidth: true
                }

                Text {
                    text: svc.stale
                        ? "stale · check binary"
                        : (svc.daemonManaged ? "live · 2s" : "live · 2s")
                    color: svc.stale ? Theme.error : Theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: panel.bodyFont
                }
            }

            // Scrollable body
            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(400, Math.min(820, bodyCol.implicitHeight))
                Layout.minimumHeight: 360
                contentHeight: bodyCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: bodyCol
                    width: parent.width
                    spacing: 10

                    // CPU
                    SystemMetricSection {
                        Layout.fillWidth: true
                        labelFont: panel.labelFont
                        valueFont: panel.valueFont
                        bodyFont: panel.bodyFont
                        sparklineHeight: panel.sparklineHeight
                        title: "󰍛 CPU"
                        valueText: svc.cpuPercent + "%"
                        subValueText: "avg " + svc.cpuAvgPercent + "%"
                        detailLine: svc.cpuModel + (svc.cpuTempC > 0 ? " · 󰈸 " + svc.cpuTempC + "°C" : "")
                            + (svc.cpuFreqGhz > 0 ? " · " + svc.cpuFreqGhz + " GHz" : "")
                            + (svc.cpuCores > 0 ? " · " + svc.cpuCores + " cores" : "")
                        history: svc.cpuHistory
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

                    // RAM
                    SystemMetricSection {
                        Layout.fillWidth: true
                        labelFont: panel.labelFont
                        valueFont: panel.valueFont
                        bodyFont: panel.bodyFont
                        sparklineHeight: panel.sparklineHeight
                        title: "󰘚 RAM"
                        valueText: svc.ramPercent + "%"
                        detailLine: svc.ramUsedGb + " / " + svc.ramTotalGb + " GB used"
                            + " · Swap " + svc.swapUsedGb + " / " + svc.swapTotalGb + " GB (" + svc.swapPercent + "%)"
                        history: svc.ramHistory
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

                    QuickBattery.BatterySection {
                        Layout.fillWidth: true
                        labelFont: panel.labelFont
                        valueFont: panel.valueFont
                        bodyFont: panel.bodyFont
                        sparklineHeight: panel.sparklineHeight
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

                    // GPU
                    SystemMetricSection {
                        Layout.fillWidth: true
                        visible: svc.gpuAvailable
                        labelFont: panel.labelFont
                        valueFont: panel.valueFont
                        bodyFont: panel.bodyFont
                        sparklineHeight: panel.sparklineHeight
                        title: "󰢮 GPU"
                        valueText: svc.gpuPercent + "%"
                        subValueText: svc.gpuPowerW > 0 ? svc.gpuPowerW + " W" : ""
                        detailLine: svc.gpuName
                            + (svc.gpuVramTotalGb > 0 ? " · VRAM " + svc.gpuVramUsedGb + " / " + svc.gpuVramTotalGb + " GB" : "")
                            + (svc.gpuTempC > 0 ? " · 󰈸 " + svc.gpuTempC + "°C" : "")
                        history: svc.gpuHistory
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

                    // Storage
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: storageCol.implicitHeight

                        ColumnLayout {
                            id: storageCol
                            anchors { left: parent.left; right: parent.right }
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "󰋊 Storage"
                                    color: Theme.text
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.labelFont
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 0.6
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: svc.disks.length + " mounts"
                                    color: Theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.bodyFont
                                }
                            }

                            Column {
                                Layout.fillWidth: true
                                spacing: 8
                                Repeater {
                                    model: svc.disks
                                    delegate: StorageRow {
                                        required property var modelData
                                        width: parent.width
                                        labelFont: panel.labelFont
                                        bodyFont: panel.bodyFont
                                        mount: modelData.mount || ""
                                        percent: modelData.percent || 0
                                        usedGb: modelData.used_gb || 0
                                        totalGb: modelData.total_gb || 0
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.hairline }

                    // Network + temps row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: netCol.implicitHeight

                            ColumnLayout {
                                id: netCol
                                anchors { left: parent.left; right: parent.right }
                                spacing: 6

                                Text {
                                    text: "󰖩 Network"
                                    color: Theme.text
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.labelFont
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 0.6
                                }
                                Text {
                                    text: "↓ " + svc.formatRate(svc.networkRxBps)
                                    color: Theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.bodyFont
                                }
                                Text {
                                    text: "↑ " + svc.formatRate(svc.networkTxBps)
                                    color: Theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.bodyFont
                                }
                                Text {
                                    text: svc.networkIface + (svc.networkIp ? " · " + svc.networkIp : "")
                                    color: Theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.bodyFont
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: false; Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.hairline }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: tempCol.implicitHeight

                            ColumnLayout {
                                id: tempCol
                                anchors { left: parent.left; right: parent.right }
                                spacing: 6

                                Text {
                                    text: "󰈸 Temps"
                                    color: Theme.text
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.labelFont
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 0.6
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: svc.sensors.slice(0, 6)
                                        delegate: Rectangle {
                                            required property var modelData
                                            radius: 2
                                            color: "transparent"
                                            border.width: 1
                                            border.color: Theme.hairline
                                            implicitWidth: chipText.implicitWidth + 16
                                            implicitHeight: 24
                                            Text {
                                                id: chipText
                                                anchors.centerIn: parent
                                                text: (modelData.label || "?") + " " + (modelData.temp_c || 0) + "°"
                                                color: Theme.textMuted
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: panel.bodyFont
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: svc.fans.length > 0
                                    text: svc.fans.length > 0
                                        ? (svc.fans[0].label || "Fan") + " " + (svc.fans[0].rpm || 0) + " RPM"
                                        : ""
                                    color: Theme.textMuted
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: panel.bodyFont
                                }
                            }
                        }
                    }
                }
            }

            // Footer
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 2
                    color: "transparent"
                    border.color: Theme.hairline
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰄨 Open btop"
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: panel.bodyFont
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: panel.launch(["bash", "-c", "kitty --title btop btop"])
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 2
                    color: "transparent"
                    border.color: Theme.hairline
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰑐 Refresh"
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: panel.bodyFont
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: svc.ensureDaemon()
                    }
                }
            }
        }
    }
}
