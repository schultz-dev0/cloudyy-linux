import QtQuick
import Quickshell
import Quickshell.Io
import "."

FloatingWindow {
    id: root
    title: "Welcome to Cloudyy"
    implicitWidth: 560
    implicitHeight: 460
    color: "transparent"

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string oobeDir: root.home + "/.config/OOBE"

    property string cTitle: "Welcome to Cloudyy"
    property string cSubtitle: ""
    property string keybindsTitle: "Keybinds"
    property string keybindsSub: ""
    property string cloudCenterTitle: "Explore Cloud Center"
    property string cloudCenterSub: ""
    property string updateTitle: "Run system update"
    property string updateSub: ""

    FileView {
        id: contentFile
        path: root.oobeDir + "/content.conf"
        onLoaded: root.parseContent(text())
    }

    function parseContent(raw) {
        if (!raw)
            return;
        const map = {};
        raw.split("\n").forEach(line => {
            const eq = line.indexOf("=");
            if (eq < 0)
                return;
            const key = line.slice(0, eq).trim();
            let value = line.slice(eq + 1).trim();
            if (value.startsWith("\"") && value.endsWith("\""))
                value = value.slice(1, -1);
            map[key] = value;
        });
        if (map.TITLE) root.cTitle = map.TITLE;
        if (map.SUBTITLE) root.cSubtitle = map.SUBTITLE;
        if (map.KEYBINDS_TITLE) root.keybindsTitle = map.KEYBINDS_TITLE;
        if (map.KEYBINDS_SUB) root.keybindsSub = map.KEYBINDS_SUB;
        if (map.CLOUDCENTER_TITLE) root.cloudCenterTitle = map.CLOUDCENTER_TITLE;
        if (map.CLOUDCENTER_SUB) root.cloudCenterSub = map.CLOUDCENTER_SUB;
        if (map.UPDATE_TITLE) root.updateTitle = map.UPDATE_TITLE;
        if (map.UPDATE_SUB) root.updateSub = map.UPDATE_SUB;
    }

    function launch(cmd) {
        launchProc.command = ["bash", "-lc", cmd];
        launchProc.running = false;
        launchProc.running = true;
    }

    Process {
        id: launchProc
        command: ["true"]
        running: false
    }

    Process {
        id: dismissProc
        command: ["bash", "-lc", "touch '" + root.oobeDir + "/.dont_show'"]
        running: false
        onRunningChanged: if (!running) Qt.quit()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.background

        Column {
            anchors { fill: parent; margins: 28 }
            spacing: 18

            Text {
                text: root.cTitle
                color: Theme.on_surface
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 24; weight: Font.Bold }
                renderType: Text.NativeRendering
            }
            Text {
                text: root.cSubtitle
                color: Theme.on_surface_variant
                width: parent.width
                wrapMode: Text.WordWrap
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 13 }
                renderType: Text.NativeRendering
            }

            Column {
                width: parent.width
                spacing: 12

                WelcomeCard {
                    width: parent.width
                    cardTitle: root.keybindsTitle
                    cardSubtitle: root.keybindsSub
                    buttonLabel: "Open →"
                    onClicked: root.launch("cloudyy-center keybinds")
                }
                WelcomeCard {
                    width: parent.width
                    cardTitle: root.cloudCenterTitle
                    cardSubtitle: root.cloudCenterSub
                    buttonLabel: "Open →"
                    onClicked: root.launch("cloudyy-center")
                }
                WelcomeCard {
                    width: parent.width
                    cardTitle: root.updateTitle
                    cardSubtitle: root.updateSub
                    buttonLabel: "Update →"
                    onClicked: root.launch(
                        "command -v cloudyy-update >/dev/null 2>&1 && cloudyy-update || " +
                        "kitty --hold --title 'System Update' -e sh -c " +
                        "'(command -v yay >/dev/null 2>&1 && yay -Syu) || paru -Syu'")
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24

                Text {
                    text: "Skip for now"
                    color: Theme.outline
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; underline: true }
                    renderType: Text.NativeRendering
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.quit()
                    }
                }
                Text {
                    text: "Don't show this again"
                    color: Theme.outline
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; underline: true }
                    renderType: Text.NativeRendering
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dismissProc.running = true
                    }
                }
            }
        }
    }
}
