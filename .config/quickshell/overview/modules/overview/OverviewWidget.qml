pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../../"
import "../../services"

Item {
    id: root

    required property var screenModel
    required property var monitorData
    required property bool overviewActive
    property int selectedWorkspaceId: activeWorkspaceId()

    signal selectedWorkspaceChanged(int workspaceId)
    signal requestWorkspace(int workspaceId)
    signal requestFocusWindow(var windowData)
    signal requestCloseWindow(var windowData)
    signal requestCloseWorkspace(int workspaceId)

    readonly property var visibleWorkspaceIds: computeVisibleWorkspaceIds()
    readonly property int tileHeight: 180
    readonly property int previewLabelHeight: 22
    readonly property int previewMargin: 16
    readonly property int minTileWidth: 80
    readonly property int maxTileWidth: 380
    readonly property real previewAreaHeight: tileHeight - previewLabelHeight - previewMargin
    readonly property int panelPaddingH: 18
    readonly property int panelPaddingV: 20
    readonly property int panelOuterMargin: 40
    readonly property int tileSpacing: 12
    readonly property real panelMaxWidth: Math.max(0, parent.width - panelOuterMargin * 2)
    readonly property real panelMaxHeight: Math.max(0, parent.height - panelOuterMargin * 2)

    function normalizeAddress(addr) {
        const s = `${addr ?? ""}`.trim().toLowerCase();
        if (!s.length)
            return "";
        return s.startsWith("0x") ? s : "0x" + s;
    }

    readonly property var toplevelByAddress: {
        const map = {};
        for (const t of ToplevelManager.toplevels?.values ?? []) {
            if (!t?.HyprlandToplevel?.address)
                continue;
            const addr = normalizeAddress(t.HyprlandToplevel.address);
            if (addr.length)
                map[addr] = t;
        }
        return map;
    }

    onOverviewActiveChanged: {
        if (overviewActive)
            Hyprland.refreshToplevels();
    }

    function tileCaptureActive(workspaceId) {
        if (!overviewActive)
            return false;
        if (!Perf.lightweightOverview)
            return true;
        return workspaceId === selectedWorkspaceId || workspaceId === activeWorkspaceId();
    }

    function activeWorkspaceId() {
        return Number(HyprlandData.activeWorkspace?.id ?? 1);
    }

    function windowsForWorkspace(workspaceId) {
        return HyprlandData.windowsByWorkspace[workspaceId] ?? [];
    }

    function monitorUsableSize(monitor) {
        if (!monitor)
            return { width: 1920, height: 1080 };

        const t = Number(monitor.transform ?? 0);
        const rawW = (t % 2 === 1) ? monitor.height : monitor.width;
        const rawH = (t % 2 === 1) ? monitor.width : monitor.height;
        return {
            width: Math.max(1, rawW - (monitor.reserved?.[0] ?? 0) - (monitor.reserved?.[2] ?? 0)),
            height: Math.max(1, rawH - (monitor.reserved?.[1] ?? 0) - (monitor.reserved?.[3] ?? 0))
        };
    }

    function tileWidthForWorkspace(workspaceId) {
        const monitor = monitorForWorkspace(workspaceId);
        const usable = monitorUsableSize(monitor);
        const previewWidth = previewAreaHeight * (usable.width / usable.height);
        const width = Math.round(previewWidth + previewMargin);
        return Math.max(minTileWidth, Math.min(maxTileWidth, width));
    }

    function tilesRowWidth(workspaceIds) {
        if (!workspaceIds?.length)
            return 0;

        let width = 0;
        for (let i = 0; i < workspaceIds.length; i++) {
            width += tileWidthForWorkspace(workspaceIds[i]);
            if (i > 0)
                width += tileSpacing;
        }
        return width;
    }

    function computeWorkspaceRows(workspaceIds, packWidth) {
        if (!workspaceIds?.length || packWidth <= 0)
            return [];

        const rows = [];
        let currentRow = [];
        let currentWidth = 0;

        for (const workspaceId of workspaceIds) {
            const tileW = tileWidthForWorkspace(workspaceId);
            const gap = currentRow.length > 0 ? tileSpacing : 0;

            if (currentRow.length > 0 && currentWidth + gap + tileW > packWidth) {
                rows.push(currentRow);
                currentRow = [workspaceId];
                currentWidth = tileW;
            } else {
                currentRow.push(workspaceId);
                currentWidth += gap + tileW;
            }
        }

        if (currentRow.length > 0)
            rows.push(currentRow);

        return rows;
    }

    readonly property real flowContentWidth: {
        const rowWidth = tilesRowWidth(visibleWorkspaceIds);
        const maxInner = panelMaxWidth - panelPaddingH * 2;
        if (rowWidth <= 0)
            return Math.max(0, maxInner);
        return Math.min(rowWidth, maxInner);
    }

    readonly property real panelWidth: {
        const rowWidth = tilesRowWidth(visibleWorkspaceIds);
        const maxInner = panelMaxWidth - panelPaddingH * 2;
        const inner = rowWidth > 0 ? Math.min(rowWidth, maxInner) : maxInner;
        return inner + panelPaddingH * 2;
    }

    readonly property var workspaceRows: computeWorkspaceRows(visibleWorkspaceIds, flowContentWidth)

    readonly property real panelContentHeight: workspacesColumn.implicitHeight
    readonly property real panelHeight: Math.min(
        panelContentHeight + panelPaddingV * 2,
        panelMaxHeight
    )

    function monitorForWorkspace(workspaceId) {
        const windows = windowsForWorkspace(workspaceId);
        for (const window of windows) {
            const monitorId = Number(window?.monitor ?? -1);
            const match = (HyprlandData.monitors ?? []).find(monitor => Number(monitor?.id ?? -2) === monitorId);
            if (match)
                return match;
        }

        if (workspaceId === activeWorkspaceId() && monitorData)
            return monitorData;

        return monitorData ?? null;
    }

    function computeVisibleWorkspaceIds() {
        const ids = new Set();
        for (const workspaceId of Object.keys(HyprlandData.windowsByWorkspace ?? {})) {
            const id = Number(workspaceId);
            if (Number.isFinite(id) && id > 0)
                ids.add(id);
        }

        const activeId = activeWorkspaceId();
        if (Number.isFinite(activeId) && activeId > 0)
            ids.add(activeId);

        return Array.from(ids).sort((a, b) => a - b);
    }

    function ensureSelectionValid() {
        const ids = visibleWorkspaceIds;
        if (ids.length === 0)
            return;

        if (!ids.includes(selectedWorkspaceId)) {
            const activeId = activeWorkspaceId();
            selectedWorkspaceId = ids.includes(activeId) ? activeId : ids[0];
            selectedWorkspaceChanged(selectedWorkspaceId);
        }
    }

    function resetSelectionToNext() {
        const ids = visibleWorkspaceIds;
        if (ids.length === 0)
            return;

        let index = ids.indexOf(activeWorkspaceId());
        if (index < 0)
            index = -1;

        const nextId = ids[(index + 1) % ids.length];
        if (selectedWorkspaceId === nextId)
            return;

        selectedWorkspaceId = nextId;
        selectedWorkspaceChanged(selectedWorkspaceId);
    }

    function resetSelectionToActive() {
        const ids = visibleWorkspaceIds;
        if (ids.length === 0)
            return;

        const activeId = activeWorkspaceId();
        const nextId = ids.includes(activeId) ? activeId : ids[0];
        if (selectedWorkspaceId === nextId)
            return;

        selectedWorkspaceId = nextId;
        selectedWorkspaceChanged(selectedWorkspaceId);
    }

    function selectDelta(delta) {
        const ids = visibleWorkspaceIds;
        if (ids.length === 0)
            return;

        let index = ids.indexOf(selectedWorkspaceId);
        if (index < 0)
            index = Math.max(0, ids.indexOf(activeWorkspaceId()));

        const next = (index + delta + ids.length) % ids.length;
        if (selectedWorkspaceId === ids[next])
            return;

        selectedWorkspaceId = ids[next];
        selectedWorkspaceChanged(selectedWorkspaceId);
    }

    function selectPrevious() {
        selectDelta(-1);
    }

    function selectNext() {
        selectDelta(1);
    }

    function selectWorkspace(workspaceId) {
        const id = Number(workspaceId);
        if (!Number.isFinite(id) || !visibleWorkspaceIds.includes(id))
            return false;

        if (selectedWorkspaceId !== id) {
            selectedWorkspaceId = id;
            selectedWorkspaceChanged(selectedWorkspaceId);
        }
        return true;
    }

    function activateSelected() {
        if (Number.isFinite(selectedWorkspaceId) && selectedWorkspaceId > 0)
            requestWorkspace(selectedWorkspaceId);
    }

    function closeSelectedWorkspace() {
        if (Number.isFinite(selectedWorkspaceId) && selectedWorkspaceId > 0)
            requestCloseWorkspace(selectedWorkspaceId);
    }

    onVisibleWorkspaceIdsChanged: Qt.callLater(ensureSelectionValid)
    Component.onCompleted: ensureSelectionValid()

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelHeight
        radius: 24
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1
        opacity: GlobalStates.overviewOpen ? 1 : 0
        scale: GlobalStates.overviewOpen ? 1.0 : 0.88
        transformOrigin: Item.Center

        Behavior on scale {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(180); easing.type: Easing.OutCubic }
        }

        Behavior on opacity {
            enabled: Perf.animationsEnabled
            NumberAnimation { duration: Perf.msHalf(140); easing.type: Easing.OutCubic }
        }

        Flickable {
            id: workspacesScroller

            anchors.fill: parent
            anchors.leftMargin: root.panelPaddingH
            anchors.rightMargin: root.panelPaddingH
            anchors.topMargin: root.panelPaddingV
            anchors.bottomMargin: root.panelPaddingV
            contentWidth: workspacesColumn.width
            contentHeight: workspacesColumn.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: workspacesColumn

                width: root.flowContentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.tileSpacing

                Repeater {
                    model: root.workspaceRows

                    delegate: Row {
                        required property var modelData

                        spacing: root.tileSpacing
                        anchors.horizontalCenter: parent.horizontalCenter

                        Repeater {
                            model: modelData

                            delegate: WorkspaceTile {
                                required property int modelData

                                workspaceId: modelData
                                windows: root.windowsForWorkspace(modelData)
                                active: modelData === root.activeWorkspaceId()
                                selected: modelData === root.selectedWorkspaceId
                                monitorData: root.monitorForWorkspace(modelData)
                                overviewActive: root.overviewActive
                                toplevelByAddress: root.toplevelByAddress
                                tileCaptureActive: root.tileCaptureActive(modelData)
                                tileWidth: root.tileWidthForWorkspace(modelData)
                                tileHeight: root.tileHeight
                                onRequestWorkspace: workspaceId => root.requestWorkspace(workspaceId)
                                onRequestFocusWindow: windowData => root.requestFocusWindow(windowData)
                                onRequestCloseWindow: windowData => root.requestCloseWindow(windowData)
                            }
                        }
                    }
                }
            }
        }
    }
}
