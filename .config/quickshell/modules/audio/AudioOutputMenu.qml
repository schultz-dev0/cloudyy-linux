pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../.."
import "../spotlight" as QuickSpotlight

PopupWindow {
    id: root

    required property Item anchorItem
    property var outputs: []
    property string errorText: ""
    property int selectedIndex: -1
    property bool refreshPending: false
    readonly property string ccRoot: Quickshell.env("HOME") + "/cloudyy-linux/cloud-center"
    readonly property string barEdge: ShellLayout.barEdge
    readonly property bool busy: switchProc.running

    signal outputChanged()
    signal settingsRequested()

    visible: false
    // HyprlandFocusGrab owns dismissal; a second native popup grab closes
    // the window during the bar-to-popup focus handoff.
    grabFocus: false
    color: "transparent"
    implicitWidth: 380
    implicitHeight: content.implicitHeight + 12
    anchor.item: anchorItem
    anchor.edges: ({ top: Edges.Bottom, bottom: Edges.Top, left: Edges.Right, right: Edges.Left })[barEdge]
    anchor.gravity: anchor.edges
    anchor.adjustment: PopupAdjustment.Slide | PopupAdjustment.Flip

    function syncAnchor() {
        const horizontal = barEdge === "top" || barEdge === "bottom";
        anchor.rect.x = horizontal ? anchorItem.width / 2 - width / 2
            : (barEdge === "left" ? anchorItem.width + 4 : -4);
        anchor.rect.y = horizontal ? (barEdge === "top" ? anchorItem.height + 4 : -4)
            : anchorItem.height / 2;
        anchor.rect.w = 1;
        anchor.rect.h = 1;
        anchor.updateAnchor();
    }

    function toggle() {
        visible = !visible;
    }

    function refresh() {
        if (!visible)
            return;
        if (listProc.running) {
            refreshPending = true;
            return;
        }
        refreshPending = false;
        listProc.running = true;
    }

    function choose(index) {
        if (busy)
            return;
        if (index === outputs.length) {
            visible = false;
            settingsRequested();
            return;
        }
        const output = outputs[index];
        if (!output)
            return;
        if (output.is_default) {
            visible = false;
            return;
        }
        errorText = "";
        switchProc.command = ["python3", "-m", "lib.audio_output_picker", "switch", output.name];
        switchProc.running = true;
    }

    onVisibleChanged: {
        if (visible) {
            errorText = "";
            selectedIndex = -1;
            syncAnchor();
            refresh();
            Qt.callLater(() => {
                if (root.visible) {
                    input.forceActiveFocus();
                    focusGrab.active = true;
                }
            });
        } else {
            refreshDelay.stop();
            focusGrab.active = false;
        }
    }
    onBarEdgeChanged: if (visible) syncAnchor()

    HyprlandFocusGrab {
        id: focusGrab
        windows: [root]
        onCleared: root.visible = false
    }

    Process {
        id: listProc
        workingDirectory: root.ccRoot
        command: ["python3", "-m", "lib.audio_output_picker", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.ok) {
                        const selectedName = root.outputs[root.selectedIndex]?.name;
                        root.outputs = result.outputs;
                        const index = root.outputs.findIndex(output => output.name === selectedName);
                        root.selectedIndex = index >= 0 ? index : root.outputs.findIndex(output => output.is_default);
                    } else {
                        root.errorText = result.error;
                    }
                } catch (error) {
                    root.errorText = "Could not load audio outputs";
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.refreshPending)
                Qt.callLater(() => root.refresh());
        }
    }

    Process {
        id: switchProc
        workingDirectory: root.ccRoot
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const result = JSON.parse(text);
                    if (result.ok) {
                        root.outputChanged();
                        root.visible = false;
                    } else {
                        root.errorText = result.error;
                        root.refresh();
                    }
                } catch (error) {
                    root.errorText = "Could not switch audio output";
                }
            }
        }
    }

    Process {
        running: root.visible
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("on sink") || line.includes("on server") || line.includes("on card"))
                    refreshDelay.restart();
            }
        }
    }

    Timer {
        id: refreshDelay
        interval: 150
        onTriggered: root.refresh()
    }

    Panel { anchors.fill: parent }

    FocusScope {
        id: input
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: event => { root.visible = false; event.accepted = true; }
        Keys.onUpPressed: event => {
            root.selectedIndex = (root.selectedIndex + root.outputs.length) % (root.outputs.length + 1);
            event.accepted = true;
        }
        Keys.onDownPressed: event => {
            root.selectedIndex = (root.selectedIndex + 1) % (root.outputs.length + 1);
            event.accepted = true;
        }
        Keys.onReturnPressed: event => { root.choose(root.selectedIndex); event.accepted = true; }

        Column {
            id: content
            width: parent.width
            y: 6

            Repeater {
                model: root.outputs
                delegate: QuickSpotlight.SpotlightRow {
                    required property var modelData
                    required property int index
                    rowWidth: root.width
                    isSelected: root.selectedIndex === index
                    enabled: !root.busy
                    resultData: ({ type: "command", name: modelData.description,
                        icon: modelData.type === "Bluetooth" ? "󰂯" : "󰓃",
                        isActive: modelData.is_default, state: modelData.is_default ? "Active" : "" })
                    onActivated: root.choose(index)
                    onHovered: root.selectedIndex = index
                }
            }

            Text {
                visible: root.errorText !== ""
                width: parent.width - 32
                x: 16
                text: root.errorText
                color: Theme.error
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            Rectangle {
                x: 16
                width: parent.width - 32
                height: 1
                color: Theme.hairline
                visible: root.outputs.length > 0
            }

            QuickSpotlight.SpotlightRow {
                rowWidth: root.width
                isSelected: root.selectedIndex === root.outputs.length
                enabled: !root.busy
                resultData: ({ type: "command", name: "Audio settings", icon: "󰒓" })
                onActivated: root.choose(root.outputs.length)
                onHovered: root.selectedIndex = root.outputs.length
            }
        }
    }
}
