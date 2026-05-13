pragma Singleton
pragma ComponentBehavior: Bound

// modules/dock/DockStore.qml — persisted dock pins (ordered)
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var pinnedApps: []
    property bool loaded: false

    readonly property var defaultPinnedApps: [
        {
            class: "zen",
            exec: "zen-browser",
            icon: "zen-browser"
        },
        {
            class: "dev.zed.Zed",
            exec: "zeditor",
            icon: "zed"
        },
        {
            class: "kitty",
            exec: "kitty",
            icon: "kitty"
        },
        {
            class: "thunar",
            exec: "thunar",
            icon: "xfce-filemanager"
        },
        {
            class: "spotify",
            exec: "spotify",
            icon: "spotify"
        }
    ]

    function normalizeEntry(e) {
        return {
            class: `${e.class ?? ""}`.trim(),
            exec: e.exec ?? "",
            icon: `${e.icon ?? ""}`.trim()
        };
    }

    function cloneList(list) {
        return list.map(a => normalizeEntry(a));
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
        const norm = normalizeEntry(entry);
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
                    if (Array.isArray(parsed))
                        root.pinnedApps = cloneList(parsed);
                    else
                        root.pinnedApps = cloneList(root.defaultPinnedApps);
                } catch (err) {
                    console.warn("dock: failed to parse pinned.json:", err);
                    root.pinnedApps = cloneList(root.defaultPinnedApps);
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
