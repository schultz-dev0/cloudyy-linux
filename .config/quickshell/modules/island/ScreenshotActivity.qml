pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string imagePath: ""
    property string activityId: ""

    readonly property int contentWidth: 232
    readonly property int headerHeight: 22
    readonly property int thumbInset: 8
    readonly property int thumbRadius: 12
    readonly property int scrimHeight: 40
    readonly property int maxThumbHeight: 140

    readonly property int thumbInnerWidth: contentWidth - thumbInset * 2

    property int previewHeight: 100

    implicitWidth:  contentWidth
    implicitHeight: headerHeight + 6 + previewHeight

    function _fileUri(path) {
        if (!path)
            return "";
        if (path.startsWith("file://"))
            return path;
        // Match Gio.File.get_uri(): encode path segments, keep slashes.
        const encoded = path.split("/").map(seg => encodeURIComponent(seg)).join("/");
        return "file://" + encoded;
    }

    readonly property string fileUri: _fileUri(root.imagePath)
    readonly property string uriListPayload: root.fileUri ? (root.fileUri + "\r\n") : ""
    // GTK popup + Nautilus/Dolphin often expect this alongside text/uri-list on Wayland.
    readonly property string gnomeFilesPayload: root.imagePath
                                                ? ("copy\n" + root.imagePath + "\n")
                                                : ""

    readonly property color _btnFill: Qt.rgba(
        Theme.surface_container_high.r,
        Theme.surface_container_high.g,
        Theme.surface_container_high.b, 0.72)
    readonly property color _btnFillHover: Qt.rgba(
        Theme.surface_container_high.r,
        Theme.surface_container_high.g,
        Theme.surface_container_high.b, 0.88)
    readonly property color _btnBorder: Qt.rgba(
        Theme.outline_variant.r,
        Theme.outline_variant.g,
        Theme.outline_variant.b, 0.4)

    property bool _dragSession: false

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 6

            Rectangle {
                Layout.preferredWidth:  20
                Layout.preferredHeight: 20
                radius: 6
                color: Qt.rgba(
                    Theme.surface_container_high.r,
                    Theme.surface_container_high.g,
                    Theme.surface_container_high.b, 0.55)

                Text {
                    anchors.centerIn: parent
                    text:           "󰹓"
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            Text {
                text:               "SCREENSHOT"
                color:              Theme.on_surface_variant
                font.family:        "JetBrainsMono Nerd Font"
                font.pixelSize:     9
                font.letterSpacing: 0.8
            }

            Item { Layout.fillWidth: true }

            Text {
                text:           "󰄬  Copied"
                color:          Theme.primary
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }

        Item {
            id: thumbHost
            Layout.fillWidth: true
            Layout.preferredWidth:  root.contentWidth
            Layout.preferredHeight: root.previewHeight

            scale: dragHandler.active ? 1.02 : 1.0
            transformOrigin: Item.Center

            Behavior on scale {
                enabled: Perf.animationsEnabled
                NumberAnimation { duration: Perf.msHalf(80); easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: thumbClip
                anchors {
                    fill: parent
                    leftMargin:   root.thumbInset
                    rightMargin:  root.thumbInset
                }
                radius: root.thumbRadius
                clip:   true
                color:  Qt.rgba(
                    Theme.surface_container_lowest.r,
                    Theme.surface_container_lowest.g,
                    Theme.surface_container_lowest.b, 0.35)

                border.width: dragHandler.active ? 1 : 0
                border.color: Qt.rgba(
                    Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)

                Behavior on border.width {
                    enabled: Perf.animationsEnabled
                    NumberAnimation { duration: Perf.msHalf(80) }
                }

                Image {
                    id: previewImage
                    anchors.fill: parent
                    source: root.imagePath
                             ? (root.imagePath.startsWith("file://")
                                ? root.imagePath
                                : "file://" + root.imagePath)
                             : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: !Perf.lightweight
                    cache: false

                    onStatusChanged: {
                        if (status !== Image.Ready)
                            return;
                        const w = sourceSize.width;
                        const h = sourceSize.height;
                        if (w <= 0)
                            return;
                        const thumbH = Math.round(h * (root.thumbInnerWidth / w));
                        const next = Math.min(thumbH, root.maxThumbHeight);
                        if (Math.abs(root.previewHeight - next) > 2)
                            root.previewHeight = next;
                    }
                }

                Rectangle {
                    anchors {
                        left:   parent.left
                        right:  parent.right
                        bottom: parent.bottom
                    }
                    height: root.scrimHeight
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop {
                            position: 1.0
                            color: Qt.rgba(
                                Theme.scrim.r,
                                Theme.scrim.g,
                                Theme.scrim.b, 0.58)
                        }
                    }
                }

                RowLayout {
                    z: 10
                    anchors {
                        left:           parent.left
                        right:          parent.right
                        bottom:         parent.bottom
                        leftMargin:     6
                        rightMargin:    6
                        bottomMargin:   4
                    }
                    height: root.scrimHeight
                    spacing: 4

                    Rectangle {
                        id: copyBtn
                        Layout.preferredWidth:  32
                        Layout.preferredHeight: 32
                        radius: 8
                        scale:  copyBtnArea.pressed ? 0.95 : 1.0
                        color:  copyBtnArea.containsMouse ? root._btnFillHover : root._btnFill
                        border.width: 1
                        border.color: root._btnBorder

                        Behavior on scale {
                            enabled: Perf.animationsEnabled
                            NumberAnimation { duration: Perf.msHalf(60) }
                        }

                        Text {
                            anchors.centerIn: parent
                            text:           "󰆏"
                            color:          Theme.on_surface
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                        }

                        MouseArea {
                            id: copyBtnArea
                            anchors.fill:   parent
                            hoverEnabled:   true
                            cursorShape:    Qt.PointingHandCursor
                            onClicked: DynamicIslandService.copyScreenshotImage(root.imagePath)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    RowLayout {
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            text:           "󰇘"
                            color:          Theme.on_surface
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            opacity:        0.85
                        }

                        Text {
                            text:           "Drag to upload"
                            color:          Theme.on_surface
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            opacity:        0.9
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        id: closeBtn
                        Layout.preferredWidth:  32
                        Layout.preferredHeight: 32
                        radius: 8
                        scale:  closeBtnArea.pressed ? 0.95 : 1.0
                        color:  closeBtnArea.containsMouse ? root._btnFillHover : root._btnFill
                        border.width: 1
                        border.color: root._btnBorder

                        Behavior on scale {
                            enabled: Perf.animationsEnabled
                            NumberAnimation { duration: Perf.msHalf(60) }
                        }

                        Text {
                            anchors.centerIn: parent
                            text:           "󰅖"
                            color:          Theme.on_surface_variant
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                        }

                        MouseArea {
                            id: closeBtnArea
                            anchors.fill:   parent
                            hoverEnabled:   true
                            cursorShape:    Qt.PointingHandCursor
                            onClicked: DynamicIslandService.dismissScreenshot(root.activityId)
                        }
                    }
                }

                // Above image/scrim, below control row (z:10). No MouseArea — that blocks Wayland drags.
                DragHandler {
                    id: dragHandler
                    target: null
                    acceptedButtons: Qt.LeftButton

                    onActiveChanged: {
                        thumbClip.Drag.active = active;
                        if (active) {
                            root._dragSession = true;
                            return;
                        }
                        if (root._dragSession) {
                            root._dragSession = false;
                            const id = root.activityId;
                            Qt.callLater(() => DynamicIslandService.dismissScreenshotAfterDrag(id));
                        }
                    }
                }

                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.imageSource: root.fileUri
                Drag.mimeData: {
                    "text/uri-list": root.uriListPayload,
                    "text/plain": root.fileUri,
                    "x-special/gnome-copied-files": root.gnomeFilesPayload
                }
            }
        }
    }
}
