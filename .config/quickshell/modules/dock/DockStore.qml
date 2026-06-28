pragma Singleton
pragma ComponentBehavior: Bound

// modules/dock/DockStore.qml — persisted dock pins (ordered)
import QtQuick
import Quickshell
import Quickshell.Io
import "../../overview/services"

Singleton {
    id: root

    property var pinnedApps: []
    property bool loaded: false

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
            class: "thunar",
            exec: "thunar",
            icon: "org.xfce.thunar"
        },
        {
            class: "spotify",
            exec: "spotify",
            icon: "spotify"
        }
    ]

    function stripDesktopExecField(s) {
        const t = `${s ?? ""}`.trim();
        if (!t)
            return "";
        return t.replace(/%[A-Za-z]/g, "").trim();
    }

    function enrichFromDesktop(e) {
        const norm = normalizeEntry(e);
        norm.class = HyprlandData.normalizeChromePwaWmclass(norm.class);
        const entry = HyprlandData.desktopEntryForClass(norm.class);
        if (entry) {
            const deExec = stripDesktopExecField(entry.exec ?? entry.Exec ?? "");
            const deIcon = `${entry.icon ?? ""}`.trim();
            if (deExec.length > 0)
                norm.exec = deExec;
            if (deIcon.length > 0)
                norm.icon = deIcon;
        } else {
            const pwaExec = HyprlandData.chromePwaExecFromClass(norm.class);
            if (pwaExec.length > 0)
                norm.exec = pwaExec;
        }
        return norm;
    }

    function normalizeEntry(e) {
        return {
            class: `${e.class ?? ""}`.trim(),
            exec: e.exec ?? "",
            icon: `${e.icon ?? ""}`.trim()
        };
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
        const cls = norm.class.toLowerCase();
        if (!cls)
            return;
        let list = root.pinnedApps.filter(a => (a.class || "").toLowerCase() !== cls);
        let at = Math.round(insertIndex);
        if (at < 0)
            at = 0;
        if (at > list.length)
            at = list.length;
        list.splice(at, 0, norm);
        root.pinnedApps = list;
        save();
    }

    function unpinClass(className) {
        const cls = (className || "").toLowerCase();
        root.pinnedApps = root.pinnedApps.filter(a => (a.class || "").toLowerCase() !== cls);
        save();
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
                    const migrated = JSON.stringify(root.pinnedApps) !== JSON.stringify(raw.map(a => normalizeEntry(a)));
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
    }
}
