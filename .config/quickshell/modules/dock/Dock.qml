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
    readonly property real maxScale: 1.8
    readonly property real spread: 1
    readonly property int frameMs: Perf.dockFrameMs
    readonly property int triggerHeight: 0
    readonly property int pillHeight: iconSize + paddingV * 2
    readonly property int dockBodyHeight: 110
    readonly property int iconSpacing: 25
    readonly property int paddingH: 14
    readonly property int paddingV: 12
    readonly property int bottomGap: 2
    readonly property int activationHeight: 4 // reduce from 16 for a more macos feel, on macos you really gotta drag your cursor all the way down to bring the dock up. 

    // ── Drag / interaction ─────────────────────────────────────────────────
    property int dragSourceIndex: -1
    property int dragHoverVisualIndex: -1
    property string dragSourceClass: ""
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
    readonly property bool dockHovered: triggerZone.containsMouse || dockMagnifyPointer.hovered
    readonly property bool animationActive: dockVisible || dockHovered || interactionBlock || dragSourceIndex >= 0
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

    function execFromWindow(w) {
        if (!w)
            return "";
        const cls = w.class || w.initialClass || w.initialTitle || "";
        const st = desktopExecForClass(cls);
        if (st.length > 0)
            return st;
        const pwaExec = HyprlandData.chromePwaExecFromClass(cls);
        if (pwaExec.length > 0)
            return pwaExec;
        return "";
    }

    // ── App list: pinned + running, deduplicated ───────────────────────────
    readonly property var runningWindows: HyprlandData.windowList
    property var mergedApps: []
    property string mergedAppsSignature: ""

    onRunningWindowsChanged: rebuildMergedApps()
    onEffectivePinnedAppsChanged: rebuildMergedApps()

    function mergedAppsSignatureFor(list) {
        let sig = "";
        for (let i = 0; i < list.length; i++) {
            const e = list[i];
            if (i > 0)
                sig += "|";
            sig += `${dock.classKey(e.class)}:${e.isPinned ? 1 : 0}:${e.isRunning ? 1 : 0}`;
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

    function windowAppKey(window) {
        return `${window?.class || window?.initialClass || ""}`.toLowerCase().trim();
    }

    function moreRecentWindow(current, candidate) {
        return !current || ((candidate?.focusHistoryID ?? 9999) < (current?.focusHistoryID ?? 9999));
    }

    function rebuildMergedApps() {
        const windows = dock.runningWindows;
        const pinnedApps = dock.effectivePinnedApps;

        const result = pinnedApps.map(app => {
            const win = dock.findWindowForClass(app.class, windows);
            return {
                class: app.class,
                exec: app.exec,
                icon: dock.iconForApp(app),
                isRunning: win != null,
                window: win,
                isPinned: true
            };
        });

        const unpinnedByKey = ({});
        windows.forEach(w => {
            if (pinnedApps.some(app => dock.windowMatchScore(w, app.class) > 0))
                return;
            const key = dock.windowAppKey(w);
            if (!key)
                return;
            if (dock.moreRecentWindow(unpinnedByKey[key], w))
                unpinnedByKey[key] = w;
        });

        Object.keys(unpinnedByKey).forEach(key => {
            const w = unpinnedByKey[key];
            const candidates = HyprlandData.iconCandidatesForWindow(w);
            let iconName = "";
            for (let i = 0; i < candidates.length; i++) {
                const candidate = `${candidates[i] ?? ""}`.trim();
                if (!candidate || candidate === "application-default-icon")
                    continue;
                iconName = candidate;
                break;
            }
            if (!iconName)
                iconName = w.class || "";
            if (w.class && w.class.toLowerCase().includes("matlab"))
                iconName = `${HyprlandData.homeDir}/.local/share/icons/matlab.png`;
            result.push({
                class: w.class,
                exec: dock.execFromWindow(w),
                icon: dock.iconForApp({ class: w.class, icon: iconName }),
                isRunning: true,
                window: w,
                isPinned: false
            });
        });

        const sig = dock.mergedAppsSignatureFor(result);
        if (sig === dock.mergedAppsSignature && dock.mergedApps.length === result.length) {
            for (let i = 0; i < result.length; i++) {
                const cur = dock.mergedApps[i];
                const next = result[i];
                cur.window = next.window;
                cur.isRunning = next.isRunning;
                cur.exec = next.exec;
                cur.icon = next.icon;
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

    function syncDragIndicesAfterRebuild() {
        if (dock.dragSourceIndex < 0)
            return;

        const srcIdx = dock.visualIndexForClass(dock.dragSourceClass);
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

    // ── Window ────────────────────────────────────────────────────────────
    anchors {
        bottom: true
    }
    implicitWidth: dockWidth
    implicitHeight: dockVisible ? dockFullHeight : activationHeight
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:dock"
    color: "transparent"

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

    function focusWindow(window) {
        HyprDispatch.focusWindow(window);
    }

    function focusClass(className) {
        HyprDispatch.focusWindowByClass(className);
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
        y: dock.dockVisible ? 0 : dock.dockFullHeight
        Behavior on y {
            NumberAnimation {
                duration: Perf.msHalf(220)
                easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
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
                            && dock.classKey(modelData.class) === dock.classKey(dock.dragSourceClass)
                        dragShiftTargetX: dock.dragShiftTargetForIndex(index)
                        onClicked: {
                            dock.dismissMagnify();
                            if (modelData.isRunning) {
                                if (modelData.window?.address)
                                    dock.focusWindow(modelData.window);
                                else
                                    dock.focusClass(modelData.class);
                            } else {
                                dock.launchApp(modelData);
                            }
                        }
                        onRequestTogglePin: dock.togglePinAtIndex(index)
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
            if (!dock.dockHovered)
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
