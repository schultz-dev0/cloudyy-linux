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

    signal requestFocusApp(var appData)

    readonly property var appList: HyprlandData.buildRunningAppList()
    readonly property int iconSize: 44
    readonly property int iconSpacing: 14
    readonly property int paddingH: 18
    readonly property int paddingV: 14
    readonly property int outerMargin: Math.max(40, Math.round(parent.width * 0.06))
    readonly property int availableWidth: Math.max(0, parent.width - outerMargin * 2)
    readonly property int iconsPerRow: Math.max(1, Math.floor((availableWidth - paddingH * 2 + iconSpacing) / (iconSize + iconSpacing)))
    readonly property int rowCount: Math.max(1, appList.length === 0 ? 1 : Math.ceil(appList.length / iconsPerRow))
    readonly property int panelWidth: Math.min(availableWidth, iconsPerRow * (iconSize + iconSpacing) - iconSpacing + paddingH * 2)
    readonly property int panelHeight: Math.min(parent.height - outerMargin * 2, rowCount * (iconSize + 8) + (rowCount - 1) * iconSpacing + paddingV * 2)

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
        const cls = `${HyprlandData.normalizeDockClass(win?.class || win?.initialClass || "")}`.toLowerCase().trim();

        for (let i = 0; i < appList.length; i++) {
            const app = appList[i];
            const appAddr = normalizeAddress(app?.window?.address);
            if (addr.length && appAddr === addr)
                return i;

            const appCls = `${HyprlandData.normalizeDockClass(app?.class || "")}`.toLowerCase().trim();
            if (cls.length && appCls === cls)
                return i;
        }
        return -1;
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
    }

    function resetSelectionToNext() {
        if (appList.length === 0)
            return;

        const currentIdx = indexForWindow(focusedWindow());
        const base = currentIdx >= 0 ? currentIdx : -1;
        selectedIndex = (base + 1) % appList.length;
    }

    function resetSelectionToActive() {
        if (appList.length === 0)
            return;

        const idx = indexForWindow(focusedWindow());
        selectedIndex = idx >= 0 ? idx : 0;
    }

    function selectDelta(delta) {
        if (appList.length === 0)
            return;

        selectedIndex = (selectedIndex + delta + appList.length) % appList.length;
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
    }

    function selectWorkspace(workspaceId) {
        return false;
    }

    function activateSelected() {
        if (selectedIndex >= 0 && selectedIndex < appList.length)
            requestFocusApp(appList[selectedIndex]);
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

        Text {
            anchors.centerIn: parent
            visible: root.appList.length === 0
            text: "No open windows"
            color: Theme.on_surface_variant
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Flow {
            anchors.centerIn: parent
            width: root.panelWidth - root.paddingH * 2
            spacing: root.iconSpacing
            visible: root.appList.length > 0

            Repeater {
                model: root.appList

                delegate: AppStripIcon {
                    required property var modelData
                    required property int index

                    appData: modelData
                    selected: index === root.selectedIndex
                    iconSize: root.iconSize
                    onClicked: root.requestFocusApp(modelData)
                }
            }
        }
    }
}
