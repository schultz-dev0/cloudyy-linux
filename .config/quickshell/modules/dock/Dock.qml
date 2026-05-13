pragma ComponentBehavior: Bound

// modules/dock/Dock.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../.."
import "../../overview/services"

PanelWindow {
    id: dock

    property string systemIconTheme: "Papirus-Dark"
    Process {
        command: ["bash", "-c", "grep '^gtk-icon-theme-name=' ~/.config/gtk-3.0/settings.ini | cut -d= -f2"]
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
    readonly property int frameMs: 16
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

    function execFromWindow(w) {
        if (!w)
            return "";
        const entry = DesktopEntries.heuristicLookup(w.class || w.initialClass || w.initialTitle);
        if (entry) {
            const raw = entry.exec ?? entry.Exec ?? entry.commandLine ?? entry.commandline ?? "";
            const st = stripDesktopExecField(raw);
            if (st.length > 0)
                return st;
        }
        return (w.class || "").toLowerCase();
    }

    // ── App list: pinned + running, deduplicated ───────────────────────────
    readonly property var mergedApps: {
        const pinnedApps = dock.effectivePinnedApps;
        const pinnedClasses = new Set(pinnedApps.map(a => a.class.toLowerCase()));
        const runningMap = {};
        HyprlandData.windowList.forEach(w => {
            const cls = (w.class || "").toLowerCase();
            if (cls && !runningMap[cls])
                runningMap[cls] = w;
        });

        const result = pinnedApps.map(app => ({
            class: app.class,
            exec: app.exec,
            icon: app.icon,
            isRunning: !!runningMap[app.class.toLowerCase()],
            window: runningMap[app.class.toLowerCase()] ?? null,
            isPinned: true
        }));

        Object.keys(runningMap).forEach(cls => {
            if (!pinnedClasses.has(cls)) {
                const w = runningMap[cls];
                const candidates = HyprlandData.iconCandidatesForWindow(w);
                let iconName = (candidates && candidates.length > 0) ? candidates[0] : (w.class || cls);
                if (w.class && w.class.toLowerCase().includes("matlab"))
                    iconName = `${HyprlandData.homeDir}/.local/share/icons/matlab.png`;
                result.push({
                    class: w.class,
                    exec: dock.execFromWindow(w),
                    icon: iconName,
                    isRunning: true,
                    window: w,
                    isPinned: false
                });
            }
        });

        return result;
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
                exec: srcEntry.exec,
                icon: srcEntry.icon
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
                exec: e.exec,
                icon: e.icon
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
        console.log("Dock Launching:", JSON.stringify(cmd));
        const p = procProto.createObject(dock, {
            command: cmd
        });
        p.running = true;
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
                    running: true
                    repeat: true
                    onTriggered: {
                        const lerp = 1.0 - Math.exp(-12.0 * dock.frameMs / 1000.0);
                        searchBtn.currentScale += (searchBtn.targetScale - searchBtn.currentScale) * lerp;
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
                        isDragSource: dock.dragSourceIndex === index
                        onClicked: {
                            if (modelData.isRunning)
                                Hyprland.dispatch("focuswindow class:" + modelData.class);
                            else {
                                const e = modelData.exec;
                                if (Array.isArray(e)) {
                                    dock.launch(e);
                                } else if (e) {
                                    dock.launch(["uwsm-app", "--", e]);
                                }
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
                    running: true
                    repeat: true
                    onTriggered: {
                        const lerp = 1.0 - Math.exp(-12.0 * dock.frameMs / 1000.0);
                        appsBtn.currentScale += (appsBtn.targetScale - appsBtn.currentScale) * lerp;
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
                    onClicked: dock.launch(["bash", "-c", "$HOME/cloudyy_scripts/rofi/applications.sh"])
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
                property var ghostSources: HyprlandData.iconSourcesForName(dock.dragGhostAppData && dock.dragGhostAppData.icon ? dock.dragGhostAppData.icon : "application-x-executable")

                anchors {
                    bottom: parent.bottom
                    bottomMargin: 6
                    horizontalCenter: parent.horizontalCenter
                }
                width: dock.iconSize
                height: dock.iconSize
                onGhostSourcesChanged: sourceIndex = 0
                source: ghostSources[sourceIndex] ?? "image://icon/application-x-executable"
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
    IpcHandler {
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
