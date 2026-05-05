pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../common"

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    property string systemIconTheme: "Papirus-Dark"
    property string homeDir: ""
    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var allWorkspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})
    property bool pendingWindowsUpdate: false
    property bool pendingMonitorsUpdate: false
    property bool pendingLayersUpdate: false
    property bool pendingWorkspacesUpdate: false
    property bool pendingActiveWorkspaceUpdate: false

    function updateWindowList() {
        getClients.running = true;
    }

    function updateLayers() {
        getLayers.running = true;
    }

    function updateMonitors() {
        getMonitors.running = true;
    }

    function updateWorkspaces() {
        getWorkspaces.running = true;
        getActiveWorkspace.running = true;
    }

    function updateAll() {
        scheduleUpdates(true, true, true, true, true);
    }

    function scheduleUpdates(windows, monitors, layers, workspaces, activeWorkspace) {
        pendingWindowsUpdate = pendingWindowsUpdate || !!windows;
        pendingMonitorsUpdate = pendingMonitorsUpdate || !!monitors;
        pendingLayersUpdate = pendingLayersUpdate || !!layers;
        pendingWorkspacesUpdate = pendingWorkspacesUpdate || !!workspaces;
        pendingActiveWorkspaceUpdate = pendingActiveWorkspaceUpdate || !!activeWorkspace;

        const debounceMs = Math.max(0, Config.options.hacks.hyprlandEventDebounceMs);
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
        if (pendingLayersUpdate) {
            pendingLayersUpdate = false;
            updateLayers();
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
        const windowsInThisWorkspace = HyprlandData.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    function mostRecentWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = root.windowList.filter(win => (win?.workspace?.id ?? -1) === workspaceId);
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
        if (lowerClass.includes("thunar"))
            pushUnique(candidates, "thunar");
        if (lowerClass.includes("matlab"))
            pushUnique(candidates, "matlab");

        if (lowerClass.includes("zen"))
            pushUnique(candidates, "zen-browser");

        if (lowerClass.includes("freecad") || lowerInitialClass.includes("freecad"))
            pushUnique(candidates, "org.freecad.FreeCAD");

        pushUnique(candidates, "application-x-executable");
        return candidates;
    }

    function iconSourcesForName(iconName) {
        const normalized = normalizeIconName(iconName);
        if (normalized.length === 0)
            return ["image://icon/application-x-executable"];

        if (normalized.startsWith("/"))
            return [`file://${normalized}`];

        if (normalized.startsWith("~"))
            return [`file://${root.homeDir}${normalized.substring(1)}`];

        const currentTheme = `${root.systemIconTheme ?? "Papirus-Dark"}`.trim() || "Papirus-Dark";
        const strippedTheme = currentTheme.replace(/-(Dark|Light)$/i, "");
        const themeNames = [];
        [currentTheme, strippedTheme, "Papirus-Dark", "Papirus", "Papirus-Light", "hicolor"].forEach(theme => pushUnique(themeNames, theme));

        const directories = [
            "48x48/apps",
            "scalable/apps",
            "64x64/apps",
            "32x32/apps",
            "24x24/apps",
            "16x16/apps",
            "128x128/apps",
            "256x256/apps",
            "48x48/devices",
            "scalable/devices",
            "48x48/places",
            "scalable/places",
            "48x48/categories",
            "scalable/categories"
        ];

        const sources = [];

        for (const theme of themeNames) {
            for (const directory of directories) {
                sources.push(`file:///usr/share/icons/${theme}/${directory}/${normalized}.svg`);
                sources.push(`file:///usr/share/icons/${theme}/${directory}/${normalized}.png`);
            }
        }
        // pixmaps fallback
        sources.push(`file:///usr/share/pixmaps/${normalized}.svg`);
        sources.push(`file:///usr/share/pixmaps/${normalized}.png`);
        // user icon dirs
        if (root.homeDir.length > 0) {
            sources.push(`file://${root.homeDir}/.local/share/icons/${normalized}.svg`);
            sources.push(`file://${root.homeDir}/.local/share/icons/${normalized}.png`);
            sources.push(`file://${root.homeDir}/.icons/${normalized}.svg`);
            sources.push(`file://${root.homeDir}/.icons/${normalized}.png`);
        }
        sources.push(Quickshell.iconPath(normalized, "image://icon/application-x-executable"));
        sources.push("image://icon/application-x-executable");
        return sources;
    }

    function iconSourcesForWindow(window) {
        const candidates = iconCandidatesForWindow(window);
        const sources = [];
        if (window && window.class && window.class.toLowerCase().includes("matlab")) return ["file:///home/schultz/.local/share/icons/matlab.png"];
        for (const iconName of candidates) {
            const candidateSources = iconSourcesForName(iconName);
            for (const source of candidateSources)
                sources.push(source);
        }
        return sources;
    }

    Component.onCompleted: {
        scheduleUpdates(true, true, true, true, true);
        flushPendingUpdates();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            const eventName = `${event?.name ?? event?.event ?? event?.type ?? ""}`;
            if (["openlayer", "closelayer", "screencast"].includes(eventName))
                return;

            if (eventName === "openwindow" || eventName === "closewindow" || eventName === "movewindow" || eventName === "movewindowv2" || eventName === "windowtitle") {
                scheduleUpdates(true, false, false, true, false);
                return;
            }

            if (eventName === "workspace" || eventName === "workspacev2" || eventName === "focusedmon" || eventName === "focusedmonv2" || eventName === "activewindow" || eventName === "activewindowv2") {
                scheduleUpdates(eventName === "activewindow" || eventName === "activewindowv2", false, false, true, true);
                return;
            }

            if (eventName.startsWith("monitor") || eventName === "configreloaded") {
                scheduleUpdates(true, true, false, true, true);
                return;
            }

            scheduleUpdates(true, true, true, true, true);
        }
    }

    Timer {
        id: eventDebounceTimer
        interval: Math.max(0, Config.options.hacks.hyprlandEventDebounceMs)
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
                root.windowList = JSON.parse(clientsCollector.text)
                let tempWinByAddress = {};
                for (var i = 0; i < root.windowList.length; ++i) {
                    var win = root.windowList[i];
                    tempWinByAddress[win.address] = win;
                }
                root.windowByAddress = tempWinByAddress;
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
                root.monitors = JSON.parse(monitorsCollector.text);
            }
        }
    }

    Process {
        id: getLayers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                root.layers = JSON.parse(layersCollector.text);
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                const rawWorkspaces = JSON.parse(workspacesCollector.text);
                root.allWorkspaces = rawWorkspaces;
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
                root.activeWorkspace = JSON.parse(activeWorkspaceCollector.text);
            }
        }
    }
}
