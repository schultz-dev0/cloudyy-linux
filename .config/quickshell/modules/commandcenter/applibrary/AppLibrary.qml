pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../.."
import "../../spotlight" as QuickSpotlight

PanelWindow {
    id: root

    readonly property var svc: AppLibraryService
    readonly property bool isSearchMode: svc.query.trim().length > 0
    // search | categories | grid
    property string focusZone: "search"
    property int categoryFocusIndex: 0
    readonly property int gridRowHeight: 84
    readonly property int gridRowSpacing: 4
    readonly property int panelPaddingH: 18
    readonly property int panelPaddingV: 6
    readonly property int gridViewportHeight: svc.visibleRows * gridRowHeight + (svc.visibleRows - 1) * gridRowSpacing
    readonly property int panelWidth: {
        const screens = Quickshell.screens;
        const sw = screens.length > 0 ? screens[0].width : 1920;
        return Math.min(700, Math.round(sw * 0.52));
    }
    readonly property int panelHeight: {
        if (isSearchMode) {
            const screens = Quickshell.screens;
            const sh = screens.length > 0 ? screens[0].height : 1080;
            return Math.min(480, Math.round(sh * 0.45));
        }
        let h = panelPaddingV * 2 + 40 + 8 + 36 + 8 + gridViewportHeight + 14;
        if (svc.recentEntries.length > 0)
            h += 100;
        return h;
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    visible: svc.visible
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:command"
    WlrLayershell.keyboardFocus: svc.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

    MouseArea {
        anchors.fill: parent
        visible: svc.visible
        onClicked: svc.close()
    }

    Item {
        id: panel
        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelHeight
        visible: svc.visible

        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.glassPanelRadius
            color: Theme.glassShell
            border.color: Theme.glassPanelBorder
            border.width: 1
            antialiasing: true
        }

        Column {
            anchors.fill: parent
            anchors.leftMargin: root.panelPaddingH
            anchors.rightMargin: root.panelPaddingH
            anchors.topMargin: root.panelPaddingV
            anchors.bottomMargin: root.panelPaddingV
            spacing: 0

            // Header / search
            Item {
                width: parent.width
                height: 40

                Text {
                    id: appSearchIcon
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    text: "󰀻"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 16
                    color: Theme.on_surface_variant
                }

                TextInput {
                    id: searchInput
                    anchors {
                        left: appSearchIcon.right
                        leftMargin: 10
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    height: 22
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.family: "JetBrainsMono Nerd Font"
                    verticalAlignment: TextInput.AlignVCenter
                    topPadding: Math.round((height - font.pixelSize) / 2)
                    bottomPadding: topPadding
                    selectByMouse: true
                    text: svc.query
                        onTextChanged: {
                            if (svc.query !== text)
                                svc.query = text;
                        }
                        Keys.onEscapePressed: {
                            root.handleEscape();
                            event.accepted = true;
                        }
                        Keys.onTabPressed: {
                            if (!root.isSearchMode) {
                                root.focusCategories(false);
                                event.accepted = true;
                            }
                        }
                        Keys.onBacktabPressed: {
                            if (!root.isSearchMode) {
                                root.focusCategories(true);
                                event.accepted = true;
                            }
                        }
                        Keys.onUpPressed: {
                            if (root.isSearchMode)
                                root.moveListSelection(-1);
                            else if (root.focusZone === "grid")
                                root.moveGrid(0, -1);
                            event.accepted = true;
                        }
                        Keys.onDownPressed: {
                            if (root.isSearchMode)
                                root.moveListSelection(1);
                            else if (root.focusZone === "search")
                                root.focusCategories(false);
                            else if (root.focusZone === "categories")
                                root.focusGrid();
                            else
                                root.moveGrid(0, 1);
                            event.accepted = true;
                        }
                        Keys.onLeftPressed: {
                            if (!root.isSearchMode && root.focusZone === "grid")
                                root.moveGrid(-1, 0);
                            event.accepted = true;
                        }
                        Keys.onRightPressed: {
                            if (!root.isSearchMode && root.focusZone === "grid")
                                root.moveGrid(1, 0);
                            event.accepted = true;
                        }
                        Keys.onReturnPressed: {
                            root.activateSelection();
                            event.accepted = true;
                        }
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 26
                        verticalCenter: parent.verticalCenter
                    }
                    visible: searchInput.text.length === 0 && !searchInput.activeFocus
                    text: "Applications"
                    color: Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.55)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.18)
            }

            // Body
            Item {
                id: body
                width: parent.width
                height: parent.height - 40

                FocusScope {
                    id: keyNav
                    anchors.fill: parent
                    focus: root.focusZone !== "search"

                    Keys.onTabPressed: event => {
                        if (root.isSearchMode)
                            return;
                        if (root.focusZone === "grid")
                            root.focusCategories(false);
                        else
                            root.stepCategory(1);
                        event.accepted = true;
                    }
                    Keys.onBacktabPressed: event => {
                        if (root.isSearchMode)
                            return;
                        if (root.focusZone === "grid")
                            root.focusCategories(false);
                        if (root.focusZone === "categories")
                            root.stepCategory(-1);
                        event.accepted = true;
                    }
                    Keys.onPressed: event => {
                        if (root.handleTypingKey(event))
                            event.accepted = true;
                    }
                    Keys.onLeftPressed: event => {
                        if (root.focusZone === "grid")
                            root.moveGrid(-1, 0);
                        event.accepted = true;
                    }
                    Keys.onRightPressed: event => {
                        if (root.focusZone === "grid")
                            root.moveGrid(1, 0);
                        event.accepted = true;
                    }
                    Keys.onUpPressed: event => {
                        if (root.focusZone === "grid")
                            root.moveGrid(0, -1);
                        event.accepted = true;
                    }
                    Keys.onDownPressed: event => {
                        if (root.focusZone === "categories")
                            root.focusGrid();
                        else if (root.focusZone === "grid")
                            root.moveGrid(0, 1);
                        event.accepted = true;
                    }
                    Keys.onReturnPressed: event => {
                        root.activateSelection();
                        event.accepted = true;
                    }
                    Keys.onEscapePressed: event => {
                        root.handleEscape();
                        event.accepted = true;
                    }
                }

                RecentRow {
                    id: recentRow
                    anchors.top: parent.top
                    width: parent.width
                    visible: !root.isSearchMode && svc.recentEntries.length > 0
                    apps: svc.recentEntries
                    isRunningFunc: app => svc.isRunning(app)
                    onAppActivated: app => svc.activateApp(app)
                }

                CategoryPills {
                    id: pills
                    anchors {
                        top: recentRow.visible ? recentRow.bottom : parent.top
                        topMargin: recentRow.visible ? 6 : 10
                    }
                    width: parent.width
                    visible: !root.isSearchMode
                    labels: svc.categoryLabels
                    activeLabel: svc.activeCategory
                    keyboardFocusIndex: root.focusZone === "categories" ? root.categoryFocusIndex : -1
                    onCategorySelected: label => {
                        root.syncCategoryFocus(label);
                        svc.setCategory(label);
                    }
                }

                // Browse grid (Repeater — GridView mishandles JS array models in Qt6)
                Flickable {
                    id: appFlick
                    anchors {
                        top: pills.bottom
                        topMargin: 8
                        left: parent.left
                        right: parent.right
                    }
                    height: root.gridViewportHeight
                    visible: !root.isSearchMode
                    clip: true
                    contentWidth: width
                    contentHeight: appGrid.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    readonly property int gridCellWidth: Math.max(1, Math.floor(width / svc.gridColumns))

                    Grid {
                        id: appGrid
                        width: parent.width
                        columns: svc.gridColumns
                        rowSpacing: root.gridRowSpacing
                        columnSpacing: 0

                        Repeater {
                            model: svc.filteredApps
                            delegate: AppIconCell {
                                required property var modelData
                                required property int index
                                appData: modelData
                                running: svc.isRunning(modelData)
                                cellWidth: appFlick.gridCellWidth
                                selected: root.focusZone === "grid" && svc.selectedIndex === index
                                onActivated: svc.activateApp(modelData)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: svc.filteredApps.length === 0 && !svc.catalogLoading
                        text: svc.catalogLoading ? "Loading applications…" : "No applications"
                        color: Theme.on_surface_variant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }

                // Search list
                Flickable {
                    id: searchFlick
                    anchors.fill: parent
                    anchors.topMargin: 8
                    visible: root.isSearchMode
                    clip: true
                    contentWidth: width
                    contentHeight: searchCol.height
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: searchCol
                        width: parent.width

                        Repeater {
                            model: svc.filteredApps
                            delegate: QuickSpotlight.SpotlightRow {
                                required property var modelData
                                required property int index
                                resultData: {
                                    const running = svc.isRunning(modelData);
                                    return {
                                        type: "app",
                                        name: modelData.name,
                                        exec: modelData.genericName || modelData.comment || "",
                                        icon: modelData.icon,
                                        iconPath: modelData.iconPath,
                                        wmclass: modelData.wmclass,
                                        isRunning: running
                                    };
                                }
                                isSelected: svc.selectedIndex >= 0 && index === svc.selectedIndex
                                rowWidth: root.panelWidth
                                onActivated: svc.activateApp(modelData)
                                onHovered: svc.selectedIndex = index
                            }
                        }

                        Text {
                            visible: svc.filteredApps.length === 0
                            width: parent.width - 32
                            anchors.horizontalCenter: parent.horizontalCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: "No matching applications"
                            color: Theme.on_surface_variant
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            topPadding: 16
                        }
                    }
                }
            }
        }
    }

    function syncCategoryFocus(label) {
        const idx = svc.categoryLabels.indexOf(label);
        categoryFocusIndex = idx >= 0 ? idx : 0;
    }

    function focusSearch() {
        focusZone = "search";
        categoryFocusIndex = -1;
        searchInput.forceActiveFocus();
    }

    function focusCategories(backward) {
        if (isSearchMode)
            return;
        focusZone = "categories";
        syncCategoryFocus(svc.activeCategory);
        if (backward)
            stepCategory(-1);
        else
            keyNav.forceActiveFocus();
    }

    function focusGrid() {
        if (isSearchMode)
            return;
        focusZone = "grid";
        categoryFocusIndex = -1;
        if (svc.filteredApps.length > 0 && svc.selectedIndex < 0)
            svc.selectedIndex = 0;
        keyNav.forceActiveFocus();
        ensureGridCellVisible(svc.selectedIndex);
    }

    function stepCategory(delta) {
        const labels = svc.categoryLabels;
        if (labels.length === 0)
            return;
        focusZone = "categories";
        let idx = categoryFocusIndex;
        if (idx < 0)
            idx = labels.indexOf(svc.activeCategory);
        if (idx < 0)
            idx = 0;
        idx = (idx + delta + labels.length) % labels.length;
        categoryFocusIndex = idx;
        svc.setCategory(labels[idx]);
        keyNav.forceActiveFocus();
    }

    function moveListSelection(delta) {
        const max = svc.filteredApps.length - 1;
        if (max < 0) {
            svc.selectedIndex = -1;
            return;
        }
        const next = svc.selectedIndex + delta;
        if (next < 0)
            svc.selectedIndex = -1;
        else if (next > max)
            svc.selectedIndex = max;
        else
            svc.selectedIndex = next;
        if (svc.selectedIndex < 0)
            focusSearch();
        else
            ensureSearchRowVisible(svc.selectedIndex);
    }

    function moveGrid(dx, dy) {
        const cols = svc.gridColumns;
        const count = svc.filteredApps.length;
        if (count === 0)
            return;

        let idx = svc.selectedIndex < 0 ? 0 : svc.selectedIndex;
        let row = Math.floor(idx / cols);
        let col = idx % cols;

        if (dx !== 0) {
            const rowStart = row * cols;
            const rowEnd = Math.min(rowStart + cols - 1, count - 1);
            const nextCol = col + dx;
            if (nextCol >= 0 && rowStart + nextCol <= rowEnd)
                idx = rowStart + nextCol;
        }

        if (dy !== 0) {
            const nextRow = row + dy;
            const maxRow = Math.floor((count - 1) / cols);
            if (nextRow < 0) {
                focusCategories(false);
                return;
            }
            if (nextRow <= maxRow) {
                const nextIdx = idx + dy * cols;
                if (nextIdx < count)
                    idx = nextIdx;
                else if (dy > 0)
                    idx = count - 1;
            }
        }

        focusZone = "grid";
        svc.selectedIndex = idx;
        ensureGridCellVisible(idx);
    }

    function ensureGridCellVisible(index) {
        if (index < 0)
            return;
        const row = Math.floor(index / svc.gridColumns);
        const cellTop = row * (gridRowHeight + gridRowSpacing);
        const cellBottom = cellTop + gridRowHeight;
        const viewTop = appFlick.contentY;
        const viewBottom = viewTop + appFlick.height;
        if (cellTop < viewTop)
            appFlick.contentY = Math.max(0, cellTop);
        else if (cellBottom > viewBottom)
            appFlick.contentY = Math.max(0, cellBottom - appFlick.height);
    }

    function ensureSearchRowVisible(index) {
        if (index < 0)
            return;
        const rowTop = index * 46;
        const rowBottom = rowTop + 46;
        const viewTop = searchFlick.contentY;
        const viewBottom = viewTop + searchFlick.height;
        if (rowTop < viewTop)
            searchFlick.contentY = Math.max(0, rowTop);
        else if (rowBottom > viewBottom)
            searchFlick.contentY = Math.max(0, rowBottom - searchFlick.height);
    }

    function activateSelection() {
        if (focusZone === "categories") {
            focusGrid();
            return;
        }
        if (svc.selectedIndex >= 0)
            svc.activateIndex(svc.selectedIndex);
    }

    function handleEscape() {
        if (!isSearchMode) {
            if (focusZone === "grid") {
                focusCategories(false);
                return;
            }
            if (focusZone === "categories") {
                focusSearch();
                return;
            }
        }
        const result = svc.escapePressed();
        if (result.commandCenter)
            QuickSpotlight.SpotlightService.restoreFromAppLibrary(result.mode, result.browseStack);
        else
            searchInput.text = svc.query;
        if (result.clearedQuery)
            focusSearch();
    }

    function moveSelection(delta) {
        moveListSelection(delta);
    }

    function isTextKey(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return false;
        const t = `${event.text ?? ""}`;
        return t.length > 0 && t.charCodeAt(0) >= 0x20;
    }

    function appendToSearch(chunk) {
        focusSearch();
        const next = svc.query + chunk;
        searchInput.text = next;
        svc.query = next;
    }

    function handleTypingKey(event) {
        if (searchInput.activeFocus)
            return false;

        if (event.key === Qt.Key_Backspace) {
            focusSearch();
            if (svc.query.length > 0) {
                const next = svc.query.slice(0, -1);
                searchInput.text = next;
                svc.query = next;
            }
            return true;
        }

        if (isTextKey(event)) {
            appendToSearch(event.text);
            return true;
        }

        return false;
    }

    Connections {
        target: svc
        function onRequestFocus() {
            root.focusSearch();
        }
        function onVisibleChanged() {
            if (svc.visible) {
                searchInput.text = svc.query;
                root.focusZone = "search";
                root.categoryFocusIndex = 0;
                Qt.callLater(() => root.focusSearch());
            } else {
                searchInput.text = "";
                root.focusZone = "search";
            }
        }
        function onQueryChanged() {
            if (searchInput.text !== svc.query)
                searchInput.text = svc.query;
            if (svc.query.trim().length > 0)
                root.focusZone = "search";
        }
        function onSelectedIndexChanged() {
            if (!svc.visible)
                return;
            if (root.isSearchMode)
                root.ensureSearchRowVisible(svc.selectedIndex);
            else if (root.focusZone === "grid")
                root.ensureGridCellVisible(svc.selectedIndex);
        }
    }

    IpcHandler {
        target: "applibrary"
        function open() {
            svc.open();
        }
        function hide() {
            svc.close();
        }
        function toggle() {
            svc.toggle();
        }
    }
}
