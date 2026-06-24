pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../../overview/services"
import "../../spotlight"
import "../applibrary"
import "../wallpapers"

Singleton {
    id: svc

    property bool visible: false
    property bool returnToCommandCenter: false
    property string commandCenterReturnMode: "command"
    property var commandCenterReturnBrowseStack: []

    property string powerProfile: "balanced"
    property int selectedIndex: 0
    property int profileFocusIndex: 0
    property string focusZone: "actions"

    readonly property var profileLabels: ["Performance", "Balanced", "Power Saver"]
    readonly property var profileIds: ["performance", "balanced", "power-saver"]

    readonly property var actions: [
        {
            id: "lock",
            label: "Lock",
            icon: "󰷛",
            run: "pidof hyprlock >/dev/null 2>&1 || hyprlock"
        },
        {
            id: "suspend",
            label: "Suspend",
            icon: "󰒲",
            run: "systemctl suspend"
            // TO-DO: Make suspend also send a command to lock the system, so upon awakining
            // The user is prompted with a password
        },
        {
            id: "logout",
            label: "Logout",
            icon: "󰍃",
            command: ["hyprctl", "dispatch", "exit"]
        },
        {
            id: "reboot",
            label: "Reboot",
            icon: "󰜉",
            run: "systemctl reboot"
        },
        {
            id: "shutdown",
            label: "Shutdown",
            icon: "󰐥",
            run: "systemctl poweroff"
        }
    ]

    signal requestFocus()

    function shellQuote(value) {
        const text = `${value ?? ""}`;
        return `'${text.replace(/'/g, `'\\''`)}'`;
    }

    function launch(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        HyprDispatch.launch(cmd);
    }

    function launchShell(script) {
        const body = `${script ?? ""}`.trim();
        if (!body)
            return;
        launch(["bash", "-lc", `cd "$HOME" && ${body}`]);
    }

    function launchCommand(cmd) {
        if (!cmd || cmd.length === 0)
            return;
        if (cmd.length >= 3 && cmd[0] === "bash" && cmd[1] === "-c")
            return launchShell(cmd[2]);
        const inner = cmd.map(part => shellQuote(part)).join(" ");
        launch(["bash", "-lc", `cd "$HOME" && exec ${inner}`]);
    }

    function runAction(action) {
        if (!action)
            return;
        if (action.run)
            launchShell(action.run);
        else if (action.command)
            launchCommand(action.command);
    }

    function profileLabelForId(id) {
        const idx = profileIds.indexOf(id);
        return idx >= 0 ? profileLabels[idx] : "Balanced";
    }

    function activeProfileLabel() {
        return profileLabelForId(powerProfile);
    }

    function openFromCommandCenter(returnMode, returnBrowseStack) {
        returnToCommandCenter = true;
        commandCenterReturnMode = returnMode || "command";
        commandCenterReturnBrowseStack = returnBrowseStack ? returnBrowseStack.slice() : [];
        openInternal();
    }

    function open() {
        returnToCommandCenter = false;
        commandCenterReturnBrowseStack = [];
        openInternal();
    }

    function closeOtherPanels() {
        if (SpotlightService.visible)
            SpotlightService.close();
        if (AppLibraryService.visible)
            AppLibraryService.close();
        if (WallpaperPickerService.visible)
            WallpaperPickerService.close();
    }

    function openInternal() {
        closeOtherPanels();
        visible = true;
        selectedIndex = 0;
        profileFocusIndex = Math.max(0, profileIds.indexOf(powerProfile));
        focusZone = "actions";
        loadPowerProfile();
        requestFocus();
    }

    function close() {
        visible = false;
        selectedIndex = 0;
        returnToCommandCenter = false;
        commandCenterReturnBrowseStack = [];
    }

    function escapePressed() {
        if (returnToCommandCenter) {
            const mode = commandCenterReturnMode;
            const stack = commandCenterReturnBrowseStack.slice();
            close();
            return { commandCenter: true, mode: mode, browseStack: stack };
        }
        close();
        return { commandCenter: false };
    }

    function toggle() {
        if (visible)
            close();
        else
            open();
    }

    function selectProfileIndex(idx) {
        if (idx < 0 || idx >= profileIds.length)
            return;
        profileFocusIndex = idx;
    }

    function applyProfileIndex(idx) {
        if (idx < 0 || idx >= profileIds.length)
            return;
        profileFocusIndex = idx;
        const profile = profileIds[idx];
        if (profile === powerProfile)
            return;
        launch(["powerprofilesctl", "set", profile]);
        Qt.callLater(() => loadPowerProfile());
    }

    function setProfileByIndex(idx) {
        applyProfileIndex(idx);
    }

    function setProfileByLabel(label) {
        const idx = profileLabels.indexOf(label);
        if (idx >= 0)
            setProfileByIndex(idx);
    }

    function activateIndex(idx) {
        if (idx < 0 || idx >= actions.length)
            return;
        runAction(actions[idx]);
        close();
    }

    function loadPowerProfile() {
        powerProfileProc.running = false;
        powerProfileProc.running = true;
    }

    Process {
        id: powerProfileProc
        running: false
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            id: powerProfileOut
            onStreamFinished: {
                const v = powerProfileOut.text.trim();
                if (v.length > 0)
                    svc.powerProfile = v;
                if (!svc.visible) {
                    const idx = svc.profileIds.indexOf(svc.powerProfile);
                    if (idx >= 0)
                        svc.profileFocusIndex = idx;
                }
            }
        }
    }
}
