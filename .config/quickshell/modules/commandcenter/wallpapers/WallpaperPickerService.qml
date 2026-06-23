pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../spotlight"
import "../applibrary"
import "../powermenu"

Singleton {
    id: svc

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string listScript: Qt.resolvedUrl("../scripts/wallpapers.sh").toString().replace("file://", "")
    readonly property string cacheScript: Qt.resolvedUrl("../scripts/wallpapers-cache.sh").toString().replace("file://", "")
    readonly property string themeCtl: homeDir + "/cloudyy_scripts/theme_controller.sh"
    readonly property int gridColumns: 3
    readonly property int debounceMs: 120

    property bool visible: false
    property string query: ""
    property int selectedIndex: -1
    property string themeMode: "dark"
    property string currentPath: ""
    property var wallpapers: []
    property var filteredWallpapers: []
    property var wallpaperRows: []
    property bool loading: false
    property bool refreshing: false
    property bool returnToCommandCenter: false
    property string commandCenterReturnMode: "command"
    property var commandCenterReturnBrowseStack: []

    signal requestFocus()

    Component {
        id: procProto
        Process {}
    }

    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        const p = procProto.createObject(svc, { command: cmd });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function normalizeText(s) {
        return `${s ?? ""}`.toLowerCase().trim();
    }

    function openFromCommandCenter(returnMode, returnBrowseStack) {
        returnToCommandCenter = true;
        commandCenterReturnMode = returnMode || "command";
        commandCenterReturnBrowseStack = returnBrowseStack ? returnBrowseStack.slice() : [];
        openInternal();
    }

    function open() {
        returnToCommandCenter = false;
        commandCenterReturnBrowseStack = [];
        openInternal();
    }

    function closeOtherPanels() {
        if (SpotlightService.visible)
            SpotlightService.close();
        if (AppLibraryService.visible)
            AppLibraryService.close();
        if (PowerMenuService.visible)
            PowerMenuService.close();
    }

    function openInternal() {
        closeOtherPanels();
        visible = true;
        query = "";
        selectedIndex = -1;
        if (wallpapers.length > 0) {
            loading = false;
            refreshFiltered();
            refreshing = true;
            startFullRefresh();
        } else {
            loadWallpapers();
        }
        requestFocus();
    }

    function close() {
        visible = false;
        query = "";
        selectedIndex = -1;
        returnToCommandCenter = false;
        commandCenterReturnBrowseStack = [];
    }

    function escapePressed() {
        if (query.trim().length > 0) {
            query = "";
            return { commandCenter: false, clearedQuery: true };
        }
        if (returnToCommandCenter) {
            const mode = commandCenterReturnMode;
            const stack = commandCenterReturnBrowseStack.slice();
            close();
            return { commandCenter: true, mode: mode, browseStack: stack };
        }
        close();
        return { commandCenter: false };
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    function isCurrent(path) {
        if (!path || !currentPath)
            return false;
        return path === currentPath;
    }

    function rebuildRows() {
        const cols = gridColumns;
        const rows = [];
        for (let i = 0; i < filteredWallpapers.length; i += cols)
            rows.push(filteredWallpapers.slice(i, i + cols));
        wallpaperRows = rows;
    }

    function refreshFiltered() {
        const q = normalizeText(query);
        if (!q) {
            filteredWallpapers = wallpapers.slice();
        } else {
            const out = [];
            for (let i = 0; i < wallpapers.length; i++) {
                const w = wallpapers[i];
                const hay = normalizeText([w.label, w.path].join(" "));
                if (hay.indexOf(q) >= 0)
                    out.push(w);
            }
            filteredWallpapers = out;
        }
        if (filteredWallpapers.length > 0)
            selectedIndex = Math.min(Math.max(selectedIndex, 0), filteredWallpapers.length - 1);
        else
            selectedIndex = -1;
        rebuildRows();
    }

    function parseCatalogText(raw) {
        const text = `${raw ?? ""}`.trim();
        if (text.length === 0)
            return null;
        try {
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    function applyCatalog(payload) {
        if (!payload)
            return false;
        themeMode = payload.mode || "dark";
        currentPath = payload.current || "";
        const rows = payload.wallpapers || [];
        if (!Array.isArray(rows))
            return false;
        // Skip re-rendering the grid if the wallpaper set hasn't changed.
        // wallpapers.sh always re-runs as a background refresh; without this guard
        // the ListView would rebuild all delegates and reload images unnecessarily.
        if (wallpapers.length > 0 && rows.length === wallpapers.length) {
            const unchanged = rows.every((w, i) => wallpapers[i] && w.path === wallpapers[i].path && w.thumb === wallpapers[i].thumb);
            if (unchanged) {
                loading = false;
                return true;
            }
        }
        wallpapers = rows;
        loading = false;
        refreshFiltered();
        return rows.length > 0;
    }

    function loadWallpapers() {
        loading = wallpapers.length === 0;
        refreshing = true;
        cacheCatalogProc.running = false;
        cacheCatalogProc.running = true;
    }

    function startFullRefresh() {
        listProc.running = false;
        listProc.running = true;
    }

    function applyWallpaper(path) {
        if (!path)
            return;
        launch(["bash", themeCtl, "set-image", path]);
        currentPath = path;
        close();
    }

    function activateIndex(idx) {
        if (idx < 0 || idx >= filteredWallpapers.length)
            return;
        applyWallpaper(filteredWallpapers[idx].path);
    }

    Timer {
        id: queryDebounce
        interval: svc.debounceMs
        onTriggered: svc.refreshFiltered()
    }

    onQueryChanged: queryDebounce.restart()

    Process {
        id: cacheCatalogProc
        running: false
        command: ["bash", svc.cacheScript]
        stdout: StdioCollector {
            id: cacheCatalogOut
            onStreamFinished: {
                const payload = svc.parseCatalogText(cacheCatalogOut.text);
                if (payload)
                    svc.applyCatalog(payload);
                else if (svc.wallpapers.length === 0)
                    svc.loading = true;
                svc.startFullRefresh();
            }
        }
    }

    Process {
        id: listProc
        running: false
        command: ["bash", svc.listScript]
        stdout: StdioCollector {
            id: listOut
            onStreamFinished: {
                const text = listOut.text.trim();
                svc.refreshing = false;
                if (text.length === 0) {
                    svc.loading = false;
                    return;
                }
                try {
                    const payload = JSON.parse(text);
                    svc.applyCatalog(payload);
                } catch (e) {
                    console.warn("wallpapers: bad catalog json", e);
                    svc.loading = false;
                }
            }
        }
    }
}
