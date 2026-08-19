pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import "../.."
import "." as QuickIsland

Item {
    id: root

    signal activateRequested

    readonly property var player: QuickIsland.MprisFocus.activePlayer
    readonly property int playerRevision: QuickIsland.MprisFocus.revision
    readonly property bool controlsActive: root.player !== null
        && QuickIsland.IslandState.currentPage === "media"
        && !QuickIsland.IslandState.expanded
    readonly property real currentPosition: {
        const _ = root.playerRevision;
        return root.player ? root.player.position : 0;
    }
    readonly property real progressFraction: {
        if (!root.player || !root.player.positionSupported
                || !root.player.lengthSupported || root.player.length <= 0)
            return 0;
        return Math.max(0, Math.min(1, root.currentPosition / root.player.length));
    }

    function formatTime(seconds) {
        const value = Math.max(0, Math.floor(seconds || 0));
        return Math.floor(value / 60) + ":" + String(value % 60).padStart(2, "0");
    }

    function runControl(action) {
        if (!root.player)
            return;
        if (action === "previous" && root.player.canGoPrevious)
            root.player.previous();
        else if (action === "next" && root.player.canGoNext)
            root.player.next();
        else if (action === "play" && root.player.canTogglePlaying)
            root.player.togglePlaying();
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.player !== null
            && root.player.playbackState === MprisPlaybackState.Playing
        onTriggered: QuickIsland.MprisFocus.refresh()
    }

    QuickIsland.IslandPageFrame {
        anchors.fill: parent

        leftContent: Item {
            Row {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 12
                spacing: 12

                Rectangle {
                    width: 68
                    height: 68
                    radius: 2
                    color: Theme.islandHover
                    clip: true

                    Image {
                        id: artwork
                        anchors.fill: parent
                        source: root.player ? root.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: artwork.status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: artwork.status !== Image.Ready
                        text: "󰎈"
                        color: Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 24
                        renderType: Text.NativeRendering
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 80
                    spacing: 5

                    Text {
                        width: parent.width
                        text: root.player ? (root.player.trackTitle || "Unknown track")
                            : "Media"
                        color: Theme.islandOnSurface
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.player ? (root.player.trackArtist || "Unknown artist")
                            : "No player active"
                        color: Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                    }
                }
            }

            TapHandler {
                onTapped: root.activateRequested()
            }
        }

        rightContent: Item {
            Column {
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 7

                    Text {
                        text: root.formatTime(root.currentPosition)
                        color: Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
                    }

                    Row {
                        id: gauge
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 82
                        spacing: 2

                        readonly property int tickCount: Math.max(6, Math.floor(width / 6))
                        readonly property real tickWidth:
                            (width - (tickCount - 1) * spacing) / tickCount

                        Repeater {
                            model: gauge.tickCount
                            delegate: Rectangle {
                                required property int index
                                width: gauge.tickWidth
                                height: 10
                                color: (index / gauge.tickCount) <= root.progressFraction
                                    ? Theme.islandAccent : Theme.islandBorder
                            }
                        }
                    }

                    Text {
                        text: root.formatTime(root.player ? root.player.length : 0)
                        color: Theme.islandOnSurfaceVariant
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        renderType: Text.NativeRendering
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Repeater {
                        model: [
                            { action: "previous", icon: "󰒮" },
                            { action: "play", icon: root.player?.playbackState
                                === MprisPlaybackState.Playing ? "󰏤" : "󰐊" },
                            { action: "next", icon: "󰒭" },
                        ]

                        delegate: Item {
                            id: control

                            required property var modelData

                            readonly property bool actionEnabled: root.player !== null
                                && (control.modelData.action === "previous"
                                    ? root.player.canGoPrevious
                                    : control.modelData.action === "next"
                                        ? root.player.canGoNext
                                        : root.player.canTogglePlaying)

                            width: 44
                            height: 30
                            enabled: root.controlsActive && control.actionEnabled
                            activeFocusOnTab: root.controlsActive
                                && control.actionEnabled

                            Rectangle {
                                id: controlFill
                                anchors.fill: parent
                                radius: 2
                                clip: true
                                color: control.activeFocus ? Theme.islandFocus
                                    : controlTap.pressed ? Theme.islandPressed
                                        : controlHover.hovered ? Theme.islandHover
                                            : "transparent"
                                border.width: control.activeFocus ? 1 : 0
                                border.color: Theme.islandFocus

                                DotTexture {
                                    anchors.fill: parent
                                    visible: controlHover.hovered || controlTap.pressed || control.activeFocus
                                    tint: Theme.islandOnSurface
                                    dotAlpha: 0.16
                                    cell: 4
                                    dotRadius: 0.6
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: control.modelData.icon
                                color: control.actionEnabled ? Theme.islandOnSurface
                                    : Theme.islandOnSurfaceVariant
                                opacity: control.actionEnabled ? 1 : 0.4
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 16
                                renderType: Text.NativeRendering
                            }

                            HoverHandler {
                                id: controlHover
                            }

                            TapHandler {
                                id: controlTap
                                onTapped: root.runControl(control.modelData.action)
                            }

                            Keys.onReturnPressed: event => {
                                root.runControl(control.modelData.action);
                                event.accepted = true;
                            }
                            Keys.onEnterPressed: event => {
                                root.runControl(control.modelData.action);
                                event.accepted = true;
                            }
                            Keys.onSpacePressed: event => {
                                root.runControl(control.modelData.action);
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
        }
    }
}
