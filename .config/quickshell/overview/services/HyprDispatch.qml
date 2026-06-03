pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Hyprland 0.55+ Lua dispatch helpers.
 * Replaces legacy Hyprland.dispatch("workspace N") / focuswindow syntax.
 */
Singleton {
    id: root

    Component {
        id: procProto
        Process {}
    }

    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;

        const p = procProto.createObject(root, {
            command: cmd
        });
        p.runningChanged.connect(() => {
            if (!p.running)
                p.destroy();
        });
        p.running = true;
    }

    function luaString(value) {
        return "\"" + `${value ?? ""}`.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    function dispatch(expression) {
        if (!expression)
            return;
        launch(["hyprctl", "dispatch", expression]);
    }

    function focusWorkspace(workspaceId) {
        const id = Number(workspaceId);
        if (!Number.isFinite(id) || id < 1)
            return;
        dispatch("hl.dsp.focus({ workspace = " + Math.trunc(id) + " })");
    }

    function focusWorkspaceRelative(direction) {
        const dir = `${direction ?? ""}`.trim();
        if (dir.length === 0)
            return;
        dispatch('hl.dsp.focus({ workspace = "' + dir.replace(/"/g, "") + '" })');
    }

    function focusWindowByClass(className) {
        const cls = `${className ?? ""}`.trim();
        if (!cls)
            return;
        dispatch("hl.dsp.focus({ window = " + luaString("class:" + cls) + " })");
    }

    function focusWindowByTitle(title) {
        const t = `${title ?? ""}`.trim();
        if (!t)
            return;
        dispatch("hl.dsp.focus({ window = " + luaString("title:" + t) + " })");
    }

    function focusWindow(windowData) {
        const address = `${windowData?.address ?? ""}`.trim();
        if (!/^0x[0-9a-fA-F]+$/.test(address))
            return;

        const workspaceId = Number(windowData?.workspace?.id ?? -1);
        if (Number.isFinite(workspaceId) && workspaceId > 0)
            focusWorkspace(workspaceId);

        Qt.callLater(() => dispatch("hl.dsp.focus({ window = " + luaString("address:" + address) + " })"));
    }

    function closeWindowByAddress(address) {
        const addr = `${address ?? ""}`.trim();
        if (!/^0x[0-9a-fA-F]+$/.test(addr))
            return;
        dispatch("hl.dsp.window.close(" + luaString("address:" + addr) + ")");
    }
}
