pragma ComponentBehavior: Bound

// modules/dock/Dock.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../../ShellEdges.js" as ShellEdges
import "../../overview/services"
import "../../overview/services/AppIdentity.js" as AppIdentity
import "DockVisibilityPolicy.js" as DockVisibilityPolicy
import "DockKeyboard.js" as DockKeyboard
import "DockLayout.js" as DockLayout
import "../spotlight"
import "../idle" as QuickIdle

PanelWindow {
    id: dock

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

    // Screen edge (ShellLayout). Content is laid out natively for the edge; there is no rotation.
    readonly property string edge: ShellLayout.dockEdge
    readonly property bool vertical: ShellEdges.isVertical(edge)

    // Space the bar reserves at the start/end of this edge — its thickness plus
    // the gap Hyprland counts twice (exclusive zone + margin), as in `reserved`.
    readonly property var barInsets: ShellEdges.barInsets(edge, ShellLayout.barEdge,
        (ShellEdges.isVertical(ShellLayout.barEdge) ? BarStyleService.verticalBarWidth : BarStyleService.barHeight)
            + BarStyleService.topGap * 2)

    // ── Rail geometry ──────────────────────────────────────────────────────
    // One glyph advance of the mono font: widths are chars × charW, so layout is
    // plain arithmetic (DockLayout.js), with no text measuring.
    FontMetrics {
        id: railFont
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 12
    }
    readonly property real charW: railFont.advanceWidth("0")
    // Length along the edge that the bar leaves free, minus the edge margins.
    readonly property real availableLength: Number((dock.vertical ? dock.resolvedScreen?.height : dock.resolvedScreen?.width) ?? 0)
        - dock.barInsets.start - dock.barInsets.end - 24
    readonly property var railEntries: {
        const out = [];
        for (let i = 0; i < dock.mergedApps.length; i++) {
            const a = dock.mergedApps[i];
            out.push({ name: dock.nameForApp(a), leds: DockLayout.ledCount(a.windowCount, a.isRunning) });
        }
        for (let i = 0; i < dock.openFolderEntries.length; i++) {
            const n = (dock.openFolderEntries[i].addresses ?? []).length;
            out.push({ name: dock.openFolderEntries[i].label, leds: DockLayout.ledCount(n, n > 0) });
        }
        return out;
    }
    // Names are full length while the rail fits, then cut (6 chars; 10 on side edges).
    readonly property int nameCap: dock.vertical ? DockLayout.NAME_CAP_SIDE
        : DockLayout.pickNameCap(dock.railEntries, dock.availableLength, dock.charW)
    readonly property real railLength: DockLayout.railLength(dock.railEntries, dock.nameCap, dock.charW, dock.vertical)
    readonly property real railThickness: dock.vertical ? DockLayout.sideThickness(dock.charW) : DockLayout.STRIP
    readonly property int activationHeight: 2 // reduce from 16 for a more macos feel, on macos you really gotta drag your cursor all the way down to bring the dock up. 2 not 1: Hyprland's cursor hotspot_padding keeps the pointer 1px off every screen edge, so a 1px strip is unreachable on the top/left edges.
    // Reveal intent: dwell on the 1px strip + a few hyprctl cursorpos checks
    // confirming the pointer stays on this monitor's dock edge (event-driven
    // only — no background poller while the dock is idle).
    readonly property int revealDwellMs: 190
    readonly property int revealSampleCount: 4
    readonly property int revealSampleIntervalMs: 48
    readonly property int revealEdgeSlopPx: Math.max(4, revealStripPx)
    // Reject U-sweeps / edge skimming: position along the edge must stay nearly planted while dwelling.
    readonly property int revealMaxAlongSpanPx: 30
    readonly property int showAnimMs: 500
    readonly property int hideAnimMs: 480
    // After a successful reveal, block hide briefly so the slide can finish and
    // the cursor can settle onto the pill / an icon (avoids between-icon races).
    readonly property int postRevealGraceMs: 500
    // One soft retry after a near-miss — long enough that a parked cursor
    // doesn't casually clear the gate (keeps the push-down feel).
    readonly property int revealRearmDelayMs: 220
    readonly property int revealRearmMax: 1
    readonly property int occupancyHideDelayMs: 180

    // ── Keyboard summon state ──────────────────────────────────────────────
    // glanceHeld: key physically down, dock shown for the peek. keyboardMode:
    // tapped, the dock owns the keyboard.
    property bool glanceHeld: false
    property bool keyboardMode: false
    property bool holdElapsed: false
    property bool pressIgnored: false
    // Shift only counts as "move the app" once it was pressed inside the mode (or a key
    // arrived with Shift up). A Shift still held from the summon chord must not reorder.
    property bool shiftHonored: false
    readonly property bool keyboardHold: glanceHeld || keyboardMode
    // Forces the dock visible (syncDockVisibility's first branch).
    readonly property bool uiBlocked: keyboardHold

    readonly property var effectivePinnedApps: DockStore.loaded ? DockStore.pinnedApps : DockStore.defaultPinnedApps
    readonly property bool hasOpenFolders: openFolderEntries.length > 0

    property var dynamicFolderEntries: []
    property string dynamicFolderEntriesSignature: ""
    property var openFolderEntries: []
    property string folderBarSignature: ""
    property string folderIconPath: ""

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockVisible: false
    property bool revealIntentArmed: false
    property int revealSampleHits: 0
    property int revealSampleMisses: 0
    property int revealSamplesDone: 0
    property bool revealDwellElapsed: false
    property bool revealSamplesComplete: false
    property bool revealVerifyComplete: false
    property bool revealAlongStable: false
    property real revealSampleMinAlong: 0
    property real revealSampleMaxAlong: 0
    property bool revealSampleAlongInit: false
    property bool postRevealGrace: false
    // After hide while still on the 1px strip, require leaving before re-intent
    // (breaks hide → immediate re-arm → show flicker loops).
    property bool revealNeedsStripExit: false
    property int revealRearmCount: 0
    property bool previousWorkspaceEmpty: false
    property bool occupancyHidePending: false
    readonly property bool dockBodyHovered: dockInteractPointer.hovered
    readonly property bool dockHovered: triggerZone.containsMouse || dockBodyHovered
    readonly property bool anyFullscreen: {
        return HyprlandData.windowList.some(w => (w.fullscreen ?? 0) > 0);
    }
    readonly property var dockMonitor: assignedScreen ? Hyprland.monitorFor(assignedScreen) : Hyprland.focusedMonitor
    readonly property int dockMonitorId: {
        const id = Number(dockMonitor?.id ?? -1);
        return Number.isFinite(id) ? id : -1;
    }
    readonly property var dockHyprMonitor: {
        const name = `${dockMonitor?.name ?? resolvedScreen?.name ?? ""}`;
        const list = HyprlandData.monitors;
        for (let i = 0; i < list.length; i++) {
            if (`${list[i]?.name ?? ""}` === name)
                return list[i];
        }
        const mid = dock.dockMonitorId;
        if (mid < 0)
            return null;
        for (let i = 0; i < list.length; i++) {
            if (Number(list[i]?.id ?? -2) === mid)
                return list[i];
        }
        return null;
    }
    readonly property bool specialWorkspaceVisibleOnMonitor: {
        const spId = Number(dockHyprMonitor?.specialWorkspace?.id ?? 0);
        return spId < 0;
    }
    readonly property int dockWorkspaceId: {
        const mon = dockMonitor;
        const id = Number(dockHyprMonitor?.activeWorkspace?.id ?? mon?.activeWorkspace?.id
            ?? Hyprland.focusedWorkspace?.id ?? HyprlandData.activeWorkspace?.id ?? -1);
        return Number.isFinite(id) ? id : -1;
    }
    readonly property bool currentWorkspaceEmpty: {
        const id = dockWorkspaceId;
        if (id < 1)
            return false;
        const windows = HyprlandData.windowsByWorkspace[id];
        if (windows && windows.length > 0)
            return false;
        // Scratchpad toggled visible treat like a non-empty workspace for autohide.
        if (dock.specialWorkspaceVisibleOnMonitor)
            return false;
        return true;
    }
    onCurrentWorkspaceEmptyChanged: syncWorkspaceOccupancy()
    onDockWorkspaceIdChanged: {
        occupancyHideTimer.stop();
        occupancyHidePending = false;
        previousWorkspaceEmpty = currentWorkspaceEmpty;
        syncDockVisibility();
    }
    onUiBlockedChanged: {
        if (uiBlocked) {
            if (occupancyHideTimer.running)
                occupancyHideTimer.stop();
        } else if (occupancyHidePending && !currentWorkspaceEmpty && !anyFullscreen) {
            occupancyHideTimer.restart();
        }
        syncDockVisibility();
    }
    // The Top-layer dock is drawn under a fullscreen window (checked by screenshot),
    // so keyboard mode must end here: it would hold the keyboard on an invisible dock.
    onAnyFullscreenChanged: {
        if (anyFullscreen && keyboardMode)
            exitKeyboardMode();
        syncDockVisibility();
    }

    // On an edge shared with another monitor the pointer can't push against
    // the edge — it crosses onto the neighbour — so the reveal strip is wider
    // there, letting the cursor rest near the edge. Same geometry source as
    // revealMonitorGeom(); Quickshell.screens covers hotplug too.
    readonly property bool edgeShared: {
        const g = dock.revealMonitorGeom();
        if (!g)
            return false;
        const others = Quickshell.screens
            .filter(s => s !== dock.resolvedScreen)
            .map(s => ({ x: Number(s.x), y: Number(s.y), width: Number(s.width), height: Number(s.height) }));
        return ShellEdges.edgeIsShared(dock.edge, g, others);
    }
    // Hidden-window thickness and reveal trigger. The shown dock keeps
    // activationHeight, so it sits the same distance from every edge. The
    // 8px strip swallows clicks on the outermost 8px of windows on that side.
    readonly property int revealStripPx: edgeShared ? 8 : activationHeight

    onDockHoveredChanged: syncDockVisibility()

    onDockVisibleChanged: {
        if (!dockVisible) {
            dock.postRevealGrace = false;
            postRevealGraceTimer.stop();
        } else {
            dock.cancelRevealIntent();
            dock.refreshOpenFolders();
        }
    }

    // ── Reveal intent (1px strip dwell + cursorpos verify) ────────────────
    function revealMonitorGeom() {
        // QScreen geometry is already transformed into logical coordinates.
        const scr = dock.resolvedScreen;
        if (scr) {
            const x = Number(scr.x);
            const y = Number(scr.y);
            const w = Number(scr.width);
            const h = Number(scr.height);
            if ([x, y, w, h].every(Number.isFinite) && w > 0 && h > 0)
                return { x: x, y: y, width: w, height: h };
        }
        const mon = dock.dockHyprMonitor;
        if (mon) {
            const x = Number(mon.x);
            const y = Number(mon.y);
            const w = Number(mon.width);
            const h = Number(mon.height);
            if ([x, y, w, h].every(Number.isFinite) && w > 0 && h > 0)
                return { x: x, y: y, width: w, height: h };
        }
        return null;
    }

    function cursorAtDockActivationEdge(cx, cy) {
        const g = dock.revealMonitorGeom();
        return g ? ShellEdges.atActivationEdge(dock.edge, g, cx, cy, dock.dockWidth, dock.revealEdgeSlopPx,
            dock.barInsets.start, dock.barInsets.end) : false;
    }

    // Cursor position along the dock's edge (x for top/bottom, y for left/right).
    function revealAlong(cx, cy) {
        const g = dock.revealMonitorGeom();
        return g ? ShellEdges.edgeCoords(dock.edge, g, cx, cy).along : cx;
    }

    function resetRevealSamples() {
        dock.revealSampleHits = 0;
        dock.revealSampleMisses = 0;
        dock.revealSamplesDone = 0;
        dock.revealDwellElapsed = false;
        dock.revealSamplesComplete = false;
        dock.revealVerifyComplete = false;
        dock.revealAlongStable = false;
        dock.revealSampleMinAlong = 0;
        dock.revealSampleMaxAlong = 0;
        dock.revealSampleAlongInit = false;
    }

    function cancelRevealIntent(allowRearm) {
        if (allowRearm === undefined)
            allowRearm = true;
        if (!dock.revealIntentArmed && !revealDwellTimer.running
                && !revealCursorProc.running && !revealVerifyProc.running
                && !revealRearmTimer.running)
            return;
        const stillOnStrip = triggerZone.containsMouse;
        dock.revealIntentArmed = false;
        revealDwellTimer.stop();
        if (revealCursorProc.running)
            revealCursorProc.running = false;
        if (revealVerifyProc.running)
            revealVerifyProc.running = false;
        dock.resetRevealSamples();
        // Soft push / near-miss: at most one delayed re-arm (keeps push feel).
        if (allowRearm && stillOnStrip && !dock.dockVisible && !dock.revealNeedsStripExit
                && !dock.anyFullscreen && !dock.currentWorkspaceEmpty
                && dock.revealRearmCount < dock.revealRearmMax)
            revealRearmTimer.restart();
        else
            revealRearmTimer.stop();
    }

    function noteRevealSamplePoint(cx, cy) {
        const ok = dock.cursorAtDockActivationEdge(cx, cy);
        dock.revealSamplesDone++;
        if (!ok) {
            dock.revealSampleMisses++;
            return false;
        }
        dock.revealSampleHits++;
        const along = dock.revealAlong(cx, cy);
        if (!dock.revealSampleAlongInit) {
            dock.revealSampleMinAlong = along;
            dock.revealSampleMaxAlong = along;
            dock.revealSampleAlongInit = true;
        } else {
            if (along < dock.revealSampleMinAlong)
                dock.revealSampleMinAlong = along;
            if (along > dock.revealSampleMaxAlong)
                dock.revealSampleMaxAlong = along;
        }
        const span = dock.revealSampleMaxAlong - dock.revealSampleMinAlong;
        dock.revealAlongStable = span <= dock.revealMaxAlongSpanPx;
        return dock.revealAlongStable;
    }

    function armRevealIntent() {
        if (dock.dockVisible || dock.revealIntentArmed || dock.anyFullscreen)
            return;
        if (dock.currentWorkspaceEmpty || dock.uiBlocked)
            return;
        if (dock.revealNeedsStripExit)
            return;
        if (!triggerZone.containsMouse)
            return;
        revealRearmTimer.stop();
        dock.revealIntentArmed = true;
        dock.resetRevealSamples();
        revealDwellTimer.restart();
        // One short burst (~4 samples over the dwell). Idle dock pays nothing.
        if (revealCursorProc.running)
            revealCursorProc.running = false;
        Qt.callLater(() => {
            if (!dock.revealIntentArmed)
                return;
            revealCursorProc.running = true;
        });
    }

    function onRevealCursorBurst(text) {
        if (!dock.revealIntentArmed)
            return;
        const raw = `${text ?? ""}`.trim();
        if (!raw.length) {
            dock.revealSampleMisses++;
            dock.revealSamplesComplete = true;
            dock.revealAlongStable = false;
            dock.tryCommitRevealIntent();
            return;
        }
        const chunks = raw.split(/\n+/).map(s => s.trim()).filter(s => s.length > 0);
        let prevAlong = NaN;
        for (let i = 0; i < chunks.length; i++) {
            const m = chunks[i].match(/^(-?\d+)\s*,\s*(-?\d+)\s*$/);
            if (!m) {
                dock.revealSampleMisses++;
                dock.revealSamplesDone++;
                continue;
            }
            const cx = Number(m[1]);
            const cy = Number(m[2]);
            if (!Number.isFinite(cx) || !Number.isFinite(cy)) {
                dock.revealSampleMisses++;
                dock.revealSamplesDone++;
                continue;
            }
            const along = dock.revealAlong(cx, cy);
            if (Number.isFinite(prevAlong) && Math.abs(along - prevAlong) > dock.revealMaxAlongSpanPx) {
                dock.revealSampleMisses++;
                dock.revealSamplesDone++;
                dock.revealAlongStable = false;
                break;
            }
            if (!dock.noteRevealSamplePoint(cx, cy))
                break;
            prevAlong = along;
        }
        dock.revealSamplesComplete = true;
        if (dock.revealSampleMisses > 0 || !dock.revealAlongStable || !triggerZone.containsMouse) {
            dock.cancelRevealIntent();
            return;
        }
        dock.tryCommitRevealIntent();
    }

    function onRevealDwellElapsed() {
        if (!dock.revealIntentArmed)
            return;
        dock.revealDwellElapsed = true;
        // End-of-dwell verify catches U-sweeps that stayed still during the early burst.
        if (revealVerifyProc.running)
            revealVerifyProc.running = false;
        Qt.callLater(() => {
            if (!dock.revealIntentArmed || !dock.revealDwellElapsed)
                return;
            revealVerifyProc.running = true;
        });
    }

    function onRevealVerifySample(text) {
        if (!dock.revealIntentArmed)
            return;
        const line = `${text ?? ""}`.trim().split(/\n+/)[0] ?? "";
        const m = line.match(/^(-?\d+)\s*,\s*(-?\d+)\s*$/);
        if (!m || !dock.noteRevealSamplePoint(Number(m[1]), Number(m[2]))) {
            dock.cancelRevealIntent();
            return;
        }
        dock.revealVerifyComplete = true;
        if (!triggerZone.containsMouse || !dock.revealAlongStable) {
            dock.cancelRevealIntent();
            return;
        }
        dock.tryCommitRevealIntent();
    }

    function tryCommitRevealIntent() {
        if (!dock.revealIntentArmed)
            return;
        // Dwell + mid-burst samples + end-of-dwell verify must all agree.
        if (!dock.revealDwellElapsed || !dock.revealSamplesComplete || !dock.revealVerifyComplete)
            return;
        const stripOk = triggerZone.containsMouse;
        const samplesOk = dock.revealSampleMisses === 0
            && dock.revealSampleHits >= Math.min(2, dock.revealSampleCount)
            && dock.revealSamplesDone > 0
            && dock.revealAlongStable;
        if (!stripOk || !samplesOk) {
            dock.cancelRevealIntent();
            return;
        }
        if (dock.anyFullscreen) {
            dock.cancelRevealIntent();
            return;
        }
        dock.cancelRevealIntent(false);
        hideTimer.stop();
        dock.revealNeedsStripExit = false;
        dock.revealRearmCount = 0;
        dock.postRevealGrace = true;
        postRevealGraceTimer.restart();
        dock.dockVisible = true;
    }

    function syncDockVisibility() {
        if (uiBlocked || ShellLayout.movingWhich === "dock") {
            dock.cancelRevealIntent();
            dock.postRevealGrace = false;
            postRevealGraceTimer.stop();
            hideTimer.stop();
            dockVisible = true;
            return;
        }
        if (anyFullscreen) {
            occupancyHideTimer.stop();
            occupancyHidePending = false;
            dock.cancelRevealIntent();
            dock.postRevealGrace = false;
            postRevealGraceTimer.stop();
            hideTimer.stop();
            dockVisible = false;
            return;
        }

        if (currentWorkspaceEmpty) {
            occupancyHideTimer.stop();
            occupancyHidePending = false;
            dock.cancelRevealIntent();
            dock.postRevealGrace = false;
            postRevealGraceTimer.stop();
            hideTimer.stop();
            dockVisible = true;
            return;
        }

        // The first mapped window owns this short edge transition. Inherited
        // hover from the launch click must not replace it with the normal hide delay.
        if (occupancyHidePending) {
            if (!occupancyHideTimer.running && !uiBlocked)
                occupancyHideTimer.restart();
            return;
        }

        if (!DockVisibilityPolicy.canRevealAfterForcedHide(
                dock.revealNeedsStripExit, dock.dockHovered)) {
            dock.cancelRevealIntent(false);
            hideTimer.stop();
            return;
        }
        if (dock.revealNeedsStripExit && !dock.dockHovered)
            dock.revealNeedsStripExit = false;

        // Already visible: hover or post-reveal grace keeps it up.
        if (dockVisible) {
            if (dockHovered || dock.postRevealGrace) {
                hideTimer.stop();
                return;
            }
            hideTimer.restart();
            return;
        }

        // Hidden: body hover is rare (slid away) but still an immediate show.
        if (dockBodyHovered) {
            dock.cancelRevealIntent();
            hideTimer.stop();
            dockVisible = true;
            return;
        }

        // Hidden + strip: arm intent only after a clean enter (not residual sit).
        if (triggerZone.containsMouse) {
            dock.armRevealIntent();
        } else {
            dock.revealNeedsStripExit = false;
            dock.revealRearmCount = 0;
            revealRearmTimer.stop();
            dock.cancelRevealIntent(false);
        }
    }

    function syncWorkspaceOccupancy() {
        const action = DockVisibilityPolicy.occupancyTransition(
            dock.previousWorkspaceEmpty,
            dock.currentWorkspaceEmpty,
            dock.uiBlocked
        );
        dock.occupancyHidePending = DockVisibilityPolicy.nextPending(
            dock.occupancyHidePending, action);
        dock.previousWorkspaceEmpty = dock.currentWorkspaceEmpty;
        if (action === "cancel")
            occupancyHideTimer.stop();
        else if (action === "schedule")
            occupancyHideTimer.restart();
        dock.syncDockVisibility();
    }

    function commitOccupancyHide() {
        if (!DockVisibilityPolicy.shouldCommitOccupancyHide(
                dock.currentWorkspaceEmpty, dock.uiBlocked, dock.anyFullscreen)) {
            if (dock.currentWorkspaceEmpty || dock.anyFullscreen)
                dock.occupancyHidePending = false;
            return;
        }
        dock.cancelRevealIntent(false);
        dock.postRevealGrace = false;
        postRevealGraceTimer.stop();
        hideTimer.stop();
        dock.revealNeedsStripExit = dock.dockHovered;
        dock.revealRearmCount = 0;
        dock.dockVisible = false;
        dock.occupancyHidePending = false;
    }

    function openFolderStructureSignature(list) {
        let sig = "";
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (i > 0)
                sig += "|";
            sig += `${e.path ?? ""}`;
            const addrs = e.addresses || (e.windows || []).map(w => `${w.address ?? ""}`);
            sig += ":" + addrs.filter(a => a.length > 0).sort().join(",");
        }
        return sig;
    }

    function folderBarSignatureFor(list) {
        let sig = "";
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (i > 0)
                sig += "|";
            sig += `${e.pinned ? 1 : 0}:${e.path ?? ""}`;
            const addrs = e.addresses || [];
            sig += ":" + addrs.filter(a => `${a}`.length > 0).join(",");
        }
        return sig;
    }

    function folderPathKey(path) {
        return `${path ?? ""}`.trim().toLowerCase();
    }

    function dynamicEntryForPath(path) {
        const key = dock.folderPathKey(path);
        if (!key.length)
            return null;
        const list = dock.dynamicFolderEntries || [];
        for (let i = 0; i < list.length; i++) {
            if (dock.folderPathKey(list[i].path) === key)
                return list[i];
        }
        return null;
    }

    function rebuildFolderBar() {
        const pinned = DockStore.foldersLoaded ? DockStore.pinnedFolders : [];
        const dynamic = dock.dynamicFolderEntries || [];
        const seen = {};
        const result = [];

        for (let p = 0; p < pinned.length; p++) {
            const pin = pinned[p];
            const path = `${pin.path ?? ""}`.trim();
            const key = dock.folderPathKey(path);
            if (!key.length || seen[key])
                continue;
            seen[key] = true;
            const live = dock.dynamicEntryForPath(path);
            result.push({
                path: path,
                label: `${pin.label ?? ""}`.trim() || dock.pathLabel(path),
                pinned: true,
                addresses: live?.addresses ?? []
            });
        }

        for (let d = 0; d < dynamic.length; d++) {
            const entry = dynamic[d];
            const path = `${entry.path ?? ""}`.trim();
            const key = dock.folderPathKey(path);
            if (!key.length || seen[key])
                continue;
            seen[key] = true;
            result.push({
                path: path,
                label: `${entry.label ?? ""}`.trim() || dock.pathLabel(path),
                pinned: false,
                addresses: entry.addresses ?? []
            });
        }

        const sig = dock.folderBarSignatureFor(result);
        if (sig === dock.folderBarSignature && dock.openFolderEntries.length === result.length) {
            for (let i = 0; i < result.length; i++) {
                const cur = dock.openFolderEntries[i];
                const next = result[i];
                cur.addresses = next.addresses;
                cur.pinned = next.pinned;
            }
            return;
        }

        dock.folderBarSignature = sig;
        dock.openFolderEntries = result;
    }

    function applyDynamicFolderEntries(parsed) {
        const list = Array.isArray(parsed) ? parsed : [];
        const sig = dock.openFolderStructureSignature(list);
        if (sig === dock.dynamicFolderEntriesSignature && dock.dynamicFolderEntries.length === list.length) {
            for (let i = 0; i < list.length; i++) {
                const cur = dock.dynamicFolderEntries[i];
                const next = list[i];
                cur.addresses = next.addresses;
            }
            dock.rebuildFolderBar();
            return;
        }
        dock.dynamicFolderEntriesSignature = sig;
        dock.dynamicFolderEntries = list;
        dock.rebuildFolderBar();
    }

    function windowForAddress(address) {
        const needle = HyprDispatch.normalizeAddress(address);
        if (!needle.length)
            return null;
        const byAddr = HyprlandData.windowByAddress ?? {};
        const raw = `${address ?? ""}`.trim();
        if (raw.length && byAddr[raw])
            return byAddr[raw];
        if (byAddr[needle])
            return byAddr[needle];
        const keys = Object.keys(byAddr);
        for (let i = 0; i < keys.length; i++) {
            if (HyprDispatch.normalizeAddress(keys[i]) === needle)
                return byAddr[keys[i]];
        }
        return null;
    }

    function stripDesktopExecField(s) {
        return HyprlandData.stripDesktopExecField(s);
    }

    function shellQuote(s) {
        const t = `${s ?? ""}`;
        return `'${t.replace(/'/g, `'\\''`)}'`;
    }

    function desktopEntryForClass(className) {
        return HyprlandData.desktopEntryForClass(className);
    }

    function desktopExecForClass(className) {
        const entry = dock.desktopEntryForClass(className);
        if (!entry)
            return "";
        const raw = entry.exec ?? entry.Exec ?? entry.commandLine ?? entry.commandline ?? "";
        return stripDesktopExecField(raw);
    }

    function iconForApp(app) {
        if (!app)
            return "";
        const entry = dock.desktopEntryForClass(app.class);
        if (entry?.icon) {
            const ic = HyprlandData.normalizeIconName(entry.icon);
            if (ic.length > 0)
                return ic;
        }
        const pinIcon = `${app.icon ?? ""}`.trim();
        if (pinIcon.length > 0)
            return pinIcon;
        return `${app.class ?? ""}`.trim();
    }

    function execForPinnedApp(app) {
        if (!app)
            return "";
        const resolved = {
            class: HyprlandData.normalizeDockClass(app.class),
            exec: app.exec,
            icon: app.icon
        };
        if (Array.isArray(resolved.exec))
            return resolved.exec;

        const desktopExec = dock.desktopExecForClass(resolved.class);
        if (desktopExec.length > 0)
            return desktopExec;

        const pinnedExec = stripDesktopExecField(resolved.exec);
        if (pinnedExec.length > 0 && !HyprlandData.isStubDockerCliExec(pinnedExec))
            return pinnedExec;

        const pwaExec = HyprlandData.chromePwaExecFromClass(resolved.class);
        if (pwaExec.length > 0)
            return pwaExec;

        const normalized = HyprlandData.normalizeChromePwaWmclass(resolved.class);
        if (normalized !== resolved.class) {
            const normExec = dock.desktopExecForClass(normalized);
            if (normExec.length > 0)
                return normExec;
            const normPwa = HyprlandData.chromePwaExecFromClass(normalized);
            if (normPwa.length > 0)
                return normPwa;
        }

        return "";
    }

    // ── App list: pinned + running, deduplicated ───────────────────────────
    readonly property var runningWindows: HyprlandData.windowList
    property var mergedApps: []
    property string mergedAppsSignature: ""

    onRunningWindowsChanged: {
        rebuildMergedApps();
        syncDockVisibility();
        openDirsRefreshDebounce.restart();
    }
    onEffectivePinnedAppsChanged: rebuildMergedApps()

    function mergedAppsSignatureFor(list) {
        let sig = "";
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (i > 0)
                sig += "|";
            const key = `${e.groupKey || e.identityKey || dock.classKey(e.class)}`.trim();
            sig += `${key}:${e.isPinned ? 1 : 0}:${e.isRunning ? 1 : 0}:${e.windowCount ?? 0}`;
        }
        return sig;
    }

    function windowMatchScore(window, pinnedClass) {
        const pCls = `${pinnedClass ?? ""}`.toLowerCase().trim();
        if (!pCls) return 0;
        const wCls = `${window.class ?? ""}`.toLowerCase();
        const wInit = `${window.initialClass ?? ""}`.toLowerCase();
        if (HyprlandData.wmclassesMatch(pCls, wCls) || HyprlandData.wmclassesMatch(pCls, wInit))
            return 3;
        const pParts = pCls.split(".");
        const pLast = pParts[pParts.length - 1] ?? "";
        const wParts = wCls.split(".");
        const wLast = wParts[wParts.length - 1] ?? "";
        if (wCls === pCls || wInit === pCls) return 3;
        if (wCls === pLast || wInit === pLast) return 2;
        if (wLast === pCls) return 2;
        if (pLast.length > 2 && wLast === pLast) return 1;
        return 0;
    }

    function findWindowForClass(pinnedClass, windowList) {
        let best = null, bestScore = 0;
        windowList.forEach(w => {
            const s = dock.windowMatchScore(w, pinnedClass);
            if (s > bestScore || (s > 0 && s === bestScore &&
                    (w.focusHistoryID ?? 9999) < (best?.focusHistoryID ?? 9999))) {
                best = w;
                bestScore = s;
            }
        });
        return best;
    }

    function dockEntryForWindow(app, win, isPinned) {
        const groupKey = HyprlandData.appGroupKey(win);
        const windowCount = HyprlandData.windowsForGroupKey(groupKey).length;
        const identity = HyprlandData.identityForWindow(win);
        return {
            class: win.class || win.initialClass || app.class,
            exec: app.exec,
            icon: dock.iconForApp(app),
            isRunning: true,
            window: win,
            groupKey: groupKey,
            windowCount: windowCount,
            groupLabel: HyprlandData.groupDisplayName(groupKey),
            identity: identity,
            identityKey: AppIdentity.canonicalKey(identity),
            label: AppIdentity.displayLabel(identity),
            isPinned: isPinned
        };
    }

    function pinnedEntriesForApp(app, windows) {
        const identityKey = AppIdentity.pinKey(app);
        const matchingWindows = HyprlandData.windowsForIdentity(app);
        if (!HyprlandData.isTerminalClass(app.class)) {
            const win = matchingWindows.length > 0 ? matchingWindows[0] : null;
            const groupKey = win ? HyprlandData.appGroupKey(win) : "";
            return [{
                class: app.class,
                exec: app.exec,
                icon: dock.iconForApp(app),
                isRunning: win != null,
                window: win,
                groupKey: groupKey,
                windowCount: groupKey ? HyprlandData.windowsForGroupKey(groupKey).length : 0,
                groupLabel: HyprlandData.groupDisplayName(groupKey),
                identity: app,
                identityKey: identityKey,
                label: AppIdentity.displayLabel(app),
                isPinned: true
            }];
        }

        const byGroup = {};
        for (let i = 0; i < matchingWindows.length; i++) {
            const w = matchingWindows[i];
            const gk = HyprlandData.appGroupKey(w);
            const existing = byGroup[gk];
            if (!existing || (w.focusHistoryID ?? 9999) < (existing.focusHistoryID ?? 9999))
                byGroup[gk] = w;
        }

        const keys = Object.keys(byGroup).sort();
        if (keys.length === 0) {
            return [{
                class: app.class,
                exec: app.exec,
                icon: dock.iconForApp(app),
                isRunning: false,
                window: null,
                groupKey: "",
                windowCount: 0,
                groupLabel: "",
                identity: app,
                identityKey: identityKey,
                label: AppIdentity.displayLabel(app),
                isPinned: true
            }];
        }

        const entries = [];
        for (let k = 0; k < keys.length; k++)
            entries.push(dock.dockEntryForWindow(app, byGroup[keys[k]], true));
        return entries;
    }

    function isGroupCovered(list, groupKey) {
        const gk = `${groupKey ?? ""}`.trim();
        if (!gk)
            return false;
        for (let i = 0; i < list.length; i++) {
            if (`${list[i].groupKey ?? ""}` === gk)
                return true;
        }
        return false;
    }

    function activateDockEntry(appData, instanceIndex) {
        if (dock.keyboardMode)
            dock.exitKeyboardMode();
        if (!appData?.isRunning) {
            dock.launchApp(appData);
            return;
        }

        const groupKey = `${appData.groupKey ?? ""}`.trim();
        if (groupKey.length) {
            const wins = HyprlandData.windowsForGroupKey(groupKey);
            if (wins.length > 1 && instanceIndex !== undefined && instanceIndex >= 0) {
                const idx = Math.max(0, Math.min(instanceIndex, wins.length - 1));
                HyprDispatch.focusWindow(wins[idx]);
                return;
            }
            HyprDispatch.focusGroupMru(groupKey);
            return;
        }
        if (appData.window)
            HyprDispatch.focusWindow(appData.window);
        else
            HyprDispatch.activateIdentity(appData.identity, { app: appData });
    }

    function rebuildMergedApps() {
        const windows = dock.runningWindows;
        const pinnedApps = dock.effectivePinnedApps;

        const result = [];
        for (let p = 0; p < pinnedApps.length; p++) {
            const entries = dock.pinnedEntriesForApp(pinnedApps[p], windows);
            for (let e = 0; e < entries.length; e++)
                result.push(entries[e]);
        }

        const runningApps = HyprlandData.buildRunningAppList();
        for (let i = 0; i < runningApps.length; i++) {
            const entry = runningApps[i];
            if (dock.isGroupCovered(result, entry.groupKey))
                continue;
            result.push({
                class: entry.class,
                exec: entry.exec,
                icon: dock.iconForApp({ class: entry.class, icon: entry.icon }),
                isRunning: true,
                window: entry.window,
                groupKey: entry.groupKey || HyprlandData.appGroupKey(entry.window),
                windowCount: entry.windowCount ?? 1,
                groupLabel: HyprlandData.groupDisplayName(entry.groupKey),
                identity: entry.identity,
                identityKey: entry.identityKey,
                label: entry.label,
                isPinned: false
            });
        }

        const sig = dock.mergedAppsSignatureFor(result);
        if (sig === dock.mergedAppsSignature && dock.mergedApps.length === result.length) {
            for (let i = 0; i < result.length; i++) {
                const cur = dock.mergedApps[i];
                const next = result[i];
                cur.window = next.window;
                cur.isRunning = next.isRunning;
                cur.exec = next.exec;
                cur.icon = next.icon;
                cur.groupKey = next.groupKey;
                cur.windowCount = next.windowCount;
                cur.groupLabel = next.groupLabel;
                cur.identity = next.identity;
                cur.identityKey = next.identityKey;
                cur.label = next.label;
            }
            return;
        }

        dock.mergedAppsSignature = sig;
        dock.mergedApps = result;
    }

    function classKey(className) {
        return `${className ?? ""}`.toLowerCase().trim();
    }

    function visualIndexForClass(className) {
        const key = dock.classKey(className);
        if (!key)
            return -1;
        const list = dock.mergedApps;
        for (let i = 0; i < list.length; i++) {
            if (dock.classKey(list[i].class) === key)
                return i;
        }
        return -1;
    }

    function visualIndexForGroupKey(groupKey, className) {
        const gk = `${groupKey ?? ""}`.trim().toLowerCase();
        if (gk.length) {
            const list = dock.mergedApps;
            for (let i = 0; i < list.length; i++) {
                if (`${list[i].groupKey ?? ""}`.trim().toLowerCase() === gk)
                    return i;
            }
        }
        return dock.visualIndexForClass(className);
    }

    function togglePinAtIndex(visualIndex, instanceIndex) {
        const list = dock.mergedApps;
        if (visualIndex < 0 || visualIndex >= list.length)
            return;
        const e = list[visualIndex];
        if (e.isPinned)
            DockStore.unpinIdentity(e.identityKey || AppIdentity.pinKey(e.identity));
        else {
            const groupWindows = `${e.groupKey ?? ""}`.length
                ? HyprlandData.windowsForGroupKey(e.groupKey) : [];
            const idx = Math.max(0, Math.min(instanceIndex ?? 0, groupWindows.length - 1));
            const selectedWindow = groupWindows.length > 0 ? groupWindows[idx] : e.window;
            const identity = selectedWindow
                ? HyprlandData.identityForWindow(selectedWindow)
                : (e.identity || HyprlandData.primaryIdentityForApp(e));
            const pin = Object.assign({}, identity, {
                class: e.class,
                exec: dock.execForPinnedApp(e),
                icon: dock.iconForApp(e)
            });
            DockStore.pinEntry(pin, DockStore.pinnedApps.length);
        }
    }

    function openPath(path) {
        const p = `${path ?? ""}`.trim();
        if (!p)
            return;
        dock.launch(["xdg-open", p]);
    }

    function focusOpenFolderAt(index) {
        if (dock.keyboardMode)
            dock.exitKeyboardMode();
        if (index < 0 || index >= dock.openFolderEntries.length)
            return;

        const entry = dock.openFolderEntries[index];
        const addrs = entry?.addresses;
        if (Array.isArray(addrs) && addrs.length > 0) {
            for (let i = 0; i < addrs.length; i++) {
                const live = dock.windowForAddress(addrs[i]);
                if (live) {
                    HyprDispatch.focusWindow(live);
                    return;
                }
            }
            const addr = `${addrs[0] ?? ""}`.trim();
            if (addr.length > 0) {
                HyprDispatch.focusWindowAddress(addr);
                return;
            }
        }

        dock.openPath(entry?.path);
    }

    function toggleFolderPinAt(index) {
        if (index < 0 || index >= dock.openFolderEntries.length)
            return;
        const entry = dock.openFolderEntries[index];
        const path = `${entry?.path ?? ""}`.trim();
        if (!path.length)
            return;
        if (entry.pinned)
            DockStore.unpinFolder(path);
        else
            DockStore.pinFolder(path);
    }

    function pathLabel(path) {
        const t = `${path ?? ""}`.trim();
        if (!t.length)
            return "";
        const slash = t.lastIndexOf("/");
        return slash >= 0 ? t.slice(slash + 1) : t;
    }

    function refreshOpenFolders() {
        openDirsProc.running = false;
        openDirsProc.running = true;
    }

    readonly property string folderImageSource: dock.folderIconSource()

    function folderIconSource() {
        const cached = `${dock.folderIconPath ?? ""}`.trim();
        if (cached.length > 0)
            return dock.fileUrl(cached);
        const themed = Quickshell.iconPath("folder", "");
        return themed && `${themed}`.length > 0 ? themed : "";
    }

    function fileUrl(path) {
        const p = `${path ?? ""}`.trim();
        if (!p)
            return "";
        if (p.startsWith("file://"))
            return p;
        if (p.startsWith("/"))
            return "file://" + p;
        return p;
    }

    // ── Dimensions ────────────────────────────────────────────────────────
    // The window is exactly the rail while shown, and just the reveal strip while hidden.
    readonly property real interactBandHeight: dock.railThickness
    readonly property real dockWidth: dock.railLength
    readonly property int visibleDockHeight: dockVisible ? railThickness : revealStripPx

    // ── Window ────────────────────────────────────────────────────────────
    anchors {
        bottom: dock.edge === "bottom"
        top: dock.edge === "top"
        left: dock.edge === "left"
        right: dock.edge === "right"
    }
    implicitWidth: vertical ? visibleDockHeight : dockWidth
    implicitHeight: vertical ? dockWidth : visibleDockHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    WlrLayershell.keyboardFocus: dock.keyboardMode ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    // Only the rail band accepts input.
    mask: Region {
        item: dockInteractZone
    }

    Item {
        id: dockInteractZone
        // Window-level on purpose, separate from the sliding rail.
        // Plain x/y, not anchors: switching edge swaps which axis is
        // anchored (e.g. bottom+horizontalCenter -> left+verticalCenter),
        // and Qt's anchor system latches the cross-axis size from before the
        // swap instead of picking up the new height/width binding — mask
        // ends up a small, mispositioned box and every left/right probe
        // misses the window entirely. Explicit x/y sidesteps that.
        width: dock.vertical ? dock.interactBandHeight : dock.dockWidth
        height: dock.vertical ? dock.dockWidth : dock.interactBandHeight
        x: dock.edge === "left" ? 0 : dock.edge === "right" ? parent.width - width : (parent.width - width) / 2
        y: dock.edge === "top" ? 0 : dock.edge === "bottom" ? parent.height - height : (parent.height - height) / 2

        HoverHandler {
            id: dockInteractPointer
            onHoveredChanged: dock.syncDockVisibility()
        }
    }

    // ── Launch helper ──────────────────────────────────────────────────────
    Component {
        id: procProto
        Process {}
    }
    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        const inner = cmd.map(a => dock.shellQuote(`${a}`)).join(" ");
        const p = procProto.createObject(dock, {
            command: ["bash", "-lc", `cd "$HOME" && setsid ${inner} </dev/null >/dev/null 2>&1 &`]
        });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function trackMove(area, mouse) {
        const scr = dock.resolvedScreen;
        if (ShellLayout.movingWhich !== "dock" || !scr)
            return;
        // ponytail: assumes the dock is centred on the whole edge; other layers'
        // exclusive zones shift it by up to their thickness — fine for picking
        // the nearest edge. Switch to hyprctl cursorpos if that ever misfires.
        const origin = ShellEdges.surfaceOrigin(dock.edge, false, scr.width, scr.height, dock.width, dock.height, 0);
        const p = area.mapToItem(null, mouse.x, mouse.y);
        ShellLayout.updateMove(origin.x + p.x, origin.y + p.y, scr.width, scr.height);
    }

    function launchApp(app, newInstance) {
        const identity = Object.assign({}, app?.identity || HyprlandData.primaryIdentityForApp(app), {
            exec: app?.identity?.exec || dock.execForPinnedApp(app),
            icon: app?.identity?.icon || dock.iconForApp(app)
        });
        HyprDispatch.activateIdentity(identity, { app: app, newInstance: newInstance === true });
    }

    // ── Rail content helpers ───────────────────────────────────────────────
    // Short display name: group label, identity label, desktop entry name, window
    // class. Never a window title.
    function nameForApp(app) {
        const groupLabel = `${app?.groupLabel ?? ""}`.trim();
        if (groupLabel.length)
            return groupLabel;
        const identityLabel = `${app?.label ?? app?.identity?.label ?? ""}`.trim();
        if (identityLabel.length)
            return identityLabel;
        const entry = HyprlandData.desktopEntryForClass(app?.class);
        const desktopName = `${entry?.name ?? entry?.Name ?? ""}`.trim();
        if (desktopName.length)
            return desktopName;
        return `${app?.class ?? ""}`.trim();
    }

    // Index in mergedApps of the app that owns the focused window, or -1.
    function focusedEntryIndex() {
        const w = dock.focusedWindow();
        if (!w)
            return -1;
        return dock.visualIndexForGroupKey(HyprlandData.appGroupKey(w), w.class);
    }
    readonly property int focusedIndex: focusedEntryIndex()

    // Long-press a slot to move the dock to another edge (ShellLayout drag).
    function moveBegin() {
        ShellLayout.beginMove("dock", dock.screen);
    }
    function moveDrag(area, mouse) {
        dock.trackMove(area, mouse);
    }
    function moveEnd() {
        if (ShellLayout.movingWhich === "dock")
            ShellLayout.endMove();
    }
    function moveCancel() {
        if (ShellLayout.movingWhich === "dock")
            ShellLayout.cancelMove();
    }

    // ── Keyboard summon ────────────────────────────────────────────────────
    // Hyprland binds Super+Shift+D press -> keyPress(), release -> keyRelease().
    // Released before holdTimer fires = tap (keyboard mode); after = hold (glance only).
    Timer {
        id: holdTimer
        interval: 350 // ponytail: press/release are separate `qs ipc` launches, a stall past this reads a tap as a hold; tune live
        onTriggered: dock.holdElapsed = true
    }

    function keyPress() {
        if (dock.keyboardMode) {
            // Second press while navigating dismisses; swallow its release.
            dock.exitKeyboardMode();
            dock.pressIgnored = true;
            return;
        }
        // Over a fullscreen window the Top-layer dock isn't drawn: don't grab the keyboard for it.
        if (dock.anyFullscreen)
            return;
        dock.pressIgnored = false;
        // Two exclusive-keyboard layers would fight; Spotlight yields.
        if (SpotlightService.visible)
            SpotlightService.close();
        dock.holdElapsed = false;
        dock.glanceHeld = true;
        holdTimer.restart();
    }

    function keyRelease() {
        if (dock.pressIgnored) {
            dock.pressIgnored = false;
            return;
        }
        if (!dock.glanceHeld)
            return;
        holdTimer.stop();
        // keyboardMode before glanceHeld = false, so uiBlocked never drops in between.
        if (!dock.holdElapsed)
            dock.enterKeyboardMode();
        dock.glanceHeld = false;
    }

    // ── Keyboard selection ─────────────────────────────────────────────────
    property int selectedIndex: -1
    // Navigation order: pinned/running apps, then open-folder shortcuts.
    readonly property int entryCount: mergedApps.length + openFolderEntries.length

    onEntryCountChanged: {
        if (dock.keyboardMode)
            dock.selectedIndex = DockKeyboard.clampIndex(dock.selectedIndex, dock.entryCount);
    }

    function focusedWindow() {
        let focused = null;
        let best = 999999;
        const list = HyprlandData.windowList ?? [];
        for (let i = 0; i < list.length; i++) {
            const history = list[i]?.focusHistoryID ?? 999999;
            if (history < best) {
                best = history;
                focused = list[i];
            }
        }
        return focused;
    }

    function focusedAppIndex() {
        const i = dock.focusedEntryIndex();
        return i >= 0 ? i : 0;
    }

    // Failsafe: the mode holds an Exclusive keyboard grab, and clicking elsewhere
    // doesn't release it, so walking away would leave the keyboard dead until Esc.
    Timer {
        id: keyboardIdleTimer
        interval: 10000
        onTriggered: dock.exitKeyboardMode()
    }

    function enterKeyboardMode() {
        dock.shiftHonored = false;
        dock.selectedIndex = DockKeyboard.clampIndex(dock.focusedAppIndex(), dock.entryCount);
        dock.keyboardMode = true;
        keyCatcher.forceActiveFocus();
        keyboardIdleTimer.restart();
    }

    function exitKeyboardMode() {
        keyboardIdleTimer.stop();
        dock.keyboardMode = false;
        dock.selectedIndex = -1;
    }

    // Another surface taking the screen/keyboard ends the mode rather than fighting it.
    Connections {
        target: SpotlightService
        function onVisibleChanged() {
            if (SpotlightService.visible && dock.keyboardMode)
                dock.exitKeyboardMode();
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen && dock.keyboardMode)
                dock.exitKeyboardMode();
        }
    }

    function activateSelected(newWindow) {
        const i = dock.selectedIndex;
        if (i < 0 || i >= dock.entryCount)
            return;
        if (i >= dock.mergedApps.length) {
            // Folder shortcut: "new window" has no meaning, both keys open it.
            dock.exitKeyboardMode();
            dock.focusOpenFolderAt(i - dock.mergedApps.length);
            return;
        }
        const app = dock.mergedApps[i];
        if (newWindow) {
            dock.exitKeyboardMode();
            dock.launchApp(app, true);
            return;
        }
        const gk = `${app.groupKey ?? ""}`.trim();
        const wins = app.isRunning && gk.length ? HyprlandData.windowsForGroupKey(gk) : [];
        // Exit first: Hyprland ignores window focus while this layer holds the keyboard.
        // Space always closes the dock, so keys typed right after a jump reach the app.
        dock.exitKeyboardMode();
        if (wins.length < 2) {
            // Not running: launches. One window: focuses it.
            dock.activateDockEntry(app);
            return;
        }
        // Several windows: the most recent one that isn't the one you're already on.
        // Summon again and Space to bounce back (ponytail: no in-mode cycling, deeper
        // windows via the overview).
        const f = dock.focusedWindow();
        const onFirst = !!f && HyprDispatch.normalizeAddress(wins[0].address)
            === HyprDispatch.normalizeAddress(f.address);
        HyprDispatch.focusWindow(wins[DockKeyboard.cycleTarget(wins.length, onFirst, 0)]);
    }

    function handleKey(key, text, shift) {
        const action = DockKeyboard.actionForKey(key, text, shift);
        if (action === "close") {
            dock.exitKeyboardMode();
            return;
        }
        if (dock.entryCount === 0)
            return;
        if (action === "prev" || action === "next") {
            dock.selectedIndex = DockKeyboard.moveIndex(dock.selectedIndex, dock.entryCount, action === "next" ? 1 : -1);
        } else if (action === "moveprev" || action === "movenext") {
            dock.moveSelectedPinned(action === "movenext" ? 1 : -1);
        } else if (action === "new") {
            dock.activateSelected(true);
        } else if (action === "jump") {
            dock.activateSelected(false);
        }
    }

    // Shift+h/l: move the selected PINNED app one slot in the pinned list. The
    // selection follows the app (it can land more than one visual slot away
    // when a pinned terminal yields several entries). Unpinned apps and folders
    // don't move.
    function moveSelectedPinned(delta) {
        const i = dock.selectedIndex;
        if (i < 0 || i >= dock.mergedApps.length)
            return;
        const e = dock.mergedApps[i];
        if (!e.isPinned)
            return;
        const pinIdx = DockStore.pinnedApps.findIndex(a => AppIdentity.pinKey(a) === e.identityKey);
        const dest = pinIdx + delta;
        if (pinIdx < 0 || dest < 0 || dest >= DockStore.pinnedApps.length)
            return;
        DockStore.movePinned(pinIdx, dest);
        const ni = dock.mergedApps.findIndex(x => x.identityKey === e.identityKey);
        if (ni >= 0)
            dock.selectedIndex = ni;
    }

    Item {
        id: keyCatcher
        focus: dock.keyboardMode
        // Swallow everything while the dock owns the keyboard.
        Keys.onPressed: event => {
            keyboardIdleTimer.restart();
            const shiftDown = (event.modifiers & Qt.ShiftModifier) !== 0;
            if (!shiftDown || event.key === Qt.Key_Shift)
                dock.shiftHonored = true;
            dock.handleKey(event.key, event.text, shiftDown && dock.shiftHonored);
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        previousWorkspaceEmpty = currentWorkspaceEmpty;
        rebuildMergedApps();
        syncDockVisibility();
        refreshOpenFolders();
        folderIconProc.running = true;
        rebuildFolderBar();
    }

    Component.onDestruction: {
        occupancyHideTimer.stop();
        // With dock_on_all_screens off, this Variants delegate can be
        // destroyed mid-drag (focus followed the drag to another monitor) —
        // no released/canceled arrives, so movingWhich would stay stuck set.
        if (ShellLayout.movingWhich === "dock" && ShellLayout.moveScreen === dock.screen)
            ShellLayout.cancelMove();
    }

    Connections {
        target: ShellLayout
        function onMovingWhichChanged() {
            dock.syncDockVisibility();
        }
    }

    // ── Rail ───────────────────────────────────────────────────────────────
    // One layout for every edge: a row on top/bottom, a column on left/right
    // (no rotation). It slides off its own edge when hidden. The input mask and
    // trigger items stay outside, at window level.
    Item {
        id: dockSlide
        anchors.fill: parent

        transform: Translate {
            x: dock.dockVisible ? 0 : (dock.edge === "left" ? -dock.railThickness : dock.edge === "right" ? dock.railThickness : 0)
            y: dock.dockVisible ? 0 : (dock.edge === "top" ? -dock.railThickness : dock.edge === "bottom" ? dock.railThickness : 0)
            Behavior on x {
                NumberAnimation {
                    duration: dock.dockVisible ? Perf.ms(dock.showAnimMs) : Perf.ms(dock.hideAnimMs)
                    easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: dock.dockVisible ? Perf.ms(dock.showAnimMs) : Perf.ms(dock.hideAnimMs)
                    easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
                }
            }
        }

        Panel {
            id: rail
            width: dock.vertical ? dock.railThickness : dock.railLength
            height: dock.vertical ? dock.railLength : dock.railThickness
            // Plain x/y, not anchors (see dockInteractZone): an edge change swaps the anchored axis.
            x: dock.edge === "left" ? 0 : dock.edge === "right" ? parent.width - width : (parent.width - width) / 2
            y: dock.edge === "top" ? 0 : dock.edge === "bottom" ? parent.height - height : (parent.height - height) / 2

            Grid {
                x: 1
                y: 1
                // One row on top/bottom (bound well above any real count), one column on the sides.
                columns: dock.vertical ? 1 : 256
                spacing: 0

                Repeater {
                    model: dock.mergedApps

                    DockSegment {
                        required property var modelData
                        required property int index
                        appData: modelData
                        name: dock.nameForApp(modelData)
                        ledCount: DockLayout.ledCount(modelData.windowCount, modelData.isRunning)
                        focused: index === dock.focusedIndex
                        closed: !modelData.isRunning
                        selected: dock.keyboardMode && dock.selectedIndex === index
                        vertical: dock.vertical
                        isFirst: index === 0
                        maxChars: dock.nameCap
                        charW: dock.charW
                        thickness: dock.railThickness - 2
                        onClicked: dock.activateDockEntry(modelData)
                        onRightClicked: dock.togglePinAtIndex(index, 0)
                        onMoveStarted: dock.moveBegin()
                        onMoveDragged: (area, mouse) => dock.moveDrag(area, mouse)
                        onMoveEnded: dock.moveEnd()
                        onMoveCanceled: dock.moveCancel()
                    }
                }

                Repeater {
                    model: dock.openFolderEntries

                    DockSegment {
                        required property var modelData
                        required property int index
                        readonly property int windowCount: (modelData.addresses ?? []).length
                        imageSource: dock.folderImageSource
                        name: modelData.label
                        ledCount: DockLayout.ledCount(windowCount, windowCount > 0)
                        closed: windowCount === 0
                        selected: dock.keyboardMode && dock.selectedIndex === dock.mergedApps.length + index
                        vertical: dock.vertical
                        groupStart: index === 0
                        isFirst: dock.mergedApps.length === 0 && index === 0
                        maxChars: dock.nameCap
                        charW: dock.charW
                        thickness: dock.railThickness - 2
                        onClicked: dock.focusOpenFolderAt(index)
                        onRightClicked: dock.toggleFolderPinAt(index)
                        onMoveStarted: dock.moveBegin()
                        onMoveDragged: (area, mouse) => dock.moveDrag(area, mouse)
                        onMoveEnded: dock.moveEnd()
                        onMoveCanceled: dock.moveCancel()
                    }
                }
            }
        }
    }

    Timer {
        id: occupancyHideTimer
        interval: dock.occupancyHideDelayMs
        repeat: false
        onTriggered: dock.commitOccupancyHide()
    }

    // ── Autohide trigger strip ─────────────────────────────────────────────
    MouseArea {
        id: triggerZone
        // Plain x/y, not anchors — see dockInteractZone's comment: an
        // anchor-axis swap on edge change leaves Qt's anchoring system
        // stuck with a stale cross-axis size.
        width: dock.vertical ? dock.revealStripPx : dock.dockWidth
        height: dock.vertical ? dock.dockWidth : dock.revealStripPx
        x: dock.edge === "left" ? 0 : dock.edge === "right" ? parent.width - width : (parent.width - width) / 2
        y: dock.edge === "top" ? 0 : dock.edge === "bottom" ? parent.height - height : (parent.height - height) / 2
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onContainsMouseChanged: dock.syncDockVisibility()
    }

    // ── Reveal intent timers / cursor burst ────────────────────────────────
    Timer {
        id: revealDwellTimer
        interval: dock.revealDwellMs
        repeat: false
        onTriggered: dock.onRevealDwellElapsed()
    }

    Timer {
        id: revealRearmTimer
        interval: dock.revealRearmDelayMs
        repeat: false
        onTriggered: {
            if (dock.dockVisible || dock.revealNeedsStripExit)
                return;
            if (!triggerZone.containsMouse)
                return;
            if (dock.revealRearmCount >= dock.revealRearmMax)
                return;
            dock.revealRearmCount++;
            dock.armRevealIntent();
        }
    }

    Timer {
        id: postRevealGraceTimer
        interval: dock.postRevealGraceMs
        repeat: false
        onTriggered: {
            dock.postRevealGrace = false;
            dock.syncDockVisibility();
        }
    }

    Process {
        id: revealCursorProc
        // Event-driven only: runs while the 1px strip is held during reveal intent.
        command: {
            const n = Math.max(1, dock.revealSampleCount);
            const sleepSec = Math.max(0.01, dock.revealSampleIntervalMs / 1000);
            // Avoid `bash -lc` / alias pollution (e.g. sleep → systemctl suspend).
            const script = `for i in $(seq 1 ${n}); do hyprctl cursorpos; if [ "$i" -lt ${n} ]; then /bin/sleep ${sleepSec}; fi; done`;
            return ["bash", "--noprofile", "--norc", "-c", script];
        }
        stdout: StdioCollector {
            id: revealCursorOut
            onStreamFinished: dock.onRevealCursorBurst(revealCursorOut.text)
        }
    }

    Process {
        id: revealVerifyProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            id: revealVerifyOut
            onStreamFinished: dock.onRevealVerifySample(revealVerifyOut.text)
        }
    }

    // ── Hide delay timer ───────────────────────────────────────────────────
    Timer {
        id: hideTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (dock.dockHovered || dock.postRevealGrace)
                return;
            if (dock.currentWorkspaceEmpty)
                return;
            // Still parked on the activation strip → require a leave before
            // the next reveal, so hide doesn't immediately re-arm intent.
            dock.revealNeedsStripExit = triggerZone.containsMouse;
            dock.dockVisible = false;
        }
    }

    readonly property string iconResolveScript: Qt.resolvedUrl("../../overview/services/icon_resolve.py").toString().replace("file://", "")

    Process {
        id: folderIconProc
        command: ["python3", dock.iconResolveScript, "lookup", "folder"]
        stdout: StdioCollector {
            id: folderIconCollector
            onStreamFinished: {
                const path = folderIconCollector.text.trim();
                if (path.length > 0)
                    dock.folderIconPath = path;
            }
        }
    }

    Process {
        id: openDirsProc
        command: ["python3", dock.iconResolveScript, "open-dirs", "scan"]
        stdout: StdioCollector {
            id: openDirsCollector
            onStreamFinished: {
                const text = openDirsCollector.text.trim();
                if (!text) {
                    dock.applyDynamicFolderEntries([]);
                    return;
                }
                try {
                    dock.applyDynamicFolderEntries(JSON.parse(text));
                } catch (e) {
                    console.warn("dock: failed to parse open-dirs json", e);
                    dock.applyDynamicFolderEntries([]);
                }
            }
        }
    }

    Timer {
        id: openDirsRefreshDebounce
        interval: 800
        repeat: false
        onTriggered: dock.refreshOpenFolders()
    }

    Connections {
        target: DockStore
        function onPinnedFoldersChanged() {
            dock.rebuildFolderBar();
        }
        function onFoldersLoadedChanged() {
            if (DockStore.foldersLoaded)
                dock.rebuildFolderBar();
        }
    }

    // ── IPC ────────────────────────────────────────────────────────────────
    Loader {
        active: dock.ipcEnabled
        sourceComponent: IpcHandler {
            target: "dock"
            function toggle() {
                dock.dockVisible = !dock.dockVisible;
            }
            function show() {
                dock.dockVisible = true;
            }
            function hide() {
                dock.dockVisible = false;
            }
            function press() {
                dock.keyPress();
            }
            function release() {
                dock.keyRelease();
            }
        }
    }
}
