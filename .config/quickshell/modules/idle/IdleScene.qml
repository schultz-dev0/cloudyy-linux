pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var assignedScreen
    screen: assignedScreen
    visible: IdleService.state === "scene"
    color: "#05070a"

    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "cloudyy-idle-scene"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: 0
    property real wakePointerX: -1
    property real wakePointerY: -1

    onVisibleChanged: {
        if (visible) {
            wakePointerX = -1;
            wakePointerY = -1;
        }
    }

    function requestDismiss() {
        if (!dismissIdle.running)
            dismissIdle.running = true;
    }

    function dismissOnPointerMotion(x, y) {
        if (wakePointerX < 0 || wakePointerY < 0) {
            wakePointerX = x;
            wakePointerY = y;
            return;
        }

        const deltaX = x - wakePointerX;
        const deltaY = y - wakePointerY;
        if (deltaX * deltaX + deltaY * deltaY >= 196)
            requestDismiss();
    }

    Process {
        id: dismissIdle
        command: ["cloudyy-idle", "dismiss"]
    }

    Item {
        id: scene
        anchors.fill: parent
        focus: root.visible

        function noise(index, salt) {
            const value = Math.sin((index + 1) * 12.9898 + salt * 78.233) * 43758.5453;
            return value - Math.floor(value);
        }
        property real rainClock: 0
        property real cloudClock: 0
        property real lightningOpacity: 0
        property real lightningX: 0.5
        property real lightningY: 0.16
        property int thunderDelay: 12000

        Timer {
            interval: 16
            running: root.visible
            repeat: true
            onTriggered: {
                scene.rainClock = Date.now();
                scene.cloudClock = scene.rainClock;
            }
        }

        Timer {
            interval: scene.thunderDelay
            running: root.visible
            repeat: true
            onTriggered: {
                scene.lightningX = 0.18 + Math.random() * 0.64;
                scene.lightningY = 0.05 + Math.random() * 0.30;
                thunderFlash.restart();
                scene.thunderDelay = 12000 + Math.floor(Math.random() * 18000);
            }
        }

        SequentialAnimation {
            id: thunderFlash
            PropertyAction { target: scene; property: "lightningOpacity"; value: 0.14 }
            PauseAnimation { duration: 55 }
            NumberAnimation { target: scene; property: "lightningOpacity"; to: 0; duration: 120 }
            PauseAnimation { duration: 110 }
            PropertyAction { target: scene; property: "lightningOpacity"; value: 0.12 }
            PauseAnimation { duration: 35 }
            NumberAnimation { target: scene; property: "lightningOpacity"; to: 0; duration: 170 }
        }

        Keys.onPressed: event => {
            root.requestDismiss();
            event.accepted = true;
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: parent.height * 0.19
            color: "#0a1011"
        }

        Repeater {
            model: [
                { y: 0.07, scale: 0.52, opacity: 0.30, phase: 0.08, duration: 76000 },
                { y: 0.15, scale: 0.72, opacity: 0.52, phase: 0.29, duration: 98000 },
                { y: 0.10, scale: 0.45, opacity: 0.42, phase: 0.53, duration: 86000 },
                { y: 0.21, scale: 0.46, opacity: 0.26, phase: 0.76, duration: 112000 },
            ]
            delegate: Text {
                required property var modelData
                readonly property real progress: (scene.cloudClock / modelData.duration + modelData.phase) % 1
                x: -width + progress * (scene.width + width * 2)
                y: scene.height * modelData.y
                text: "          .-~~~-.          \n"
                    + "  .- ~ ~-(       )_ _      \n"
                    + " /                    ~ -. \n"
                    + "|                          ',\n"
                    + " \\                         .'\n"
                    + "   ~- ._ ,. ,.,.,., ,.. -~ \n"
                    + "           '       '       "
                color: "#113321"
                opacity: modelData.opacity
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: Math.max(20, scene.width / 76) * modelData.scale
                lineHeight: 0.84
            }
        }

        Repeater {
            model: 115
            delegate: Rectangle {
                required property int index
                readonly property real horizontal: scene.noise(index, 1)
                readonly property real phase: scene.noise(index, 2)
                readonly property real length: 5 + scene.noise(index, 3) * 13
                readonly property int fallDuration: 800 + scene.noise(index, 4) * 1900
                readonly property real progress: (scene.rainClock / fallDuration + phase) % 1
                width: 1
                height: length
                x: horizontal * Math.max(1, scene.width - width)
                y: -height + progress * (scene.height * (0.84 + scene.noise(index, 6) * 0.10) + height)
                radius: width / 2
                color: "#79aebd"
                opacity: 0.16 + scene.noise(index, 5) * 0.44
            }
        }

        Repeater {
            model: 28
            delegate: Text {
                required property int index
                property int glyph: index % 3
                text: glyph === 0 ? "*" : glyph === 1 ? "." : "'"
                x: (index * 151 + 47) % Math.max(1, scene.width)
                y: scene.height * 0.83 + (index % 4) * 9
                color: "#78a8ae"
                opacity: 0
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 15 + index % 9
                SequentialAnimation on opacity {
                    running: root.visible
                    loops: Animation.Infinite
                    PauseAnimation { duration: 200 + (index % 10) * 290 }
                    NumberAnimation { to: 0.72; duration: 90 }
                    NumberAnimation { to: 0; duration: 320 }
                }
            }
        }

        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 36 }
            text: "CLOUDYY // RAINFALL"
            color: "#7d9da4"
            opacity: 0.72
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 13
        }

        Text {
            x: scene.width * scene.lightningX - width / 2
            y: scene.height * scene.lightningY
            text: "       /\\\n"
                + "      /  \\\n"
                + "        /  \\\n"
                + "       /  \\\n"
                + "      /  \\\n"
                + "       \\/"
            color: "#e0fbff"
            opacity: Math.min(1, scene.lightningOpacity * 4)
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: Math.max(18, scene.width / 96)
            lineHeight: 0.76
            z: 2
        }

        Rectangle {
            anchors.fill: parent
            color: "#c3edf2"
            opacity: scene.lightningOpacity
            z: 1
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: root.dismissOnPointerMotion(mouse.x, mouse.y)
            onClicked: root.requestDismiss()
            z: 3
        }
    }
}
