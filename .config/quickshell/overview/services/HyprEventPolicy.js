.pragma library

function updatePlan(eventName) {
    const name = `${eventName ?? ""}`.trim().toLowerCase();
    const none = {
        debounce: "none", windows: false, monitors: false,
        workspaces: false, activeWorkspace: false
    };

    if (["openlayer", "closelayer", "screencast"].includes(name))
        return none;

    if (name === "windowtitle" || name === "windowtitlev2") {
        return {
            debounce: "title", windows: true, monitors: false,
            workspaces: false, activeWorkspace: false
        };
    }

    if (["openwindow", "closewindow", "movewindow", "movewindowv2"].includes(name)) {
        return {
            debounce: "standard", windows: true, monitors: false,
            workspaces: true, activeWorkspace: false
        };
    }

    const activeWindow = name === "activewindow" || name === "activewindowv2";
    if (["workspace", "workspacev2", "focusedmon", "focusedmonv2"].includes(name)
            || activeWindow) {
        return {
            debounce: "standard", windows: activeWindow, monitors: true,
            workspaces: true, activeWorkspace: true
        };
    }

    return {
        debounce: "standard", windows: true, monitors: true,
        workspaces: true, activeWorkspace: true
    };
}

function titleDebounceMs() {
    return 400;
}
