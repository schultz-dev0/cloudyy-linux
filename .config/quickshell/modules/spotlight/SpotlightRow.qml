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
                source: root.resultData.type === "app"
                    ? Quickshell.iconPath(root.resultData.icon ?? "", "image://icon/application-x-executable")
                    : ""
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
