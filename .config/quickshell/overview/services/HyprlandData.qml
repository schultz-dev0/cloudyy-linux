pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "AppIdentity.js" as AppIdentity
import "ClientSnapshot.js" as ClientSnapshot
import "HyprEventPolicy.js" as HyprEventPolicy

/**
 * Provides access to some Hyprland data not available in Quickshell.Hyprland.
 */
Singleton {
    id: root
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string clientsHelperPath: decodeURIComponent(
        Qt.resolvedUrl("hypr_clients.py").toString().replace("file://", ""))
    property string genericIconSource: {
        const themed = Quickshell.iconPath("application-default-icon", "");
        if (themed && `${themed}`.length > 0)
            return themed;
        return "file:///usr/share/icons/Fluent-green/scalable/apps/application-default-icon.svg";
    }
    property int maxIconSourcesPerWindow: 32
    property var iconSourcesByWindowCache: ({})
    property var desktopModelByClassCache: ({})
    property var identityByWindowCache: ({})
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

    function scheduleTitleUpdate() {
        pendingWindowsUpdate = true;
        titleDebounceTimer.restart();
    }

    function flushPendingUpdates() {
        if (pendingWindowsUpdate) {
            pendingWindowsUpdate = false;
            titleDebounceTimer.stop();
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

    function mostRecentWindow() {
        const windows = root.windowList ?? [];
        if (windows.length === 0)
            return null;

        let best = windows[0];
        let bestHistory = best?.focusHistoryID ?? 999999;
        for (let i = 1; i < windows.length; i++) {
            const win = windows[i];
            const history = win?.focusHistoryID ?? 999999;
            if (history < bestHistory) {
                bestHistory = history;
                best = win;
            }
        }
        return best;
    }

    function isTerminalClass(className) {
        const lower = `${className ?? ""}`.trim().toLowerCase();
        if (!lower)
            return false;

        const terminals = [
            "kitty", "alacritty", "foot", "wezterm", "ghostty", "hyper",
            "gnome-terminal", "org.gnome.terminal", "konsole", "xterm",
            "xfce4-terminal", "terminator", "tilix", "rxvt", "urxvt",
            "st-256color", "st"
        ];
        for (let i = 0; i < terminals.length; i++) {
            if (lower === terminals[i])
                return true;
        }
        return lower.includes("terminal");
    }

    function shellPromptTitlePattern(title) {
        const t = `${title ?? ""}`.trim();
        return /^[\w.-]+@[\w.-]+:/.test(t);
    }

    function isMultiplexerTerminal(window) {
        const cls = `${window?.class || window?.initialClass || ""}`.trim();
        if (!isTerminalClass(cls))
            return false;

        const title = `${window?.title ?? ""}`.trim();
        const initialTitle = `${window?.initialTitle ?? ""}`.trim();
        if (!title.length || title === initialTitle)
            return false;

        const lower = title.toLowerCase();
        if (lower.includes("tmux") || lower.includes("zellij") || lower.includes(" screen "))
            return true;

        // Zellij titles are commonly "session-name | pane title".
        if (title.includes(" | "))
            return true;

        // tmux titles are commonly "session: window" or "0: pane".
        if (/^\d+:\s*\S/.test(title))
            return true;
        if (/^[^@]+:[^:]+/.test(title) && !shellPromptTitlePattern(title))
            return true;

        return false;
    }

    function appGroupKey(window) {
        const identity = identityForWindow(window);
        const key = AppIdentity.canonicalKey(identity);
        if (!key)
            return "";
        if (isTerminalClass(identity.class))
            return key + (isMultiplexerTerminal(window) ? "#mux" : "#shell");
        return key;
    }

    function windowsForGroupKey(groupKey) {
        const needle = `${groupKey ?? ""}`.trim().toLowerCase();
        if (!needle)
            return [];

        const windows = root.windowList || [];
        const result = [];
        for (let i = 0; i < windows.length; i++) {
            const win = windows[i];
            if (appGroupKey(win) === needle)
                result.push(win);
        }

        result.sort((a, b) => (a.focusHistoryID ?? 9999) - (b.focusHistoryID ?? 9999));
        return result;
    }

    function windowLabel(window) {
        const title = `${window?.title ?? ""}`.trim();
        if (title.length)
            return title;

        const cls = `${window?.class || window?.initialClass || ""}`.trim();
        return cls.length ? cls : "Window";
    }

    function groupDisplayName(groupKey) {
        const gk = `${groupKey ?? ""}`.trim().toLowerCase();
        if (gk.endsWith("#mux"))
            return "Multiplexer";
        if (gk.endsWith("#shell"))
            return "Shell";
        return "";
    }

    function runningWindowsForClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return [];

        const windows = root.windowList || [];
        const result = [];
        for (let i = 0; i < windows.length; i++) {
            const win = windows[i];
            const winClass = `${win.class || win.initialClass || ""}`.trim();
            if (!winClass)
                continue;
            if (winClass === cls || wmclassesMatch(cls, winClass))
                result.push(win);
        }

        result.sort((a, b) => (a.focusHistoryID ?? 9999) - (b.focusHistoryID ?? 9999));
        return result;
    }

    function desktopModelForClass(className) {
        const cls = normalizeDockClass(className);
        const cacheKey = `${cls}`.trim().toLowerCase();
        return ClientSnapshot.resolveCached(root.desktopModelByClassCache, cacheKey, () => {
            const entry = desktopEntryForClass(cls);
            const entryId = desktopEntryIdForClass(cls);
            const options = desktopLaunchOptionsForClass(cls, "");
            return {
                resolved: entry != null,
                id: entryId,
                name: `${entry?.name ?? entry?.genericName ?? cls}`.trim(),
                wmclass: cls,
                exec: options.exec,
                desktopPath: options.desktopPath,
                icon: `${entry?.icon ?? ""}`.trim()
            };
        });
    }

    function hasProcessIdentityCollision(window) {
        const cls = `${window?.class || window?.initialClass || ""}`.trim().toLowerCase();
        if (!cls)
            return false;
        const keys = {};
        for (const candidate of root.windowList || []) {
            const candidateClass = `${candidate?.class || candidate?.initialClass || ""}`
                .trim().toLowerCase();
            const processKey = `${candidate?.processAppKey ?? ""}`.trim().toLowerCase();
            if (candidateClass === cls && processKey)
                keys[processKey] = true;
        }
        return Object.keys(keys).length > 1;
    }

    function identityForWindow(window) {
        const cacheKey = [
            window?.address, window?.class, window?.initialClass,
            window?.title, window?.initialTitle, window?.processAppKey
        ].map(value => `${value ?? ""}`).join("\u001f");
        return ClientSnapshot.resolveCached(root.identityByWindowCache, cacheKey, () => {
            const cls = `${window?.class || window?.initialClass || ""}`.trim();
            const desktop = desktopModelForClass(cls);
            const identityWindow = hasProcessIdentityCollision(window)
                ? Object.assign({}, window, { forceProcessIdentity: true })
                : window;
            const identity = AppIdentity.identityForWindow(identityWindow, desktop);
            if (AppIdentity.canonicalKey(identity) === "cursor::main")
                identity.launchTarget = AppIdentity.workspaceTargetForWindow(
                    window, CursorWorkspaceStore.recentUris);
            return identity;
        });
    }

    function primaryIdentityForApp(app) {
        if (!app)
            return AppIdentity.primaryIdentityForApp({});
        const cls = `${app.wmclass || app.class || ""}`.trim();
        const appId = `${app.appId || app.id || ""}`.trim();
        const fallback = appId ? {} : desktopModelForClass(cls);
        return AppIdentity.primaryIdentityForApp({
            id: appId || fallback.id,
            name: app.name || fallback.name,
            wmclass: cls || fallback.wmclass,
            exec: app.exec || fallback.exec,
            desktopPath: app.desktopPath || fallback.desktopPath,
            icon: app.icon || fallback.icon
        });
    }

    function windowsForIdentity(identity) {
        const result = [];
        for (const window of root.windowList || []) {
            if (AppIdentity.sameIdentity(identity, identityForWindow(window)))
                result.push(window);
        }
        result.sort((a, b) => (a.focusHistoryID ?? 999999) - (b.focusHistoryID ?? 999999));
        return result;
    }

    function isIdentityRunning(identity) {
        return windowsForIdentity(identity).length > 0;
    }

    function mostRecentWindowForIdentity(identity) {
        const windows = windowsForIdentity(identity);
        return windows.length > 0 ? windows[0] : null;
    }

    function monitorNameForWindow(window) {
        const monitorId = Number(window?.monitor ?? -1);
        if (!Number.isFinite(monitorId) || monitorId < 0)
            return "";
        const monitor = (root.monitors ?? []).find(m => Number(m?.id ?? -2) === monitorId);
        return `${monitor?.name ?? ""}`.trim();
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
        if (cacheObjectSize(iconSourcesByWindowCache) > 512)
            iconSourcesByWindowCache = {};
    }

    function chromePwaAppId(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return "";
        let m = cls.match(/^crx?_+([a-z0-9]+)$/i);
        if (m)
            return m[1].toLowerCase();
        m = cls.match(/^(?:chrome|chromium|msedge)-([a-z0-9]+)-/i);
        if (m)
            return m[1].toLowerCase();
        return "";
    }

    function chromePwaProfileForExec(profileSegment) {
        const p = `${profileSegment ?? ""}`.trim();
        if (!p)
            return "Default";
        if (p.toLowerCase() === "default")
            return "Default";
        return p.replace(/_/g, " ");
    }

    function chromePwaExecFromClass(className) {
        const cls = `${className ?? ""}`.trim();
        const m = cls.match(/^(chrome|chromium|msedge)-([a-z0-9]+)-(.+)$/i);
        if (!m)
            return "";
        const browser = m[1].toLowerCase();
        const appId = m[2];
        const profile = chromePwaProfileForExec(m[3]);
        if (browser === "msedge")
            return `microsoft-edge-stable --profile-directory=${profile} --app-id=${appId}`;
        if (browser === "chromium")
            return `chromium --profile-directory=${profile} --app-id=${appId}`;
        return `google-chrome-stable --profile-directory=${profile} --app-id=${appId}`;
    }

    function normalizeChromePwaWmclass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return cls;
        if (/^(?:chrome|chromium|msedge)-/i.test(cls))
            return cls;

        const crx = cls.match(/^crx?_+([a-z0-9]+)$/i);
        if (!crx)
            return cls;

        const appId = crx[1].toLowerCase();
        const candidates = [
            `chrome-${appId}-Default`,
            `chrome-${appId}-Profile_1`,
            `msedge-${appId}-Default`,
            `chromium-${appId}-Default`
        ];
        for (let i = 0; i < candidates.length; i++) {
            if (DesktopEntries.heuristicLookup(candidates[i]))
                return candidates[i];
        }
        return cls;
    }

    function wmclassesMatch(storedClass, windowClass) {
        const stored = `${storedClass ?? ""}`.trim().toLowerCase();
        const window = `${windowClass ?? ""}`.trim().toLowerCase();
        if (!stored || !window)
            return false;
        if (stored === window)
            return true;

        const storedId = chromePwaAppId(stored);
        const windowId = chromePwaAppId(window);
        if (storedId && windowId && storedId === windowId)
            return true;

        if (storedId && window.startsWith(`chrome-${storedId}-`))
            return true;
        if (storedId && window.startsWith(`chromium-${storedId}-`))
            return true;
        if (storedId && window.startsWith(`msedge-${storedId}-`))
            return true;
        if (windowId && stored.startsWith(`crx_`) && stored.includes(windowId))
            return true;
        if (windowId && stored.startsWith(`cr_`) && stored.includes(windowId))
            return true;

        return false;
    }

    function desktopEntryLookupCandidates(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return [];

        const candidates = [cls];
        const normalized = normalizeChromePwaWmclass(cls);
        if (normalized !== cls)
            candidates.push(normalized);

        const appId = chromePwaAppId(cls);
        if (appId) {
            candidates.push(`chrome-${appId}-Default`);
            candidates.push(`chrome-${appId}-default`);
            candidates.push(`chrome-${appId}-Profile_1`);
            candidates.push(`msedge-${appId}-Default`);
            candidates.push(`crx_${appId}`);
            candidates.push(`cr_${appId}`);
        }

        const chromeClass = cls.match(/^(chrome|chromium|msedge)-([a-z0-9]+)-(.+)$/i);
        if (chromeClass) {
            const profile = chromeClass[3];
            const profileDefault = profile.charAt(0).toUpperCase() + profile.slice(1).toLowerCase();
            if (profileDefault !== profile)
                candidates.push(`${chromeClass[1]}-${chromeClass[2]}-${profileDefault}`);
        }

        const lower = cls.toLowerCase();
        if (!/^(chrome|chromium|msedge)-[a-z0-9]+-/i.test(cls)) {
            if (/google[- ]?chrome/.test(lower) || lower === "chrome")
                candidates.push("google-chrome", "com.google.Chrome");
            else if (lower.includes("chromium"))
                candidates.push("chromium");
            else if (lower.includes("msedge") || lower.includes("microsoft-edge"))
                candidates.push("microsoft-edge", "com.microsoft.Edge");
        }

        return candidates;
    }

    function isChromePwaClass(className) {
        return /^(chrome|chromium|msedge)-[a-z0-9]+-/i.test(`${className ?? ""}`.trim());
    }

    function isMainBrowserClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls || isChromePwaClass(cls))
            return false;
        const lower = cls.toLowerCase();
        return lower.includes("chrome") || lower.includes("chromium")
            || lower.includes("msedge") || lower.includes("microsoft-edge")
            || lower === "google chrome";
    }

    function normalizeDockClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return cls;
        const lower = cls.toLowerCase();
        if (lower === "google chrome" || lower === "google-chrome" || lower === "googlechrome")
            return "google-chrome";
        return normalizeChromePwaWmclass(cls);
    }

    function desktopPathForEntryId(entryId) {
        const id = `${entryId ?? ""}`.trim();
        if (!id)
            return "";
        // DesktopEntries exposes an ID, not the source file location. Keep the
        // portable filename and let gtk-launch resolve XDG user/system priority.
        return `${id}.desktop`;
    }

    function desktopEntryForClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return null;

        const candidates = desktopEntryLookupCandidates(cls);
        for (let i = 0; i < candidates.length; i++) {
            const entry = DesktopEntries.heuristicLookup(candidates[i]);
            if (entry)
                return entry;
        }

        const lower = cls.toLowerCase();
        if (lower.includes("docker"))
            return DesktopEntries.heuristicLookup("docker-desktop")
                || DesktopEntries.heuristicLookup("Docker Desktop");
        if (lower.includes("cloudcenter"))
            return DesktopEntries.heuristicLookup("org.cloudyy.cloudcenter")
                || DesktopEntries.heuristicLookup("Cloud Center");
        if (isMainBrowserClass(cls))
            return DesktopEntries.heuristicLookup("google-chrome")
                || DesktopEntries.heuristicLookup("com.google.Chrome")
                || DesktopEntries.heuristicLookup("chromium")
                || DesktopEntries.heuristicLookup("microsoft-edge");

        if (cls.includes(".")) {
            const last = cls.split(".").pop();
            if (last && last !== cls)
                return DesktopEntries.heuristicLookup(last);
        }

        return null;
    }

    function stripDesktopExecField(s) {
        const t = `${s ?? ""}`.trim();
        if (!t)
            return "";
        return t.replace(/%[A-Za-z]/g, "").trim();
    }

    function isStubDockerCliExec(exec) {
        const s = `${exec ?? ""}`.trim().toLowerCase();
        return s === "docker desktop" || s === "docker";
    }

    function desktopEntryIdForClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return "";
        const entry = desktopEntryForClass(cls);
        if (!entry)
            return "";

        const candidates = desktopEntryLookupCandidates(cls);
        const lower = cls.toLowerCase();
        if (lower.includes("docker"))
            candidates.push("docker-desktop");
        if (lower.includes("nautilus"))
            candidates.push("org.gnome.Nautilus");
        if (isMainBrowserClass(cls)) {
            candidates.push("google-chrome", "com.google.Chrome", "chromium", "microsoft-edge");
        } else if (isChromePwaClass(cls)) {
            candidates.push(cls);
        }

        const seen = {};
        for (let i = 0; i < candidates.length; i++) {
            const id = candidates[i];
            if (!id || seen[id])
                continue;
            seen[id] = true;
            if (DesktopEntries.heuristicLookup(id) === entry)
                return id;
        }
        return "";
    }

    function desktopLaunchOptionsForClass(className, execFallback) {
        const entry = desktopEntryForClass(className);
        const entryId = desktopEntryIdForClass(className);
        let exec = "";
        if (entry)
            exec = stripDesktopExecField(entry.exec ?? entry.Exec ?? "");
        if (isStubDockerCliExec(exec))
            exec = "";
        const fallback = `${execFallback ?? ""}`.trim();
        if (!exec && fallback.length > 0 && !isStubDockerCliExec(fallback))
            exec = fallback;
        let desktopPath = "";
        if (entryId.length > 0)
            desktopPath = desktopPathForEntryId(entryId);
        return { desktopPath: desktopPath, exec: exec };
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

        const chromeAppId = chromePwaAppId(rawClass) || chromePwaAppId(rawInitialClass);
        if (chromeAppId) {
            pushUnique(candidates, `chrome-${chromeAppId}-Default`);
            pushUnique(candidates, `crx_${chromeAppId}`);
            const chromeEntry = desktopEntryForClass(rawClass || rawInitialClass);
            pushUnique(candidates, chromeEntry?.icon);
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
            if (needle && wmclassesMatch(needle, cls))
                return true;
            if (steamClass && cls === steamClass)
                return true;
        }
        return false;
    }

    function execFromWindow(window) {
        const cls = `${window?.class || window?.initialClass || ""}`.trim();
        const entry = desktopEntryForClass(cls);
        let exec = stripDesktopExecField(entry?.exec ?? entry?.Exec ?? "");
        if (!exec || isStubDockerCliExec(exec)) {
            const pwa = chromePwaExecFromClass(cls);
            if (pwa.length > 0)
                exec = pwa;
        }
        return exec;
    }

    function buildRunningAppList() {
        const windows = root.windowList || [];
        const byKey = {};
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            const key = appGroupKey(w);
            if (!key)
                continue;
            const existing = byKey[key];
            if (!existing || (w.focusHistoryID ?? 9999) < (existing.window.focusHistoryID ?? 9999))
                byKey[key] = { window: w, key: key };
        }
        const result = [];
        const keys = Object.keys(byKey).sort();
        for (let i = 0; i < keys.length; i++) {
            const entry = byKey[keys[i]];
            const w = entry.window;
            const cls = w.class || w.initialClass || "";
            const candidates = iconCandidatesForWindow(w);
            let iconName = "";
            for (let c = 0; c < candidates.length; c++) {
                const candidate = `${candidates[c] ?? ""}`.trim();
                if (candidate && candidate !== "application-default-icon") {
                    iconName = candidate;
                    break;
                }
            }
            if (!iconName)
                iconName = cls;
            if (cls && cls.toLowerCase().includes("matlab"))
                iconName = `${root.homeDir}/.local/share/icons/matlab.png`;
            const groupWindows = windowsForGroupKey(entry.key);
            const identity = identityForWindow(w);
            result.push({
                class: cls,
                exec: execFromWindow(w),
                icon: iconName,
                window: w,
                groupKey: entry.key,
                identity: identity,
                identityKey: AppIdentity.canonicalKey(identity),
                role: identity.role,
                label: AppIdentity.displayLabel(identity),
                windowCount: groupWindows.length,
                isRunning: true
            });
        }
        return result;
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

    Component.onCompleted: {
        scheduleUpdates(true, true, true, true);
        flushPendingUpdates();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            const eventName = `${event?.name ?? event?.event ?? event?.type ?? ""}`;
            const plan = HyprEventPolicy.updatePlan(eventName);
            if (plan.debounce === "none")
                return;
            if (plan.debounce === "title") {
                root.scheduleTitleUpdate();
                return;
            }
            root.scheduleUpdates(plan.windows, plan.monitors,
                plan.workspaces, plan.activeWorkspace);
        }
    }

    Timer {
        id: eventDebounceTimer
        interval: Math.max(0, 50)
        repeat: false
        onTriggered: root.flushPendingUpdates()
    }

    Timer {
        id: titleDebounceTimer
        interval: HyprEventPolicy.titleDebounceMs()
        repeat: false
        onTriggered: root.flushPendingUpdates()
    }

    Process {
        id: getClients
        command: ["python3", root.clientsHelperPath]
        stdout: StdioCollector {
            id: clientsCollector
            onStreamFinished: {
                const nextWindowList = root.parseJson(clientsCollector.text, [], "clients");
                const snapshot = ClientSnapshot.build(nextWindowList);
                root.identityByWindowCache = {};
                root.windowByAddress = snapshot.windowByAddress;
                root.windowsByWorkspace = snapshot.windowsByWorkspace;
                root.addresses = snapshot.addresses;
                root.windowList = snapshot.windowList;
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
