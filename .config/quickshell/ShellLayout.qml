pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "ShellEdges.js" as ShellEdges

// Which screen edge the bar and the dock sit on. Persisted as one-word files
// next to Cloud Center's monitor settings (bar_on_all_screens, ...). Bar and
// dock never share an edge — setEdge swaps them (ShellEdges.swapResult).
Singleton {
    id: root

    property string barEdge: "top"
    property string dockEdge: "bottom"

    // Drag-to-move (long-press on bar/dock, see EdgeDropOverlay.qml).
    property string movingWhich: ""
    property var moveScreen: null
    property string moveTargetEdge: ""

    readonly property string settingsDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config"))
        + "/cloud-center/settings/monitors/quickshell"

    property string barFileText: ""
    property string dockFileText: ""

    function applyFiles() {
        const pair = ShellEdges.normalizePair(root.barFileText.trim(), root.dockFileText.trim());
        root.barEdge = pair.bar;
        root.dockEdge = pair.dock;
    }

    function setEdge(which, edge) {
        if (!ShellEdges.isEdge(edge) || (which !== "bar" && which !== "dock")) {
            console.warn("ShellLayout: ignoring setEdge", which, edge);
            return;
        }
        const pair = ShellEdges.swapResult(root.barEdge, root.dockEdge, which, edge);
        root.barEdge = pair.bar;
        root.dockEdge = pair.dock;
        writeProc.command = ["sh", "-c",
            'mkdir -p "$1" && printf %s "$2" > "$1/bar_edge" && printf %s "$3" > "$1/dock_edge"',
            "sh", root.settingsDir, pair.bar, pair.dock];
        writeProc.running = false;
        writeProc.running = true;
    }

    function beginMove(which, screen) {
        root.movingWhich = which;
        root.moveScreen = screen;
        root.moveTargetEdge = which === "bar" ? root.barEdge : root.dockEdge;
    }

    // Pointer in screen-local coords of moveScreen.
    function updateMove(x, y, w, h) {
        if (root.movingWhich !== "")
            root.moveTargetEdge = ShellEdges.nearestEdge(x, y, w, h);
    }

    function endMove() {
        const which = root.movingWhich;
        const edge = root.moveTargetEdge;
        root.cancelMove();
        if (which !== "")
            root.setEdge(which, edge);
    }

    function cancelMove() {
        root.movingWhich = "";
        root.moveScreen = null;
        root.moveTargetEdge = "";
    }

    Process {
        id: writeProc
    }

    // ponytail: read once at startup, no watchChanges — every live change goes
    // through setEdge (IPC / drag). Add a watch when Cloud Center writes these.
    FileView {
        path: root.settingsDir + "/bar_edge"
        blockLoading: true
        onLoaded: {
            root.barFileText = text();
            root.applyFiles();
        }
        onLoadFailed: error => root.applyFiles()
    }

    FileView {
        path: root.settingsDir + "/dock_edge"
        blockLoading: true
        onLoaded: {
            root.dockFileText = text();
            root.applyFiles();
        }
        onLoadFailed: error => root.applyFiles()
    }
}
