pragma ComponentBehavior: Bound

// modules/dock/Dock.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../../overview/services"
import "../commandcenter/applibrary" as AppLibrary

PanelWindow {
    id: dock

    property var assignedScreen: null
    screen: assignedScreen
    property bool ipcEnabled: true

    property string systemIconTheme: "Fluent-green"
    Process {
        command: ["bash", "-c", "theme=$(grep -m1 '^gtk-icon-theme-name=' \"$HOME/.config/gtk-3.0/settings.ini\" 2>/dev/null | cut -d= -f2- | tr -d '\\r'); if [[ -z \"$theme\" ]] && command -v gtk-query-settings >/dev/null 2>&1; then theme=$(gtk-query-settings 2>/dev/null | sed -n 's/.*gtk-icon-theme-name: \"\\(.*\\)\"/\\1/p' | head -n1); fi; if [[ -z \"$theme\" ]] && command -v gsettings >/dev/null 2>&1; then theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d \"'\"); fi; printf '%s\\n' \"${theme:-Fluent-green}\""]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim();
                if (t.length > 0)
                    dock.systemIconTheme = t;
            }
        }
    }

    // ── Tunables ───────────────────────────────────────────────────────────
    readonly property int iconSize: 48
    readonly property real maxScale: 1.7
    readonly property real spread: 1
    readonly property int frameMs: Perf.dockFrameMs
    readonly property int triggerHeight: 0
    readonly property int pillHeight: iconSize + paddingV * 2
    readonly property int dockBodyHeight: 110
    readonly property int iconSpacing: 25
    readonly property int paddingH: 14
    readonly property int paddingV: 12
    readonly property int bottomGap: 4
    readonly property int activationHeight: 1 // reduce from 16 for a more macos feel, on macos you really gotta drag your cursor all the way down to bring the dock up. 

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

    // ── State ──────────────────────────────────────────────────────────────
    property bool dockVisible: false
    property real dockMouseXRaw: -9999
    property real dockMouseXSmooth: -9999
    property int exposeOverflowPx: 0
    readonly property bool dockHovered: triggerZone.containsMouse
        || dockMagnifyPointer.hovered
        || dockPanelPointer.hovered
    readonly property bool animationActive: dockVisible || dockHovered || interactionBlock
        || dragSourceIndex >= 0
    readonly property bool dockIdle: !dockVisible && !dockHovered && !interactionBlock && dragSourceIndex < 0
    readonly property real dockMouseXEffective: interactionBlock ? -9999 : dockMouseXSmooth
    readonly property bool anyFullscreen: {
        return HyprlandData.windowList.some(w => (w.fullscreen ?? 0) > 0);
    }
    onAnyFullscreenChanged: {
        if (anyFullscreen) {
            hideTimer.stop();
            dockMouseXRaw = -9999;
            dockVisible = false;
        } else {
            syncDockVisibility();
        }
    }

    onDockHoveredChanged: syncDockVisibility()

    onDockVisibleChanged: {
        if (!dockVisible)
            dock.dismissMagnify();
    }

    function syncDockVisibility() {
        if (interactionBlock) {
            hideTimer.stop();
            dockVisible = true;
            return;
        }
        if (anyFullscreen) {
            hideTimer.stop();
            dockMouseXRaw = -9999;
            dockVisible = false;
            return;
        }

        if (dockHovered) {
            hideTimer.stop();
            dockVisible = true;
            Qt.callLater(() => {
                if (dockMagnifyPointer.hovered)
                    dockMagnifyPointer.updateMouseX();
            });
            return;
        }

        // Keep last mouse X while the dock is still visible — clearing it here
        // caused a magnify feedback loop when scaled icons paint above the hover region.
        if (dockVisible)
            hideTimer.restart();
    }

    function iconSlotCenterX(index) {
        return index * (iconSize + iconSpacing) + iconSize / 2;
    }

    function stripDesktopExecField(s) {
        const t = `${s ?? ""}`.trim();
        if (!t)
            return "";
        return t.replace(/%[A-Za-z]/g, "").trim();
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
    property bool windowPickerOpen: false
    property string windowPickerGroupKey: ""
    property Item windowPickerAnchor: null

    onRunningWindowsChanged: rebuildMergedApps()
    onEffectivePinnedAppsChanged: rebuildMergedApps()

    function mergedAppsSignatureFor(list) {
        let sig = "";
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (i > 0)
                sig += "|";
            const key = `${e.groupKey || dock.classKey(e.class)}`.trim();
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
        return {
            class: win.class || win.initialClass || app.class,
            exec: app.exec,
            icon: dock.iconForApp(app),
            isRunning: true,
            window: win,
            groupKey: groupKey,
            windowCount: windowCount,
            groupLabel: HyprlandData.groupDisplayName(groupKey),
            isPinned: isPinned
        };
    }

    function pinnedEntriesForApp(app, windows) {
        if (!HyprlandData.isTerminalClass(app.class)) {
            const win = dock.findWindowForClass(app.class, windows);
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
                isPinned: true
            }];
        }

        const byGroup = {};
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            if (dock.windowMatchScore(w, app.class) <= 0)
                continue;
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

    function activateDockEntry(appData) {
        if (dock.windowPickerOpen)
            dock.closeWindowPicker();

        dock.dismissMagnify();
        if (!appData?.isRunning) {
            dock.launchApp(appData);
            return;
        }

        const groupKey = `${appData.groupKey ?? ""}`.trim();
        if (groupKey.length)
            HyprDispatch.focusGroupMru(groupKey);
        else if (appData.window)
            HyprDispatch.focusWindow(appData.window);
        else
            HyprDispatch.focusWindowByClass(appData.class);
    }

    function openWindowPicker(groupKey, anchorItem) {
        const gk = `${groupKey ?? ""}`.trim();
        if (!gk.length || HyprlandData.windowsForGroupKey(gk).length <= 1)
            return;

        dock.cancelExposeAutoClose();
        dock.windowPickerAnchor = anchorItem;
        dock.windowPickerGroupKey = gk;
        dock.windowPickerOpen = true;
        dock.positionWindowPicker();
        Qt.callLater(() => {
            if (dock.windowPickerOpen)
                dock.positionWindowPicker();
        });
        dock.syncDockVisibility();
    }

    function closeWindowPicker() {
        dock.cancelExposeAutoClose();
        dock.windowPickerOpen = false;
        dock.windowPickerGroupKey = "";
        dock.windowPickerAnchor = null;
        dock.exposeOverflowPx = 0;
        dock.syncDockVisibility();
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
            if (pinnedApps.some(app =>
                !HyprlandData.isTerminalClass(app.class)
                && dock.windowMatchScore(entry.window, app.class) > 0))
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
            }
            dock.syncDragIndicesAfterRebuild();
            return;
        }

        if (dock.windowPickerOpen)
            dock.closeWindowPicker();

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
                a => dock.classKey(a.class) === dock.classKey(snapshot.srcClass));
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
            DockStore.pinEntry({
                class: snapshot.srcClass,
                exec: snapshot.exec,
                icon: snapshot.icon
            }, insertAt);
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

    function togglePinAtIndex(visualIndex) {
        const list = dock.mergedApps;
        if (visualIndex < 0 || visualIndex >= list.length)
            return;
        const e = list[visualIndex];
        if (e.isPinned)
            DockStore.unpinClass(e.class);
        else
            DockStore.pinEntry({
                class: e.class,
                exec: dock.execForPinnedApp(e),
                icon: dock.iconForApp(e)
            }, DockStore.pinnedApps.length);
    }

    // ── Dimensions ────────────────────────────────────────────────────────
    readonly property int dockFullHeight: dockBodyHeight + bottomGap + triggerHeight
    readonly property int dockWidth: (mergedApps.length + 2) * (iconSize + iconSpacing) - iconSpacing + paddingH * 2
    readonly property int visibleDockHeight: dockVisible ? dockFullHeight + exposeOverflowPx : activationHeight

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

    HoverHandler {
        id: dockPanelPointer

        onHoveredChanged: {
            dock.syncDockVisibility();
            if (dock.windowPickerOpen && !hovered)
                dock.scheduleExposeAutoClose();
        }
        onPointChanged: {
            if (dock.windowPickerOpen)
                dock.syncExposeDismissState();
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
        const cls = HyprlandData.normalizeDockClass(app?.class ?? "");
        if (!AppLibrary.AppLibraryService.launchByClass(cls, dock.execForPinnedApp(app)))
            console.warn("dock: no launch command for", app?.class ?? "<unknown>");
    }

    Component.onCompleted: rebuildMergedApps()

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

    // ── Dock body ──────────────────────────────────────────────────────────
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
                    duration: Perf.msHalf(220)
                    easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
                }
            }
        }

        // Glass pill background
        Rectangle {
            width: parent.width
            height: dock.pillHeight
            anchors.bottom: parent.bottom
            radius: dock.paddingV + dock.iconSize * 0.22
            color: Theme.glassShell
        }

        // Icon row (search button pinned left + app icons)
        Row {
            anchors {
                bottom: parent.bottom
                bottomMargin: dock.paddingV
                horizontalCenter: parent.horizontalCenter
            }
            spacing: dock.iconSpacing

            // Search button — always leftmost, never displaced by app list
            Item {
                id: searchBtn
                width: dock.iconSize
                height: dock.iconSize * dock.maxScale + 6

                readonly property real btnCenterX: -(dock.iconSpacing + dock.iconSize / 2)
                readonly property real targetScale: {
                    if (dock.dockMouseXEffective < -1000)
                        return 1.0;
                    const d = Math.abs(dock.dockMouseXEffective - btnCenterX);
                    const sigma = dock.iconSize * dock.spread;
                    return 1.0 + (dock.maxScale - 1.0) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
                }
                property real currentScale: 1.0
                Timer {
                    interval: dock.frameMs
                    running: dock.animationActive
                    repeat: true
                    onTriggered: {
                        const delta = searchBtn.targetScale - searchBtn.currentScale;
                        if (Math.abs(delta) < 0.005) {
                            searchBtn.currentScale = searchBtn.targetScale;
                            return;
                        }
                        const lerp = 1.0 - Math.exp(-12.0 * dock.frameMs / 1000.0);
                        searchBtn.currentScale += delta * lerp;
                    }
                }

                Text {
                    width: dock.iconSize
                    height: dock.iconSize
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 6
                        horizontalCenter: parent.horizontalCenter
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "󰍉"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Math.round(dock.iconSize * 0.72)
                    color: Theme.on_surface
                    scale: searchBtn.currentScale
                    transformOrigin: Item.Bottom
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        dock.dismissMagnify();
                        dock.launch(["quickshell", "ipc", "call", "spotlight", "toggle"]);
                    }
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
                        onClicked: dock.activateDockEntry(modelData)
                        onExposeRequested: {
                            if (`${modelData.groupKey ?? ""}`.length)
                                dock.openWindowPicker(modelData.groupKey, dockIconRoot);
                        }
                        onContextMenuRequested: {
                            if (modelData.isRunning
                                && (modelData.windowCount ?? 1) > 1
                                && `${modelData.groupKey ?? ""}`.length) {
                                dock.openWindowPicker(modelData.groupKey, dockIconRoot);
                            } else {
                                dock.togglePinAtIndex(index);
                            }
                        }
                        onDragReorderStarted: (vi, bx, by) => dock.beginIconDrag(vi, bx, by)
                        onDragReorderMoved: (bx, by) => dock.updateDragFromBodyPoint(bx, by)
                        onDragReorderEnded: dock.finalizeIconDrag()
                        onDragReorderCanceled: dock.abortIconDragFromIcon()
                    }
                }
            }

            // Apps launcher button — always rightmost
            Item {
                id: appsBtn
                width: dock.iconSize
                height: dock.iconSize * dock.maxScale + 6

                readonly property real btnCenterX: iconsRow.width + dock.iconSpacing + dock.iconSize / 2
                readonly property real targetScale: {
                    if (dock.dockMouseXEffective < -1000)
                        return 1.0;
                    const d = Math.abs(dock.dockMouseXEffective - btnCenterX);
                    const sigma = dock.iconSize * dock.spread;
                    return 1.0 + (dock.maxScale - 1.0) * Math.exp(-0.5 * (d / sigma) * (d / sigma));
                }
                property real currentScale: 1.0
                Timer {
                    interval: dock.frameMs
                    running: dock.animationActive
                    repeat: true
                    onTriggered: {
                        const delta = appsBtn.targetScale - appsBtn.currentScale;
                        if (Math.abs(delta) < 0.005) {
                            appsBtn.currentScale = appsBtn.targetScale;
                            return;
                        }
                        const lerp = 1.0 - Math.exp(-12.0 * dock.frameMs / 1000.0);
                        appsBtn.currentScale += delta * lerp;
                    }
                }

                Text {
                    width: dock.iconSize
                    height: dock.iconSize
                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 6
                        horizontalCenter: parent.horizontalCenter
                    }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "󰀻"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Math.round(dock.iconSize * 0.72)
                    color: Theme.on_surface
                    scale: appsBtn.currentScale
                    transformOrigin: Item.Bottom
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        dock.dismissMagnify();
                        dock.launch(["qs", "ipc", "call", "applibrary", "open"]);
                    }
                }
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

        // Taller than the pill so hover stays active over magnified icon pixels.
        Item {
            id: dockMagnifyHover
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.bottom
            }
            width: parent.width
            height: dock.dockBodyHeight + dock.iconSize * (dock.maxScale - 1)

            HoverHandler {
                id: dockMagnifyPointer

                function updateMouseX() {
                    dock.dockMouseXRaw = iconsRow.mapFromGlobal(
                        dockBody.mapToGlobal(point.position.x, point.position.y).x,
                        0
                    ).x;
                }

                onHoveredChanged: {
                    dock.syncDockVisibility();
                    if (hovered)
                        updateMouseX();
                }
                onPointChanged: {
                    if (hovered || dock.dockVisible)
                        updateMouseX();
                    if (dock.windowPickerOpen)
                        dock.syncExposeDismissState();
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
            onHoveredChanged: dock.syncDockVisibility()
            onPointChanged: {
                if (hovered)
                    dockMagnifyPointer.updateMouseX();
            }
        }

    }

    Item {
        id: exposeHoverPad

        visible: dock.windowPickerOpen
        z: 500

        HoverHandler {
            id: exposePadPointer

            onHoveredChanged: {
                if (hovered) {
                    dock.cancelExposeAutoClose();
                } else if (dock.windowPickerOpen) {
                    dock.scheduleExposeAutoClose();
                }
            }
        }

        WindowGroupMenu {
            id: dockWindowPicker

            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            open: dock.windowPickerOpen
            groupKey: dock.windowPickerGroupKey
            maxMenuWidth: Math.min(520, Math.max(280, dock.width - 16))

            onOpenChanged: {
                if (open)
                    dock.positionWindowPicker();
                else
                    dock.exposeOverflowPx = 0;
                dock.syncDockVisibility();
            }

            onWidthChanged: {
                if (dock.windowPickerOpen)
                    dock.positionWindowPicker();
            }

            onHeightChanged: {
                if (dock.windowPickerOpen)
                    dock.positionWindowPicker();
            }

            onWindowChosen: win => {
                HyprDispatch.focusWindow(win);
                dock.closeWindowPicker();
            }

            onDismissed: dock.closeWindowPicker()

            onPointerInsideChanged: {
                if (dockWindowPicker.pointerInside) {
                    dock.cancelExposeAutoClose();
                } else if (dock.windowPickerOpen) {
                    dock.scheduleExposeAutoClose();
                }
            }
        }
    }

    function pointerInExposeZone() {
        if (!dock.windowPickerOpen || !dockWindowPicker.open)
            return false;

        return exposePadPointer.hovered || dockWindowPicker.pointerInside;
    }

    function pointerOnWindowPickerSource() {
        if (!dock.windowPickerOpen || !dock.windowPickerAnchor)
            return false;

        let local = null;
        if (dockMagnifyPointer.hovered) {
            const p = dockMagnifyPointer.point.position;
            local = dock.windowPickerAnchor.mapFromItem(dockMagnifyHover, p.x, p.y);
        } else if (dockBodyHover.hovered) {
            const p = dockBodyHover.point.position;
            local = dock.windowPickerAnchor.mapFromItem(dockBody, p.x, p.y);
        }

        if (!local)
            return false;

        return local.x >= 0
            && local.y >= 0
            && local.x <= dock.windowPickerAnchor.width
            && local.y <= dock.windowPickerAnchor.height;
    }

    function shouldKeepWindowPickerOpen() {
        if (dock.pointerOnWindowPickerSource())
            return true;

        // Dock hover is the most reliable signal when moving from exposé down
        // to another icon. Treat any non-source dock hover as leaving exposé,
        // even if the exposé HoverHandler is stale.
        if (dockMagnifyPointer.hovered || dockBodyHover.hovered)
            return false;

        return dock.pointerInExposeZone();
    }

    function syncExposeDismissState() {
        if (!dock.windowPickerOpen)
            return;

        if (dock.shouldKeepWindowPickerOpen()) {
            dock.cancelExposeAutoClose();
            return;
        }

        dock.scheduleExposeAutoClose();
    }

    function scheduleExposeAutoClose() {
        if (!dock.windowPickerOpen)
            return;
        if (exposeCloseTimer.running)
            return;
        exposeCloseTimer.restart();
    }

    function cancelExposeAutoClose() {
        exposeCloseTimer.stop();
    }

    function positionWindowPicker() {
        if (!dock.windowPickerAnchor || !dock.windowPickerOpen)
            return;

        const gk = `${dock.windowPickerGroupKey ?? ""}`.trim();
        const wins = HyprlandData.windowsForGroupKey(gk);
        if (wins.length === 0)
            return;

        const menuW = Math.max(dockWindowPicker.width, 200);
        const menuH = Math.max(dockWindowPicker.height, wins.length * 38 + 16);

        const iconInBody = dock.windowPickerAnchor.mapToItem(dockBody, 0, 0);
        const iconCX = dockBody.x + iconInBody.x + dock.windowPickerAnchor.width / 2;
        const padW = menuW + 16;
        const padH = menuH + 12;
        const requiredOverflow = Math.max(0, Math.round(padH + 8 - iconInBody.y)) + 8;
        // dockBody is bottom-anchored with bottomGap; when exposeOverflowPx grows,
        // dockBody.y equals requiredOverflow — use that predicted Y, not dockBody.y.
        const finalDockBodyY = requiredOverflow;

        if (dock.exposeOverflowPx !== requiredOverflow) {
            dock.exposeOverflowPx = requiredOverflow;
            Qt.callLater(() => {
                if (dock.windowPickerOpen)
                    dock.positionWindowPicker();
            });
        }

        exposeHoverPad.width = Math.round(padW);
        exposeHoverPad.height = Math.round(padH);
        exposeHoverPad.x = Math.round(Math.max(8, Math.min(
            iconCX - padW / 2,
            dock.width - padW - 8
        )));
        exposeHoverPad.y = Math.round(finalDockBodyY + iconInBody.y - padH - 8);
    }

    Timer {
        id: exposeCloseTimer
        interval: 40
        repeat: false
        onTriggered: {
            if (!dock.windowPickerOpen)
                return;
            if (dock.shouldKeepWindowPickerOpen())
                return;
            dock.closeWindowPicker();
        }
    }

    Timer {
        id: exposePointerPoll
        interval: 32
        repeat: true
        running: dock.windowPickerOpen
        onTriggered: dock.syncExposeDismissState()
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

    // ── Hide delay timer ───────────────────────────────────────────────────
    Timer {
        id: hideTimer
        interval: 500
        repeat: false
        onTriggered: {
            if (dock.dockHovered)
                return;
            if (dock.windowPickerOpen)
                dock.closeWindowPicker();
            dock.dockVisible = false;
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
