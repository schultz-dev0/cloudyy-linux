// lock/shell.qml
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import "." // Shared Theme.qml is symlinked into this standalone config root.

ShellRoot {
    id: root

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/cloudyy-lock"
    readonly property string readyFile: runtimeDir + "/secure"
    readonly property string wallpaperPath: Quickshell.env("HOME")
        + "/.config/hypr/theme_state/current_wallpaper/current.jpg"
    readonly property string user: Quickshell.env("USER")
    readonly property string promptOutput: Quickshell.env("CLOUDYY_LOCK_PROMPT_OUTPUT")
    readonly property string workspaceAnimation: Quickshell.env("CLOUDYY_LOCK_WORKSPACE_ANIMATION")
    readonly property bool responseRequired: pam.responseRequired
    readonly property bool responseVisible: pam.responseVisible
    readonly property bool authenticating: pam.active

    property bool secure: false
    property bool unlocking: false
    property string errorMessage: ""
    property date now: new Date()

    function beginAuthentication() {
        if (!pam.active && !pam.start())
            errorMessage = "Authentication unavailable";
    }

    function respond(password: string) {
        if (!secure || !pam.responseRequired || pam.responseVisible)
            return;

        errorMessage = "";
        pam.respond(password);
    }

    function failAuthentication(message: string) {
        errorMessage = message;
        retryTimer.restart();
    }

    function isPromptScreen(screen) {
        if (promptOutput !== "")
            return screen.name === promptOutput;
        return Quickshell.screens.length > 0 && screen.name === Quickshell.screens[0].name;
    }

    function finishUnlock() {
        if (unlocking)
            return;

        unlocking = true;
        retryTimer.stop();
        if (pam.active)
            pam.abort();
        unlockTimer.restart();
    }

    WlSessionLock {
        id: sessionLock
        locked: true

        surface: LockSurface {
            lockService: root
        }

        onSecureStateChanged: {
            if (!sessionLock.secure)
                return;

            root.secure = true;
            readyMarker.running = true;
            root.beginAuthentication();
        }
    }

    PamContext {
        id: pam
        config: "cloudyy-lock"
        user: Quickshell.env("USER")

        onCompleted: result => {
            if (root.unlocking)
                return;

            if (result === PamResult.Success) {
                root.errorMessage = "";
                root.finishUnlock();
            } else {
                root.failAuthentication("Authentication failed");
            }
        }

        onError: root.failAuthentication("Authentication unavailable")
    }

    Process {
        id: readyMarker
        command: ["touch", root.readyFile]
    }

    Process {
        id: finishedMarker
        command: ["rm", "-f", root.readyFile]
    }

    Timer {
        id: retryTimer
        interval: 250
        repeat: false
        onTriggered: {
            if (root.secure && !pam.active)
                root.beginAuthentication();
        }
    }

    Timer {
        id: unlockTimer
        interval: root.workspaceAnimation === "none" ? 0 : 180
        repeat: false
        onTriggered: {
            sessionLock.locked = false;
            finishedMarker.running = true;
            quitTimer.restart();
        }
    }

    Timer {
        id: quitTimer
        interval: 100
        repeat: false
        onTriggered: Qt.quit()
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
}
