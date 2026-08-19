pragma ComponentBehavior: Bound

// modules/dock/Dock.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../../overview/services"
import "../../overview/services/AppIdentity.js" as AppIdentity
import "DockVisibilityPolicy.js" as DockVisibilityPolicy
import "fit" as DockFit
import "../commandcenter/applibrary" as AppLibrary
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

    DockFit.DockFitMetrics {
        id: fitMetrics
        screenWidth: Number(dock.resolvedScreen?.width ?? 0)
        appCount: dock.mergedApps.length
        folderCount: dock.openFolderEntries.length
    }

    // ── Tunables ───────────────────────────────────────────────────────────
    readonly property real iconSize: fitMetrics.iconSize
    readonly property real maxScale: 1.7
    readonly property real spread: 1
    readonly property int frameMs: Perf.dockFrameMs
    readonly property int triggerHeight: 0
    readonly property real pillHeight: iconSize + paddingV * 2
    readonly property int dockBodyHeight: 110
    readonly property real iconSpacing: fitMetrics.iconSpacing
    readonly property real paddingH: fitMetrics.paddingH
    readonly property real paddingV: fitMetrics.paddingV
    readonly property int bottomGap: 1
    readonly property int activationHeight: 1 // reduce from 16 for a more macos feel, on macos you really gotta drag your cursor all the way down to bring the dock up.
    // Reveal intent: dwell on the 1px strip + a few hyprctl cursorpos checks
    // confirming the pointer stays on this monitor's bottom edge (event-driven
    // only — no background poller while the dock is idle).
    readonly property int revealDwellMs: 190
    readonly property int revealSampleCount: 4
    readonly property int revealSampleIntervalMs: 48
    readonly property int revealBottomSlopPx: 4
    // Reject U-sweeps / edge skimming: X must stay nearly planted while dwelling.
    readonly property int revealMaxHorizontalSpanPx: 30
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

    // ── Drag / interaction ─────────────────────────────────────────────────
    property int dragSourceIndex: -1
    property int dragHoverVisualIndex: -1
    property string dragSourceClass: ""
    property string dragSourceGroupKey: ""
    property bool dragStoreCommitPending: false
    property bool interactionBlock: false
    property var dragGhostAppData: null
    property real dragGhostTargetCenterX: 0
    property real dragGhostTargetCenterY: 0
    property real dragGhostVisualCenterX: 0
    property real dragGhostVisualCenterY: 0
    property real dragGhostLiftScale: 1

    readonly property var effectivePinnedApps: DockStore.loaded ? DockStore.pinnedApps : DockStore.defaultPinnedApps
    readonly property bool hasOpenFolders: openFolderEntries.length > 0
    readonly property real rightClusterStartX: iconsRow.width + iconSpacing + 1 + iconSpacing
    readonly property real appBrowserCenterX: (hasOpenFolders
        ? rightClusterStartX + openFolderEntries.length * (iconSize + iconSpacing) + iconSpacing + 1 + iconSpacing
        : iconsRow.width + iconSpacing + 1 + iconSpacing)
        + iconSize / 2

    property var dynamicFolderEntries: []
    property string dynamicFolderEntriesSignature: ""
    property var openFolderEntries: []
    property string folderBarSignature: ""
    property string folderIconPath: ""

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockVisible: false
    property real dockMouseXRaw: -9999
    property real dockMouseXSmooth: -9999
    property bool revealIntentArmed: false
    property int revealSampleHits: 0
    property int revealSampleMisses: 0
    property int revealSamplesDone: 0
    property bool revealDwellElapsed: false
    property bool revealSamplesComplete: false
    property bool revealVerifyComplete: false
    property bool revealHorizontalStable: false
    property real revealSampleMinX: 0
    property real revealSampleMaxX: 0
    property bool revealSampleXInit: false
    property bool postRevealGrace: false
    // After hide while still on the 1px strip, require leaving before re-intent
    // (breaks hide → immediate re-arm → show flicker loops).
    property bool revealNeedsStripExit: false
    property int revealRearmCount: 0
    property bool previousWorkspaceEmpty: false
    property bool occupancyHidePending: false
    readonly property bool dockBodyHovered: dockMagnifyPointer.hovered || dockInteractPointer.hovered
    readonly property bool dockHovered: triggerZone.containsMouse || dockBodyHovered
    readonly property bool animationActive: dockVisible || dockHovered || interactionBlock
        || dragSourceIndex >= 0 || revealIntentArmed || postRevealGrace
    readonly property bool dockIdle: !dockVisible && !dockHovered && !interactionBlock && dragSourceIndex < 0
        && !revealIntentArmed && !postRevealGrace
    readonly property real dockMouseXEffective: interactionBlock ? -9999 : dockMouseXSmooth
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
    onInteractionBlockChanged: {
        if (interactionBlock) {
            if (occupancyHideTimer.running)
                occupancyHideTimer.stop();
        } else if (occupancyHidePending && !currentWorkspaceEmpty && !anyFullscreen) {
            occupancyHideTimer.restart();
        }
        syncDockVisibility();
    }
    onAnyFullscreenChanged: {
        if (anyFullscreen) {
            occupancyHideTimer.stop();
            occupancyHidePending = false;
            dock.cancelRevealIntent();
            dock.postRevealGrace = false;
            postRevealGraceTimer.stop();
            hideTimer.stop();
            dockMouseXRaw = -9999;
            dockVisible = false;
        } else {
            syncDockVisibility();
        }
    }

    onDockHoveredChanged: syncDockVisibility()

    onDockVisibleChanged: {
        if (!dockVisible) {
            dock.postRevealGrace = false;
            postRevealGraceTimer.stop();
            dock.dismissMagnify();
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
        if (!g)
            return false;
        const bottom = g.y + g.height - 1;
        if (cy < bottom - dock.revealBottomSlopPx)
            return false;
        const dockW = dock.dockWidth;
        const left = g.x + (g.width - dockW) / 2;
        return cx >= left - 4 && cx <= left + dockW + 4;
    }

    function resetRevealSamples() {
        dock.revealSampleHits = 0;
        dock.revealSampleMisses = 0;
        dock.revealSamplesDone = 0;
        dock.revealDwellElapsed = false;
        dock.revealSamplesComplete = false;
        dock.revealVerifyComplete = false;
        dock.revealHorizontalStable = false;
        dock.revealSampleMinX = 0;
        dock.revealSampleMaxX = 0;
        dock.revealSampleXInit = false;
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
        if (!dock.revealSampleXInit) {
            dock.revealSampleMinX = cx;
            dock.revealSampleMaxX = cx;
            dock.revealSampleXInit = true;
        } else {
            if (cx < dock.revealSampleMinX)
                dock.revealSampleMinX = cx;
            if (cx > dock.revealSampleMaxX)
                dock.revealSampleMaxX = cx;
        }
        const span = dock.revealSampleMaxX - dock.revealSampleMinX;
        dock.revealHorizontalStable = span <= dock.revealMaxHorizontalSpanPx;
        return dock.revealHorizontalStable;
    }

    function armRevealIntent() {
        if (dock.dockVisible || dock.revealIntentArmed || dock.anyFullscreen)
            return;
        if (dock.currentWorkspaceEmpty || dock.interactionBlock)
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
            dock.revealHorizontalStable = false;
            dock.tryCommitRevealIntent();
            return;
        }
        const chunks = raw.split(/\n+/).map(s => s.trim()).filter(s => s.length > 0);
        let prevX = NaN;
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
            if (Number.isFinite(prevX) && Math.abs(cx - prevX) > dock.revealMaxHorizontalSpanPx) {
                dock.revealSampleMisses++;
                dock.revealSamplesDone++;
                dock.revealHorizontalStable = false;
                break;
            }
            if (!dock.noteRevealSamplePoint(cx, cy))
                break;
            prevX = cx;
        }
        dock.revealSamplesComplete = true;
        if (dock.revealSampleMisses > 0 || !dock.revealHorizontalStable || !triggerZone.containsMouse) {
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
        if (!triggerZone.containsMouse || !dock.revealHorizontalStable) {
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
            && dock.revealHorizontalStable;
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
        Qt.callLater(() => {
            if (dockMagnifyPointer.hovered)
                dockMagnifyPointer.updateMouseX();
        });
    }

    function syncDockVisibility() {
        if (interactionBlock) {
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
            dockMouseXRaw = -9999;
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
            if (!dockMagnifyPointer.hovered && !dockBodyHover.hovered)
                dismissMagnify();
            return;
        }

        // The first mapped window owns this short edge transition. Inherited
        // hover from the launch click must not replace it with the normal hide delay.
        if (occupancyHidePending) {
            if (!occupancyHideTimer.running && !interactionBlock)
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
                Qt.callLater(() => {
                    if (dockMagnifyPointer.hovered)
                        dockMagnifyPointer.updateMouseX();
                });
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
            Qt.callLater(() => {
                if (dockMagnifyPointer.hovered)
                    dockMagnifyPointer.updateMouseX();
            });
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
            dock.interactionBlock
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
                dock.currentWorkspaceEmpty, dock.interactionBlock, dock.anyFullscreen)) {
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

    function iconSlotCenterX(index) {
        return index * (iconSize + iconSpacing) + iconSize / 2;
    }

    function openFolderSlotCenterX(index) {
        return rightClusterStartX + index * (iconSize + iconSpacing) + iconSize / 2;
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

    function dismissMagnify() {
        dock.dockMouseXRaw = -9999;
        dock.dockMouseXSmooth = -9999;
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
        dock.dismissMagnify();
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
            dock.syncDragIndicesAfterRebuild();
            return;
        }

        dock.mergedAppsSignature = sig;
        dock.mergedApps = result;
        dock.syncDragIndicesAfterRebuild();
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

    function syncDragIndicesAfterRebuild() {
        if (dock.dragSourceIndex < 0)
            return;

        const srcIdx = dock.visualIndexForGroupKey(dock.dragSourceGroupKey, dock.dragSourceClass);
        if (srcIdx < 0) {
            dock.abortIconDrag();
            return;
        }

        dock.dragSourceIndex = srcIdx;
        dock.dragGhostAppData = dock.mergedApps[srcIdx] ?? dock.dragGhostAppData;

        if (dock.dragHoverVisualIndex < 0 || dock.dragHoverVisualIndex >= dock.mergedApps.length)
            dock.dragHoverVisualIndex = srcIdx;
    }

    function iconSlotWidth() {
        return dock.iconSize + dock.iconSpacing;
    }

    function visualIndexAtRowX(rowLocalX) {
        const slot = dock.iconSlotWidth();
        const n = dock.mergedApps.length;
        if (n <= 0)
            return 0;
        let i = Math.floor((rowLocalX + slot * 0.5) / slot);
        if (i < 0)
            i = 0;
        if (i >= n)
            i = n - 1;
        return i;
    }

    function dragShiftTargetForIndex(visualIndex) {
        if (dock.dragSourceIndex < 0)
            return 0;

        const src = dock.dragSourceIndex;
        const dst = dock.dragHoverVisualIndex >= 0 ? dock.dragHoverVisualIndex : src;
        if (visualIndex === src || dst === src)
            return 0;

        // Part icons by the natural inter-icon gap — not a full slot (avoids overlap).
        const gap = dock.iconSpacing;
        if (dst > src) {
            if (visualIndex > src && visualIndex <= dst)
                return -gap;
        } else if (dst < src) {
            if (visualIndex >= dst && visualIndex < src)
                return gap;
        }
        return 0;
    }

    function clampDragGhostCenterX(cx) {
        const half = dock.iconSize * dock.maxScale * 0.5 + 4;
        const w = dockBody.width;
        if (w <= half * 2)
            return w * 0.5;
        return Math.max(half, Math.min(w - half, cx));
    }

    function clampDragGhostCenterY(cy) {
        const half = (dock.iconSize * dock.maxScale + 6) * 0.5;
        const h = dockBody.height;
        if (h <= half * 2)
            return h * 0.5;
        return Math.max(half + 2, Math.min(h - half - 2, cy));
    }

    function setDragGhostTargetFromBodyPoint(bodyX, bodyY) {
        dock.dragGhostTargetCenterX = dock.clampDragGhostCenterX(bodyX);
        dock.dragGhostTargetCenterY = dock.clampDragGhostCenterY(bodyY);
    }

    function beginIconDrag(visualIndex, ghostCenterBodyX, ghostCenterBodyY) {
        if (dock.dragStoreCommitPending)
            return;

        const entry = dock.mergedApps[visualIndex] ?? null;
        dock.dragGhostAppData = entry;
        dock.dragSourceClass = entry?.class ?? "";
        dock.dragSourceGroupKey = `${entry?.groupKey ?? ""}`.trim();
        const cx = dock.clampDragGhostCenterX(ghostCenterBodyX);
        const cy = dock.clampDragGhostCenterY(ghostCenterBodyY);
        dock.dragGhostTargetCenterX = cx;
        dock.dragGhostTargetCenterY = cy;
        dock.dragGhostVisualCenterX = cx;
        dock.dragGhostVisualCenterY = cy;
        dock.dragGhostLiftScale = 1.12;
        dock.dragSourceIndex = visualIndex;
        dock.dragHoverVisualIndex = visualIndex;
        dock.interactionBlock = true;
        dock.syncDockVisibility();
    }

    function updateDragHoverFromRowX(rowLocalX) {
        const slot = dock.iconSlotWidth();
        const n = dock.mergedApps.length;
        if (n <= 0) {
            dock.dragHoverVisualIndex = 0;
            return;
        }

        let idx = dock.dragHoverVisualIndex;
        if (idx < 0 || idx >= n)
            idx = dock.visualIndexAtRowX(rowLocalX);

        const margin = slot * 0.18;
        const leftBound = idx * slot - margin;
        const rightBound = idx * slot + slot - margin;

        if (rowLocalX > rightBound && idx < n - 1)
            idx++;
        else if (rowLocalX < leftBound && idx > 0)
            idx--;

        dock.dragHoverVisualIndex = idx;
    }

    function endDragSession() {
        dock.dragSourceIndex = -1;
        dock.dragHoverVisualIndex = -1;
        dock.dragSourceClass = "";
        dock.dragSourceGroupKey = "";
        dock.interactionBlock = false;
        dock.clearDragGhost();
        dock.syncDockVisibility();
    }

    function buildDragCommitSnapshot() {
        if (dock.dragSourceIndex < 0)
            return null;

        const src = dock.dragSourceIndex;
        const dst = dock.dragHoverVisualIndex >= 0 ? dock.dragHoverVisualIndex : src;
        const list = dock.mergedApps;
        if (src >= list.length)
            return null;

        const srcEntry = list[src];
        return {
            srcClass: srcEntry.class,
            srcIdentity: srcEntry.identity,
            srcIdentityKey: srcEntry.identityKey,
            srcPinned: !!srcEntry.isPinned,
            dst: Math.min(dst, Math.max(0, list.length - 1)),
            exec: dock.execForPinnedApp(srcEntry),
            icon: dock.iconForApp(srcEntry),
            pinnedCountAtDrop: DockStore.pinnedApps.length
        };
    }

    function applyDragCommit(snapshot) {
        if (!snapshot)
            return;

        const dstClamped = snapshot.dst;
        const pinnedCount = snapshot.pinnedCountAtDrop;

        if (snapshot.srcPinned) {
            const srcIdx = DockStore.pinnedApps.findIndex(
                a => AppIdentity.pinKey(a) === snapshot.srcIdentityKey);
            if (srcIdx < 0)
                return;
            if (dstClamped < pinnedCount) {
                if (srcIdx !== dstClamped)
                    DockStore.movePinned(srcIdx, dstClamped);
            } else {
                if (pinnedCount > 0 && srcIdx !== pinnedCount - 1)
                    DockStore.movePinned(srcIdx, pinnedCount - 1);
            }
        } else {
            const insertAt = Math.min(dstClamped, pinnedCount);
            const pin = Object.assign({}, snapshot.srcIdentity || {}, {
                class: snapshot.srcClass,
                exec: snapshot.exec,
                icon: snapshot.icon
            });
            DockStore.pinEntry(pin, insertAt);
        }
    }

    function finalizeIconDrag() {
        if (dock.dragSourceIndex < 0)
            return;

        const snapshot = dock.buildDragCommitSnapshot();
        dock.endDragSession();
        if (!snapshot)
            return;

        dock.dragStoreCommitPending = true;
        Qt.callLater(() => {
            dock.applyDragCommit(snapshot);
            dock.dragStoreCommitPending = false;
        });
    }

    function abortIconDragFromIcon() {
        dock.endDragSession();
    }

    function updateDragFromBodyPoint(bodyX, bodyY) {
        dock.setDragGhostTargetFromBodyPoint(bodyX, bodyY);
        const lp = dockBody.mapToItem(iconsRow, bodyX, bodyY);
        dock.updateDragHoverFromRowX(lp.x);
    }

    function clearDragGhost() {
        dock.dragGhostAppData = null;
        dock.dragGhostLiftScale = 1;
    }

    function abortIconDrag() {
        dock.endDragSession();
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
        dock.dismissMagnify();
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

    function openAppLibrary() {
        dock.dismissMagnify();
        AppLibrary.AppLibraryService.open();
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
    readonly property int dockFullHeight: dockBodyHeight + bottomGap + triggerHeight
    // Extra window height above the pill for magnify + instance labels
    readonly property int visualOverflowPx: Math.ceil(iconSize * (maxScale - 1)) + 44
    // Pill + magnify lift only excludes the instance-label band above icons.
    readonly property int magnifyHoverHeight: pillHeight + Math.ceil(iconSize * (maxScale - 1))
    // Nudge the hit band a few px below the peak magnify tip so the label
    // band / near-miss cursor above icons doesn't keep the dock "hot".
    readonly property int interactTrimPx: 10
    readonly property int magnifyInteractHeight: Math.max(pillHeight, magnifyHoverHeight - interactTrimPx)
    // Bottom activation strip + dock body hover up to (trimmed) magnify top.
    readonly property int interactBandHeight: activationHeight + bottomGap + magnifyInteractHeight
    readonly property real dockWidth: fitMetrics.dockWidth
    readonly property int visibleDockHeight: dockVisible
        ? dockFullHeight + activationHeight + visualOverflowPx
        : activationHeight

    // ── Window ────────────────────────────────────────────────────────────
    anchors {
        bottom: true
    }
    implicitWidth: dockWidth
    implicitHeight: visibleDockHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    // Window stays tall for tooltip paint; only this band accepts input.
    // Label overflow above magnified icons stays click-through.
    mask: Region {
        item: dockInteractZone
    }

    // Hover / input footprint ends at the (trimmed) magnify tip — not the
    // visual-overflow band used for hover labels above icons.
    Item {
        id: dockInteractZone
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        width: dock.dockWidth
        height: dock.interactBandHeight

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

    function launchApp(app) {
        const identity = Object.assign({}, app?.identity || HyprlandData.primaryIdentityForApp(app), {
            exec: app?.identity?.exec || dock.execForPinnedApp(app),
            icon: app?.identity?.icon || dock.iconForApp(app)
        });
        HyprDispatch.activateIdentity(identity, { app: app });
    }

    Component.onCompleted: {
        previousWorkspaceEmpty = currentWorkspaceEmpty;
        rebuildMergedApps();
        syncDockVisibility();
        refreshOpenFolders();
        folderIconProc.running = true;
        rebuildFolderBar();
    }

    Component.onDestruction: occupancyHideTimer.stop()

    // Overview's full-screen Overlay can steal the mouse release during a dock drag.
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (dock.dragSourceIndex < 0 && !dock.interactionBlock)
                return;
            if (GlobalStates.overviewOpen)
                dock.abortIconDrag();
            else if (dock.interactionBlock)
                dock.abortIconDrag();
        }
    }

    // ── Dock body (fixed to screen bottom; overflow grows above, not under) ─
    Item {
        id: dockChrome
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        anchors.bottomMargin: dock.activationHeight
        width: parent.width
        height: dock.dockFullHeight + dock.visualOverflowPx
        clip: false

        Item {
            id: dockFoot
            anchors.bottom: parent.bottom
            width: parent.width
            height: dock.dockFullHeight
            clip: false

        Item {
            id: dockBody
            width: dock.dockWidth
            height: dock.dockBodyHeight
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: dock.bottomGap
            clip: false

        transform: Translate {
            id: dockBodySlide
            y: dock.dockVisible ? 0 : dock.dockFullHeight
            Behavior on y {
                NumberAnimation {
                    duration: dock.dockVisible ? Perf.ms(dock.showAnimMs) : Perf.ms(dock.hideAnimMs)
                    easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
                }
            }
        }

        // Pill background — Resin material, independent of the bar's own
        // solid/transparent toggle. See Theme.qml's resin() comment.
        Rectangle {
            id: dockPill
            width: parent.width
            height: dock.pillHeight
            anchors.bottom: parent.bottom
            radius: dock.paddingV + dock.iconSize * 0.22
            color: Theme.resin(Theme.resinFillAlpha)
            border.width: 1
            border.color: Theme.resinBorder
            clip: true

            // Gloss — light catching the material's upper edge.
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: parent.height * 0.45
                radius: dockPill.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.resinGloss }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Inner glow — a hint of structure beneath the material.
            // Actually blurred, not just low-opacity, so it reads as soft
            // light rather than a defined shape.
            Rectangle {
                width: parent.height * 1.4
                height: width
                radius: width / 2
                x: parent.width * 0.06
                y: (parent.height - height) / 2
                color: Theme.resinGlow
                opacity: 0.4
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 80 }
            }
        }

        // Icon row (search button pinned left + app icons)
        Row {
            anchors {
                bottom: parent.bottom
                bottomMargin: dock.paddingV
                horizontalCenter: parent.horizontalCenter
            }
            spacing: dock.iconSpacing

            DockDockButton {
                iconSize: dock.iconSize
                maxScale: dock.maxScale
                spread: dock.spread
                frameMs: dock.frameMs
                dockMouseX: dock.dockMouseXEffective
                btnCenterX: -(dock.iconSpacing + dock.iconSize / 2)
                animationActive: dock.animationActive
                glyph: "󰍉"
                hoverLabel: "Search"
                onClicked: {
                    dock.dismissMagnify();
                    SpotlightService.toggle();
                }
            }

            Row {
                id: iconsRow
                spacing: dock.iconSpacing

                Repeater {
                    model: dock.mergedApps
                    DockIcon {
                        id: dockIconRoot
                        required property var modelData
                        required property int index
                        dockBodyRef: dockBody
                        iconsRowRef: iconsRow
                        visualIndex: index
                        appData: modelData
                        iconSize: dock.iconSize
                        maxScale: dock.maxScale
                        spread: dock.spread
                        frameMs: dock.frameMs
                        dockMouseX: dock.dockMouseXEffective
                        iconCenterX: dock.iconSlotCenterX(index)
                        animationActive: dock.animationActive
                        dockIdle: dock.dockIdle
                        dockDragActive: dock.dragSourceIndex >= 0
                        isDragSource: dock.dragSourceIndex >= 0
                            && (`${modelData.groupKey ?? ""}`.trim().length
                                ? `${modelData.groupKey ?? ""}`.trim().toLowerCase()
                                    === dock.dragSourceGroupKey.toLowerCase()
                                : dock.classKey(modelData.class) === dock.classKey(dock.dragSourceClass))
                        dragShiftTargetX: dock.dragShiftTargetForIndex(index)
                        onClicked: dock.activateDockEntry(modelData, dockIconRoot.instanceIndex)
                        onContextMenuRequested: instanceIndex => dock.togglePinAtIndex(index, instanceIndex)
                        onDragReorderStarted: (vi, bx, by) => dock.beginIconDrag(vi, bx, by)
                        onDragReorderMoved: (bx, by) => dock.updateDragFromBodyPoint(bx, by)
                        onDragReorderEnded: dock.finalizeIconDrag()
                        onDragReorderCanceled: dock.abortIconDragFromIcon()
                    }
                }
            }

            DockDivider { iconSize: dock.iconSize; maxScale: dock.maxScale }

            Row {
                id: openFoldersRow
                spacing: dock.iconSpacing
                visible: dock.hasOpenFolders

                Repeater {
                    model: dock.openFolderEntries
                    DockDockButton {
                        required property var modelData
                        required property int index
                        iconSize: dock.iconSize
                        maxScale: dock.maxScale
                        spread: dock.spread
                        frameMs: dock.frameMs
                        dockMouseX: dock.dockMouseXEffective
                        btnCenterX: dock.openFolderSlotCenterX(index)
                        animationActive: dock.animationActive
                        imageSource: dock.folderImageSource
                        hoverLabel: dock.pathLabel(modelData.path)
                        onClicked: dock.focusOpenFolderAt(index)
                        onRightClicked: dock.toggleFolderPinAt(index)
                    }
                }
            }

            DockDivider {
                iconSize: dock.iconSize
                maxScale: dock.maxScale
                visible: dock.hasOpenFolders
            }

            DockDockButton {
                iconSize: dock.iconSize
                maxScale: dock.maxScale
                spread: dock.spread
                frameMs: dock.frameMs
                dockMouseX: dock.dockMouseXEffective
                btnCenterX: dock.appBrowserCenterX
                animationActive: dock.animationActive
                glyph: "󰀻"
                hoverLabel: "Apps"
                onClicked: dock.openAppLibrary()
            }
        }

        Item {
            id: dragGhostLayer
            z: 5000
            visible: dock.dragSourceIndex >= 0 && dock.dragGhostAppData !== null
            width: dock.iconSize
            height: dock.iconSize * dock.maxScale + 6
            x: dock.dragGhostVisualCenterX - width / 2
            y: dock.dragGhostVisualCenterY - height / 2
            scale: dock.dragGhostLiftScale
            transformOrigin: Item.Bottom

            Behavior on scale {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            Image {
                id: ghostImg
                property int sourceIndex: 0
                property var ghostSources: dock.dragGhostAppData
                    ? HyprlandData.iconSourcesForAppData(dock.dragGhostAppData)
                    : [HyprlandData.genericIconSource]

                anchors {
                    bottom: parent.bottom
                    bottomMargin: 6
                    horizontalCenter: parent.horizontalCenter
                }
                width: dock.iconSize
                height: dock.iconSize
                onGhostSourcesChanged: sourceIndex = 0
                source: ghostSources[sourceIndex] ?? HyprlandData.genericIconSource
                sourceSize: Qt.size(dock.iconSize * 2, dock.iconSize * 2)
                smooth: true
                scale: dock.maxScale * 0.92
                transformOrigin: Item.Bottom
                onStatusChanged: {
                    if (status === Image.Error && ghostImg.sourceIndex < ghostSources.length - 1)
                        Qt.callLater(() => {
                            ghostImg.sourceIndex++;
                        });
                }
            }

            Rectangle {
                visible: dock.dragGhostAppData && dock.dragGhostAppData.isRunning
                width: 4
                height: 4
                radius: 2
                color: Theme.primary
                anchors {
                    bottom: parent.bottom
                    horizontalCenter: parent.horizontalCenter
                }
            }
        }

        Timer {
            id: dragGhostLerpTimer
            interval: dock.frameMs
            running: dock.dragSourceIndex >= 0
            repeat: true
            onTriggered: {
                const dt = dock.frameMs / 1000.0;
                const k = 1 - Math.exp(-24 * dt);
                dock.dragGhostVisualCenterX += (dock.dragGhostTargetCenterX - dock.dragGhostVisualCenterX) * k;
                dock.dragGhostVisualCenterY += (dock.dragGhostTargetCenterY - dock.dragGhostVisualCenterY) * k;
            }
        }

        // Covers magnified icon pixels only (trimmed), not the label overflow band above.
        Item {
            id: dockMagnifyHover
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
            }
            width: parent.width
            height: dock.magnifyInteractHeight

            HoverHandler {
                id: dockMagnifyPointer

                function updateMouseX() {
                    dock.dockMouseXRaw = iconsRow.mapFromGlobal(
                        dockMagnifyHover.mapToGlobal(point.position.x, point.position.y).x,
                        0
                    ).x;
                }

                onHoveredChanged: {
                    dock.syncDockVisibility();
                    if (hovered)
                        updateMouseX();
                    else if (dock.currentWorkspaceEmpty && !dockBodyHover.hovered)
                        dock.dismissMagnify();
                }
                onPointChanged: {
                    if (hovered)
                        updateMouseX();
                }
            }
        }

        // HoverHandler tracks pointer inside dockBody without competing with
        // child MouseAreas for hover events — fixes hide timer firing on icon hover.
        HoverHandler {
            id: dockBodyHover
            function updateMouseX() {
                dock.dockMouseXRaw = iconsRow.mapFromGlobal(
                    dockBody.mapToGlobal(point.position.x, point.position.y).x,
                    0
                ).x;
            }
            onHoveredChanged: {
                dock.syncDockVisibility();
                if (!hovered && dock.currentWorkspaceEmpty && !dockMagnifyPointer.hovered)
                    dock.dismissMagnify();
            }
            onPointChanged: {
                if (hovered)
                    updateMouseX();
            }
        }

        }

        }

    }

    Timer {
        id: dockMouseSmoothTimer
        interval: dock.frameMs
        running: dock.animationActive
        repeat: true
        onTriggered: {
            const raw = dock.dockMouseXRaw;
            const smooth = dock.dockMouseXSmooth;
            const rate = dock.dockVisible ? 0.35 : 0.28;
            if (raw < -1000) {
                if (smooth < -1000)
                    return;
                const next = smooth + (-9999 - smooth) * rate;
                dock.dockMouseXSmooth = Math.abs(next + 9999) < 2 ? -9999 : next;
                return;
            }
            dock.dockMouseXSmooth = smooth < -1000 ? raw : smooth + (raw - smooth) * rate;
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
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        width: dock.dockWidth
        height: dock.activationHeight
        hoverEnabled: true
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
        }
    }
}
