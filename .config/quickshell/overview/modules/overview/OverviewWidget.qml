pragma ComponentBehavior: Bound

import QtQuick
import "../../../"
import "../../services"

Item {
    id: root

    required property var screenModel
    required property var monitorData
    required property bool overviewActive

    property int selectedIndex: 0
    property int selectedInstanceIndex: 0

    signal requestFocusApp(var appData)

    readonly property var appList: HyprlandData.buildRunningAppList()
    readonly property int iconSize: 44
    readonly property int iconCellSize: iconSize + 8
    readonly property int iconSpacing: 14
    readonly property int paddingH: 18
    readonly property int paddingV: 14
    readonly property int outerMargin: Math.max(40, Math.round(parent.width * 0.06))
    readonly property int availableWidth: Math.max(0, parent.width - outerMargin * 2)
    readonly property int iconsPerRow: Math.max(1, Math.floor((availableWidth - paddingH * 2 + iconSpacing) / (iconCellSize + iconSpacing)))

    readonly property var appRows: {
        const rows = [];
        const list = appList;
        const perRow = iconsPerRow;
        for (let i = 0; i < list.length; i += perRow)
            rows.push(list.slice(i, Math.min(i + perRow, list.length)));
        return rows;
    }

    readonly property int flowContentWidth: {
        let maxW = 0;
        for (let r = 0; r < appRows.length; r++) {
            const count = appRows[r].length;
            const w = count * iconCellSize + Math.max(0, count - 1) * iconSpacing;
            if (w > maxW)
                maxW = w;
        }
        return maxW;
    }

    readonly property int rowCount: Math.max(1, appRows.length)
    readonly property int panelWidth: appList.length === 0
        ? Math.min(availableWidth, 220)
        : Math.min(availableWidth, flowContentWidth + paddingH * 2)
    readonly property int panelHeight: Math.min(
        parent.height - outerMargin * 2,
        rowCount * iconCellSize + Math.max(0, rowCount - 1) * iconSpacing + paddingV * 2
    )

    function normalizeAddress(addr) {
        const s = `${addr ?? ""}`.trim().toLowerCase();
        if (!s.length)
            return "";
        return s.startsWith("0x") ? s : "0x" + s;
    }

    function focusedWindow() {
        const windows = HyprlandData.windowList ?? [];
        if (windows.length === 0)
            return null;

        let best = windows[0];
        let bestHistory = best?.focusHistoryID ?? 999999;
        for (let i = 1; i < windows.length; i++) {
            const w = windows[i];
            const history = w?.focusHistoryID ?? 999999;
            if (history < bestHistory) {
                bestHistory = history;
                best = w;
            }
        }
        return best;
    }

    function indexForWindow(win) {
        if (!win || appList.length === 0)
            return -1;

        const addr = normalizeAddress(win.address);
        const groupKey = HyprlandData.appGroupKey(win);

        for (let i = 0; i < appList.length; i++) {
            const app = appList[i];
            const appAddr = normalizeAddress(app?.window?.address);
            if (addr.length && appAddr === addr)
                return i;

            const appGroup = `${app?.groupKey || HyprlandData.appGroupKey(app?.window)}`.toLowerCase().trim();
            if (groupKey.length && appGroup === groupKey)
                return i;
        }
        return -1;
    }

    function selectedApp() {
        if (selectedIndex < 0 || selectedIndex >= appList.length)
            return null;
        return appList[selectedIndex];
    }

    function windowsInSelectedGroup() {
        const app = selectedApp();
        if (!app)
            return [];
        const gk = `${app.groupKey || HyprlandData.appGroupKey(app.window)}`.trim();
        return gk.length ? HyprlandData.windowsForGroupKey(gk) : [];
    }

    function syncInstanceForSelection() {
        const wins = windowsInSelectedGroup();
        if (wins.length === 0) {
            selectedInstanceIndex = 0;
            return;
        }

        const addr = normalizeAddress(focusedWindow()?.address);
        let idx = 0;
        for (let i = 0; i < wins.length; i++) {
            if (normalizeAddress(wins[i].address) === addr) {
                idx = i;
                break;
            }
        }
        selectedInstanceIndex = idx;
    }

    function advanceTabSelection() {
        if (appList.length === 0)
            return;

        const wins = windowsInSelectedGroup();
        if (wins.length > 1 && selectedInstanceIndex < wins.length - 1) {
            selectedInstanceIndex++;
            return;
        }

        selectedIndex = (selectedIndex + 1) % appList.length;
        selectedInstanceIndex = 0;
    }

    function retreatTabSelection() {
        if (appList.length === 0)
            return;

        if (selectedInstanceIndex > 0) {
            selectedInstanceIndex--;
            return;
        }

        selectedIndex = (selectedIndex - 1 + appList.length) % appList.length;
        const wins = windowsInSelectedGroup();
        selectedInstanceIndex = Math.max(0, wins.length - 1);
    }

    function selectedWindow() {
        const wins = windowsInSelectedGroup();
        if (wins.length === 0)
            return selectedApp()?.window ?? null;
        const idx = Math.max(0, Math.min(selectedInstanceIndex, wins.length - 1));
        return wins[idx];
    }

    function selectAppAt(globalIndex) {
        if (globalIndex < 0 || globalIndex >= appList.length)
            return;
        selectedIndex = globalIndex;
        syncInstanceForSelection();
    }

    function ensureSelectionValid() {
        if (appList.length === 0) {
            selectedIndex = 0;
            return;
        }
        if (selectedIndex < 0)
            selectedIndex = 0;
        if (selectedIndex >= appList.length)
            selectedIndex = appList.length - 1;
        syncInstanceForSelection();
    }

    function resetSelectionToNext() {
        if (appList.length === 0)
            return;

        const currentIdx = indexForWindow(focusedWindow());
        const base = currentIdx >= 0 ? currentIdx : -1;
        selectedIndex = (base + 1) % appList.length;
        syncInstanceForSelection();
    }

    function resetSelectionToActive() {
        if (appList.length === 0)
            return;

        const idx = indexForWindow(focusedWindow());
        selectedIndex = idx >= 0 ? idx : 0;
        syncInstanceForSelection();
    }

    function selectDelta(delta) {
        if (appList.length === 0)
            return;

        selectedIndex = (selectedIndex + delta + appList.length) % appList.length;
        syncInstanceForSelection();
    }

    function selectPrevious() {
        selectDelta(-1);
    }

    function selectNext() {
        selectDelta(1);
    }

    function selectRowDelta(rowDelta) {
        if (appList.length === 0)
            return;

        const next = selectedIndex + rowDelta * iconsPerRow;
        selectedIndex = ((next % appList.length) + appList.length) % appList.length;
        syncInstanceForSelection();
    }

    function selectWorkspace(workspaceId) {
        return false;
    }

    function activateSelected() {
        const win = selectedWindow();
        if (!win)
            return;
        requestFocusApp({
            window: win,
            groupKey: selectedApp()?.groupKey ?? HyprlandData.appGroupKey(win)
        });
    }

    onAppListChanged: Qt.callLater(ensureSelectionValid)
    Component.onCompleted: ensureSelectionValid()

    Rectangle {
        id: panel

        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelHeight
        radius: 22
        color: Theme.glassShell
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.3)
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

        Text {
            anchors.centerIn: parent
            visible: root.appList.length === 0
            text: "No open windows"
            color: Theme.textMuted
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Column {
            anchors.centerIn: parent
            spacing: root.iconSpacing
            visible: root.appList.length > 0
            width: root.flowContentWidth

            Repeater {
                model: root.appRows

                delegate: Row {
                    id: appRow

                    required property var modelData
                    required property int index

                    spacing: root.iconSpacing
                    anchors.horizontalCenter: parent.horizontalCenter

                    Repeater {
                        model: modelData

                        delegate: AppStripIcon {
                            required property var modelData
                            required property int index

                            readonly property int globalIndex: appRow.index * root.iconsPerRow + index

                            appData: modelData
                            selected: globalIndex === root.selectedIndex
                            iconSize: root.iconSize
                            instanceIndex: globalIndex === root.selectedIndex ? root.selectedInstanceIndex : -1
                            onClicked: root.selectAppAt(globalIndex)
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: panel.bottom
            anchors.topMargin: 10
            visible: root.windowsInSelectedGroup().length > 1 && GlobalStates.overviewOpen
            width: Math.min(root.availableWidth, 420)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: {
                const wins = root.windowsInSelectedGroup();
                if (wins.length <= 1)
                    return "";
                const label = HyprlandData.windowLabel(wins[root.selectedInstanceIndex]);
                return `${root.selectedInstanceIndex + 1}/${wins.length} — ${label}`;
            }
            color: Theme.text
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12
        }
    }
}
