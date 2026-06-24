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
    property string systemIconTheme: "Fluent-green"
    property string homeDir: ""
    property string genericIconSource: {
        const themed = Quickshell.iconPath("application-default-icon", "");
        if (themed && `${themed}`.length > 0)
            return themed;
        return "file:///usr/share/icons/Fluent-green/scalable/apps/application-default-icon.svg";
    }
    property int maxIconSourcesPerWindow: 32
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
        if (cacheObjectSize(iconSourcesByNameCache) > 512)
            iconSourcesByNameCache = {};
        if (cacheObjectSize(iconSourcesByWindowCache) > 512)
            iconSourcesByWindowCache = {};
    }

    function directIconSource(iconName) {
        const normalized = normalizeIconName(iconName);
        if (normalized.startsWith("/"))
            return `file://${normalized}`;
        if (normalized.startsWith("~")) {
            const home = `${root.homeDir ?? ""}`.trim();
            if (home.length > 0)
                return `file://${home}${normalized.substring(1)}`;
        }
        return "";
    }

    function pushThemedIconSource(sources, iconName) {
        const themed = Quickshell.iconPath(iconName, "");
        if (themed && `${themed}`.length > 0)
            pushUniqueSource(sources, themed);
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
        if (normalized === "steam-native" || normalized === "steam-launcher" || normalized === "steam-icon")
            return "steam";
        const steamApp = normalized.match(/^steam_app_(\d+)$/i);
        if (steamApp)
            return `steam_icon_${steamApp[1]}`;
        if (normalized === "md.obsidian.obsidian" || normalized === "appimagekit-obsidian")
            return "obsidian";
        if (normalized === "org.cloudyy.cloudcenter" || normalized.toLowerCase().endsWith("cloudcenter"))
            return "cloud-center";
        return normalized;
    }

    function pushCustomAppIconSources(sources, lookupName) {
        const home = `${root.homeDir ?? ""}`.trim();
        if (home.length === 0)
            return;

        for (const ext of ["svg", "png"])
            pushUniqueSource(sources, `file://${home}/.local/share/icons/cloudyy-apps/${lookupName}.${ext}`);

        pushUniqueSource(sources, `file://${home}/.local/share/pixmaps/${lookupName}.png`);
        pushUniqueSource(sources, `file://${home}/.local/share/pixmaps/${lookupName}.svg`);
        pushUniqueSource(sources, `file://${home}/.steam/steam/games/${lookupName}.png`);
        pushUniqueSource(sources, `file://${home}/.local/share/Steam/steam/games/${lookupName}.png`);
    }

    function pushThemeIconSources(sources, lookupName) {
        const themes = [];
        const active = `${root.systemIconTheme ?? ""}`.trim();
        if (active.length > 0)
            themes.push(active);
        for (const fallback of ["Fluent-green", "Fluent", "hicolor", "Adwaita"]) {
            if (!themes.includes(fallback))
                themes.push(fallback);
        }

        const iconRoots = [];
        const home = `${root.homeDir ?? ""}`.trim();
        if (home.length > 0) {
            iconRoots.push(`${home}/.local/share/icons`);
            iconRoots.push(`${home}/.icons`);
        }
        iconRoots.push("/usr/share/icons");

        for (const rootPath of iconRoots) {
            for (const theme of themes) {
                pushUniqueSource(sources, `file://${rootPath}/${theme}/scalable/apps/${lookupName}.svg`);
                pushUniqueSource(sources, `file://${rootPath}/${theme}/128x128/apps/${lookupName}.svg`);
                pushUniqueSource(sources, `file://${rootPath}/${theme}/128x128/apps/${lookupName}.png`);
            }
        }

        pushUniqueSource(sources, `file:///usr/share/pixmaps/${lookupName}.png`);
        pushUniqueSource(sources, `file:///usr/share/pixmaps/${lookupName}.svg`);
        pushCustomAppIconSources(sources, lookupName);
        if (lookupName === "co.anysphere.cursor")
            pushUniqueSource(sources, "file:///usr/share/pixmaps/co.anysphere.cursor.png");
    }

    function desktopEntryForClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return null;

        const entry = DesktopEntries.heuristicLookup(cls);
        if (entry)
            return entry;

        const lower = cls.toLowerCase();
        if (lower.includes("docker"))
            return DesktopEntries.heuristicLookup("docker-desktop")
                || DesktopEntries.heuristicLookup("Docker Desktop");
        if (lower.includes("cloudcenter"))
            return DesktopEntries.heuristicLookup("org.cloudyy.cloudcenter")
                || DesktopEntries.heuristicLookup("Cloud Center");

        if (cls.includes(".")) {
            const last = cls.split(".").pop();
            if (last && last !== cls)
                return DesktopEntries.heuristicLookup(last);
        }

        return null;
    }

    function iconCandidatesForWindow(window) {
        const entry = desktopEntryForClass(window?.class || window?.initialClass || window?.initialTitle);
        const candidates = [];
        const rawClass = `${window?.class ?? ""}`.trim();
        const rawInitialClass = `${window?.initialClass ?? ""}`.trim();
        const lowerClass = rawClass.toLowerCase();
        const lowerInitialClass = rawInitialClass.toLowerCase();

        const steamAppMatch = lowerClass.match(/^steam_app_(\d+)$/) ?? lowerInitialClass.match(/^steam_app_(\d+)$/);
        if (steamAppMatch)
            pushUnique(candidates, `steam_icon_${steamAppMatch[1]}`);

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

        if (lowerClass === "steam" || lowerInitialClass === "steam")
            pushUnique(candidates, "steam");

        if (lowerClass.includes("obsidian") || lowerInitialClass.includes("obsidian")) {
            pushUnique(candidates, "obsidian");
            pushUnique(candidates, "md.obsidian.Obsidian");
            pushUnique(candidates, "Obsidian");
        }

        if (lowerClass.includes("cloudcenter") || lowerInitialClass.includes("cloudcenter")) {
            pushUnique(candidates, "cloud-center");
            if (`${root.homeDir ?? ""}`.trim().length > 0)
                pushUnique(candidates, `${root.homeDir}/.local/share/icons/cloudyy-apps/cloud-center.svg`);
        }

        if (lowerClass.includes("docker") || lowerInitialClass.includes("docker")) {
            pushUnique(candidates, "docker-desktop");
            const dockerEntry = desktopEntryForClass("docker-desktop");
            pushUnique(candidates, dockerEntry?.icon);
        }

        pushUnique(candidates, "application-default-icon");
        return candidates;
    }

    function iconSourcesForName(iconName) {
        return IconResolver.sourcesForName(iconName);
    }

    function iconSourcesForAppData(appData) {
        const cls = `${appData?.class ?? ""}`.trim();
        const icon = `${appData?.icon ?? ""}`.trim();
        const entry = desktopEntryForClass(cls);
        const entryIcon = normalizeIconName(entry?.icon ?? "");
        const resolvedIcon = icon || entryIcon;
        const resolvedPath = resolvedIcon.startsWith("/") ? resolvedIcon : (entryIcon.startsWith("/") ? entryIcon : "");

        const sources = [];
        const appSources = IconResolver.sourcesForApp({
            icon: resolvedIcon,
            iconPath: resolvedPath,
            id: cls,
            wmclass: cls
        });
        for (let i = 0; i < appSources.length; i++)
            pushUniqueSource(sources, appSources[i]);

        if (appData?.window) {
            const winSources = iconSourcesForWindow(appData.window);
            for (let i = 0; i < winSources.length; i++)
                pushUniqueSource(sources, winSources[i]);
        }

        return sources.length > 0 ? sources : [root.genericIconSource];
    }

    function isAppRunning(wmclass, exec) {
        const needle = `${wmclass ?? ""}`.trim().toLowerCase();
        const execText = `${exec ?? ""}`;
        const steamMatch = execText.match(/steam:\/\/rungameid\/(\d+)/i);
        const steamClass = steamMatch ? `steam_app_${steamMatch[1]}`.toLowerCase() : "";
        const windows = root.windowList || [];
        for (let i = 0; i < windows.length; i++) {
            const cls = `${windows[i].class || windows[i].initialClass || ""}`.trim().toLowerCase();
            if (!cls)
                continue;
            if (needle && cls === needle)
                return true;
            if (steamClass && cls === steamClass)
                return true;
        }
        return false;
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
            const normalized = normalizeIconName(iconName);
            if (normalized.startsWith("/")) {
                pushUniqueSource(sources, `file://${normalized}`);
                if (sources.length >= root.maxIconSourcesPerWindow) {
                    root.iconSourcesByWindowCache[cacheKey] = sources;
                    maybeTrimIconCaches();
                    return sources;
                }
                continue;
            }
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
        command: ["bash", "-c", "theme=$(grep -m1 '^gtk-icon-theme-name=' \"$HOME/.config/gtk-3.0/settings.ini\" 2>/dev/null | cut -d= -f2- | tr -d '\\r'); if [[ -z \"$theme\" ]] && command -v gtk-query-settings >/dev/null 2>&1; then theme=$(gtk-query-settings 2>/dev/null | sed -n 's/.*gtk-icon-theme-name: \"\\(.*\\)\"/\\1/p' | head -n1); fi; if [[ -z \"$theme\" ]] && command -v gsettings >/dev/null 2>&1; then theme=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d \"'\"); fi; printf '%s\\n' \"${theme:-Fluent-green}\""]
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
