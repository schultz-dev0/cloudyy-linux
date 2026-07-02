pragma ComponentBehavior: Bound

// Bar.qml macOS-style floating menu bar
// The old pill style is preserved as a .old for idk reference i guess?

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Io
import Quickshell.Wayland
import "overview/services"
import "modules/timer" as QuickTimer
import "modules/systemmonitor" as QuickSystemMonitor
import "modules/battery" as QuickBattery

PanelWindow {
    id: bar

    property var assignedScreen: null
    property bool ipcEnabled: true
    screen: assignedScreen

    // ── Tunables ─────────────────────────────────────
    readonly property int barHeight: 18          // shrink the size a bit 
    readonly property int topGap: 3              // create a larger gap to accomodate for the shrink ^ 
    readonly property int sideGap: 0
    readonly property int radius: 0              
    readonly property int pillRadius: 6
    readonly property int pillPadH: 6
    readonly property int pillPadV: 3
    readonly property int pillGap: 6
    readonly property real bgOpacity: 0.0        

    // ── Bar colors (macOS floating style) ─────────────────────────────────────
    // Basic colors for the bar
    readonly property color barFg: Qt.rgba(1, 1, 1, 0.92)
    readonly property color barFgStrong: Qt.rgba(1, 1, 1, 0.98)
    readonly property color barFgMuted: Qt.rgba(1, 1, 1, 0.98) //0.58)
    readonly property color barFgCharging: Qt.rgba(0.65, 0.95, 0.72, 0.98)
    readonly property color barHoverBg: Qt.rgba(1, 1, 1, 0.12)

    // ── Props ─────────────────────────────────────────────────────────────────
    property bool notifOpen: false
    property bool dnd: false
    property string keyboardLayoutLabel: "--"
    signal notifToggle
    signal calendarToggle

    // ── Window ────────────────────────────────────────────────────────────────
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: topGap
        left: sideGap
        right: sideGap
    }
    implicitHeight: barHeight + topGap
    exclusiveZone: barHeight + topGap
    color: "transparent"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // ── One-shot command launcher ─────────────────────────────────────────────
    Component {
        id: procProto
        Process {}
    }
    function launch(cmd) {
        const p = procProto.createObject(bar, {
            command: ["bash", "-lc", `setsid ${cmd.map(part => "'" + String(part).replace(/'/g, "'\\''") + "'").join(" ")} </dev/null >/dev/null 2>&1 &`]
        });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    Timer {
        id: deferredWindowFocusTimer
        interval: 500
        repeat: false
        property string windowTitle: ""
        onTriggered: HyprDispatch.focusWindowByTitle(windowTitle)
    }

    function launchAndFocusByTitle(cmd, title) {
        launch(cmd);
        deferredWindowFocusTimer.windowTitle = title;
        deferredWindowFocusTimer.restart();
    }

    Component.onCompleted: getKeyboardDevices.running = true

    function updateKeyboardLayout(devices) {
        const keyboards = devices?.keyboards ?? [];
        const activeKeyboard = keyboards.find(keyboard => keyboard?.main) || keyboards[0];

        if (!activeKeyboard) {
            keyboardLayoutLabel = "--";
            return;
        }

        const layouts = `${activeKeyboard.layout ?? ""}`.split(",").map(part => part.trim()).filter(Boolean);
        const layoutIndex = Math.max(0, Number(activeKeyboard.active_layout_index ?? 0));
        const activeLayout = layouts[layoutIndex] ?? layouts[0] ?? "";

        keyboardLayoutLabel = activeLayout.length > 0 ? activeLayout.toUpperCase() : "--";
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            const eventName = `${event?.name ?? event?.event ?? event?.type ?? ""}`;
            if (eventName === "activelayout" || eventName === "configreloaded")
                getKeyboardDevices.running = true;
        }
    }

    Process {
        id: getKeyboardDevices
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            id: keyboardDevicesCollector
            onStreamFinished: bar.updateKeyboardLayout(JSON.parse(keyboardDevicesCollector.text))
        }
    }

    // ── Module component (minimal for macos profile) ──────────────────────────
    component Pill: Rectangle {
        id: pill
        property string label: ""
        property int iconSize: 12
        property color fg: bar.barFg
        property color bg: Qt.rgba(0, 0, 0, 0)
        property bool hoverable: true
        signal clicked
        signal scrollUp
        signal scrollDown
        signal hoverEntered
        signal hoverExited

        height: bar.barHeight - bar.pillPadV * 2
        implicitWidth: pillText.implicitWidth
        radius: bar.pillRadius
        color: bg

        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: pill.iconSize
            font.weight: Font.DemiBold
            // No text shadows for macOS clean look
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: pill.hoverable
            onClicked: pill.clicked()
            onWheel: e => {
                e.angleDelta.y > 0 ? pill.scrollUp() : pill.scrollDown();
            }
            onEntered: {
                if (pill.hoverable) {
                    pill.color = bar.barHoverBg;
                    pill.hoverEntered();
                }
            }
            onExited: {
                pill.color = pill.bg;
                if (pill.hoverable)
                    pill.hoverExited();
            }
        }
    }

    // LEFT
    Row {
        id: leftRow
        anchors {
            left: parent.left
            leftMargin: 4
            top: parent.top
            topMargin: bar.topGap
        }
        height: bar.barHeight
        spacing: bar.pillGap

        Pill {
            label: "󰅟"
            iconSize: 16
            width: implicitWidth + bar.pillPadH * 2
            fg: bar.barFgStrong
            bg: Qt.rgba(0, 0, 0, 0)
            onClicked: bar.launch(["qs", "ipc", "call", "spotlight", "command"])
        }

        Item {
            id: clockPill
            height: bar.barHeight - bar.pillPadV * 2
            implicitWidth: clockRow.implicitWidth
            width: implicitWidth + bar.pillPadH * 2

            property string dateText: Qt.formatDateTime(new Date(), "ddd MMM d")
            property string timeText: Qt.formatDateTime(new Date(), "HH:mm")

            function refreshClock() {
                const now = new Date();
                dateText = Qt.formatDateTime(now, "ddd MMM d");
                timeText = Qt.formatDateTime(now, "HH:mm");
            }

            Rectangle {
                anchors.fill: parent
                radius: bar.pillRadius
                color: clockMouse.containsMouse ? bar.barHoverBg : Qt.rgba(0, 0, 0, 0)
            }

            Row {
                id: clockRow
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: clockPill.dateText
                    color: bar.barFg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Text {
                    text: clockPill.timeText
                    color: bar.barFg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }

            Timer {
                interval: 10000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: clockPill.refreshClock()
            }

            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: bar.calendarToggle()
            }
        }

        Pill {
            id: updatesPill
            property string n: "0"
            label: "󰏔 " + n
            width: implicitWidth + bar.pillPadH * 2
            onClicked: bar.launchAndFocusByTitle(
                ["bash", "-c", "kitty --title cloudyy-updater ~/cloudyy_scripts/cloudyy-updater.sh"],
                "cloudyy-updater")
            Timer {
                interval: 3600000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: updatesProc.running = true
            }
            Process {
                id: updatesProc
                command: ["bash", "-c", "checkupdates 2>/dev/null | wc -l || echo 0"]
                stdout: SplitParser {
                    onRead: d => updatesPill.n = d.trim()
                }
            }
        }

        Pill {
            id: notifBell
            label: bar.dnd ? "󰂛" : "󰂚"
            width: implicitWidth + bar.pillPadH * 2
            iconSize: 13
            onClicked: bar.notifToggle()
        }

        QuickTimer.TimerBarPill {
            plain: true
            height: bar.barHeight - bar.pillPadV * 2
            fg: bar.barFg
            fgActive: bar.barFgStrong
            fgWarn: Theme.error
            fgMuted: bar.barFgMuted
        }
    }

    // CENTER
    Row {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: bar.topGap
        }
        height: bar.barHeight
        spacing: bar.pillGap

        // Workspaces 
        Row {
            id: wsRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
                model: Array.from({ length: 5 }, (_, i) => i + 1)

                delegate: Item {
                    required property int modelData
                    readonly property var workspaceWindow: HyprlandData.mostRecentWindowForWorkspace(modelData)
                    readonly property var workspaceIconSources: workspaceWindow ? HyprlandData.iconSourcesForWindow(workspaceWindow) : []
                    readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                    readonly property bool empty: workspaceWindow === null

                    width: 18
                    height: bar.barHeight - bar.pillPadV * 2

                    Image {
                        id: workspaceIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: focused ? -2 : 0
                        visible: !empty
                        width: focused ? 14 : 12
                        height: focused ? 14 : 12
                        property var currentIconSources: workspaceIconSources
                        property int sourceIndex: 0
                        onCurrentIconSourcesChanged: sourceIndex = 0
                        sourceSize: Qt.size(28, 28)
                        smooth: true
                        source: currentIconSources[sourceIndex] ?? HyprlandData.genericIconSource
                        layer.enabled: visible && !Perf.lightweight
                        layer.smooth: !Perf.lightweight
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: focused ? bar.barFgStrong : bar.barFgMuted
                        }
                        onStatusChanged: {
                            if (status === Image.Error && sourceIndex < currentIconSources.length - 1)
                                Qt.callLater(() => sourceIndex++);
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: focused ? -2 : 0
                        visible: empty
                        text: String(modelData)
                        color: focused ? bar.barFgStrong : bar.barFgMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: focused ? 11 : 10
                        font.weight: Font.DemiBold
                    }

                    Rectangle {
                        visible: focused
                        width: 2
                        height: 2
                        radius: 1
                        color: bar.barFgStrong
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: HyprDispatch.focusWorkspace(modelData)
                        onWheel: e => HyprDispatch.focusWorkspaceRelative(e.angleDelta.y > 0 ? "e-1" : "e+1")
                    }
                }
            }
        }
    }

    // RIGHT
    Row {
        id: rightRow
        anchors {
            right: parent.right
            rightMargin: 4
            top: parent.top
            topMargin: bar.topGap
        }
        height: bar.barHeight
        spacing: bar.pillGap

        // Mpris
        Pill {
            id: mprisPill
            readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
            visible: player !== null && (player.playbackState === MprisPlaybackState.Playing || player.playbackState === MprisPlaybackState.Paused)
            label: {
                if (!player) return "";
                const icon = player.playbackState === MprisPlaybackState.Playing ? "▶ " : "⏸ ";
                return icon + (player.trackTitle ?? "").substring(0, 16);
            }
            width: visible ? Math.max(implicitWidth + bar.pillPadH * 2, 50) : 0
            fg: bar.barFg
            bg: Qt.rgba(0,0,0,0)
            onClicked: if (player) player.togglePlaying()
            onScrollUp: if (player) player.next()
            onScrollDown: if (player) player.previous()
        }

        Pill {
            id: keyboardLayoutPill
            label: " " + bar.keyboardLayoutLabel
            width: implicitWidth + bar.pillPadH * 2
            iconSize: 12
            fg: bar.barFgMuted
            bg: Qt.rgba(0,0,0,0)
            hoverable: false
        }

        // Network
        Pill {
            id: netPill
            property string lbl: "󰤨"
            label: lbl
            width: implicitWidth + bar.pillPadH * 2
            iconSize: 12
            Timer {
                interval: 5000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: netProc.running = true
            }
            Process {
                id: netProc
                command: ["bash", "-c", "nmcli -t -f active,ssid,signal dev wifi 2>/dev/null | awk -F: '/^yes/{print $2\" \"$3\"%\"}' | head -1 || echo OFF"]
                stdout: SplitParser {
                    onRead: d => {
                        const s = d.trim();
                        netPill.lbl = s === "OFF" ? "󰖪" : "󰤨 " + s;
                    }
                }
            }
            onClicked: bar.launch(["bash", "-c", "uwsm-app -- ~/cloudyy_scripts/cloud-center --wifi"])
        }

        // Volume
        Pill {
            id: volPill
            property string lbl: "󰕾"
            label: lbl
            width: implicitWidth + bar.pillPadH * 2
            iconSize: 12
            Timer {
                interval: 2000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: volProc.running = true
            }
            Process {
                id: volProc
                command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@"]
                stdout: SplitParser {
                    onRead: d => {
                        const muted = d.includes("[MUTED]");
                        const m = d.match(/[\d.]+/);
                        if (m) {
                            const v = Math.round(parseFloat(m[0]) * 100);
                            volPill.lbl = muted ? "󰖁" : (v < 33 ? "󰕿 " : v < 66 ? "󰕾 " : "󱄠 ") + v + "%";
                        }
                    }
                }
            }
            onClicked: bar.notifToggle()
            onScrollUp: bar.launch(["bash", "-lc", "$HOME/cloudyy_scripts/sliders/volume-slider.sh up"])
            onScrollDown: bar.launch(["bash", "-lc", "$HOME/cloudyy_scripts/sliders/volume-slider.sh down"])
        }

        // CPU
        Pill {
            id: cpuPill
            readonly property var sys: QuickSystemMonitor.SystemMonitorService
            label: "󰍛 " + sys.cpuPercent + "%"
            width: implicitWidth + bar.pillPadH * 2
            fg: sys.open ? bar.barFgStrong : bar.barFgMuted
            bg: Qt.rgba(0,0,0,0)
            onClicked: sys.toggleOpen()
        }

        // Memory
        Pill {
            id: memPill
            readonly property var sys: QuickSystemMonitor.SystemMonitorService
            label: "󰘚 " + sys.ramPercent + "%"
            width: implicitWidth + bar.pillPadH * 2
            fg: sys.open ? bar.barFgStrong : bar.barFgMuted
            bg: Qt.rgba(0,0,0,0)
            onClicked: sys.toggleOpen()
        }

        // Battery
        Pill {
            id: batPill
            readonly property var bat: QuickBattery.BatteryService
            readonly property var sys: QuickSystemMonitor.SystemMonitorService
            visible: bat.available
            label: bat.barLabel
            width: visible ? implicitWidth + bar.pillPadH * 2 : 0
            fg: bat.full
                ? bar.barFgStrong
                : bat.charging
                    ? bar.barFgCharging
                    : (bat.percent < 15 ? "#ffdddd" : (sys.open ? bar.barFgStrong : bar.barFgMuted))
            bg: Qt.rgba(0,0,0,0)
            onClicked: sys.toggleOpen()
            onHoverEntered: batteryTooltip.hovered = true
            onHoverExited: batteryTooltipHideTimer.restart()
        }

        // Power
        Pill {
            label: "󰐥"
            iconSize: 12
            width: implicitWidth + bar.pillPadH * 2
            fg: bar.barFgStrong
            bg: Qt.rgba(0, 0, 0, 0)
            onClicked: bar.launch(["qs", "ipc", "call", "powermenu", "open"])
        }
    }

    QuickBattery.BatteryTooltip {
        id: batteryTooltip
        anchorItem: batPill
    }

    Timer {
        id: batteryTooltipHideTimer
        interval: 200
        onTriggered: batteryTooltip.hovered = false
    }
}
