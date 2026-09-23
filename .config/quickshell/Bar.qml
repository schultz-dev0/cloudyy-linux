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
import "Readout.js" as Readout
import "ShellEdges.js" as ShellEdges

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
    readonly property int radius: 0
    readonly property int pillRadius: 2
    readonly property int pillPadH: 6
    readonly property int pillPadV: 3
    readonly property int pillGap: 10
    readonly property real bgOpacity: BarStyleService.bgOpacity
    readonly property string edge: ShellLayout.barEdge
    readonly property bool vertical: ShellEdges.isVertical(edge)
    // Size across the bar: barHeight on top/bottom, a fixed width on the sides.
    readonly property int thickness: vertical ? BarStyleService.verticalBarWidth : barHeight

    // ── Bar colors ─────────────────────────────────────
    // Theme-derived, not hardcoded white — the text role is guaranteed to
    // contrast against surface in both light and dark mode, which fixed
    // white text never was (invisible on a light-mode solid bar). Used in
    // both bar states now, not just solid — no vignette to lean on anymore.
    readonly property color barFgStrong: Theme.text
    readonly property color barFg: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.85)
    readonly property color barFgMuted: Theme.textMuted
    // Charging is a semantic status color, not a legibility token — themes'
    // tertiary roles aren't reliably green (Nord/Gruvbox/Catppuccin are all
    // purple), so tokenizing this would break the "green = charging" meaning.
    readonly property color barFgCharging: Qt.rgba(0.65, 0.95, 0.72, 0.98)

    // ── Props ─────────────────────────────────────────────────────────────────
    property string keyboardLayoutLabel: "--"
    signal notifToggle

    // ── Window ────────────────────────────────────────────────────────────────
    anchors {
        top: bar.edge !== "bottom"
        bottom: bar.edge !== "top"
        left: bar.edge !== "right"
        right: bar.edge !== "left"
    }
    margins {
        top: bar.edge === "top" ? topGap : 0
        bottom: bar.edge === "bottom" ? topGap : 0
        left: bar.edge === "left" ? topGap : 0
        right: bar.edge === "right" ? topGap : 0
    }
    implicitHeight: vertical ? 0 : thickness + topGap
    implicitWidth: vertical ? thickness + topGap : 0
    exclusiveZone: thickness + topGap
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

    function trackMove(area, mouse) {
        if (ShellLayout.movingWhich !== "bar" || !bar.screen)
            return;
        const origin = ShellEdges.surfaceOrigin(bar.edge, true, bar.screen.width, bar.screen.height, bar.width, bar.height, bar.topGap);
        const p = area.mapToItem(null, mouse.x, mouse.y);
        ShellLayout.updateMove(origin.x + p.x, origin.y + p.y, bar.screen.width, bar.screen.height);
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

    // With bar_on_all_screens off, this Variants delegate can be destroyed
    // mid-drag (focus followed the drag to another monitor) — no
    // released/canceled arrives, so movingWhich would stay stuck set.
    Component.onDestruction: {
        if (ShellLayout.movingWhich === "bar" && ShellLayout.moveScreen === bar.screen)
            ShellLayout.cancelMove();
    }

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

        // Text shown on a vertical bar; pills override it where the generic rule is wrong.
        property string verticalText: ShellEdges.verticalLabel(label)

        width: bar.vertical ? bar.thickness - bar.pillPadV * 2 : implicitWidth + bar.pillPadH * 2
        height: bar.vertical ? pillText.implicitHeight + bar.pillPadV * 2 : bar.barHeight - bar.pillPadV * 2
        implicitWidth: pillText.implicitWidth
        radius: bar.pillRadius
        color: bg

        Text {
            id: pillText
            anchors.centerIn: parent
            text: bar.vertical ? pill.verticalText : pill.label
            horizontalAlignment: Text.AlignHCenter
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

    // Double-click empty bar space to switch solid <-> transparent+vignette;
    // long-press it to drag the bar to another screen edge.
    // Declared before the zones/pills below so their own MouseAreas still
    // win on direct hits — this only catches clicks that land on nothing.
    MouseArea {
        id: barBackground
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        pressAndHoldInterval: 400
        onDoubleClicked: BarStyleService.toggle()
        onPressAndHold: ShellLayout.beginMove("bar", bar.screen)
        onPositionChanged: mouse => bar.trackMove(barBackground, mouse)
        onReleased: if (ShellLayout.movingWhich === "bar") ShellLayout.endMove()
        onCanceled: if (ShellLayout.movingWhich === "bar") ShellLayout.cancelMove()
    }

    // See leftRowZone's comment (below, LEFT section): Grid's own width/height
    // are not a safe anchor source across a vertical<->horizontal round-trip.
    // wsZone is content-sized on one axis and full-sized on the other; on the
    // full-sized axis wsRowCentered centers itself using its own verified
    // contentW/contentH (never its own possibly-stale width/height).
    Item {
        id: wsZone
        anchors.centerIn: parent
        width: bar.vertical ? parent.width : wsRowCentered.contentW
        height: bar.vertical ? wsRowCentered.contentH : parent.height
    }

    // Workspaces
    Grid {
        id: wsRowCentered
        parent: wsZone
        x: bar.vertical ? (wsZone.width - contentW) / 2 : 0
        y: bar.vertical ? 0 : (wsZone.height - contentH) / 2
        spacing: 4
        // One column on left/right; one row of all items on top/bottom (columns
        // fixed to the item count, not -1, so a mode flip can't land on a stale
        // rows/columns pair that's briefly too small for the item count).
        columns: bar.vertical ? 1 : children.length
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        // Used by wsZone and by x/y above, not by Grid itself — see
        // leftRowZone's comment (LEFT section): a plain `width:`/`height:`
        // override on the Grid itself doesn't reliably stick.
        readonly property real contentW: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.x + c.width); return m; }
        readonly property real contentH: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.y + c.height); return m; }

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
                    height: bar.vertical ? 22 : bar.barHeight - bar.pillPadV * 2

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
            left: parent.left
            bottom: bar.vertical ? wsZone.top : parent.bottom
            right: bar.vertical ? parent.right : wsZone.left
        }
        clip: true
    }

    Item {
        id: rightZone
        anchors {
            top: bar.vertical ? wsZone.bottom : parent.top
            left: bar.vertical ? parent.left : wsZone.right
            bottom: parent.bottom
            right: parent.right
        }
        clip: true
    }

    // LEFT
    // Grid's own width/height are not a safe anchor source across a vertical<->
    // horizontal round-trip: Grid repositions children correctly (verified live)
    // but its own reported size can go stale, and a plain QML `width:`/`height:`
    // override on the Grid itself doesn't reliably stick (Positioner's own
    // relayout pass wins). So leftRowZone — a plain Item, not a Positioner —
    // carries the real position, sized from leftRow's verified-correct
    // contentW/contentH; leftRow itself just sits at the wrapper's origin.
    //
    // No `anchors` block: ternary-toggling BETWEEN DIFFERENT anchor lines on the
    // same axis (left <-> horizontalCenter, top <-> verticalCenter as bar.vertical
    // flips) can transiently over-constrain Qt's Anchors engine when both lines
    // update in the same batch — verified live, it computes garbage width/height
    // via a direct write that silently clears any QML width/height binding (no
    // binding re-evaluation at all, confirmed with logging). Plain x/y bindings
    // never touch the Anchors engine, so they can't hit this.
    Item {
        id: leftRowZone
        parent: leftZone
        width: leftRow.contentW
        height: leftRow.contentH
        x: bar.vertical ? (leftZone.width - width) / 2 : 4
        y: bar.vertical ? 4 : (leftZone.height - height) / 2
    }

    Grid {
        id: leftRow
        parent: leftRowZone
        spacing: bar.pillGap
        // One column on left/right; one row of all items on top/bottom (columns
        // fixed to the item count, not -1, so a mode flip can't land on a stale
        // rows/columns pair that's briefly too small for the item count).
        columns: bar.vertical ? 1 : children.length
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        // Used by leftRowZone above, not by Grid itself (see leftRowZone's comment).
        readonly property real contentW: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.x + c.width); return m; }
        readonly property real contentH: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.y + c.height); return m; }

        Pill {
            label: "󰅟"
            iconSize: 16
            fg: bar.barFgStrong
            bg: Qt.rgba(0, 0, 0, 0)
            onClicked: bar.launch(["qs", "-p", Quickshell.env("HOME") + "/.config/quickshell", "ipc", "call", "spotlight", "command"])
        }

        Item {
            id: clockPill
            height: bar.vertical ? clockColumn.implicitHeight + bar.pillPadV * 2 : bar.barHeight - bar.pillPadV * 2
            implicitWidth: clockRow.implicitWidth
            width: bar.vertical ? bar.thickness - bar.pillPadV * 2 : implicitWidth + bar.pillPadH * 2

            property string dateText: Qt.formatDateTime(new Date(), "ddd MMM d")
            property string timeText: Qt.formatDateTime(new Date(), "HH:mm")

            function refreshClock() {
                const now = new Date();
                dateText = Qt.formatDateTime(now, "ddd MMM d");
                timeText = Qt.formatDateTime(now, "HH:mm");
            }

            Row {
                id: clockRow
                visible: !bar.vertical
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

            // Vertical bar: HH over MM, date only in the calendar.
            Column {
                id: clockColumn
                visible: bar.vertical
                anchors.centerIn: parent

                Repeater {
                    model: [clockPill.timeText.slice(0, 2), clockPill.timeText.slice(3, 5)]
                    Text {
                        required property string modelData
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData
                        color: bar.barFg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
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
    // See leftRowZone's comment: rightRowZone (a plain Item, plain x/y, no
    // `anchors`) carries the real position, sized from rightRow's verified-
    // correct contentW/contentH.
    Item {
        id: rightRowZone
        parent: rightZone
        width: rightRow.contentW
        height: rightRow.contentH
        x: bar.vertical ? (rightZone.width - width) / 2 : rightZone.width - width - 4
        y: bar.vertical ? rightZone.height - height - 4 : (rightZone.height - height) / 2
    }

    Grid {
        id: rightRow
        parent: rightRowZone
        spacing: bar.pillGap
        // One column on left/right; one row of all items on top/bottom (columns
        // fixed to the item count, not -1, so a mode flip can't land on a stale
        // rows/columns pair that's briefly too small for the item count).
        columns: bar.vertical ? 1 : children.length
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        // Used by rightRowZone above, not by Grid itself (see leftRowZone's comment).
        readonly property real contentW: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.x + c.width); return m; }
        readonly property real contentH: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.y + c.height); return m; }

        // Live screen-recording indicator (macOS-style): red dot while capturing;
        // hover expands to timer + Stop. Only the dot is red.
        // Height matches Pill; do not clip — bar pills rely on text overflowing the
        // tiny barHeight box the same way the rest of the tray does.
        Item {
            id: recordingControl
            readonly property var svc: QuickRecording.RecordingService
            readonly property bool active: svc.recordingActive
            readonly property color recRed: Theme.error
            readonly property int collapsedW: 18
            readonly property int expandedW: Math.max(118, Math.round(expandedRow.implicitWidth + 18))
            readonly property bool expanded: hovered && !bar.vertical
            property bool hovered: false
            property string elapsedText: "00:00"

            visible: active
            height: bar.vertical ? collapsedW : bar.barHeight - bar.pillPadV * 2
            width: !active ? 0 : (bar.vertical ? bar.thickness - bar.pillPadV * 2 : (expanded ? expandedW : collapsedW))

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
                visible: !recordingControl.expanded
                width: 8
                height: 8
                radius: 4
                anchors.centerIn: parent
                color: recordingControl.recRed

                SequentialAnimation on opacity {
                    running: recordingControl.active && !recordingControl.expanded
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.45; to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }

            // Expanded: bracketed readout + Stop. Grammar only here, not on the dot.
            Row {
                id: expandedRow
                visible: recordingControl.expanded
                anchors.centerIn: parent
                spacing: 8

                Row {
                    spacing: 0
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "[ "
                        color: bar.barFgStrong
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: "REC"
                        color: Theme.error
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }
                    Text {
                        text: " · " + recordingControl.elapsedText + " ]"
                        color: bar.barFgStrong
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                    }
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
                visible: recordingControl.expanded
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

            // Vertical bar has no room to expand: the dot itself stops the recording.
            MouseArea {
                z: 3
                visible: bar.vertical
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: recordingControl.svc.stopRecording()
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
            property int clock: 0
            visible: player !== null && (player.playbackState === MprisPlaybackState.Playing || player.playbackState === MprisPlaybackState.Paused)
            label: {
                const _ = QuickMpris.MprisFocus.revision;
                const __ = clock;
                return Readout.mpris(player);
            }
            width: bar.vertical ? bar.thickness - bar.pillPadV * 2 : Math.max(implicitWidth + bar.pillPadH * 2, 50)
            verticalText: "󰎈"
            fg: bar.barFg
            bg: Qt.rgba(0,0,0,0)
            onClicked: if (player) player.togglePlaying()
            onScrollUp: if (player) player.next()
            onScrollDown: if (player) player.previous()

            Timer {
                interval: 1000
                running: mprisPill.visible && mprisPill.player
                    && mprisPill.player.playbackState === MprisPlaybackState.Playing
                repeat: true
                onTriggered: mprisPill.clock++
            }
        }

        Pill {
            id: keyboardLayoutPill
            label: " " + bar.keyboardLayoutLabel
            verticalText: bar.keyboardLayoutLabel
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
            fg: bat.full
                ? bar.barFgStrong
                : bat.charging
                    ? bar.barFgCharging
                    : (bat.percent < 15 ? Theme.error : (sys.open ? bar.barFgStrong : bar.barFgMuted))
            bg: Qt.rgba(0,0,0,0)
            onClicked: sys.toggleOpen()
            onHoverEntered: batteryTooltip.hovered = true
            onHoverExited: batteryTooltipHideTimer.restart()
        }

        // Power
        Pill {
            label: "󰐥"
            iconSize: 12
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
