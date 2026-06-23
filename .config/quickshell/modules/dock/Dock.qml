pragma ComponentBehavior: Bound

// modules/dock/Dock.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../../overview/services"

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
    readonly property int bottomGap: 0
    readonly property int activationHeight: 16

    // ── Drag / interaction ─────────────────────────────────────────────────
    property int dragSourceIndex: -1
    property int dragHoverVisualIndex: -1
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
    property real dockMouseX: -9999
    readonly property bool dockHovered: triggerZone.containsMouse || dockBodyHover.hovered
    readonly property bool animationActive: dockVisible || dockHovered || interactionBlock || dragSourceIndex >= 0
    readonly property bool dockIdle: !dockVisible && !dockHovered && !interactionBlock && dragSourceIndex < 0
    readonly property bool anyFullscreen: {
        return HyprlandData.windowList.some(w => (w.fullscreen ?? 0) > 0);
    }
    onAnyFullscreenChanged: {
        if (anyFullscreen) {
            hideTimer.stop();
            dockMouseX = -9999;
            dockVisible = false;
        } else {
            syncDockVisibility();
        }
    }

    onDockHoveredChanged: syncDockVisibility()

    function syncDockVisibility() {
        if (interactionBlock) {
            hideTimer.stop();
            dockVisible = true;
            return;
        }
        if (anyFullscreen) {
            hideTimer.stop();
            dockMouseX = -9999;
            dockVisible = false;
            return;
        }

        if (dockHovered) {
            hideTimer.stop();
            dockVisible = true;
            return;
        }

        dockMouseX = -9999;
        if (dockVisible)
            hideTimer.restart();
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
        if (Array.isArray(app.exec))
            return app.exec;

        const desktopExec = dock.desktopExecForClass(app.class);
        if (desktopExec.length > 0)
            return desktopExec;

        const pinnedExec = stripDesktopExecField(app.exec);
        if (pinnedExec.length > 0)
            return pinnedExec;

        return `${app.class ?? ""}`.toLowerCase();
    }

    function execFromWindow(w) {
        if (!w)
            return "";
        const st = desktopExecForClass(w.class || w.initialClass || w.initialTitle);
        if (st.length > 0)
            return st;
        return (w.class || "").toLowerCase();
    }

    // ── App list: pinned + running, deduplicated ───────────────────────────
    readonly property var runningWindows: HyprlandData.windowList
    property var mergedApps: []

    onRunningWindowsChanged: rebuildMergedApps()
    onEffectivePinnedAppsChanged: rebuildMergedApps()

    function windowMatchScore(window, pinnedClass) {
        const pCls = `${pinnedClass ?? ""}`.toLowerCase().trim();
        if (!pCls) return 0;
        const pParts = pCls.split(".");
        const pLast = pParts[pParts.length - 1] ?? "";
        const wCls = `${window.class ?? ""}`.toLowerCase();
        const wInit = `${window.initialClass ?? ""}`.toLowerCase();
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
            let iconName = (candidates && candidates.length > 0) ? candidates[0] : (w.class || "");
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

        dock.mergedApps = result;
    }

    function visualIndexAtRowX(rowLocalX) {
        const slot = dock.iconSize + dock.iconSpacing;
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
        dock.dragGhostAppData = dock.mergedApps[visualIndex] ?? null;
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
        dock.dragHoverVisualIndex = dock.visualIndexAtRowX(rowLocalX);
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
        dock.dragSourceIndex = -1;
        dock.dragHoverVisualIndex = -1;
        dock.interactionBlock = false;
        dock.clearDragGhost();
        dock.syncDockVisibility();
    }

    function finishIconDrag() {
        if (dock.dragSourceIndex < 0)
            return;
        const src = dock.dragSourceIndex;
        const dst = dock.dragHoverVisualIndex >= 0 ? dock.dragHoverVisualIndex : src;
        const list = dock.mergedApps;
        const pinnedCount = DockStore.pinnedApps.length;
        if (src >= list.length) {
            dock.dragSourceIndex = -1;
            dock.dragHoverVisualIndex = -1;
            dock.interactionBlock = false;
            dock.clearDragGhost();
            dock.syncDockVisibility();
            return;
        }
        const srcEntry = list[src];
        const srcPinned = !!srcEntry.isPinned;
        const dstClamped = Math.min(dst, Math.max(0, list.length - 1));

        if (srcPinned) {
            if (dstClamped < pinnedCount) {
                if (src !== dstClamped)
                    DockStore.movePinned(src, dstClamped);
            } else {
                if (pinnedCount > 0 && src !== pinnedCount - 1)
                    DockStore.movePinned(src, pinnedCount - 1);
            }
        } else {
            const insertAt = Math.min(dstClamped, pinnedCount);
            DockStore.pinEntry({
                class: srcEntry.class,
                exec: dock.execForPinnedApp(srcEntry),
                icon: dock.iconForApp(srcEntry)
            }, insertAt);
        }

        dock.dragSourceIndex = -1;
        dock.dragHoverVisualIndex = -1;
        dock.interactionBlock = false;
        dock.clearDragGhost();
        dock.syncDockVisibility();
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
    readonly property real dockMouseXEffective: interactionBlock ? -9999 : dockMouseX

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
            command: ["bash", "-lc", `cd "$HOME" && exec ${inner}`]
        });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function launchApp(app) {
        const e = dock.execForPinnedApp(app);
        if (Array.isArray(e)) {
            dock.launch(e);
        } else if (e) {
            dock.launch(["uwsm-app", "--", e]);
        } else {
            console.warn("dock: no launch command for", app?.class ?? "<unknown>");
        }
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
                duration: 220
                easing.type: dock.dockVisible ? Easing.OutCubic : Easing.InCubic
            }
        }

        // Glass pill background
        Rectangle {
            width: parent.width
            height: dock.pillHeight
            anchors.bottom: parent.bottom
            radius: dock.paddingV + dock.iconSize * 0.22
            color: Qt.rgba(Theme.surface_container.r, Theme.surface_container.g, Theme.surface_container.b, 0.72)
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
                        if (Math.abs(delta) < 0.002) {
                            searchBtn.currentScale = searchBtn.targetScale;
                            return;
                        }
                        const lerp = 1.0 - Math.exp(-12.0 * dock.frameMs / 1000.0);
                        searchBtn.currentScale += delta * lerp;
                    }
                }
                Connections {
                    target: dock
                    function onDockIdleChanged() {
                        if (dock.dockIdle)
                            searchBtn.currentScale = 1.0;
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
                    onClicked: dock.launch(["quickshell", "ipc", "call", "spotlight", "toggle"])
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
                        iconCenterX: x + dock.iconSize / 2
                        animationActive: dock.animationActive || dock.dragSourceIndex === index
                        dockIdle: dock.dockIdle
                        isDragSource: dock.dragSourceIndex === index
                        onClicked: {
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
                        onDragReorderEnded: {
                            dock.finishIconDrag();
                        }
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
                        if (Math.abs(delta) < 0.002) {
                            appsBtn.currentScale = appsBtn.targetScale;
                            return;
                        }
                        const lerp = 1.0 - Math.exp(-12.0 * dock.frameMs / 1000.0);
                        appsBtn.currentScale += delta * lerp;
                    }
                }
                Connections {
                    target: dock
                    function onDockIdleChanged() {
                        if (dock.dockIdle)
                            appsBtn.currentScale = 1.0;
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
                    onClicked: dock.launch(["qs", "ipc", "call", "applibrary", "open"])
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
                property var ghostSources: dock.dragGhostAppData && dock.dragGhostAppData.icon ? HyprlandData.iconSourcesForName(dock.dragGhostAppData.icon) : [HyprlandData.genericIconSource]

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

        // HoverHandler tracks pointer inside dockBody without competing with
        // child MouseAreas for hover events — fixes hide timer firing on icon hover.
        HoverHandler {
            id: dockBodyHover
            onHoveredChanged: {
                dock.syncDockVisibility();
            }
            onPointChanged: {
                if (hovered)
                    dock.dockMouseX = dockBody.mapToItem(iconsRow, point.position.x, point.position.y).x;
                if (dock.dragSourceIndex >= 0 && hovered)
                    dock.updateDragFromBodyPoint(point.position.x, point.position.y);
            }
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
