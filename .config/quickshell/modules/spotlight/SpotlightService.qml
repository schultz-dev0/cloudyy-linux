// modules/spotlight/SpotlightService.qml — shared launcher brain (Spotlight + Command Center modes)
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../overview/services"
import "../commandcenter/applibrary"
import "../commandcenter/powermenu"
import "../commandcenter/wallpapers"

Singleton {
    id: svc

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string themeCtl: "cloudyy-theme"
    readonly property string cloudCenter: "cloudyy-center"
    readonly property string searchScript: Qt.resolvedUrl("search.sh").toString().replace("file://", "")
    // Command Center data + helper scripts live in modules/commandcenter/
    readonly property string commandsJson: Qt.resolvedUrl("../commandcenter/commands.json").toString().replace("file://", "")
    readonly property string hyprbindsScript: Qt.resolvedUrl("../commandcenter/scripts/hyprbinds.sh").toString().replace("file://", "")
    readonly property string cycleCtlScript: Qt.resolvedUrl("../commandcenter/scripts/cycle-ctl.sh").toString().replace("file://", "")
    readonly property string ollamaModelsScript: Qt.resolvedUrl("../commandcenter/scripts/ollama-models.sh").toString().replace("file://", "")
    readonly property string ollamaMgmtScript: Qt.resolvedUrl("../commandcenter/scripts/ollama-mgmt.sh").toString().replace("file://", "")
    readonly property string ollamaServiceScript: "cloudyy-quickshell-ollama-service"
    readonly property string openWebuiMgmtScript: Qt.resolvedUrl("../commandcenter/scripts/open-webui-mgmt.sh").toString().replace("file://", "")
    readonly property string packagesCtlScript: Qt.resolvedUrl("../commandcenter/scripts/packages-ctl.sh").toString().replace("file://", "")

    property bool visible: false
    property bool keyboardGrab: false
    property bool closing: false
    property string mode: "spotlight"
    property string anchor: "top"
    property string query: ""
    property var results: []
    property int selectedIndex: 0
    property var browseStack: []
    property var registry: []
    property var keybindRows: []
    property bool showingKeybinds: false
    property bool registryLoaded: false
    property string pendingScheme: ""
    property string powerProfile: "balanced"
    property string ollamaServiceStatus: ""
    property string openWebuiStatus: ""
    property var cycleState: ({})
    property string packagesListMode: ""
    property string packagesListFilter: ""
    property string packageManager: ""
    property string pendingPackageName: ""
    property var packageRows: []
    property string ollamaListMode: ""
    property string ollamaListFilter: ""
    property string ollamaListOp: ""
    property string pendingOllamaModel: ""
    property var ollamaModelRows: []

    readonly property int overlayWidth: 640
    readonly property int topMargin: 80
    readonly property int rowHeight: 46
    readonly property int debounceMs: 120
    readonly property int maxFileResults: 10

    property int searchEpoch: 0
    property var searchExtras: []
    property var lastCommandHits: []
    property int cycleStateEpoch: 0

    signal requestFocus()

    Component {
        id: procProto
        Process {}
    }

    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        const resolved = cmd.map(part => {
            if (part === "_cloud_center")
                return cloudCenter;
            return part;
        });
        const p = procProto.createObject(svc, { command: resolved });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function runOllamaServiceAction(op) {
        ollamaServiceProc.op = op || "";
        ollamaServiceProc.running = false;
        ollamaServiceProc.running = true;
    }

    function runOpenWebuiServiceAction(op) {
        openWebuiServiceProc.op = op || "";
        openWebuiServiceProc.running = false;
        openWebuiServiceProc.running = true;
    }

    function resolveScript(path) {
        if (path === "_theme_toggle")
            return ["bash", themeCtl, "toggle"];
        if (path === "_theme_next")
            return ["bash", themeCtl, "next"];
        if (path === "_updater")
            return ["kitty", "--hold", "cloudyy-update"];
        if (path === "_system_info")
            return ["kitty", "-e", "sh", "-c", "fastfetch 2>/dev/null || neofetch 2>/dev/null || echo 'No system info tool'; read -p 'Press Enter...'"];
        if (path === "_ollama_pull_custom")
            return ["bash", ollamaMgmtScript, "pull-custom"];
        return ["bash", "-lc", path];
    }

    function entryById(id) {
        for (let i = 0; i < registry.length; i++) {
            if (registry[i].id === id)
                return registry[i];
        }
        return null;
    }

    function stripJsonComments(text) {
        return `${text ?? ""}`
            .replace(/\/\*[\s\S]*?\*\//g, "")
            .replace(/^\s*\/\/.*$/gm, "");
    }

    function parseCommandsRegistry(text) {
        return JSON.parse(stripJsonComments(text));
    }

    function childrenOf(parentId) {
        const out = [];
        for (let i = 0; i < registry.length; i++) {
            const e = registry[i];
            const p = e.parent ?? null;
            if (p === parentId)
                out.push(e);
        }
        return out;
    }

    function currentParentId() {
        if (browseStack.length === 0)
            return null;
        return browseStack[browseStack.length - 1];
    }

    function currentBrowseItems() {
        if (mode === "apps")
            return [];
        const parentId = currentParentId();
        if (mode === "command")
            return childrenOf(parentId).map(e => commandResult(e));
        return [];
    }

    function keybindResults() {
        return keybindRows.map(k => ({
                type: "keybind",
                label: k.combo,
                subtitle: k.description || (k.dispatcher + " " + k.arg).trim(),
                dispatcher: k.dispatcher,
                arg: k.arg,
                icon: "󱊨"
            }));
    }

    function profileForEntryId(id) {
        if (id === "power.performance")
            return "performance";
        if (id === "power.balanced")
            return "balanced";
        if (id === "power.saver")
            return "power-saver";
        return "";
    }

    function cycleIntervalLabel(secs) {
        const map = { 300: "5 min", 600: "10 min", 900: "15 min", 1800: "30 min",
            3600: "1 hour", 7200: "2 hours", 14400: "4 hours" };
        return map[secs] || `${secs}s`;
    }

    function cycleHourLabel(hour) {
        const h = Math.max(0, Number(hour) || 0);
        return `${h < 10 ? "0" : ""}${h}:00`;
    }

    function displayLabel(entry) {
        const id = entry.id || "";
        const cs = cycleState || {};

        if (id === "cycle.toggle")
            return cs.cycle_enabled ? "Disable Wallpaper Cycling" : "Enable Wallpaper Cycling";
        if (id === "cycle.interval") {
            const lbl = cycleIntervalLabel(cs.cycle_interval || 1800);
            return `Cycle Interval — ${lbl}`;
        }
        if (id === "cycle.order") {
            const order = cs.cycle_order === "sequential" ? "Sequential" : "Random";
            return `Cycle Order — ${order}`;
        }
        if (id === "cycle.automode") {
            const on = cs.automode_enabled ? "ON" : "OFF";
            const light = cycleHourLabel(cs.automode_light_hour || 7);
            const dark = cycleHourLabel(cs.automode_dark_hour || 20);
            return `Auto Light/Dark — ${on} (${light} / ${dark})`;
        }
        if (id === "cycle.automode.toggle")
            return cs.automode_enabled ? "Disable Auto Switch" : "Enable Auto Switch";
        if (id === "cycle.automode.light")
            return `Light Mode Start — ${cycleHourLabel(cs.automode_light_hour || 7)}`;
        if (id === "cycle.automode.dark")
            return `Dark Mode Start — ${cycleHourLabel(cs.automode_dark_hour || 20)}`;
        if (id.indexOf("cycle.interval.") === 0) {
            const secs = Number(id.split(".").pop());
            const cur = Number(cs.cycle_interval || 0);
            return entry.label + (secs === cur ? " (current)" : "");
        }
        if (id === "cycle.order.random" && cs.cycle_order === "random")
            return entry.label + " (current)";
        if (id === "cycle.order.sequential" && cs.cycle_order === "sequential")
            return entry.label + " (current)";
        if (id.indexOf("cycle.automode.light.") === 0) {
            const h = Number(id.split(".").pop());
            if (h === Number(cs.automode_light_hour || -1))
                return entry.label + " (current)";
        }
        if (id.indexOf("cycle.automode.dark.") === 0) {
            const h = Number(id.split(".").pop());
            if (h === Number(cs.automode_dark_hour || -1))
                return entry.label + " (current)";
        }
        if (id === "power" && powerProfile) {
            const names = { "performance": "Performance", "balanced": "Balanced", "power-saver": "Power Saver" };
            return entry.label + ` — ${names[powerProfile] || powerProfile}`;
        }
        if (id === "ai.service" && ollamaServiceStatus) {
            const names = { "running": "Running", "stopped": "Stopped" };
            return entry.label + ` — ${names[ollamaServiceStatus] || ollamaServiceStatus}`;
        }
        if (id === "ai.chat" && openWebuiStatus) {
            const names = { "running": "Running", "stopped": "Stopped" };
            return entry.label + ` — Open WebUI ${names[openWebuiStatus] || openWebuiStatus}`;
        }

        return entry.label;
    }

    function commandRootSubtitle(entry, action) {
        const type = action.type || "";
        if (type === "applibrary")
            return "App library";
        if (type === "powermenu")
            return "Menu";
        if (type === "wallpapers")
            return "Wallpapers";
        if (type === "keybinds")
            return "Keybinds";
        if (type === "ollama_models")
            return "Ollama models";
        if (type === "ollama_models_list")
            return action.op === "delete" ? "Delete model" : (action.op === "stop" ? "Stop model" : "Model info");
        if (type === "ollama_pull")
            return "Pull model";
        if (type === "ollama_service")
            return "Ollama service";
        if (type === "open_webui_service")
            return "Open WebUI";
        if (type === "packages_list")
            return action.filter === "explicit" ? "Remove package" : "Package info";
        if (type === "scheme")
            return "Color scheme";
        if (type === "cycle")
            return "Theme cycle";
        if (type === "power_profile")
            return "Power profile";
        if (type === "external") {
            const cmd = action.command || [];
            if (cmd.includes("gtk-launch"))
                return "Launch app";
            if (cmd.includes("xdg-open"))
                return "Open link";
            if (cmd.some(p => `${p}`.includes("cloud-center")))
                return "Cloud Center";
            return "Open";
        }
        if (type === "exec")
            return "Run command";
        if (type === "script") {
            const path = action.path || "";
            if (path === "_theme_toggle")
                return "Toggle theme";
            if (path === "_theme_next")
                return "Next wallpaper";
            if (path === "_updater")
                return "System update";
            if (path === "_system_info")
                return "System info";
            return "Run script";
        }
        return "Command";
    }

    function commandResult(entry) {
        const hasChildren = childrenOf(entry.id).length > 0;
        const action = entry.action || {};
        const navigable = action.type === "navigate"
            || (hasChildren && action.type !== "exec" && action.type !== "applibrary" && action.type !== "apps" && action.type !== "powermenu");
        const parent = entry.parent ? entryById(entry.parent) : null;
        const profileKey = profileForEntryId(entry.id);
        const cs = cycleState || {};
        const isActive = profileKey.length > 0 && powerProfile === profileKey;
        let subtitle = navigable
            ? "Menu"
            : (parent ? parent.label : commandRootSubtitle(entry, action));
        if (isActive)
            subtitle = "Active";
        else if (idIsCycleLeaf(entry.id))
            subtitle = "Theme cycle";
        let icon = entry.icon || "󰧭";
        if (entry.id === "cycle.automode.toggle")
            icon = cs.automode_enabled ? "󰔡" : "󰨙";
        return {
            type: "command",
            id: entry.id,
            label: displayLabel(entry),
            icon: icon,
            subtitle: subtitle,
            entry: entry,
            navigable: navigable,
            isActive: isActive
        };
    }

    function idIsCycleLeaf(id) {
        return id.indexOf("cycle.") === 0 && id !== "cycle.interval" && id !== "cycle.order"
            && id !== "cycle.automode" && id !== "cycle.automode.light" && id !== "cycle.automode.dark";
    }

    function normalizeText(text) {
        return `${text ?? ""}`.toLowerCase().trim().replace(/[^\w\s-]/g, " ").replace(/\s+/g, " ");
    }

    function collapseText(text) {
        return normalizeText(text).replace(/\s+/g, "");
    }

    function tokensOf(text) {
        return normalizeText(text).split(" ").filter(token => token.length > 0);
    }

    function entryHaystack(entry) {
        const parts = [entry.label, entry.id.replace(/\./g, " ")];
        const keys = entry.keywords || [];
        for (let i = 0; i < keys.length; i++)
            parts.push(keys[i]);
        let parentId = entry.parent;
        while (parentId) {
            const parent = entryById(parentId);
            if (!parent)
                break;
            parts.push(parent.label);
            parentId = parent.parent;
        }
        return normalizeText(parts.join(" "));
    }

    function scoreCommandEntry(entry, needle, queryTokens) {
        const action = entry.action || {};
        const hasChildren = childrenOf(entry.id).length > 0;
        if (action.type === "navigate" && !hasChildren)
            return 0;

        const labelNorm = normalizeText(entry.label);
        const haystack = entryHaystack(entry);
        const labelTokens = tokensOf(entry.label);
        const collapsedNeedle = collapseText(needle);
        let score = 0;

        if (labelNorm === needle)
            score = Math.max(score, 100);
        if (collapseText(labelNorm) === collapsedNeedle)
            score = Math.max(score, 98);

        const keywords = entry.keywords || [];
        for (let i = 0; i < keywords.length; i++) {
            const kwNorm = normalizeText(keywords[i]);
            if (kwNorm === needle)
                score = Math.max(score, 96);
            if (collapseText(kwNorm) === collapsedNeedle)
                score = Math.max(score, 94);
            if (kwNorm.startsWith(needle))
                score = Math.max(score, 88);
            if (needle.startsWith(kwNorm) && kwNorm.length >= 3)
                score = Math.max(score, 72);
            if (kwNorm.includes(needle))
                score = Math.max(score, 66);
            if (needle.includes(kwNorm) && kwNorm.length >= 4)
                score = Math.max(score, 58);
        }

        if (labelNorm.startsWith(needle))
            score = Math.max(score, 86);
        if (haystack.includes(needle))
            score = Math.max(score, 78);
        if (collapseText(haystack).includes(collapsedNeedle))
            score = Math.max(score, 76);

        if (queryTokens.length > 0) {
            const matchedTokens = queryTokens.filter(token => haystack.includes(token));
            if (matchedTokens.length === queryTokens.length) {
                const labelHits = queryTokens.filter(token => labelTokens.includes(token)).length;
                const prefixHits = queryTokens.filter(token => labelTokens.some(word => word.startsWith(token))).length;
                score = Math.max(score, 68 + labelHits * 10 + prefixHits * 4);
            } else if (matchedTokens.length > 0) {
                score = Math.max(score, 40 + matchedTokens.length * 12);
            }
        }

        for (let t = 0; t < queryTokens.length; t++) {
            const token = queryTokens[t];
            for (let w = 0; w < labelTokens.length; w++) {
                if (labelTokens[w].startsWith(token))
                    score = Math.max(score, 54);
            }
        }

        if (action.type === "navigate" && hasChildren && score < 95)
            score = Math.floor(score * 0.82);

        return score;
    }

    function matchCommands(q) {
        const needle = normalizeText(q);
        if (!needle || !registryLoaded)
            return [];
        const queryTokens = tokensOf(needle);
        const scored = [];
        for (let i = 0; i < registry.length; i++) {
            const entry = registry[i];
            const score = scoreCommandEntry(entry, needle, queryTokens);
            if (score > 0)
                scored.push({ score: score, item: commandResult(entry) });
        }
        scored.sort((a, b) => b.score - a.score);
        return scored.map(s => s.item);
    }

    function cancelAsyncSearch() {
        debounce.stop();
        searchEpoch++;
        searchProc.running = false;
        searchExtras = [];
        lastCommandHits = [];
    }

    function isInPowerMenu() {
        if (currentParentId() === "power")
            return true;
        for (let i = 0; i < browseStack.length; i++) {
            if (browseStack[i] === "power")
                return true;
        }
        return false;
    }

    function isInOllamaServiceMenu() {
        const parentId = currentParentId();
        if (parentId === "ai" || parentId === "ai.service")
            return true;
        for (let i = 0; i < browseStack.length; i++) {
            const id = browseStack[i];
            if (id === "ai" || id === "ai.service")
                return true;
        }
        return false;
    }

    function isInAiChatMenu() {
        const parentId = currentParentId();
        if (parentId === "ai" || parentId === "ai.chat")
            return true;
        for (let i = 0; i < browseStack.length; i++) {
            const id = browseStack[i];
            if (id === "ai" || id === "ai.chat")
                return true;
        }
        return false;
    }

    function applySearchResults(commands, extras) {
        const calc = results.filter(r => {
            if (r.type !== "calculator" && r.type !== "currency" && r.type !== "time")
                return false;
            if (r.type === "calculator" || r.type === "time")
                return (r.expression ?? "") === query;
            return true;
        });
        const apps = extras.filter(r => r.type === "app");
        const files = extras.filter(r => r.type === "file");
        if (mode === "spotlight")
            results = calc.concat(apps).concat(files).concat(commands);
        else
            results = calc.concat(commands).concat(apps).concat(files);
        if (selectedIndex >= results.length)
            selectedIndex = results.length > 0 ? 0 : -1;
    }

    function closeSubPanels() {
        if (AppLibraryService.visible)
            AppLibraryService.close();
        if (PowerMenuService.visible)
            PowerMenuService.close();
        if (WallpaperPickerService.visible)
            WallpaperPickerService.close();
    }

    function loadCommandsRegistry() {
        registryProc.running = false;
        registryProc.running = true;
    }

    function openMode(m) {
        if (m === "wallpaper") {
            WallpaperPickerService.open();
            return;
        }
        closeSubPanels();
        mode = m;
        browseStack = [];
        cancelAsyncSearch();
        query = "";
        results = [];
        selectedIndex = -1;
        keybindRows = [];
        showingKeybinds = false;
        svc.showPanel();
        if (m === "command")
            loadCommandsRegistry();
        refreshDynamicState();
        refreshDisplay();
        requestFocus();
    }

    function restoreFromAppLibrary(m, stack) {
        closeSubPanels();
        mode = m || "command";
        browseStack = stack ? stack.slice() : [];
        cancelAsyncSearch();
        query = "";
        results = [];
        selectedIndex = -1;
        showingKeybinds = false;
        svc.showPanel();
        refreshDynamicState();
        refreshDisplay();
        requestFocus();
    }

    function showPanel() {
        hideTimer.stop();
        closing = false;
        visible = true;
        keyboardGrab = true;
    }

    function finishClose() {
        visible = false;
        closing = false;
        cancelAsyncSearch();
        query = "";
        results = [];
        selectedIndex = 0;
        browseStack = [];
        keybindRows = [];
        showingKeybinds = false;
        packagesListMode = "";
        packagesListFilter = "";
        packageRows = [];
        pendingPackageName = "";
        packageManager = "";
        ollamaListMode = "";
        ollamaListFilter = "";
        ollamaListOp = "";
        pendingOllamaModel = "";
        ollamaModelRows = [];
    }

    function close() {
        keyboardGrab = false;
        if (!visible && !closing) {
            finishClose();
            return;
        }
        if (closing)
            return;
        closing = true;
        hideTimer.restart();
    }

    function toggle() {
        if (visible && mode === "spotlight")
            close();
        else
            openMode("spotlight");
    }

    Timer {
        id: hideTimer
        interval: 140
        repeat: false
        onTriggered: svc.finishClose()
    }

    function browseInto(id) {
        browseStack = browseStack.concat([id]);
        selectedIndex = -1;
        refreshDynamicState();
        refreshDisplay();
    }

    function browseBack() {
        if (showingKeybinds) {
            showingKeybinds = false;
            keybindRows = [];
            selectedIndex = -1;
            refreshDisplay();
            requestFocus();
            return true;
        }
        if (ollamaListMode === "confirm") {
            ollamaListMode = ollamaListOp;
            pendingOllamaModel = "";
            query = "";
            filterOllamaModelRows();
            selectedIndex = -1;
            requestFocus();
            return true;
        }
        if (ollamaListMode) {
            ollamaListMode = "";
            ollamaListFilter = "";
            ollamaListOp = "";
            ollamaModelRows = [];
            pendingOllamaModel = "";
            query = "";
            selectedIndex = -1;
            refreshDisplay();
            requestFocus();
            return true;
        }
        if (packagesListMode === "confirm") {
            packagesListMode = packagesListFilter;
            pendingPackageName = "";
            query = "";
            filterPackageRows();
            selectedIndex = -1;
            requestFocus();
            return true;
        }
        if (packagesListMode) {
            packagesListMode = "";
            packagesListFilter = "";
            packageRows = [];
            pendingPackageName = "";
            query = "";
            selectedIndex = -1;
            refreshDisplay();
            requestFocus();
            return true;
        }
        if (browseStack.length > 0) {
            browseStack = browseStack.slice(0, browseStack.length - 1);
            selectedIndex = -1;
            refreshDynamicState();
            refreshDisplay();
            return true;
        }
        return false;
    }

    function refreshDisplay() {
        if (showingKeybinds) {
            results = keybindResults();
            selectedIndex = results.length > 0 ? Math.max(0, selectedIndex) : -1;
            return;
        }
        if (ollamaListMode && ollamaListMode !== "confirm") {
            filterOllamaModelRows();
            return;
        }
        if (packagesListMode && packagesListMode !== "confirm") {
            filterPackageRows();
            return;
        }
        if (query.trim().length > 0) {
            runSearch();
            return;
        }
        cancelAsyncSearch();
        if (mode === "command")
            results = currentBrowseItems();
        else
            results = [];
        selectedIndex = -1;
    }

    function runSearch() {
        const q = query.trim();
        if (!q) {
            refreshDisplay();
            return;
        }

        cancelAsyncSearch();
        const epoch = searchEpoch;
        searchProc.activeEpoch = epoch;
        searchProc.activeQuery = q;
        lastCommandHits = matchCommands(q);
        searchExtras = [];
        applySearchResults(lastCommandHits, searchExtras);
        selectedIndex = results.length > 0 ? 0 : -1;

        if (mode === "spotlight" || mode === "command") {
            searchProc.running = false;
            searchProc.command = ["bash", searchScript, q];
            searchProc.running = true;
        }
    }

    function appendSearchResult(result) {
        if (searchProc.activeEpoch !== searchEpoch)
            return;
        if (searchProc.activeQuery !== query.trim())
            return;
        if (result.type === "app") {
            result.identity = HyprlandData.primaryIdentityForApp(result);
            result.isRunning = HyprlandData.isIdentityRunning(result.identity);
        }
        searchExtras = searchExtras.concat([result]);
        applySearchResults(lastCommandHits, searchExtras);
    }

    function activateIndex(idx) {
        if (idx < 0)
            return;
        if (idx >= results.length)
            return;
        const r = results[idx];
        if (r.type === "command" && !r.entry)
            return;
        if (r.type === "command")
            activateCommand(r.entry);
        else if (r.type === "app") {
            const identity = r.identity || HyprlandData.primaryIdentityForApp(r);
            HyprDispatch.activateIdentity(identity, { app: r });
            close();
        } else if (r.type === "keybind") {
            const args = ["hyprctl", "dispatch", r.dispatcher];
            if (r.arg && r.arg.length > 0)
                args.push(r.arg);
            launch(args);
            close();
        } else if (r.type === "file") {
            launch(["xdg-open", r.path]);
            close();
        } else if (r.type === "calculator" || r.type === "currency" || r.type === "time") {
            launch(["wl-copy", r.result]);
            close();
        } else if (r.type === "ollama_model") {
            if (ollamaListMode === "delete") {
                pendingOllamaModel = r.name;
                ollamaListMode = "confirm";
                results = [
                    {
                        type: "ollama_action",
                        action: "confirm_delete",
                        label: "Confirm Deletion",
                        name: r.name,
                        icon: "󰆴",
                        subtitle: r.name
                    },
                    {
                        type: "ollama_action",
                        action: "cancel",
                        label: "Cancel",
                        icon: "󰘐",
                        subtitle: "Back to model list"
                    }
                ];
                selectedIndex = 0;
            } else if (ollamaListMode === "stop") {
                ollamaMgmtProc.command = ["bash", ollamaMgmtScript, "stop", r.name];
                ollamaMgmtProc.running = false;
                ollamaMgmtProc.running = true;
            } else if (ollamaListMode === "info") {
                launch(["bash", ollamaMgmtScript, "info", r.name]);
                close();
            } else {
                launch(["kitty", "--class", "ollama_chat", "--title", "ollama — " + r.name, "-e", "ollama", "run", r.name]);
                close();
            }
        } else if (r.type === "ollama_action") {
            if (r.action === "confirm_delete") {
                const model = r.name || pendingOllamaModel;
                launch(["bash", ollamaMgmtScript, "remove", model]);
                ollamaListMode = "";
                ollamaListFilter = "";
                ollamaListOp = "";
                ollamaModelRows = [];
                pendingOllamaModel = "";
                close();
            } else {
                ollamaListMode = ollamaListOp;
                pendingOllamaModel = "";
                query = "";
                filterOllamaModelRows();
                selectedIndex = -1;
            }
        } else if (r.type === "package") {
            if (packagesListFilter === "explicit") {
                pendingPackageName = r.name;
                if (r.pm)
                    packageManager = r.pm;
                packagesListMode = "confirm";
                results = [
                    {
                        type: "package_action",
                        action: "confirm_remove",
                        label: "Confirm Removal",
                        name: r.name,
                        icon: "󰆴",
                        subtitle: r.name
                    },
                    {
                        type: "package_action",
                        action: "cancel",
                        label: "Cancel",
                        icon: "󰘐",
                        subtitle: "Back to package list"
                    }
                ];
                selectedIndex = 0;
            } else {
                launch(["bash", packagesCtlScript, "info", r.name]);
                close();
            }
        } else if (r.type === "package_action") {
            if (r.action === "confirm_remove") {
                const pkg = r.name || pendingPackageName;
                launch(["bash", packagesCtlScript, "remove", pkg]);
                packagesListMode = "";
                packagesListFilter = "";
                packageRows = [];
                pendingPackageName = "";
                close();
            } else {
                packagesListMode = packagesListFilter;
                pendingPackageName = "";
                query = "";
                filterPackageRows();
                selectedIndex = -1;
            }
        }
    }

    function runCycleAction(op, value) {
        optimisticCycleOp(op, value);
        const args = ["bash", cycleCtlScript, op];
        if (value !== undefined && value !== null && `${value}`.length > 0)
            args.push(`${value}`);
        cycleCtlProc.command = args;
        cycleCtlProc.running = false;
        cycleCtlProc.running = true;
    }

    function optimisticCycleOp(op, value) {
        const cs = cycleState || {};
        if (op === "toggle-automode") {
            cycleState = Object.assign({}, cs, {
                automode_enabled: !cs.automode_enabled
            });
        } else if (op === "toggle-cycle") {
            cycleState = Object.assign({}, cs, {
                cycle_enabled: !cs.cycle_enabled
            });
        } else if (op === "set-light-hour") {
            const h = Number(`${value ?? cs.automode_light_hour ?? 7}`);
            if (Number.isFinite(h))
                cycleState = Object.assign({}, cs, { automode_light_hour: h });
        } else if (op === "set-dark-hour") {
            const h = Number(`${value ?? cs.automode_dark_hour ?? 20}`);
            if (Number.isFinite(h))
                cycleState = Object.assign({}, cs, { automode_dark_hour: h });
        } else if (op === "set-interval") {
            const n = Number(`${value ?? cs.cycle_interval ?? 1800}`);
            if (Number.isFinite(n))
                cycleState = Object.assign({}, cs, { cycle_interval: n });
        } else if (op === "set-order") {
            cycleState = Object.assign({}, cs, { cycle_order: `${value ?? cs.cycle_order ?? "random"}` });
        }
        if (visible && isInCycleMenu())
            reloadCommandResults();
    }

    function activateCommand(entry) {
        if (!entry)
            return;
        const action = entry.action || {};
        const hasChildren = childrenOf(entry.id).length > 0;

        if (action.type === "applibrary" || action.type === "apps") {
            AppLibraryService.openFromCommandCenter(mode, browseStack);
            return;
        }
        if (action.type === "powermenu") {
            PowerMenuService.openFromCommandCenter(mode, browseStack);
            return;
        }
        if (action.type === "navigate" || (hasChildren && action.type !== "exec")) {
            browseInto(entry.id);
            return;
        }
        if (action.type === "wallpapers") {
            WallpaperPickerService.openFromCommandCenter(mode, browseStack);
            return;
        }
        if (action.type === "keybinds") {
            showingKeybinds = true;
            keybindRows = [];
            results = [];
            selectedIndex = -1;
            loadKeybinds();
            return;
        }
        if (action.type === "ollama_models") {
            loadOllamaModels();
            return;
        }
        if (action.type === "ollama_models_list") {
            loadOllamaModelList(action.filter || "installed", action.op || "info");
            return;
        }
        if (action.type === "ollama_pull") {
            launch(["bash", ollamaMgmtScript, "pull", action.model || ""]);
            close();
            return;
        }
        if (action.type === "ollama_service") {
            runOllamaServiceAction(action.op || "");
            return;
        }
        if (action.type === "open_webui_service") {
            runOpenWebuiServiceAction(action.op || "");
            return;
        }
        if (action.type === "packages_list") {
            loadPackageList(action.filter || "all");
            return;
        }
        if (action.type === "power_profile") {
            launch(["powerprofilesctl", "set", action.profile]);
            Qt.callLater(() => {
                loadPowerProfile();
                reloadCommandResults();
            });
            return;
        }
        if (action.type === "cycle") {
            runCycleAction(action.op, action.value);
            return;
        }
        if (action.type === "exec") {
            launch(action.command);
            close();
            return;
        }
        if (action.type === "external") {
            launch(action.command);
            close();
            return;
        }
        if (action.type === "script") {
            launch(resolveScript(action.path));
            close();
            return;
        }
        if (action.type === "scheme") {
            pendingScheme = action.scheme;
            launch(["bash", themeCtl, "refresh", action.scheme, "0.0"]);
            close();
            return;
        }
    }

    function loadKeybinds() {
        keybindRows = [];
        keybindsProc.running = true;
    }

    function loadPowerProfile() {
        powerProfileProc.running = true;
    }

    function loadOllamaServiceStatus() {
        ollamaServiceStatusProc.running = true;
    }

    function loadOpenWebuiStatus() {
        openWebuiStatusProc.running = true;
    }

    function loadCycleState() {
        cycleStateEpoch++;
        cycleStateProc.epoch = cycleStateEpoch;
        cycleStateProc.running = false;
        cycleStateProc.running = true;
    }

    function loadOllamaModels() {
        ollamaListMode = "";
        ollamaListFilter = "";
        ollamaListOp = "";
        ollamaModelsProc.running = false;
        ollamaModelsProc.running = true;
    }

    function loadOllamaModelList(filter, op) {
        ollamaListMode = op || "info";
        ollamaListFilter = filter || "installed";
        ollamaListOp = op || "info";
        ollamaModelRows = [];
        ollamaModelsListProc.filter = ollamaListFilter;
        ollamaModelsListProc.running = false;
        ollamaModelsListProc.running = true;
    }

    function ollamaModelRowsToResults(rows) {
        let subtitle = "Model info";
        let icon = "󰋼";
        if (ollamaListOp === "stop") {
            subtitle = "Stop loaded model";
            icon = "󰓩";
        } else if (ollamaListOp === "delete") {
            subtitle = "Permanently remove model";
            icon = "󰆴";
        }
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            out.push({
                type: "ollama_model",
                name: r.name,
                label: r.name,
                icon: icon,
                subtitle: subtitle
            });
        }
        return out;
    }

    function filterOllamaModelRows() {
        const q = normalizeText(query);
        let rows = ollamaModelRows;
        if (q.length > 0) {
            rows = [];
            for (let i = 0; i < ollamaModelRows.length; i++) {
                if (normalizeText(ollamaModelRows[i].name).indexOf(q) >= 0)
                    rows.push(ollamaModelRows[i]);
            }
        }
        results = ollamaModelRowsToResults(rows);
        if (results.length === 0) {
            let label = "No models installed";
            if (ollamaListFilter === "running")
                label = "No models are currently loaded";
            results = [{
                type: "command",
                label: label,
                subtitle: ollamaListFilter === "running" ? "Nothing to stop" : "Use Pull / Download Model",
                icon: "󰚩",
                entry: null
            }];
        }
        selectedIndex = -1;
    }

    function packageRowsToResults(rows) {
        const subtitle = packagesListFilter === "explicit" ? "Remove package" : "View package info";
        const icon = packagesListFilter === "explicit" ? "󰆴" : "󰋼";
        const out = [];
        for (let i = 0; i < rows.length; i++) {
            const r = rows[i];
            out.push({
                type: "package",
                name: r.name,
                label: r.name,
                pm: r.pm || packageManager,
                icon: icon,
                subtitle: subtitle
            });
        }
        return out;
    }

    function filterPackageRows() {
        const q = normalizeText(query);
        let rows = packageRows;
        if (q.length > 0) {
            rows = [];
            for (let i = 0; i < packageRows.length; i++) {
                if (normalizeText(packageRows[i].name).indexOf(q) >= 0)
                    rows.push(packageRows[i]);
            }
        }
        results = packageRowsToResults(rows);
        if (results.length === 0) {
            results = [{
                    type: "command",
                    label: q.length > 0 ? "No matching packages" : "No packages found",
                    subtitle: "Package list",
                    icon: "󰏖",
                    entry: null
                }];
        }
        selectedIndex = -1;
    }

    function loadPackageList(filter) {
        packagesListFilter = filter === "explicit" ? "explicit" : "all";
        packagesListMode = packagesListFilter;
        packageRows = [];
        pendingPackageName = "";
        query = "";
        results = [{
                type: "command",
                label: "Loading packages…",
                subtitle: packagesListFilter === "explicit" ? "Explicit installs" : "All installed packages",
                icon: "󰏖",
                entry: null
            }];
        selectedIndex = -1;
        packagesListProc.filter = packagesListFilter;
        packagesListProc.running = false;
        packagesListProc.running = true;
    }

    function isInCycleMenu() {
        const parentId = currentParentId();
        if (parentId === "appearance.cycle" || (parentId && parentId.indexOf("cycle.") === 0))
            return true;
        for (let i = 0; i < browseStack.length; i++) {
            const id = browseStack[i];
            if (id === "appearance.cycle" || id.indexOf("cycle.") === 0)
                return true;
        }
        return false;
    }

    function refreshDynamicState() {
        loadPowerProfile();
        if (isInOllamaServiceMenu())
            loadOllamaServiceStatus();
        if (isInAiChatMenu())
            loadOpenWebuiStatus();
        if (isInCycleMenu())
            loadCycleState();
    }

    function reloadCommandResults() {
        const q = query.trim();
        if (q.length > 0) {
            lastCommandHits = matchCommands(q);
            applySearchResults(lastCommandHits, searchExtras);
            return;
        }
        if (mode === "command")
            results = currentBrowseItems();
    }

    Process {
        id: powerProfileProc
        running: false
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            onRead: line => {
                const v = line.trim();
                if (v.length > 0)
                    svc.powerProfile = v;
                if (svc.visible && svc.isInPowerMenu())
                    svc.reloadCommandResults();
            }
        }
    }

    Process {
        id: ollamaServiceStatusProc
        running: false
        command: ["bash", svc.ollamaServiceScript, "status"]
        stdout: SplitParser {
            onRead: line => {
                const v = line.trim();
                if (v.length > 0)
                    svc.ollamaServiceStatus = v;
                if (svc.visible && svc.isInOllamaServiceMenu())
                    svc.reloadCommandResults();
            }
        }
    }

    Process {
        id: ollamaServiceProc
        property string op: ""
        running: false
        command: ["bash", svc.ollamaServiceScript, op]
        stdout: SplitParser {
            onRead: line => {
                if (line.trim() === "TERMINAL")
                    svc.close();
            }
        }
        onRunningChanged: {
            if (!running && svc.visible && op !== "show-status")
                svc.loadOllamaServiceStatus();
        }
    }

    Process {
        id: openWebuiStatusProc
        running: false
        command: ["bash", svc.openWebuiMgmtScript, "status"]
        stdout: SplitParser {
            onRead: line => {
                const v = line.trim();
                if (v.length > 0)
                    svc.openWebuiStatus = v;
                if (svc.visible && svc.isInAiChatMenu())
                    svc.reloadCommandResults();
            }
        }
    }

    Process {
        id: openWebuiServiceProc
        property string op: ""
        running: false
        command: ["bash", svc.openWebuiMgmtScript, op]
        onRunningChanged: {
            if (!running && svc.visible)
                svc.loadOpenWebuiStatus();
        }
    }

    Process {
        id: cycleCtlProc
        running: false
        onRunningChanged: {
            if (!running)
                svc.loadCycleState();
        }
    }

    Process {
        id: cycleStateProc
        running: false
        property int epoch: 0
        command: ["bash", svc.cycleCtlScript, "state"]
        stdout: StdioCollector {
            id: cycleStateCollector
            onStreamFinished: {
                if (cycleStateProc.epoch !== svc.cycleStateEpoch)
                    return;
                const text = cycleStateCollector.text.trim();
                if (!text)
                    return;
                try {
                    svc.cycleState = JSON.parse(text);
                    if (svc.visible && svc.isInCycleMenu())
                        svc.reloadCommandResults();
                } catch (e) {
                    console.warn("spotlight: bad cycle state json", e);
                }
            }
        }
    }

    Process {
        id: packagesListProc
        property string filter: "all"
        running: false
        command: ["bash", svc.packagesCtlScript, "list", filter]
        stdout: StdioCollector {
            id: packagesListCollector
            onStreamFinished: {
                const lines = packagesListCollector.text.split("\n");
                const rows = [];
                for (let i = 0; i < lines.length; i++) {
                    const text = lines[i].trim();
                    if (!text)
                        continue;
                    try {
                        rows.push(JSON.parse(text));
                    } catch (e) {
                        console.warn("spotlight: bad package json", text);
                    }
                }
                svc.packageRows = rows;
                if (rows.length > 0 && rows[0].pm)
                    svc.packageManager = rows[0].pm;
                svc.filterPackageRows();
            }
        }
    }

    Process {
        id: ollamaModelsProc
        running: false
        command: ["bash", svc.ollamaModelsScript]
        stdout: StdioCollector {
            id: ollamaModelsCollector
            onStreamFinished: {
                const lines = ollamaModelsCollector.text.split("\n");
                const rows = [];
                for (let i = 0; i < lines.length; i++) {
                    const text = lines[i].trim();
                    if (!text)
                        continue;
                    try {
                        rows.push(JSON.parse(text));
                    } catch (e) {
                        console.warn("spotlight: bad ollama model json", text);
                    }
                }
                if (rows.length === 0) {
                    svc.results = [{
                            type: "command",
                            label: "No models installed",
                            subtitle: "Use Model Management to pull a model",
                            icon: "󰚩",
                            entry: null
                        }];
                } else {
                    svc.results = rows.map(m => ({
                            type: "ollama_model",
                            name: m.name,
                            label: m.name,
                            icon: "󰚩",
                            subtitle: "ollama run"
                        }));
                }
                svc.selectedIndex = 0;
            }
        }
    }

    Process {
        id: ollamaModelsListProc
        property string filter: "installed"
        running: false
        command: ["bash", svc.ollamaMgmtScript, filter === "running" ? "list-running" : "list-installed"]
        stdout: StdioCollector {
            id: ollamaModelsListCollector
            onStreamFinished: {
                const lines = ollamaModelsListCollector.text.split("\n");
                const rows = [];
                for (let i = 0; i < lines.length; i++) {
                    const text = lines[i].trim();
                    if (!text)
                        continue;
                    try {
                        rows.push(JSON.parse(text));
                    } catch (e) {
                        console.warn("spotlight: bad ollama mgmt json", text);
                    }
                }
                svc.ollamaModelRows = rows;
                svc.filterOllamaModelRows();
            }
        }
    }

    Process {
        id: ollamaMgmtProc
        running: false
        onRunningChanged: {
            if (!running && svc.ollamaListMode === "stop" && svc.ollamaListFilter === "running")
                svc.loadOllamaModelList("running", "stop");
        }
    }

    Process {
        id: registryProc
        running: true
        command: ["cat", svc.commandsJson]
        stdout: StdioCollector {
            id: registryCollector
            onStreamFinished: {
                try {
                    const data = parseCommandsRegistry(registryCollector.text);
                    if (Array.isArray(data))
                        svc.registry = data;
                } catch (e) {
                    console.warn("spotlight: failed to parse commands.json", e);
                }
                svc.registryLoaded = true;
                if (svc.visible) {
                    if (svc.query.trim().length > 0)
                        svc.runSearch();
                    else if (svc.mode === "command")
                        svc.refreshDisplay();
                }
            }
        }
    }

    Process {
        id: searchProc
        running: false
        property int activeEpoch: 0
        property string activeQuery: ""
        environment: ({
                MAX_FILE_RESULTS: svc.maxFileResults.toString()
            })
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line.trim().length === 0)
                    return;
                try {
                    svc.appendSearchResult(JSON.parse(line));
                } catch (_) {}
            }
        }
    }

    Process {
        id: keybindsProc
        running: false
        command: ["bash", svc.hyprbindsScript]
        stdout: SplitParser {
            onRead: line => {
                const text = line.trim();
                if (!text)
                    return;
                try {
                    svc.keybindRows = svc.keybindRows.concat([JSON.parse(text)]);
                    if (svc.showingKeybinds)
                        svc.refreshDisplay();
                } catch (e) {
                    console.warn("spotlight: bad keybind json", text);
                }
            }
        }
    }

    Process {
        id: anchorProc
        running: true
        command: ["bash", "-c",
            "f=\"$HOME/.config/cloud-center/settings/quickshell/spotlight_anchor\"; " +
            "if [ -f \"$f\" ]; then cat \"$f\"; else echo top; fi"]
        stdout: SplitParser {
            onRead: line => {
                const v = line.trim().toLowerCase();
                if (["top", "bottom", "left", "right"].includes(v))
                    svc.anchor = v;
            }
        }
    }

    Timer {
        id: debounce
        interval: svc.debounceMs
        repeat: false
        onTriggered: svc.runSearch()
    }

    onQueryChanged: {
        if (!visible)
            return;
        if (query.trim().length > 0)
            showingKeybinds = false;
        if (ollamaListMode) {
            if (ollamaListMode !== "confirm")
                filterOllamaModelRows();
            return;
        }
        if (packagesListMode) {
            if (packagesListMode !== "confirm")
                filterPackageRows();
            return;
        }
        if (query.trim().length === 0)
            refreshDisplay();
        else
            debounce.restart();
    }
}
