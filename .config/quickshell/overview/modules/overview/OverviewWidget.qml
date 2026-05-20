pragma ComponentBehavior: Bound

import QtQuick
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
    readonly property int tileWidth: 178
    readonly property int tileHeight: 82
    readonly property int panelPaddingH: 14
    readonly property int panelPaddingV: 14
    readonly property int tileSpacing: 10

    function activeWorkspaceId() {
        return Number(HyprlandData.activeWorkspace?.id ?? 1);
    }

    function windowsForWorkspace(workspaceId) {
        return HyprlandData.windowsByWorkspace[workspaceId] ?? [];
    }

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
        width: Math.min(Math.max(0, parent.width - 80), workspacesRow.implicitWidth + root.panelPaddingH * 2)
        height: workspacesRow.implicitHeight + root.panelPaddingV * 2
        radius: 24
        color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.85)
        border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.3)
        border.width: 1
        clip: true
        opacity: GlobalStates.overviewOpen ? 1 : 0
        scale: GlobalStates.overviewOpen ? 1.0 : 0.88
        transformOrigin: Item.Center

        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 0.4 }
        }

        Behavior on opacity {
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Row {
            id: workspacesRow

            anchors.centerIn: parent
            spacing: root.tileSpacing

            Repeater {
                model: root.visibleWorkspaceIds

                delegate: WorkspaceTile {
                    required property int modelData

                    workspaceId: modelData
                    windows: root.windowsForWorkspace(modelData)
                    active: modelData === root.activeWorkspaceId()
                    selected: modelData === root.selectedWorkspaceId
                    monitorData: root.monitorForWorkspace(modelData)
                    overviewActive: root.overviewActive
                    tileWidth: root.tileWidth
                    tileHeight: root.tileHeight
                    onRequestWorkspace: workspaceId => root.requestWorkspace(workspaceId)
                    onRequestFocusWindow: windowData => root.requestFocusWindow(windowData)
                    onRequestCloseWindow: windowData => root.requestCloseWindow(windowData)
                }
            }
        }
    }
}
