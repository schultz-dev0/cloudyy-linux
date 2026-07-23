import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "." as QuickIsland

Item {
    id: root

    property bool expanded: false
    property bool controlsVisible: false

    readonly property var player: QuickIsland.MprisFocus.activePlayer
    readonly property bool active: player
        && (player.playbackState === MprisPlaybackState.Playing
            || player.playbackState === MprisPlaybackState.Paused)
    readonly property real progressFraction: {
        const _ = QuickIsland.MprisFocus.revision;
        if (!player || !player.lengthSupported || player.length <= 0)
            return 0;
        return Math.min(1, Math.max(0, player.position / player.length));
    }

    function fmtTime(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        const m = Math.floor(s / 60);
        const r = s % 60;
        return m + ":" + String(r).padStart(2, "0");
    }

    function togglePlaying() {
        if (!root.player)
            return;
        if (root.player.canTogglePlaying === false)
            return;
        root.player.togglePlaying();
    }

    anchors.fill: parent

    Timer {
        interval: 1000
        repeat: true
        running: root.active && player?.playbackState === MprisPlaybackState.Playing
        onTriggered: player?.positionChanged()
    }

    RowLayout {
        id: compactRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.expanded
        spacing: 8

        Rectangle {
            width: 28
            height: 28
            radius: 6
            color: Qt.rgba(1, 1, 1, 0.08)
            clip: true
            visible: root.player?.trackArtUrl?.length > 0

            Image {
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
            }
        }

        Text {
            text: root.player ? (root.player.trackTitle || "Unknown") : ""
            color: "#ffffff"
            font.pixelSize: 12
            font.family: "JetBrainsMono Nerd Font"
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Item {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28

            Text {
                id: compactPlayPause
                anchors.centerIn: parent
                text: root.player?.playbackState === MprisPlaybackState.Playing ? "⏸" : "⏵"
                color: "#ffffff"
                font.pixelSize: 14
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: root.togglePlaying()
            }
        }
    }

    ColumnLayout {
        id: expandedCol
        anchors.fill: parent
        visible: root.expanded
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                width: 40
                height: 40
                radius: 8
                color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    visible: root.player?.trackArtUrl?.length > 0
                }

                Text {
                    anchors.centerIn: parent
                    text: "♪"
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.pixelSize: 18
                    visible: !(root.player?.trackArtUrl?.length > 0)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackTitle || "Unknown") : ""
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.family: "JetBrainsMono Nerd Font"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackArtist || "") : ""
                    color: Qt.rgba(1, 1, 1, 0.65)
                    font.pixelSize: 10
                    font.family: "JetBrainsMono Nerd Font"
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.fmtTime(root.player?.position ?? 0)
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 9
                font.family: "JetBrainsMono Nerd Font"
            }

            Rectangle {
                Layout.fillWidth: true
                height: 3
                radius: 999
                color: Qt.rgba(1, 1, 1, 0.18)

                Rectangle {
                    width: parent.width * root.progressFraction
                    height: parent.height
                    radius: parent.radius
                    color: "#ffffff"
                }
            }

            Text {
                text: root.fmtTime(root.player?.length ?? 0)
                color: Qt.rgba(1, 1, 1, 0.55)
                font.pixelSize: 9
                font.family: "JetBrainsMono Nerd Font"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            visible: root.controlsVisible
            spacing: 24

            Item {
                width: 32
                height: 32

                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.player?.previous()
                }
            }

            Item {
                width: 36
                height: 36

                Text {
                    anchors.centerIn: parent
                    text: root.player?.playbackState === MprisPlaybackState.Playing ? "⏸" : "⏵"
                    color: "#ffffff"
                    font.pixelSize: 20
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.togglePlaying()
                }
            }

            Item {
                width: 32
                height: 32

                Text {
                    anchors.centerIn: parent
                    text: ""
                    color: Qt.rgba(1, 1, 1, 0.75)
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.player?.next()
                }
            }
        }
    }
}
