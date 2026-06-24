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

    function launchDesktopApp(opts) {
        const desktopPath = `${opts?.desktopPath ?? ""}`.trim();
        const exec = `${opts?.exec ?? ""}`.trim();
        if (desktopPath.length > 0) {
            launch(["uwsm-app", "--", desktopPath]);
            return;
        }
        const parts = exec.split(/\s+/).filter(part => part.length > 0);
        if (parts.length === 0)
            return;
        launch(["uwsm-app", "--"].concat(parts));
    }

    function luaString(value) {
        return "\"" + `${value ?? ""}`.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"";
    }

    function dispatch(expression) {
        if (!expression)
            return;
        launch(["hyprctl", "dispatch", expression]);
    }

    function monitorNameForWorkspace(workspaceId) {
        const id = Math.trunc(Number(workspaceId));
        const ws = HyprlandData.workspaceById?.[id];
        if (ws?.monitor)
            return `${ws.monitor}`.trim();

        for (const window of HyprlandData.windowsByWorkspace?.[id] ?? []) {
            const monitorId = Number(window?.monitor ?? -1);
            const monitor = (HyprlandData.monitors ?? []).find(m => Number(m?.id ?? -2) === monitorId);
            if (monitor?.name)
                return monitor.name;
        }

        return "";
    }

    function applyWorkspaceFocus(workspaceId) {
        const id = Math.trunc(Number(workspaceId));
        if (!Number.isFinite(id) || id < 1)
            return;

        const monitorName = monitorNameForWorkspace(id);
        if (monitorName.length)
            dispatch("hl.dsp.focus({ monitor = " + luaString(monitorName) + " })");

        dispatch("hl.dsp.focus({ workspace = " + id + " })");
    }

    function focusWorkspace(workspaceId) {
        const id = Math.trunc(Number(workspaceId));
        if (!Number.isFinite(id) || id < 1)
            return;

        const targetWindow = HyprlandData.mostRecentWindowForWorkspace(id)
            ?? HyprlandData.biggestWindowForWorkspace(id);
        if (targetWindow) {
            focusWindow(targetWindow);
            return;
        }

        applyWorkspaceFocus(id);
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
            applyWorkspaceFocus(workspaceId);

        Qt.callLater(() => dispatch("hl.dsp.focus({ window = " + luaString("address:" + address) + " })"));
    }

    function closeWindowByAddress(address) {
        const addr = `${address ?? ""}`.trim();
        if (!/^0x[0-9a-fA-F]+$/.test(addr))
            return;
        dispatch("hl.dsp.window.close(" + luaString("address:" + addr) + ")");
    }
}
