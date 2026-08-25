pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../.."
import "../../spotlight" as QuickSpotlight

PanelWindow {
    id: root

    readonly property var svc: WallpaperPickerService
    property string focusZone: "search"
    readonly property int gridColumns: svc.gridColumns
    readonly property int gridRowHeight: 176
    readonly property int gridRowSpacing: 10
    readonly property int visibleRows: 3
    readonly property int gridViewportHeight: visibleRows * gridRowHeight + (visibleRows - 1) * gridRowSpacing
    readonly property int panelWidth: {
        const screens = Quickshell.screens;
        const sw = screens.length > 0 ? screens[0].width : 1920;
        return Math.min(580, Math.round(sw * 0.48));
    }
    readonly property int panelHeight: 48 + 1 + 40 + 8 + gridViewportHeight + 14

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    visible: svc.visible
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:command"
    WlrLayershell.keyboardFocus: svc.keyboardGrab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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

        // Resin material — real theme-hue tint, not neutral glass. See
        // Theme.qml's resin() comment for the keycap reasoning.
        Rectangle {
            id: panelShell
            anchors.fill: parent
            radius: 0
            color: Theme.resin(Theme.resinFillAlpha)
            border.width: 1
            border.color: Theme.resinBorder
            antialiasing: true
            clip: true

            // Gloss — light catching the material's upper edge.
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: parent.height * 0.4
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.resinGloss }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            // Inner glow — a hint of structure beneath the material.
            // Corner-anchored with the center pushed past the edge (clipped
            // by panelShell) so it never lands under a grid row.
            Rectangle {
                width: parent.width * 0.3
                height: width
                radius: width / 2
                anchors {
                    left: parent.left
                    bottom: parent.bottom
                    leftMargin: -width * 0.5
                    bottomMargin: -height * 0.5
                }
                color: Theme.resinGlow
                opacity: 0.5
                layer.enabled: true
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 80 }
            }
        }

        FocusScope {
            id: keyNav
            anchors.fill: parent
            anchors.margins: 2
            focus: true

            Keys.onDownPressed: event => {
                if (focusZone === "search")
                    focusGrid();
                else
                    moveGrid(0, 1);
                event.accepted = true;
            }
            Keys.onUpPressed: event => {
                if (focusZone === "grid")
                    moveGrid(0, -1);
                event.accepted = true;
            }
            Keys.onLeftPressed: event => {
                if (focusZone === "grid")
                    moveGrid(-1, 0);
                event.accepted = true;
            }
            Keys.onRightPressed: event => {
                if (focusZone === "grid")
                    moveGrid(1, 0);
                event.accepted = true;
            }
            Keys.onReturnPressed: event => {
                activateSelection();
                event.accepted = true;
            }
            Keys.onEscapePressed: event => {
                handleEscape();
                event.accepted = true;
            }

            Column {
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 48

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 16
                            rightMargin: 16
                        }
                        spacing: 10

                        Text {
                            text: "󰸉"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                            color: Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Wallpapers"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        anchors {
                            right: parent.right
                            rightMargin: 16
                            verticalCenter: parent.verticalCenter
                        }
                        text: svc.themeMode === "light" ? "Light mode" : "Dark mode"
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.hairline
                }

                Item {
                    width: parent.width
                    height: 40

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 16
                            verticalCenter: parent.verticalCenter
                        }
                        text: "󰍉"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        color: Theme.textMuted
                    }

                    TextInput {
                        id: searchInput
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 36
                            rightMargin: 16
                        }
                        text: svc.query
                        color: Theme.text
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        selectByMouse: true
                        clip: true
                        onTextChanged: svc.query = text
                        onActiveFocusChanged: if (activeFocus)
                            root.focusZone = "search"
                    }
                }

                Item {
                    width: parent.width
                    height: root.gridViewportHeight + 8

                        ListView {
                        id: wallList
                        anchors {
                            top: parent.top
                            topMargin: 8
                            left: parent.left
                            right: parent.right
                        }
                        height: root.gridViewportHeight
                        clip: true
                        model: svc.wallpaperRows
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: root.gridRowHeight
                        spacing: root.gridRowSpacing

                        delegate: Item {
                            id: rowItem
                            width: wallList.width
                            height: root.gridRowHeight

                            required property int index
                            required property var modelData

                            readonly property int rowIndex: index
                            readonly property var rowData: modelData
                            readonly property int cellWidth: Math.max(1, Math.floor(width / root.gridColumns))

                            Row {
                                Repeater {
                                    model: rowItem.rowData
                                    delegate: WallpaperCell {
                                        required property var modelData
                                        required property int index
                                        readonly property int flatIndex: rowItem.rowIndex * root.gridColumns + index
                                        label: modelData.label
                                        imagePath: modelData.thumb || modelData.path
                                        selected: root.focusZone === "grid" && svc.selectedIndex === flatIndex
                                        isCurrent: svc.isCurrent(modelData.path)
                                        cellWidth: rowItem.cellWidth
                                        onActivated: svc.activateIndex(flatIndex)
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: svc.filteredWallpapers.length === 0
                            text: (svc.loading || svc.refreshing) ? "Loading wallpapers…" : "No wallpapers found"
                            color: Theme.textMuted
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

    function focusSearch() {
        focusZone = "search";
        searchInput.forceActiveFocus();
    }

    function focusGrid() {
        focusZone = "grid";
        if (svc.filteredWallpapers.length > 0 && svc.selectedIndex < 0)
            svc.selectedIndex = 0;
        keyNav.forceActiveFocus();
        ensureGridCellVisible(svc.selectedIndex);
    }

    function moveGrid(dx, dy) {
        const cols = gridColumns;
        const count = svc.filteredWallpapers.length;
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
                focusSearch();
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
        const row = Math.floor(index / gridColumns);
        wallList.positionViewAtIndex(row, ListView.Beginning);
    }

    function activateSelection() {
        if (focusZone === "search") {
            focusGrid();
            return;
        }
        if (svc.selectedIndex >= 0)
            svc.activateIndex(svc.selectedIndex);
    }

    function handleEscape() {
        if (focusZone === "grid") {
            focusSearch();
            return;
        }
        const result = svc.escapePressed();
        if (result.commandCenter)
            QuickSpotlight.SpotlightService.restoreFromAppLibrary(result.mode, result.browseStack);
        else
            searchInput.text = svc.query;
        if (result.clearedQuery)
            focusSearch();
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

    Connections {
        target: svc
        function onRequestFocus() {
            keyNav.forceActiveFocus();
            focusSearch();
        }
        function onVisibleChanged() {
            if (svc.visible)
                Qt.callLater(() => focusSearch());
        }
    }

    IpcHandler {
        target: "wallpapers"
        function open() { svc.open(); }
        function hide() { svc.close(); }
        function toggle() { svc.toggle(); }
    }
}
