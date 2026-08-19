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

        // Where the ground starts. Single source of truth -- the ground rect and
        // the bolt's strike length both derive from it.
        readonly property real groundTop: scene.height * 0.81

        // Bolt is generated per strike rather than drawn as fixed art: walk down
        // one row at a time picking from "| / \", and let the glyph decide the
        // sideways step. The zigzag falls out of the glyph choice for free.
        property var boltSegments: []
        property int boltGrown: 0
        property real boltFade: 0
        property real sparkProgress: 0
        property int strikeSeed: 0
        property real boltTipX: 0
        property real boltTipY: 0
        readonly property real boltPixelSize: Math.max(18, scene.width / 96)
        readonly property real boltColumnStep: boltPixelSize * 0.6
        readonly property real boltRowStep: boltPixelSize * 0.76

        function growBolt(segments, column, row, lastRow, canBranch) {
            while (row < lastRow) {
                const roll = Math.random();
                const glyph = roll < 0.34 ? "|" : roll < 0.67 ? "/" : "\\";
                segments.push({ column: column, row: row, glyph: glyph });
                column += glyph === "\\" ? 1 : glyph === "/" ? -1 : 0;
                row += 1;
                if (canBranch && Math.random() < 0.14)
                    growBolt(segments, column, row, Math.min(lastRow, row + 4 + Math.floor(Math.random() * 5)), false);
            }
        }

        function buildBolt() {
            const segments = [];
            const startY = scene.height * scene.lightningY;
            const rows = Math.max(6, Math.round((scene.groundTop - startY) / scene.boltRowStep));
            growBolt(segments, 0, 0, rows, true);
            const tip = segments[segments.length - 1];
            scene.boltTipX = scene.width * scene.lightningX + tip.column * scene.boltColumnStep;
            scene.boltTipY = scene.height * scene.lightningY + tip.row * scene.boltRowStep;
            scene.strikeSeed = scene.strikeSeed + 1;
            scene.boltSegments = segments;
        }
        property real rainClock: 0
        property real cloudClock: 0
        property real lightningOpacity: 0
        property real lightningX: 0.5
        property real lightningY: 0.16
        property int thunderDelay: 12000

        // Vsync-locked instead of a fixed 16ms Timer, which beats against any
        // refresh rate that isn't exactly 62.5Hz.
        FrameAnimation {
            running: root.visible
            onTriggered: {
                scene.rainClock = elapsedTime * 1000;
                scene.cloudClock = scene.rainClock;
            }
        }

        Timer {
            interval: scene.thunderDelay
            running: root.visible
            repeat: true
            onTriggered: {
                scene.lightningX = 0.18 + Math.random() * 0.64;
                scene.lightningY = Math.random() * 0.03;
                thunderFlash.restart();
                scene.thunderDelay = 12000 + Math.floor(Math.random() * 18000);
            }
        }

        SequentialAnimation {
            id: thunderFlash

            // `to` is assigned imperatively, not bound -- binding it to
            // boltSegments.length makes Qt cry binding loop.
            ScriptAction {
                script: {
                    scene.buildBolt();
                    boltGrowth.to = scene.boltSegments.length;
                }
            }
            PropertyAction { target: scene; property: "boltFade"; value: 1 }
            PropertyAction { target: scene; property: "sparkProgress"; value: 0 }

            ParallelAnimation {
                NumberAnimation { id: boltGrowth; target: scene; property: "boltGrown"; from: 0; duration: 170 }
                SequentialAnimation {
                    PropertyAction { target: scene; property: "lightningOpacity"; value: 0.14 }
                    PauseAnimation { duration: 55 }
                    NumberAnimation { target: scene; property: "lightningOpacity"; to: 0; duration: 120 }
                    PauseAnimation { duration: 110 }
                    PropertyAction { target: scene; property: "lightningOpacity"; value: 0.12 }
                    PauseAnimation { duration: 35 }
                    NumberAnimation { target: scene; property: "lightningOpacity"; to: 0; duration: 170 }
                }
            }

            ParallelAnimation {
                NumberAnimation { target: scene; property: "sparkProgress"; to: 1; duration: 620 }
                SequentialAnimation {
                    PauseAnimation { duration: 90 }
                    NumberAnimation { target: scene; property: "boltFade"; to: 0; duration: 320 }
                }
            }
        }

        Keys.onPressed: event => {
            root.requestDismiss();
            event.accepted = true;
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: scene.height - scene.groundTop
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

        Repeater {
            model: scene.boltSegments
            delegate: Text {
                required property var modelData
                required property int index
                x: scene.width * scene.lightningX + modelData.column * scene.boltColumnStep
                y: scene.height * scene.lightningY + modelData.row * scene.boltRowStep
                text: modelData.glyph
                color: "#e0fbff"
                opacity: index < scene.boltGrown ? scene.boltFade : 0
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: scene.boltPixelSize
                renderType: Text.NativeRendering
                z: 2
            }
        }

        // Sparks off the strike point: one parabola per particle, driven by the
        // shared sparkProgress. ponytail: no per-spark animators, no Bezier paths.
        Repeater {
            model: 14
            delegate: Text {
                required property int index
                readonly property real angle: Math.PI * (1.15 + scene.noise(index, scene.strikeSeed) * 0.7)
                readonly property real speed: scene.boltPixelSize * (2.2 + scene.noise(index, scene.strikeSeed + 40) * 3.4)
                readonly property real t: scene.sparkProgress
                x: scene.boltTipX + Math.cos(angle) * speed * t
                y: scene.boltTipY + Math.sin(angle) * speed * t + scene.boltPixelSize * 9 * t * t
                text: index % 2 === 0 ? "*" : "."
                color: "#cdf3ff"
                opacity: t > 0 && t < 1 ? (1 - t) * 0.9 : 0
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: scene.boltPixelSize * (0.4 + scene.noise(index, scene.strikeSeed + 80) * 0.3)
                renderType: Text.NativeRendering
                z: 2
            }
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
