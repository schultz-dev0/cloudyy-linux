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

    visible: root.title !== ""
    implicitHeight: visible ? cardCol.implicitHeight + 24 : 0
    radius: 12
    color: Theme.surface_container
    border.color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.25)
    border.width: 1

    ElevatedEffect {
        target: root
    }

    ColumnLayout {
        id: cardCol
        anchors {
            fill: parent
            margins: 12
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
                radius: 8
                layer.enabled: true
                gradient: Gradient {
                    orientation: Gradient.Diagonal
                    GradientStop {
                        position: 0.0
                        color: Theme.primary_container
                    }
                    GradientStop {
                        position: 1.0
                        color: Theme.tertiary_container
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
                    color: Theme.on_primary_container
                    visible: artImage.status !== Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1

                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: Theme.on_surface
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.artist
                    color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }

                Text {
                    text: root.playerName
                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
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
            radius: 999
            color: Qt.rgba(Theme.outline_variant.r, Theme.outline_variant.g, Theme.outline_variant.b, 0.4)

            Rectangle {
                width: parent.width * root.progressFraction
                height: parent.height
                radius: parent.radius
                color: Theme.primary
            }
        }

        // ── Controls ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 20

            Text {
                text: ""
                color: Theme.on_surface_variant
                font.pixelSize: 16
                MouseArea {
                    anchors.fill: parent
                    onClicked: prevProc.running = true
                }
            }

            Text {
                text: root.playing ? "⏸" : "⏵"
                color: Theme.primary
                font.pixelSize: 22
                MouseArea {
                    anchors.fill: parent
                    onClicked: playPauseProc.running = true
                }
            }

            Text {
                text: ""
                color: Theme.on_surface_variant
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
        running: true
        triggeredOnStart: true
        onTriggered: statusProc.running = true
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
