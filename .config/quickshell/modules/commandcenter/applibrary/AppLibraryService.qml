// modules/commandcenter/applibrary/AppLibraryService.qml
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../../overview/services"
import "../../spotlight"
import "../powermenu"
import "../wallpapers"

Singleton {
    id: svc

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string catalogScript: Qt.resolvedUrl("apps-catalog.sh").toString().replace("file://", "")
    readonly property string catalogCacheFile: homeDir + "/.config/cloud-center/settings/quickshell/app_catalog.json"
    readonly property string recentsFile: homeDir + "/.config/cloud-center/settings/quickshell/app_recents.json"
    readonly property int debounceMs: 120
    readonly property int maxRecents: 8
    readonly property int gridColumns: 5
    readonly property int visibleRows: 4

    property bool visible: false
    property bool keyboardGrab: false
    property string query: ""
    property int selectedIndex: -1
    property var catalog: []
    property var categoryLabels: ["All"]
    property string activeCategory: "All"
    property var filteredApps: []
    property var recentIds: []
    property var recentEntries: []
    property bool catalogLoaded: false
    property bool catalogLoading: false
    property bool returnToCommandCenter: false
    property string commandCenterReturnMode: "command"
    property var commandCenterReturnBrowseStack: []
    property bool windowPickerOpen: false
    property var windowPickerWindows: []
    property var windowPickerApp: null

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

    function appById(id) {
        for (let i = 0; i < catalog.length; i++) {
            if (catalog[i].id === id)
                return catalog[i];
        }
        return null;
    }

    function refreshRecentEntries() {
        const out = [];
        for (let i = 0; i < recentIds.length; i++) {
            const app = appById(recentIds[i]);
            if (app)
                out.push(app);
        }
        recentEntries = out;
    }

    function recentApps() {
        return recentEntries;
    }

    function isRunning(app) {
        if (!app)
            return false;
        return HyprlandData.isAppRunning(app.wmclass, app.exec);
    }

    function catalogAppForClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls || catalog.length === 0)
            return null;

        for (let i = 0; i < catalog.length; i++) {
            const app = catalog[i];
            if (`${app.id ?? ""}` === cls)
                return app;
            const wm = `${app.wmclass ?? ""}`.trim();
            if (wm.length > 0 && HyprlandData.wmclassesMatch(cls, wm))
                return app;
        }

        const lower = cls.toLowerCase();
        for (let i = 0; i < catalog.length; i++) {
            const app = catalog[i];
            const id = `${app.id ?? ""}`.toLowerCase();
            const wm = `${app.wmclass ?? ""}`.toLowerCase();
            if (lower === id || lower === wm)
                return app;
            if (lower.includes("nautilus") && (id.includes("nautilus") || wm.includes("nautilus")))
                return app;
            if (lower.includes("docker") && id.includes("docker"))
                return app;
        }

        if (HyprlandData.isMainBrowserClass(cls)) {
            const preferIds = ["google-chrome", "com.google.Chrome", "chromium", "microsoft-edge"];
            for (let i = 0; i < preferIds.length; i++) {
                const hit = appById(preferIds[i]);
                if (hit)
                    return hit;
            }
            for (let i = 0; i < catalog.length; i++) {
                const app = catalog[i];
                const id = `${app.id ?? ""}`.toLowerCase();
                const wm = `${app.wmclass ?? ""}`.toLowerCase();
                if (id.includes("chrome") || wm.includes("chrome"))
                    return app;
            }
        }

        return null;
    }

    function launchCatalogApp(app) {
        if (!app)
            return false;
        HyprDispatch.launchDesktopApp({
            desktopPath: app.desktopPath,
            exec: app.exec
        });
        return true;
    }

    function launchByClass(className, execFallback) {
        const cls = `${className ?? ""}`.trim();
        const app = catalogAppForClass(cls);
        if (launchCatalogApp(app))
            return true;

        if (Array.isArray(execFallback)) {
            HyprDispatch.launchDetached(["uwsm-app", "--"].concat(execFallback));
            return true;
        }

        const fb = typeof execFallback === "string" ? execFallback.trim() : "";
        const pwaExec = HyprlandData.chromePwaExecFromClass(cls);
        const execCandidate = fb || pwaExec;
        if (execCandidate.length > 0) {
            const parts = HyprDispatch.parseDesktopExec(execCandidate);
            if (parts.length > 0) {
                HyprDispatch.launchDetached(["uwsm-app", "--"].concat(parts));
                return true;
            }
        }

        const opts = HyprlandData.desktopLaunchOptionsForClass(cls, fb);
        if (opts.desktopPath.length > 0 || opts.exec.length > 0) {
            HyprDispatch.launchDesktopApp(opts);
            return true;
        }
        return false;
    }

    function appMatchesCategory(app, category) {
        if (category === "All")
            return true;
        const cats = app.categories || [];
        for (let i = 0; i < cats.length; i++) {
            if (cats[i] === category)
                return true;
        }
        return false;
    }

    function refreshFilteredApps() {
        const q = normalizeText(query);
        if (q.length > 0) {
            const out = [];
            for (let i = 0; i < catalog.length; i++) {
                const app = catalog[i];
                const hay = normalizeText([app.name, app.genericName, app.comment, app.id].join(" "));
                if (hay.indexOf(q) >= 0)
                    out.push(app);
            }
            filteredApps = out;
            selectedIndex = out.length > 0 ? 0 : -1;
            return;
        }

        const out = [];
        for (let i = 0; i < catalog.length; i++) {
            if (appMatchesCategory(catalog[i], activeCategory))
                out.push(catalog[i]);
        }
        filteredApps = out;
        selectedIndex = -1;
    }

    function setCategory(label) {
        activeCategory = label;
        refreshFilteredApps();
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
        if (PowerMenuService.visible)
            PowerMenuService.close();
        if (WallpaperPickerService.visible)
            WallpaperPickerService.close();
    }

    function openInternal() {
        closeOtherPanels();
        showPanel();
        query = "";
        activeCategory = "All";
        selectedIndex = -1;
        loadRecents();
        if (catalog.length === 0)
            catalogLoaded = false;
        loadCatalog();
        IconResolver.refreshIndex();
        refreshFilteredApps();
        requestFocus();
    }

    function showPanel() {
        hideTimer.stop();
        visible = true;
        keyboardGrab = true;
    }

    function finishClose() {
        closeWindowPicker();
        visible = false;
        query = "";
        selectedIndex = -1;
        returnToCommandCenter = false;
        commandCenterReturnBrowseStack = [];
    }

    function close() {
        keyboardGrab = false;
        if (!visible) {
            finishClose();
            return;
        }
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 80
        repeat: false
        onTriggered: svc.finishClose()
    }

    function escapePressed() {
        if (windowPickerOpen) {
            closeWindowPicker();
            return { commandCenter: false, closedPicker: true };
        }
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

    function loadRecents() {
        recentsProc.running = false;
        recentsProc.running = true;
    }

    function saveRecents() {
        const payload = JSON.stringify(recentIds);
        saveRecentsProc.running = false;
        saveRecentsProc.command = [
            "bash", "-c",
            "mkdir -p \"$(dirname '" + recentsFile.replace(/'/g, "'\\''") + "')\" && " +
            "printf '%s' '" + payload.replace(/'/g, "'\\''") + "' > '" + recentsFile.replace(/'/g, "'\\''") + "'"
        ];
        saveRecentsProc.running = true;
    }

    function pushRecent(id) {
        if (!id)
            return;
        let ids = recentIds.filter(x => x !== id);
        ids.unshift(id);
        if (ids.length > maxRecents)
            ids = ids.slice(0, maxRecents);
        recentIds = ids;
        refreshRecentEntries();
        saveRecents();
    }

    function runningWindowsForApp(app) {
        if (!app)
            return [];
        return HyprlandData.runningWindowsForClass(app.wmclass);
    }

    function closeWindowPicker() {
        windowPickerOpen = false;
        windowPickerWindows = [];
        windowPickerApp = null;
    }

    function choosePickerWindow(win) {
        if (win)
            HyprDispatch.focusWindow(win);
        if (windowPickerApp)
            pushRecent(windowPickerApp.id);
        closeWindowPicker();
        close();
    }

    function activateApp(app) {
        if (!app)
            return;
        if (!isRunning(app)) {
            launchCatalogApp(app);
            pushRecent(app.id);
            close();
            return;
        }

        const wins = runningWindowsForApp(app);
        if (wins.length === 1) {
            HyprDispatch.focusWindow(wins[0]);
            pushRecent(app.id);
            close();
            return;
        }

        if (wins.length > 1) {
            windowPickerWindows = wins;
            windowPickerApp = app;
            windowPickerOpen = true;
            return;
        }

        HyprDispatch.focusWindowForApp(app.wmclass, app.exec);
        pushRecent(app.id);
        close();
    }

    function activateIndex(idx) {
        if (idx < 0 || idx >= filteredApps.length)
            return;
        activateApp(filteredApps[idx]);
    }

    function refreshCategoryLabels() {
        const set = { All: true };
        for (let i = 0; i < catalog.length; i++) {
            const cats = catalog[i].categories || [];
            for (let c = 0; c < cats.length; c++)
                set[cats[c]] = true;
        }
        const labels = Object.keys(set).filter(k => k !== "All").sort();
        categoryLabels = ["All"].concat(labels);
    }

    function applyCatalogRows(rows) {
        if (rows.length === 0)
            console.warn("applibrary: catalog empty");
        catalog = rows;
        catalogLoaded = rows.length > 0;
        catalogLoading = false;
        refreshCategoryLabels();
        refreshRecentEntries();
        refreshFilteredApps();
    }

    function loadCatalog() {
        if (catalogLoading)
            return;
        catalogLoading = true;
        cacheCatalogProc.running = false;
        cacheCatalogProc.running = true;
    }

    Process {
        id: recentsProc
        running: false
        command: ["bash", "-c", "if [ -f \"" + svc.recentsFile + "\" ]; then cat \"" + svc.recentsFile + "\"; else echo '[]'; fi"]
        stdout: StdioCollector {
            id: recentsCollector
            onStreamFinished: {
                try {
                    const data = JSON.parse(recentsCollector.text.trim() || "[]");
                    svc.recentIds = Array.isArray(data) ? data : [];
                    svc.refreshRecentEntries();
                } catch (e) {
                    svc.recentIds = [];
                }
            }
        }
    }

    Process {
        id: saveRecentsProc
        running: false
    }

    function parseCatalogText(raw) {
        const rows = [];
        const text = `${raw ?? ""}`.trim();
        if (text.length === 0)
            return rows;
        try {
            const parsed = JSON.parse(text);
            if (Array.isArray(parsed)) {
                for (let i = 0; i < parsed.length; i++)
                    rows.push(parsed[i]);
                return rows;
            }
        } catch (e) {
        }
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line)
                continue;
            try {
                rows.push(JSON.parse(line));
            } catch (err) {
                console.warn("applibrary: bad catalog json", line);
            }
        }
        return rows;
    }

    Process {
        id: cacheCatalogProc
        running: false
        command: ["bash", "-c", "if [ -f \"" + svc.catalogCacheFile + "\" ]; then cat \"" + svc.catalogCacheFile + "\"; fi"]
        stdout: StdioCollector {
            id: cacheCatalogCollector
            onStreamFinished: {
                const rows = svc.parseCatalogText(cacheCatalogCollector.text);
                if (rows.length > 0)
                    svc.applyCatalogRows(rows);
                catalogProc.running = false;
                catalogProc.running = true;
            }
        }
    }

    Process {
        id: catalogProc
        running: false
        command: ["bash", svc.catalogScript, "list"]
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("applibrary: catalog script failed", exitCode, exitStatus);
                svc.catalogLoading = false;
            }
        }
        stdout: StdioCollector {
            id: catalogCollector
            onStreamFinished: {
                const rows = svc.parseCatalogText(catalogCollector.text);
                svc.applyCatalogRows(rows);
            }
        }
    }

    Component.onCompleted: {
        loadRecents();
        loadCatalog();
    }

    Timer {
        id: debounce
        interval: svc.debounceMs
        repeat: false
        onTriggered: svc.refreshFilteredApps()
    }

    onQueryChanged: {
        if (!visible)
            return;
        if (query.trim().length === 0)
            refreshFilteredApps();
        else
            debounce.restart();
    }
}
