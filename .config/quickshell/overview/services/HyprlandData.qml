pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property string systemIconTheme: "Papirus-Dark"
    property string homeDir: ""
    readonly property string genericIconSource: "file:///usr/share/icons/Papirus/128x128/apps/application-default-icon.svg"
    property int maxIconSourcesPerWindow: 96
    property var iconSourcesByNameCache: ({})
    property var iconSourcesByWindowCache: ({})
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var windowsByWorkspace: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property bool pendingWindowsUpdate: false
    property bool pendingMonitorsUpdate: false
    property bool pendingWorkspacesUpdate: false
    property bool pendingActiveWorkspaceUpdate: false

    function updateWindowList() {
        getClients.running = true;
    }

    function updateMonitors() {
        getMonitors.running = true;
    }

    function updateWorkspaces() {
        getWorkspaces.running = true;
        getActiveWorkspace.running = true;
    }

    function updateAll() {
        scheduleUpdates(true, true, true, true);
    }

    function scheduleUpdates(windows, monitors, workspaces, activeWorkspace) {
        pendingWindowsUpdate = pendingWindowsUpdate || !!windows;
        pendingMonitorsUpdate = pendingMonitorsUpdate || !!monitors;
        pendingWorkspacesUpdate = pendingWorkspacesUpdate || !!workspaces;
        pendingActiveWorkspaceUpdate = pendingActiveWorkspaceUpdate || !!activeWorkspace;

        const debounceMs = Math.max(0, 50);
        if (debounceMs === 0) {
            flushPendingUpdates();
        } else {
            eventDebounceTimer.interval = debounceMs;
            eventDebounceTimer.restart();
        }
    }

    function flushPendingUpdates() {
        if (pendingWindowsUpdate) {
            pendingWindowsUpdate = false;
            updateWindowList();
        }
        if (pendingMonitorsUpdate) {
            pendingMonitorsUpdate = false;
            updateMonitors();
        }
        if (pendingWorkspacesUpdate) {
            pendingWorkspacesUpdate = false;
            getWorkspaces.running = true;
        }
        if (pendingActiveWorkspaceUpdate) {
            pendingActiveWorkspaceUpdate = false;
            getActiveWorkspace.running = true;
        }
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = root.windowsByWorkspace[workspaceId] ?? [];
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    function mostRecentWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = root.windowsByWorkspace[workspaceId] ?? [];
        return windowsInThisWorkspace.reduce((mostRecentWin, win) => {
            const currentHistory = mostRecentWin?.focusHistoryID ?? 999999;
            const nextHistory = win?.focusHistoryID ?? 999999;
            return nextHistory < currentHistory ? win : mostRecentWin;
        }, null);
    }

    function normalizeIconName(icon) {
        const raw = `${icon ?? ""}`.trim();
        const withoutProviderPrefix = raw.replace(/^image:\/\/icon\//, "");
        return withoutProviderPrefix.split("?")[0].trim();
    }

    function pushUnique(values, value) {
        const normalized = normalizeIconName(value);
        if (normalized.length === 0 || values.includes(normalized))
            return;
        values.push(normalized);
    }

    function pushUniqueSource(values, value) {
        const source = `${value ?? ""}`.trim();
        if (source.length === 0 || values.includes(source))
            return;
        values.push(source);
    }

    function clearIconCaches() {
        iconSourcesByNameCache = {};
        iconSourcesByWindowCache = {};
    }

    function parseJson(text, fallback, label) {
        const trimmed = `${text ?? ""}`.trim();
        if (trimmed.length === 0)
            return fallback;

        try {
            return JSON.parse(trimmed);
        } catch (err) {
            console.warn("hyprland-data: failed to parse", label, err);
            return fallback;
        }
    }

    function cacheObjectSize(cache) {
        return Object.keys(cache ?? {}).length;
    }

    function maybeTrimIconCaches() {
        if (cacheObjectSize(iconSourcesByNameCache) > 128)
            iconSourcesByNameCache = {};
        if (cacheObjectSize(iconSourcesByWindowCache) > 128)
            iconSourcesByWindowCache = {};
    }

    function resolveIconLookupName(iconName) {
        const normalized = normalizeIconName(iconName);
        if (normalized === "xfce-filemanager" || normalized === "thunar")
            return "org.xfce.thunar";
        if (normalized === "cursor")
            return "co.anysphere.cursor";
        if (normalized === "zen" || normalized === "zen-bin")
            return "zen-browser";
        if (normalized === "vesktop" || normalized === "dev.vencord.vesktop")
            return "dev.vencord.Vesktop";
        if (normalized === "dev.zed.zed" || normalized === "zeditor")
            return "dev.zed.Zed";
        return normalized;
    }

    function pushThemeIconSources(sources, lookupName) {
        const themes = [];
        const active = `${root.systemIconTheme ?? ""}`.trim();
        if (active.length > 0)
            themes.push(active);
        for (const fallback of ["hicolor", "Papirus-Dark", "Papirus"]) {
            if (!themes.includes(fallback))
                themes.push(fallback);
        }

        // Keep candidate list small — probing dozens of missing paths per icon stresses Qt on reload.
        const sizes = ["128x128", "64x64", "48x48"];
        const exts = ["svg", "png"];
        const iconRoots = ["/usr/share/icons"];

        for (const rootPath of iconRoots) {
            for (const theme of themes) {
                for (const size of sizes) {
                    for (const ext of exts)
                        pushUniqueSource(sources, `file://${rootPath}/${theme}/${size}/apps/${lookupName}.${ext}`);
                }
                pushUniqueSource(sources, `file://${rootPath}/${theme}/scalable/apps/${lookupName}.svg`);
            }
        }

        pushUniqueSource(sources, `file:///usr/share/pixmaps/${lookupName}.png`);
        pushUniqueSource(sources, `file:///usr/share/pixmaps/${lookupName}.svg`);
        if (lookupName === "co.anysphere.cursor")
            pushUniqueSource(sources, "file:///usr/share/pixmaps/co.anysphere.cursor.png");
    }

    function iconCandidatesForWindow(window) {
        const entry = DesktopEntries.heuristicLookup(window?.class || window?.initialClass || window?.initialTitle);
        const candidates = [];
        const rawClass = `${window?.class ?? ""}`.trim();
        const rawInitialClass = `${window?.initialClass ?? ""}`.trim();
        const lowerClass = rawClass.toLowerCase();
        const lowerInitialClass = rawInitialClass.toLowerCase();

        pushUnique(candidates, entry?.icon);
        pushUnique(candidates, rawClass);
        pushUnique(candidates, rawInitialClass);

        if (rawClass.includes(".")) {
            const classParts = rawClass.split(".");
            const lowerClassParts = lowerClass.split(".");
            pushUnique(candidates, classParts[classParts.length - 1]);
            pushUnique(candidates, lowerClassParts[lowerClassParts.length - 1]);
        }
        if (rawInitialClass.includes(".")) {
            const initialClassParts = rawInitialClass.split(".");
            const lowerInitialClassParts = lowerInitialClass.split(".");
            pushUnique(candidates, initialClassParts[initialClassParts.length - 1]);
            pushUnique(candidates, lowerInitialClassParts[lowerInitialClassParts.length - 1]);
        }

        if (lowerClass.includes("firefox"))
            pushUnique(candidates, "firefox");
        if (lowerClass.includes("kitty") || lowerClass.includes("terminal"))
            pushUnique(candidates, "terminal");
        if (lowerClass.includes("zed") || lowerInitialClass.includes("zed")) {
            pushUnique(candidates, "dev.zed.Zed");
            pushUnique(candidates, "zed");
        }
        if (lowerClass.includes("code"))
            pushUnique(candidates, "vscode");
        if (lowerClass.includes("spotify"))
            pushUnique(candidates, "spotify");
        if (lowerClass.includes("discord"))
            pushUnique(candidates, "discord");
        if (lowerClass.includes("vesktop") || lowerInitialClass.includes("vesktop")) {
            pushUnique(candidates, "dev.vencord.Vesktop");
            pushUnique(candidates, "vesktop");
        }
        if (lowerClass.includes("thunar") || lowerClass.includes("xfce"))
            pushUnique(candidates, "org.xfce.thunar");
        if (lowerClass.includes("curseforge"))
            pushUnique(candidates, "curseforge");
        if (lowerClass.includes("matlab"))
            pushUnique(candidates, "matlab");

        if (lowerClass.includes("zen"))
            pushUnique(candidates, "zen-browser");

        if (lowerClass.includes("freecad") || lowerInitialClass.includes("freecad"))
            pushUnique(candidates, "org.freecad.FreeCAD");

        pushUnique(candidates, "application-default-icon");
        return candidates;
    }

    function iconSourcesForName(iconName) {
        const normalized = normalizeIconName(iconName);
        if (normalized.length === 0)
            return [root.genericIconSource];
        const lookupName = resolveIconLookupName(normalized);

        if (normalized.startsWith("/"))
            return [`file://${normalized}`];

        if (normalized.startsWith("~"))
            return [`file://${root.homeDir}${normalized.substring(1)}`];

        const currentTheme = `${root.systemIconTheme ?? "Papirus-Dark"}`.trim() || "Papirus-Dark";
        const cacheKey = `${currentTheme}|${root.homeDir}|${normalized}`;
        if (root.iconSourcesByNameCache[cacheKey])
            return root.iconSourcesByNameCache[cacheKey];

        const sources = [];
        pushThemeIconSources(sources, lookupName);
        pushUniqueSource(sources, root.genericIconSource);
        root.iconSourcesByNameCache[cacheKey] = sources;
        maybeTrimIconCaches();
        return sources;
    }

    function iconSourcesForWindow(window) {
        const candidates = iconCandidatesForWindow(window);
        const cacheKey = candidates.join("|");
        if (root.iconSourcesByWindowCache[cacheKey])
            return root.iconSourcesByWindowCache[cacheKey];

        const sources = [];
        if (window && window.class && window.class.toLowerCase().includes("matlab"))
            return [`file://${root.homeDir}/.local/share/icons/matlab.png`];

        for (const iconName of candidates) {
            const candidateSources = iconSourcesForName(iconName);
            for (const source of candidateSources) {
                pushUniqueSource(sources, source);
                if (sources.length >= root.maxIconSourcesPerWindow) {
                    root.iconSourcesByWindowCache[cacheKey] = sources;
                    maybeTrimIconCaches();
                    return sources;
                }
            }
        }
        root.iconSourcesByWindowCache[cacheKey] = sources;
        maybeTrimIconCaches();
        return sources;
    }

    onSystemIconThemeChanged: clearIconCaches()
    onHomeDirChanged: clearIconCaches()

    Component.onCompleted: {
        scheduleUpdates(true, true, true, true);
        flushPendingUpdates();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            const eventName = `${event?.name ?? event?.event ?? event?.type ?? ""}`;
            if (["openlayer", "closelayer", "screencast"].includes(eventName))
                return;

            if (eventName === "openwindow" || eventName === "closewindow" || eventName === "movewindow" || eventName === "movewindowv2" || eventName === "windowtitle") {
                scheduleUpdates(true, false, true, false);
                return;
            }

            if (eventName === "workspace" || eventName === "workspacev2" || eventName === "focusedmon" || eventName === "focusedmonv2" || eventName === "activewindow" || eventName === "activewindowv2") {
                scheduleUpdates(eventName === "activewindow" || eventName === "activewindowv2", false, true, true);
                return;
            }

            if (eventName.startsWith("monitor") || eventName === "configreloaded") {
                scheduleUpdates(true, true, true, true);
                return;
            }

            scheduleUpdates(true, true, true, true);
        }
    }

    Timer {
        id: eventDebounceTimer
        interval: Math.max(0, 50)
        repeat: false
        onTriggered: root.flushPendingUpdates()
    }

    Process {
        id: getIconTheme
        command: ["bash", "-c", "grep '^gtk-icon-theme-name=' ~/.config/gtk-3.0/settings.ini | cut -d= -f2"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const themeName = line.trim();
                if (themeName.length > 0)
                    root.systemIconTheme = themeName;
            }
        }
    }

    Process {
        id: getHomeDir
        command: ["sh", "-c", "echo $HOME"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const h = line.trim();
                if (h.length > 0) root.homeDir = h;
            }
        }
    }

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                root.windowList = root.parseJson(clientsCollector.text, [], "clients");
                let tempWinByAddress = {};
                let tempWindowsByWorkspace = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                    const workspaceId = Number(win?.workspace?.id ?? -1);
                    if (Number.isFinite(workspaceId) && workspaceId > 0) {
                        if (!tempWindowsByWorkspace[workspaceId])
                            tempWindowsByWorkspace[workspaceId] = [];
                        tempWindowsByWorkspace[workspaceId].push(win);
                    }
                }
                root.windowByAddress = tempWinByAddress;
                root.windowsByWorkspace = tempWindowsByWorkspace;
                root.addresses = root.windowList.map(win => win.address);
            }
        }
    }

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                root.monitors = root.parseJson(monitorsCollector.text, [], "monitors");
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                const rawWorkspaces = root.parseJson(workspacesCollector.text, [], "workspaces");
                root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                let tempWorkspaceById = {};
                for (var i = 0; i < root.workspaces.length; ++i) {
                    var ws = root.workspaces[i];
                    tempWorkspaceById[ws.id] = ws;
                }
                root.workspaceById = tempWorkspaceById;
                root.workspaceIds = root.workspaces.map(ws => ws.id);
            }
        }
    }

    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            id: activeWorkspaceCollector
            onStreamFinished: {
                root.activeWorkspace = root.parseJson(activeWorkspaceCollector.text, root.activeWorkspace, "activeworkspace");
            }
        }
    }
}
