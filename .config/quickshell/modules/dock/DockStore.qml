pragma Singleton
pragma ComponentBehavior: Bound

// modules/dock/DockStore.qml — persisted dock pins (ordered)
import QtQuick
import Quickshell
import Quickshell.Io
import "../../overview/services"
import "../../overview/services/AppIdentity.js" as AppIdentity

Singleton {
    id: root

    property var pinnedApps: []
    property bool loaded: false

    property var pinnedFolders: []
    property bool foldersLoaded: false

    function folderLabel(path) {
        const p = `${path ?? ""}`.trim();
        if (!p)
            return "";
        const parts = p.split("/").filter(s => s.length > 0);
        return parts.length > 0 ? parts[parts.length - 1] : p;
    }

    function normalizeFolder(entry) {
        const path = `${entry.path ?? ""}`.trim();
        return {
            path: path,
            label: `${entry.label ?? ""}`.trim() || folderLabel(path)
        };
    }

    function cloneFolderList(list) {
        return list.map(f => normalizeFolder(f)).filter(f => f.path.length > 0);
    }

    function saveFolders() {
        const payload = JSON.stringify(root.pinnedFolders);
        saveFoldersProc.environment = ({ "QS_DATA": payload });
        saveFoldersProc.running = false;
        saveFoldersProc.running = true;
    }

    function pinFolder(path) {
        const norm = normalizeFolder({ path: path });
        if (!norm.path)
            return;
        const key = norm.path.toLowerCase();
        let list = root.pinnedFolders.filter(f => `${f.path ?? ""}`.toLowerCase() !== key);
        list.push(norm);
        root.pinnedFolders = list;
        saveFolders();
    }

    function unpinFolder(path) {
        const key = `${path ?? ""}`.trim().toLowerCase();
        root.pinnedFolders = root.pinnedFolders.filter(f => `${f.path ?? ""}`.toLowerCase() !== key);
        saveFolders();
    }

    readonly property var defaultPinnedApps: [
        {
            class: "zen",
            exec: "/opt/zen-browser-bin/zen-bin",
            icon: "zen-browser"
        },
        {
            class: "dev.zed.Zed",
            exec: "zeditor",
            icon: "dev.zed.Zed"
        },
        {
            class: "kitty",
            exec: "kitty",
            icon: "kitty"
        },
        {
            class: "org.gnome.Nautilus",
            exec: "nautilus --new-window",
            icon: "org.gnome.Nautilus"
        },
    ]

    function stripDesktopExecField(s) {
        return HyprlandData.stripDesktopExecField(s);
    }

    function enrichFromDesktop(e) {
        const source = e || {};
        const cls = HyprlandData.normalizeDockClass(source.class || source.wmclass || "");
        const desktop = HyprlandData.desktopModelForClass(cls);
        const norm = AppIdentity.normalizePin(
            source, desktop, null, CursorWorkspaceStore.recentUris);
        norm.class = cls || norm.class;
        const entry = HyprlandData.desktopEntryForClass(norm.class);
        if (entry) {
            const deExec = stripDesktopExecField(entry.exec ?? entry.Exec ?? "");
            const deIcon = `${entry.icon ?? ""}`.trim();
            if (!norm.exec && deExec.length > 0 && !HyprlandData.isStubDockerCliExec(deExec))
                norm.exec = deExec;
            else if (HyprlandData.isStubDockerCliExec(norm.exec))
                norm.exec = "";
            if (!norm.icon && deIcon.length > 0)
                norm.icon = deIcon;
        } else if (HyprlandData.isStubDockerCliExec(norm.exec)) {
            norm.exec = "";
        } else {
            const pwaExec = HyprlandData.chromePwaExecFromClass(norm.class);
            if (pwaExec.length > 0)
                norm.exec = pwaExec;
        }
        return norm;
    }

    function normalizeEntry(e) {
        return enrichFromDesktop(e || {});
    }

    function cloneList(list) {
        return list.map(a => enrichFromDesktop(a));
    }

    function save() {
        const payload = JSON.stringify(root.pinnedApps);
        saveProc.environment = ({
            "QS_DATA": payload
        });
        saveProc.running = false;
        saveProc.running = true;
    }

    function pinEntry(entry, insertIndex) {
        const norm = enrichFromDesktop(entry);
        const key = AppIdentity.pinKey(norm);
        if (!key || key.startsWith("unknown::"))
            return;
        let list = root.pinnedApps.filter(a => AppIdentity.pinKey(a) !== key);
        let at = Math.round(insertIndex);
        if (at < 0)
            at = 0;
        if (at > list.length)
            at = list.length;
        list.splice(at, 0, norm);
        root.pinnedApps = list;
        save();
    }

    function unpinIdentity(identityKey) {
        const key = `${identityKey ?? ""}`.trim().toLowerCase();
        root.pinnedApps = root.pinnedApps.filter(a => AppIdentity.pinKey(a) !== key);
        save();
    }

    function unpinClass(className) {
        const cls = `${className ?? ""}`.trim().toLowerCase();
        const match = root.pinnedApps.find(pin => `${pin.class ?? ""}`.trim().toLowerCase() === cls);
        if (match)
            unpinIdentity(AppIdentity.pinKey(match));
    }

    function movePinned(fromIndex, toIndex) {
        if (fromIndex === toIndex)
            return;
        const list = [...root.pinnedApps];
        if (fromIndex < 0 || fromIndex >= list.length)
            return;
        const item = list.splice(fromIndex, 1)[0];
        let dest = Math.round(toIndex);
        if (dest < 0)
            dest = 0;
        if (dest > list.length)
            dest = list.length;
        list.splice(dest, 0, item);
        root.pinnedApps = list;
        save();
    }

    function setPinnedApps(arr) {
        root.pinnedApps = Array.isArray(arr) ? cloneList(arr) : [];
        save();
    }

    Process {
        id: initFoldersProc
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/dock\";" +
            "mkdir -p \"$dir\";" +
            "if [ ! -r \"$dir/pinned_folders.json\" ]; then echo '__NOFILE__';" +
            "elif [ ! -s \"$dir/pinned_folders.json\" ]; then echo '[]';" +
            "else cat \"$dir/pinned_folders.json\"; fi"
        ]
        stdout: StdioCollector {
            id: initFoldersCollector
            onStreamFinished: {
                const text = initFoldersCollector.text.trim();
                if (text === "__NOFILE__" || !text) {
                    root.pinnedFolders = [];
                    if (text === "__NOFILE__")
                        root.saveFolders();
                    root.foldersLoaded = true;
                    return;
                }
                try {
                    const parsed = JSON.parse(text);
                    root.pinnedFolders = cloneFolderList(Array.isArray(parsed) ? parsed : []);
                } catch (err) {
                    console.warn("dock: failed to parse pinned_folders.json:", err);
                    root.pinnedFolders = [];
                    root.saveFolders();
                }
                root.foldersLoaded = true;
            }
        }
    }

    Process {
        id: saveFoldersProc
        running: false
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/dock\";" +
            "printf '%s' \"$QS_DATA\" > \"$dir/pinned_folders.json\""
        ]
    }

    Process {
        id: initProc
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/dock\";" +
            "mkdir -p \"$dir\";" +
            "if [ ! -r \"$dir/pinned.json\" ]; then echo '__NOFILE__';" +
            "elif [ ! -s \"$dir/pinned.json\" ]; then echo '[]';" +
            "else cat \"$dir/pinned.json\"; fi"
        ]
        stdout: StdioCollector {
            id: initCollector
            onStreamFinished: {
                const text = initCollector.text.trim();
                if (text === "__NOFILE__") {
                    root.pinnedApps = cloneList(root.defaultPinnedApps);
                    root.save();
                    root.loaded = true;
                    return;
                }
                if (!text) {
                    root.pinnedApps = [];
                    root.loaded = true;
                    return;
                }
                try {
                    const parsed = JSON.parse(text);
                    const raw = Array.isArray(parsed) ? parsed : root.defaultPinnedApps;
                    root.pinnedApps = raw.map(a => enrichFromDesktop(a));
                    const migrated = JSON.stringify(root.pinnedApps) !== JSON.stringify(raw);
                    if (migrated)
                        root.save();
                } catch (err) {
                    console.warn("dock: failed to parse pinned.json:", err);
                    root.pinnedApps = cloneList(root.defaultPinnedApps);
                    root.save();
                }
                root.loaded = true;
            }
        }
    }

    Process {
        id: saveProc
        running: false
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/dock\";" +
            "printf '%s' \"$QS_DATA\" > \"$dir/pinned.json\""
        ]
    }

    Component.onCompleted: {
        initProc.running = true;
        initFoldersProc.running = true;
    }
}
