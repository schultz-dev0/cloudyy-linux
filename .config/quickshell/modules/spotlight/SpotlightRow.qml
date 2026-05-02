import QtQuick
import Quickshell
import "../.."

Item {
    id: root

    required property var  resultData   // {type,name,icon?,exec?,wmclass?,isRunning?,path?} or {type:"web",query}
    required property bool isSelected
    required property int  rowWidth

    signal activated()
    signal hovered()

    width:  rowWidth
    height: 46

    // Selection highlight
    Rectangle {
        anchors { fill: parent; margins: 3 }
        radius: 8
        color: root.isSelected
            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
            : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }
    }

    Row {
        anchors {
            left: parent.left; right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 14; rightMargin: 14
        }
        spacing: 10

        // ── Icon ──────────────────────────────────────────────────────────
        Item {
            width: 28; height: 28
            anchors.verticalCenter: parent.verticalCenter

            Image {
                id: iconImg
                anchors.fill: parent
                sourceSize: Qt.size(56, 56)
                smooth:     true
                visible: root.resultData.type === "app"
                
                property int fallbackStage: 0
                property string baseIcon: root.resultData.icon ?? "application-x-executable"
                onBaseIconChanged: fallbackStage = 0

                                source: {
                    if (root.resultData.type !== "app") return ""
                    if (baseIcon.startsWith("/")) return "file://" + baseIcon
                    const theme = parent.themeName || "Papirus-Dark"
                    if (fallbackStage === 0) return `file:///usr/share/icons/${theme}/48x48/apps/${baseIcon}.svg`
                    if (fallbackStage === 1) return `file:///usr/share/icons/${theme}/scalable/apps/${baseIcon}.svg`
                    if (fallbackStage === 2) return `file:///usr/share/icons/${theme}/48x48/devices/${baseIcon}.svg`
                    if (fallbackStage === 3) return `file:///usr/share/icons/${theme}/scalable/devices/${baseIcon}.svg`
                    if (fallbackStage === 4) return `file:///usr/share/icons/${theme}/48x48/places/${baseIcon}.svg`
                    if (fallbackStage === 5) return `file:///usr/share/icons/${theme}/scalable/places/${baseIcon}.svg`
                    if (fallbackStage === 6) return `file:///usr/share/icons/${theme}/48x48/categories/${baseIcon}.svg`
                    if (fallbackStage === 7) return `file:///usr/share/icons/${theme}/scalable/categories/${baseIcon}.svg`
                    if (fallbackStage === 8) return `file:///usr/share/icons/Papirus-Dark/48x48/apps/${baseIcon}.svg`
                    if (fallbackStage === 9) return `file:///usr/share/icons/Papirus-Dark/48x48/devices/${baseIcon}.svg`
                    return `file:///usr/share/icons/${theme}/48x48/apps/application-x-executable.svg`
                }

                onStatusChanged: {
                    if (status === Image.Error && fallbackStage < 10) {
                        fallbackStage++
                    }
                }
            }

            Text {
                anchors.fill: parent
                visible: root.resultData.type !== "app"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:   Text.AlignVCenter
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 20
                color: Theme.on_surface_variant
                text: root.resultData.type === "file" ? "󰈔" : "󰖟"
            }
        }

        // ── Text ──────────────────────────────────────────────────────────
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            width: root.rowWidth - 28 - 10 - 14 - 14

            Text {
                width: parent.width
                text:  root.resultData.type === "web"
                    ? `Search DDG for "${root.resultData.query}"`
                    : (root.resultData.name ?? "")
                color: root.resultData.type === "web"
                    ? Qt.rgba(Theme.textMuted.r, Theme.textMuted.g, Theme.textMuted.b, 0.6)
                    : Theme.textPrimary
                font.pixelSize: 13
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideRight
            }

            Text {
                width:   parent.width
                visible: root.resultData.type === "app" || root.resultData.type === "file"
                text:    root.resultData.type === "app"
                    ? (root.resultData.isRunning ? "Running" : (root.resultData.exec ?? ""))
                    : (root.resultData.path ?? "")
                color:   Theme.textMuted
                font.pixelSize: 11
                font.family:    "JetBrainsMono Nerd Font"
                elide: Text.ElideMiddle
            }
        }
    }

    // ── Interaction ───────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered()
        onClicked: root.activated()
    }
}
