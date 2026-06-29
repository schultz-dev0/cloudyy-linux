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

    function shellQuote(value) {
        const s = `${value ?? ""}`;
        return "'" + s.replace(/'/g, "'\\''") + "'";
    }

    // Detach GUI apps from quickshell so a shell reload does not kill them.
    function launchDetached(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        const inner = cmd.map(part => shellQuote(part)).join(" ");
        launch(["bash", "-lc", `setsid ${inner} </dev/null >/dev/null 2>&1 &`]);
    }

    function profileFromExec(exec) {
        const s = `${exec ?? ""}`;
        const m = s.match(/--profile-directory=(?:"([^"]+)"|'([^']+)'|(Default|Profile\s+\d+))/i);
        if (!m)
            return "Default";
        return (m[1] || m[2] || m[3]).trim();
    }

    function chromePwaLaunchParts(exec) {
        const s = `${exec ?? ""}`.trim();
        const appIdM = s.match(/--app-id=([a-z0-9]+)/i);
        if (!appIdM)
            return [];
        const appId = appIdM[1];
        const profile = profileFromExec(s);

        if (/flatpak|com\.google\.Chrome/i.test(s)) {
            return [
                "flatpak", "run", "com.google.Chrome",
                `--profile-directory=${profile}`,
                `--app-id=${appId}`
            ];
        }

        if (/msedge|microsoft-edge|com\.microsoft\.Edge/i.test(s)) {
            if (/flatpak|com\.microsoft\.Edge/i.test(s))
                return [
                    "flatpak", "run", "com.microsoft.Edge",
                    `--profile-directory=${profile}`,
                    `--app-id=${appId}`
                ];
            let edgeBin = "microsoft-edge-stable";
            const edgePath = s.match(/(\/[\w./-]*(?:microsoft-edge|msedge)[\w.-]*)/i);
            if (edgePath)
                edgeBin = edgePath[1];
            return [edgeBin, `--profile-directory=${profile}`, `--app-id=${appId}`];
        }

        let bin = "google-chrome-stable";
        const chromePath = s.match(/(\/[\w./-]*google-chrome(?:-stable)?)/i)
            || s.match(/(\/opt\/google\/chrome\/google-chrome)/i);
        if (chromePath)
            bin = chromePath[1];
        // Arch/deb packages often ship only google-chrome-stable in PATH.
        if (bin === "/opt/google/chrome/google-chrome")
            bin = "google-chrome-stable";
        else if (/brave/i.test(s)) {
            bin = "brave";
            const bravePath = s.match(/(\/[\w./-]*brave[\w.-]*)/i);
            if (bravePath)
                bin = bravePath[1];
        } else if (/chromium/i.test(s) && !/google-chrome/i.test(s)) {
            bin = "chromium";
            const chromiumPath = s.match(/(\/[\w./-]*chromium)/i);
            if (chromiumPath)
                bin = chromiumPath[1];
        }

        return [bin, `--profile-directory=${profile}`, `--app-id=${appId}`];
    }

    function parseDesktopExec(exec) {
        const s = `${exec ?? ""}`.replace(/ %[a-zA-Z]/g, "").trim();
        if (!s)
            return [];

        if (/^(chrome|chromium|msedge)-[a-z0-9]+-/i.test(s)) {
            const pwaExec = HyprlandData.chromePwaExecFromClass(s);
            if (pwaExec.length > 0) {
                const pwa = chromePwaLaunchParts(pwaExec);
                if (pwa.length > 0)
                    return pwa;
            }
        }

        if (/--app-id=/i.test(s)) {
            const pwa = chromePwaLaunchParts(s);
            if (pwa.length > 0)
                return pwa;
        }

        const parts = [];
        const re = /'([^']*)'|"([^"]*)"|(\S+)/g;
        let m;
        while ((m = re.exec(s)) !== null)
            parts.push(m[1] ?? m[2] ?? m[3]);
        return parts;
    }

    function launchDesktopApp(opts) {
        const desktopPath = `${opts?.desktopPath ?? ""}`.trim();
        const exec = `${opts?.exec ?? ""}`.trim();
        if (desktopPath.length > 0) {
            launchDetached(["uwsm-app", "--", desktopPath]);
            return;
        }
        const parts = parseDesktopExec(exec);
        if (parts.length > 0)
            launchDetached(["uwsm-app", "--"].concat(parts));
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

    function focusWindowForApp(wmclass, exec) {
        const needle = `${wmclass ?? ""}`.trim();
        if (!needle)
            return;

        const windows = HyprlandData.windowList || [];
        for (let i = 0; i < windows.length; i++) {
            const win = windows[i];
            const cls = `${win.class || win.initialClass || ""}`.trim();
            if (!cls)
                continue;
            if (cls === needle || HyprlandData.wmclassesMatch(needle, cls)) {
                focusWindow(win);
                return;
            }
        }

        focusWindowByClass(HyprlandData.normalizeChromePwaWmclass(needle) || needle);
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

        const workspaceName = `${windowData?.workspace?.name ?? ""}`.trim();
        if (workspaceName.startsWith("special:")) {
            const specialName = workspaceName.slice("special:".length);
            const activeName = `${HyprlandData.activeWorkspace?.name ?? ""}`.trim();
            const onActiveSpecial = activeName === workspaceName
                || activeName === specialName
                || activeName === `special:${specialName}`;
            if (!onActiveSpecial)
                dispatch("hl.dsp.workspace.toggle_special(" + luaString(specialName) + ")");
            Qt.callLater(() => dispatch("hl.dsp.focus({ window = " + luaString("address:" + address) + " })"));
            return;
        }

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
