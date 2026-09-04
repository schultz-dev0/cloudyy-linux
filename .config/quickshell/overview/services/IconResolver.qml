pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: resolver

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string resolveScript: Qt.resolvedUrl("icon_resolve.py").toString().replace("file://", "")
    readonly property string indexFile: homeDir + "/.config/cloud-center/settings/quickshell/icon_index.json"
    readonly property string genericIconSource: {
        const themed = Quickshell.iconPath("application-default-icon", "");
        if (themed && `${themed}`.length > 0)
            return themed;
        return "file:///usr/share/icons/Fluent-green/scalable/apps/application-default-icon.svg";
    }

    property var pathByName: ({})
    property bool indexReady: false
    property var runtimeCache: ({})
    // Names already handed to lookupNameAsync this session (hit OR miss). Mutated
    // in place so it never emits — its only job is to stop the same name being
    // re-spawned every time runtimeCache/pathByName change and wake every AppIcon.
    property var attemptedNames: ({})

    function normalizeName(icon) {
        const raw = `${icon ?? ""}`.trim();
        const withoutProvider = raw.replace(/^image:\/\/icon\//, "");
        return withoutProvider.split("?")[0].trim();
    }

    function aliasNames(iconName) {
        const normalized = normalizeName(iconName);
        if (!normalized)
            return [];
        const names = [normalized];
        // Window classes like "Proton Mail" never match a lowercase-dashed
        // .desktop stem / freedesktop icon name; try the slug form too.
        const slug = normalized.replace(/\s+/g, "-").toLowerCase();
        if (slug && !names.includes(slug))
            names.push(slug);
        const aliases = {
            "xfce-filemanager": "org.xfce.thunar",
            "thunar": "org.xfce.thunar",
            "cursor": "co.anysphere.cursor",
            "zen": "zen-browser",
            "zen-bin": "zen-browser",
            "vesktop": "dev.vencord.Vesktop",
            "dev.vencord.vesktop": "dev.vencord.Vesktop",
            "dev.zed.zed": "dev.zed.Zed",
            "zeditor": "dev.zed.Zed",
            "steam-native": "steam",
            "steam-launcher": "steam",
            "steam-icon": "steam",
            "md.obsidian.obsidian": "obsidian",
            "appimagekit-obsidian": "obsidian",
            "org.cloudyy.cloudcenter": "cloud-center"
        };
        const alias = aliases[normalized];
        if (alias && !names.includes(alias))
            names.push(alias);
        const steamApp = normalized.match(/^steam_app_(\d+)$/i);
        if (steamApp) {
            const iconName = `steam_icon_${steamApp[1]}`;
            if (!names.includes(iconName))
                names.push(iconName);
        }
        if (normalized.toLowerCase().endsWith("cloudcenter") && !names.includes("cloud-center"))
            names.push("cloud-center");
        return names;
    }

    function fileUrl(path) {
        const value = `${path ?? ""}`.trim();
        if (!value)
            return "";
        return value.startsWith("file://") ? value : `file://${value}`;
    }

    function directIconSource(iconName) {
        const normalized = normalizeName(iconName);
        if (normalized.startsWith("/"))
            return fileUrl(normalized);
        if (normalized.startsWith("~")) {
            const home = `${homeDir}`.trim();
            if (home.length > 0)
                return fileUrl(`${home}${normalized.substring(1)}`);
        }
        return "";
    }

    function pathForName(iconName) {
        const names = aliasNames(iconName);
        for (let i = 0; i < names.length; i++) {
            const key = names[i];
            const lower = key.toLowerCase();
            const hit = pathByName[key] || pathByName[lower] || runtimeCache[key] || runtimeCache[lower];
            if (hit)
                return hit;
        }
        return "";
    }

    function pushUniqueSource(sources, value) {
        const source = `${value ?? ""}`.trim();
        if (!source || sources.includes(source))
            return;
        sources.push(source);
    }

    function sourcesForName(iconName) {
        const normalized = normalizeName(iconName);
        if (!normalized)
            return [genericIconSource];

        const sources = [];
        const direct = directIconSource(normalized);
        if (direct)
            pushUniqueSource(sources, direct);

        for (let i = 0; i < aliasNames(normalized).length; i++) {
            const name = aliasNames(normalized)[i];
            const indexed = pathForName(name);
            if (indexed)
                pushUniqueSource(sources, fileUrl(indexed));

            const themed = Quickshell.iconPath(name, "");
            if (themed)
                pushUniqueSource(sources, themed);
        }

        pushUniqueSource(sources, genericIconSource);
        return sources.length > 0 ? sources : [genericIconSource];
    }

    function sourcesForApp(app) {
        if (!app)
            return [genericIconSource];

        const sources = [];
        const icon = `${app.icon ?? ""}`.trim();

        if (icon) {
            if (icon.startsWith("/") || icon.startsWith("file://"))
                pushUniqueSource(sources, icon.startsWith("file://") ? icon : fileUrl(icon));
            else {
                const resolved = sourcesForName(icon);
                for (let j = 0; j < resolved.length; j++)
                    pushUniqueSource(sources, resolved[j]);
            }
        }

        const iconPath = `${app.iconPath ?? ""}`.trim();
        if (iconPath)
            pushUniqueSource(sources, fileUrl(iconPath));

        const id = `${app.id ?? ""}`.trim();
        if (id && id !== icon) {
            const resolved = sourcesForName(id);
            for (let j = 0; j < resolved.length; j++)
                pushUniqueSource(sources, resolved[j]);
        }

        const wmclass = `${app.wmclass ?? ""}`.trim();
        if (wmclass && wmclass !== icon && wmclass !== id) {
            const resolved = sourcesForName(wmclass);
            for (let j = 0; j < resolved.length; j++)
                pushUniqueSource(sources, resolved[j]);
        }

        pushUniqueSource(sources, genericIconSource);
        return sources.length > 0 ? sources : [genericIconSource];
    }

    function lookupNameAsync(iconName) {
        const key = normalizeName(iconName);
        if (!key || attemptedNames[key] || runtimeCache[key] || pathByName[key] || pathByName[key.toLowerCase()])
            return;
        // ponytail: never retried this session even if the icon theme changes;
        // buildIndexProc rebuilding pathByName is the recovery path, restart is the fallback.
        attemptedNames[key] = true;

        const proc = lookupProto.createObject(resolver, {
            command: ["python3", resolveScript, "lookup", key]
        });
        proc.stdout = lookupCollectorProto.createObject(proc);
        proc.stdout.onStreamFinished.connect(() => {
            const path = `${proc.stdout.text ?? ""}`.trim();
            if (path.length > 0) {
                const next = Object.assign({}, runtimeCache);
                next[key] = path;
                next[key.toLowerCase()] = path;
                runtimeCache = next;
            }
            proc.destroy();
        });
        proc.running = true;
    }

    function applyIndexText(raw) {
        const text = `${raw ?? ""}`.trim();
        if (!text)
            return;
        try {
            const parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object")
                pathByName = parsed;
        } catch (e) {
            console.warn("icon-resolver: failed to parse index", e);
        }
        indexReady = true;
    }

    Component {
        id: lookupProto
        Process {}
    }

    Component {
        id: lookupCollectorProto
        StdioCollector {}
    }

    function refreshIndex() {
        if (buildIndexProc.running)
            return;
        buildIndexProc.running = false;
        buildIndexProc.running = true;
    }

    Component.onCompleted: {
        readIndexProc.running = true;
        buildIndexProc.running = true;
    }

    Process {
        id: readIndexProc
        running: false
        command: ["bash", "-c", "if [ -f \"" + resolver.indexFile + "\" ]; then cat \"" + resolver.indexFile + "\"; fi"]
        stdout: StdioCollector {
            id: readIndexCollector
            onStreamFinished: resolver.applyIndexText(readIndexCollector.text)
        }
    }

    Process {
        id: buildIndexProc
        running: false
        command: ["python3", resolver.resolveScript, "build-index", resolver.indexFile]
        stdout: StdioCollector {
            id: buildIndexCollector
            onStreamFinished: resolver.applyIndexText(buildIndexCollector.text)
        }
    }
}
