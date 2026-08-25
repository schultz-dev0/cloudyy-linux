pragma ComponentBehavior: Bound

// modules/controlcenter/MediaCard.qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../.."

Rectangle {
    id: root

    property bool playing: false
    property string title: ""
    property string artist: ""
    property string artUrl: ""
    property string playerName: ""
    property real progressFraction: 0
    property bool active: true

    visible: root.title !== ""
    implicitHeight: visible ? cardCol.implicitHeight + 16 : 0
    radius: 0
    color: "transparent"
    border.width: 0

    ColumnLayout {
        id: cardCol
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 8

        // ── Art + info ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                id: artContainer
                width: 44
                height: 44
                radius: 2
                layer.enabled: true
                gradient: Gradient {
                    GradientStop {
                        position: 0.0
                        color: Theme.accentMuted
                    }
                    GradientStop {
                        position: 1.0
                        color: Theme.accentAlt
                    }
                }

                Image {
                    id: artImage
                    anchors.fill: parent
                    source: root.artUrl
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    text: "♪"
                    font.pixelSize: 20
                    color: Theme.accentText
                    visible: artImage.status !== Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.artist
                    color: Theme.textMuted
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Text {
                    text: root.playerName
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 8
                    visible: root.playerName !== ""
                }
            }
        }

        // ── Progress bar ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 3
            radius: 0
            color: Theme.hairline

            Rectangle {
                width: parent.width * root.progressFraction
                height: parent.height
                radius: 0
                color: Theme.accent
            }
        }

        // ── Controls ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 20

            Text {
                text: ""
                color: Theme.textMuted
                font.pixelSize: 16
                MouseArea {
                    anchors.fill: parent
                    onClicked: prevProc.running = true
                }
            }

            Text {
                text: root.playing ? "⏸" : "⏵"
                color: Theme.accent
                font.pixelSize: 22
                MouseArea {
                    anchors.fill: parent
                    onClicked: playPauseProc.running = true
                }
            }

            Text {
                text: ""
                color: Theme.textMuted
                font.pixelSize: 16
                MouseArea {
                    anchors.fill: parent
                    onClicked: nextProc.running = true
                }
            }
        }
    }

    // ── Polling ─────────────────────────────────────────────────────────────
    Timer {
        interval: 2000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: statusProc.running = true
    }

    onActiveChanged: {
        if (active)
            statusProc.running = true;
    }

    Process {
        id: statusProc
        command: ["bash", "-c", "playerctl status 2>/dev/null"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const s = line.trim();
                if (s === "") {
                    root.title = "";
                    root.playing = false;
                    return;
                }
                root.playing = (s === "Playing");
                metaProc.running = false;
                metaProc.running = true;
            }
        }
    }

    Process {
        id: metaProc
        command: ["bash", "-c", "playerctl metadata --format '{{title}}\t{{artist}}\t{{mpris:artUrl}}\t{{mpris:length}}\t{{position}}\t{{playerName}}' 2>/dev/null"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const p = line.split("\t");
                if (p.length < 4)
                    return;
                root.title = p[0] || "";
                root.artist = p[1] || "";
                root.artUrl = p[2] || "";
                const lenUs = parseFloat(p[3]) || 0;
                const posSec = parseFloat(p[4]) || 0;
                root.progressFraction = lenUs > 0 ? Math.max(0, Math.min(1, (posSec * 1e6) / lenUs)) : 0;
                root.playerName = p[5] || "";
            }
        }
    }

    Process {
        id: prevProc
        command: ["playerctl", "previous"]
        running: false
    }
    Process {
        id: playPauseProc
        command: ["playerctl", "play-pause"]
        running: false
    }
    Process {
        id: nextProc
        command: ["playerctl", "next"]
        running: false
    }
}
