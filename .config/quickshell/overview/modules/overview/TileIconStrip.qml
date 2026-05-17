import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../common/functions"

Item {
    id: root
    property var windows: []
    property real tileScale: 1.0

    height: Math.round(28 * tileScale)
    visible: windows.length > 0
    z: 10

    function iconForWindow(win) {
        const entry = DesktopEntries.heuristicLookup(win?.class || win?.initialClass || win?.initialTitle)
        const raw = `${entry?.icon ?? ""}`.trim()
        const clean = raw.replace(/^image:\/\/icon\//, "").split("?")[0].trim()
        if (clean.length > 0) return clean
        const cls = (win?.class || "").toLowerCase()
        if (cls.includes("firefox")) return "firefox"
        if (cls.includes("kitty") || cls.includes("terminal")) return "terminal"
        if (cls.includes("zed")) return "zed"
        if (cls.includes("code")) return "vscode"
        if (cls.includes("spotify")) return "spotify"
        if (cls.includes("discord")) return "discord"
        if (cls.includes("thunar")) return "thunar"
        return "application-x-executable"
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.5) }
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: Math.round(3 * root.tileScale)

        Repeater {
            model: Math.min(root.windows.length, 5)
            delegate: Image {
                required property int index
                property string iconName: root.iconForWindow(root.windows[index])
                width: Math.round(14 * root.tileScale)
                height: Math.round(14 * root.tileScale)
                source: `file:///usr/share/icons/Papirus-Dark/48x48/apps/${iconName}.svg`
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
                onStatusChanged: {
                    if (status === Image.Error)
                        source = "file:///usr/share/icons/Papirus-Dark/48x48/apps/application-x-executable.svg"
                }
            }
        }

        Text {
            visible: root.windows.length > 5
            text: `+${root.windows.length - 5}`
            font.pixelSize: Math.round(9 * root.tileScale)
            font.family: Appearance.font.family.main
            color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer1, 0.6)
            verticalAlignment: Text.AlignVCenter
        }
    }
}
