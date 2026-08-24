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
import "modules/systemmonitor" as QuickSystemMonitor
import "modules/battery" as QuickBattery
import "modules/mpris" as QuickMpris
import "modules/recording" as QuickRecording
import "modules/calendar" as QuickCalendar
import "modules/idle" as QuickIdle
import "modules/notifpanel" as QuickNotifPanel

PanelWindow {
    id: bar

    property var assignedScreen: null
    property bool ipcEnabled: true

    readonly property var resolvedScreen: {
        const pref = assignedScreen;
        const all = Quickshell.screens;
        if (!all.length)
            return null;
        if (!pref)
            return all[0];
        const name = pref.name;
        for (let i = 0; i < all.length; i++) {
            if (all[i].name === name)
                return all[i];
        }
        return all[0];
    }

    screen: resolvedScreen
    visible: QuickIdle.IdleService.state !== "scene"

    // ── Tunables ─────────────────────────────────────
    // barHeight/topGap/bgOpacity come from BarStyleService — double-click
    // the bar to switch between solid (Omarchy-style) and the old floating
    // transparent+vignette look. Keeping bar.* as the read interface here
    // so the rest of this file doesn't need to change.
    readonly property int barHeight: BarStyleService.barHeight
    readonly property int topGap: BarStyleService.topGap
    readonly property int sideGap: 0
    readonly property int radius: 0
    readonly property int pillRadius: 2
    readonly property int pillPadH: 6
    readonly property int pillPadV: 3
    readonly property int pillGap: 10
    readonly property real bgOpacity: BarStyleService.bgOpacity

    // ── Bar colors ─────────────────────────────────────
    // Theme-derived, not hardcoded white — on_surface is guaranteed to
    // contrast against surface in both light and dark mode, which fixed
    // white text never was (invisible on a light-mode solid bar). Used in
    // both bar states now, not just solid — no vignette to lean on anymore.
    readonly property color barFgStrong: Theme.on_surface
    readonly property color barFg: Qt.rgba(Theme.on_surface.r, Theme.on_surface.g, Theme.on_surface.b, 0.85)
    readonly property color barFgMuted: Theme.on_surface_variant
    // Charging is a semantic status color, not a legibility token — themes'
    // tertiary roles aren't reliably green (Nord/Gruvbox/Catppuccin are all
    // purple), so tokenizing this would break the "green = charging" meaning.
    readonly property color barFgCharging: Qt.rgba(0.65, 0.95, 0.72, 0.98)

    // ── Props ─────────────────────────────────────────────────────────────────
    property string keyboardLayoutLabel: "--"
    signal notifToggle

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
    // Frost material — neutral Theme.surface tint, no resin saturation or
    // dot texture. Opacity is still owned by BarStyleService's solid/
    // transparent toggle, not the material itself.
    color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, bar.bgOpacity)
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
                if (pill.hoverable)
                    pill.hoverEntered();
            }
            onExited: {
                if (pill.hoverable)
                    pill.hoverExited();
            }
        }
    }

    // Double-click empty bar space to switch solid <-> transparent+vignette.
    // Declared before the zones/pills below so their own MouseAreas still
    // win on direct hits — this only catches clicks that land on nothing.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: BarStyleService.toggle()
    }

    Item {
        id: wsZone
        anchors.horizontalCenter: parent.horizontalCenter
        width: wsRowCentered.implicitWidth
        height: parent.height
    }

    // Workspaces
    Row {
        id: wsRowCentered
        parent: wsZone
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: Array.from({ length: 5 }, (_, i) => i + 1)

            delegate: Item {
                required property int modelData
                readonly property var workspaceWindow: HyprlandData.mostRecentWindowForWorkspace(modelData)
                readonly property var workspaceIconSources: workspaceWindow ? HyprlandData.iconSourcesForWindow(workspaceWindow) : []
                readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                readonly property bool empty: workspaceWindow === null

                width: 20
                // Icon cell matches pill height so icons share the bar
                // baseline; the keyline sits below it instead of clipping
                // through the icon.
                height: workspaceIconCell.height + workspaceKeyline.height + 2

                Item {
                    id: workspaceIconCell
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    height: bar.barHeight - bar.pillPadV * 2

                    Image {
                        id: workspaceIcon
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
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
                        visible: empty
                        text: String(modelData)
                        color: focused ? bar.barFgStrong : bar.barFgMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: focused ? 11 : 10
                        font.weight: Font.DemiBold
                    }
                }

                Rectangle {
                    id: workspaceKeyline
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: 2
                    color: bar.barFgStrong
                    visible: focused
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: HyprDispatch.focusWorkspace(modelData)
                    onWheel: e => HyprDispatch.focusWorkspaceRelative(e.angleDelta.y > 0 ? "e-1" : "e+1")
                }
            }
        }
    }

    Item {
        id: leftZone
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: wsZone.left
        }
        clip: true
    }

    Item {
        id: rightZone
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: wsZone.right
            right: parent.right
        }
        clip: true
    }

    // LEFT
    Row {
        id: leftRow
        parent: leftZone
        anchors {
            left: parent.left
            leftMargin: 4
            verticalCenter: parent.verticalCenter
        }
        spacing: bar.pillGap

        Pill {
            label: "󰅟"
            iconSize: 16
            width: implicitWidth + bar.pillPadH * 2
            fg: bar.barFgStrong
            bg: Qt.rgba(0, 0, 0, 0)
            onClicked: bar.launch(["qs", "-p", Quickshell.env("HOME") + "/.config/quickshell", "ipc", "call", "spotlight", "command"])
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
                onClicked: QuickCalendar.CalendarPanelService.toggle()
            }
        }

        Pill {
            id: updatesPill
            property string n: "0"
            label: "󰏔 " + n
            width: implicitWidth + bar.pillPadH * 2
            onClicked: bar.launchAndFocusByTitle(
                ["bash", "-c", "kitty --title cloudyy-update cloudyy-update"],
                "cloudyy-update")
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

    }

    // RIGHT
    Row {
        id: rightRow
        parent: rightZone
        anchors {
            right: parent.right
            rightMargin: 4
            verticalCenter: parent.verticalCenter
        }
        spacing: bar.pillGap

        // Live screen-recording indicator (macOS-style): red dot while capturing;
        // hover expands to timer + Stop. Only the dot is red.
        // Height matches Pill; do not clip — bar pills rely on text overflowing the
        // tiny barHeight box the same way the rest of the tray does.
        Item {
            id: recordingControl
            readonly property var svc: QuickRecording.RecordingService
            readonly property bool active: svc.recordingActive
            readonly property color recRed: Qt.rgba(1, 0.27, 0.23, 1)
            readonly property int collapsedW: 18
            readonly property int expandedW: 86
            property bool hovered: false
            property string elapsedText: "00:00"

            visible: active
            height: bar.barHeight - bar.pillPadV * 2
            width: !active ? 0 : (hovered ? expandedW : collapsedW)

            Behavior on width {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            function refreshElapsed() {
                const start = svc.recordingStartedAt;
                if (!start) {
                    elapsedText = "00:00";
                    return;
                }
                const s = Math.max(0, Math.floor((Date.now() - start) / 1000));
                const m = Math.floor(s / 60);
                const r = s % 60;
                elapsedText = String(m).padStart(2, "0") + ":" + String(r).padStart(2, "0");
            }

            // Collapsed: just the live dot, centered in the slot.
            Rectangle {
                id: liveDot
                visible: !recordingControl.hovered
                width: 8
                height: 8
                radius: 4
                anchors.centerIn: parent
                color: recordingControl.recRed

                SequentialAnimation on opacity {
                    running: recordingControl.active && !recordingControl.hovered
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // Expanded: neutral chrome row (dot stays red).
            Row {
                id: expandedRow
                visible: recordingControl.hovered
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: recordingControl.recRed
                }

                Text {
                    text: recordingControl.elapsedText
                    color: bar.barFgStrong
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    renderType: Text.NativeRendering
                    anchors.verticalCenter: parent.verticalCenter
                }

                Rectangle {
                    width: 9
                    height: 9
                    radius: 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: bar.barFgStrong
                }
            }

            MouseArea {
                id: recordingHover
                z: 1
                anchors.fill: parent
                // Tall hit target so hover is usable on the thin bar.
                anchors.topMargin: -6
                anchors.bottomMargin: -6
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onEntered: {
                    leaveDelay.stop();
                    recordingControl.hovered = true;
                }
                onExited: leaveDelay.restart()
            }

            MouseArea {
                z: 2
                visible: recordingControl.hovered
                width: 22
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: -6
                anchors.bottomMargin: -6
                anchors.right: parent.right
                cursorShape: Qt.PointingHandCursor
                onClicked: recordingControl.svc.stopRecording()
                onEntered: {
                    leaveDelay.stop();
                    recordingControl.hovered = true;
                }
                onExited: leaveDelay.restart()
            }

            Timer {
                id: leaveDelay
                interval: 180
                repeat: false
                onTriggered: {
                    if (!recordingHover.containsMouse)
                        recordingControl.hovered = false;
                }
            }

            Timer {
                interval: 1000
                running: recordingControl.active
                repeat: true
                triggeredOnStart: true
                onTriggered: recordingControl.refreshElapsed()
            }

            onActiveChanged: {
                if (!active)
                    hovered = false;
                else
                    refreshElapsed();
            }
        }

        // Mpris
        Pill {
            id: mprisPill
            readonly property var player: QuickMpris.MprisFocus.activePlayer
            visible: player !== null && (player.playbackState === MprisPlaybackState.Playing || player.playbackState === MprisPlaybackState.Paused)
            label: {
                const _ = QuickMpris.MprisFocus.revision;
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
            onClicked: bar.launch(["bash", "-c", "uwsm-app -- cloudyy-center --wifi"])
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
            onScrollUp: bar.launch(["bash", "-lc", "cloudyy-slider-volume up"])
            onScrollDown: bar.launch(["bash", "-lc", "cloudyy-slider-volume down"])
        }

        // Notification Bell
        Pill {
            id: bellPill
            readonly property int unread: QuickNotifPanel.NotifPanelService.unreadCount
            label: "󰂚" + (unread > 0 ? (" " + unread) : "")
            width: implicitWidth + bar.pillPadH * 2
            fg: bar.barFg
            bg: Qt.rgba(0, 0, 0, 0)
            onClicked: bar.notifToggle()
        }

        // commenting out to clean up the bar, leaving optional for later when I implement bar customisation

        // CPU
        //Pill {
        //    id: cpuPill
        //    readonly property var sys: QuickSystemMonitor.SystemMonitorService
        //    label: "󰍛 " + sys.cpuPercent + "%"
        //    width: implicitWidth + bar.pillPadH * 2
        //    fg: sys.open ? bar.barFgStrong : bar.barFgMuted
        //    bg: Qt.rgba(0,0,0,0)
        //    onClicked: sys.toggleOpen()
        //}

        // Memory
        //Pill {
        //    id: memPill
        //    readonly property var sys: QuickSystemMonitor.SystemMonitorService
        //    label: "󰘚 " + sys.ramPercent + "%"
        //    width: implicitWidth + bar.pillPadH * 2
        //    fg: sys.open ? bar.barFgStrong : bar.barFgMuted
        //    bg: Qt.rgba(0,0,0,0)
        //    onClicked: sys.toggleOpen()
        //}

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
            onClicked: bar.launch(["qs", "-p", Quickshell.env("HOME") + "/.config/quickshell", "ipc", "call", "powermenu", "open"])
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
