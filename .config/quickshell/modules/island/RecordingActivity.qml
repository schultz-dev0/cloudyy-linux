pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string videoPath: ""
    property string activityId: ""

    readonly property int contentWidth: 232
    readonly property int headerHeight: 22
    readonly property int bodyHeight: 96
    readonly property int scrimHeight: 40

    readonly property string fileName: {
        const p = root.videoPath || "";
        if (!p)
            return "";
        const parts = p.split("/");
        return parts.length ? parts[parts.length - 1] : p;
    }

    implicitWidth:  contentWidth
    implicitHeight: headerHeight + 6 + bodyHeight

    function _fileUri(path) {
        if (!path)
            return "";
        if (path.startsWith("file://"))
            return path;
        const encoded = path.split("/").map(seg => encodeURIComponent(seg)).join("/");
        return "file://" + encoded;
    }

    readonly property string fileUri: _fileUri(root.videoPath)
    readonly property string uriListPayload: root.fileUri ? (root.fileUri + "\r\n") : ""
    readonly property string gnomeFilesPayload: root.videoPath
                                                ? ("copy\n" + root.videoPath + "\n")
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
                    text:           "󰕧"
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            Text {
                text:               "RECORDING"
                color:              Theme.on_surface_variant
                font.family:        "JetBrainsMono Nerd Font"
                font.pixelSize:     9
                font.letterSpacing: 0.8
            }

            Item { Layout.fillWidth: true }

            Text {
                text:           "󰄬  Saved"
                color:          Theme.primary
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }

        Rectangle {
            id: bodyClip
            Layout.fillWidth: true
            Layout.preferredHeight: root.bodyHeight
            radius: 12
            clip:   true
            color:  Qt.rgba(
                Theme.surface_container_lowest.r,
                Theme.surface_container_lowest.g,
                Theme.surface_container_lowest.b, 0.35)

            border.width: dragHandler.active ? 1 : 0
            border.color: Qt.rgba(
                Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)

            ColumnLayout {
                anchors {
                    fill:           parent
                    topMargin:      10
                    bottomMargin:   root.scrimHeight
                    leftMargin:     10
                    rightMargin:    10
                }
                spacing: 4

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:             "󰎁"
                    color:            Theme.on_surface
                    font.family:      "JetBrainsMono Nerd Font"
                    font.pixelSize:   28
                    opacity:          0.9
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text:             root.fileName || "recording.mp4"
                    color:            Theme.on_surface_variant
                    font.family:      "JetBrainsMono Nerd Font"
                    font.pixelSize:   10
                    elide:            Text.ElideMiddle
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text:           "Double-click to open"
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    opacity:        0.65
                }
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                gesturePolicy:   TapHandler.DragWithinBounds
                onDoubleTapped:  DynamicIslandService.openRecordingVideo(root.videoPath)
            }

            HoverHandler {
                id: bodyHover
                cursorShape: bodyHover.hovered ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            DragHandler {
                id: dragHandler
                target: null
                acceptedButtons: Qt.LeftButton

                onActiveChanged: {
                    bodyClip.Drag.active = active;
                    if (active) {
                        root._dragSession = true;
                        return;
                    }
                    if (root._dragSession) {
                        root._dragSession = false;
                        const id = root.activityId;
                        Qt.callLater(() => DynamicIslandService.dismissRecordingAfterDrag(id));
                    }
                }
            }

            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: {
                "text/uri-list": root.uriListPayload,
                "text/plain": root.fileUri,
                "x-special/gnome-copied-files": root.gnomeFilesPayload
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
                    Layout.preferredWidth:  32
                    Layout.preferredHeight: 32
                    radius: 8
                    scale:  pathBtnArea.pressed ? 0.95 : 1.0
                    color:  pathBtnArea.containsMouse ? root._btnFillHover : root._btnFill
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
                        id: pathBtnArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: DynamicIslandService.copyRecordingPath(root.videoPath)
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
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: DynamicIslandService.dismissRecording(root.activityId)
                    }
                }
            }
        }
    }
}
