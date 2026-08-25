pragma ComponentBehavior: Bound

import QtQuick
import "../.."

Item {
    id: root

    required property string name
    required property string mode
    required property var colors
    required property string preview
    required property var wallpapers
    required property int focusedWallpaperIndex
    required property bool selected
    required property bool isCurrent
    signal activated()
    signal wallpaperActivated(int index)

    readonly property int previewSize: 48
    // At-a-glance palette, not the full 17 roles — background/accent/status trio
    // is what actually answers "will this look decent" without crowding the row.
    readonly property var swatchKeys: ["background", "accent", "success", "warning", "error"]

    // Only the active theme gets a wallpaper strip (see the picker's design
    // notes) — browsing another theme's wallpapers before switching to it is
    // a rare case not worth a second row state.
    readonly property bool showWallpaperStrip: isCurrent && wallpapers.length > 1
    readonly property int stripHeight: 38

    width: parent ? parent.width : 0
    height: 68 + (showWallpaperStrip ? stripHeight : 0)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: 2
        color: root.selected
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
            : "transparent"
        border.color: (root.selected || root.isCurrent)
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.selected ? 0.55 : 0.35)
            : "transparent"
        border.width: root.selected ? 1.5 : 1
    }

    Row {
        id: mainRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 12
            rightMargin: 12
        }
        height: 68
        spacing: 12

        Image {
            width: root.previewSize
            height: root.previewSize
            anchors.verticalCenter: parent.verticalCenter
            source: root.preview.length > 0 ? "file://" + root.preview : ""
            // Never decode a full-resolution wallpaper for a 48px thumbnail.
            sourceSize.width: Math.ceil(root.previewSize * 1.25)
            sourceSize.height: Math.ceil(root.previewSize * 1.25)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            cache: false
            layer.enabled: true
            layer.smooth: true
        }

        Column {
            width: parent.width - root.previewSize - (root.isCurrent ? 76 : 0) - parent.spacing * (root.isCurrent ? 2 : 1)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Text {
                text: root.name
                color: Theme.text
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                font.weight: Font.Medium
            }

            Text {
                text: root.mode
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                opacity: 0.7
            }

            Row {
                spacing: 4
                Repeater {
                    model: root.swatchKeys
                    delegate: Rectangle {
                        required property string modelData
                        width: 14
                        height: 14
                        radius: 3
                        color: root.colors[modelData] || "transparent"
                    }
                }
            }
        }

        Rectangle {
            visible: root.isCurrent
            anchors.verticalCenter: parent.verticalCenter
            width: currentLabel.width + 12
            height: 18
            radius: 3
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85)

            Text {
                id: currentLabel
                anchors.centerIn: parent
                text: "current"
                color: Theme.accentText
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
    }

    Row {
        id: wallpaperStrip
        visible: root.showWallpaperStrip
        anchors {
            top: mainRow.bottom
            left: parent.left
            leftMargin: 12 + root.previewSize + mainRow.spacing
        }
        spacing: 6

        Repeater {
            model: root.showWallpaperStrip ? root.wallpapers : []
            delegate: Item {
                id: wallCell
                required property string modelData
                required property int index

                readonly property bool focused: index === root.focusedWallpaperIndex

                width: 40
                height: 28

                Image {
                    anchors.fill: parent
                    source: wallCell.modelData.length > 0 ? "file://" + wallCell.modelData : ""
                    sourceSize.width: 50
                    sourceSize.height: 35
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    cache: false
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: "transparent"
                    border.width: wallCell.focused ? 2 : 1
                    border.color: wallCell.focused
                        ? Theme.accent
                        : Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, 0.5)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.wallpaperActivated(wallCell.index)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: mainRow
        onClicked: root.activated()
    }
}
