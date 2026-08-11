pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import "../.."
import "IslandPreviewDragPolicy.js" as DragPolicy

Item {
    id: root

    property string videoPath: ""
    property string activityId: ""
    property string thumbPath: ""

    readonly property int contentWidth: Theme.islandPreviewContentWidth
    readonly property int thumbRadius: Theme.islandPreviewRadius
    readonly property int scrimHeight: 34
    readonly property int maxThumbHeight: 132
    readonly property int thumbInnerWidth: contentWidth
    readonly property string _thumbTarget: "/tmp/cloudyy-recording.preview.jpg"

    property int previewHeight: 100

    implicitWidth:  contentWidth
    implicitHeight: previewHeight

    function _shellQuote(path) {
        return "'" + String(path).replace(/'/g, "'\\''") + "'";
    }

    function _fileUri(path) {
        if (!path)
            return "";
        if (path.startsWith("file://"))
            return path;
        const encoded = path.split("/").map(seg => encodeURIComponent(seg)).join("/");
        return "file://" + encoded;
    }

    function _requestThumb() {
        root.thumbPath = "";
        if (!root.videoPath)
            return;
        thumbGen._video = root.videoPath;
        thumbGen.running = false;
        thumbGen.running = true;
    }

    readonly property string fileUri: _fileUri(root.videoPath)

    readonly property color _btnFill: Qt.rgba(1, 1, 1, 0)
    readonly property color _btnFillHover: Qt.rgba(1, 1, 1, 0)
    readonly property color _btnBorder: Qt.rgba(1, 1, 1, 0)

    property bool _dragSession: false
    property bool _qtDragStarted: false

    function _dismissAfterDrag() {
        const id = root.activityId;
        Qt.callLater(() => DynamicIslandService.dismissRecordingAfterDrag(id));
    }

    function _beginPreviewDrag() {
        const tw = Math.max(1, Math.round(imageBounds.width));
        const th = Math.max(1, Math.round(imageBounds.height));
        DynamicIslandService.beginPreviewDrag();
        imageBounds.grabToImage(result => {
            if (!DragPolicy.shouldStartQtDrag(
                    root._dragSession, root._qtDragStarted, dragHandler.active))
                return;
            thumbClip.Drag.imageSource = result.url;
            root._qtDragStarted = true;
            thumbClip.Drag.active = true;
        }, Qt.size(tw, th));
    }

    anchors.fill: parent

    onVideoPathChanged: root._requestThumb()

    Process {
        id: thumbGen
        property string _video: ""
        running: false
        command: [
            "sh", "-c",
            "thumb=" + root._shellQuote(root._thumbTarget) + "; "
            + "video=" + root._shellQuote(_video) + "; "
            + "rm -f \"$thumb\"; "
            + "if command -v ffmpeg >/dev/null 2>&1; then "
            + "ffmpeg -y -loglevel error -ss 0.25 -i \"$video\" -frames:v 1 -vf scale=534:-1 \"$thumb\" 2>/dev/null || "
            + "ffmpeg -y -loglevel error -i \"$video\" -frames:v 1 -vf scale=534:-1 \"$thumb\" 2>/dev/null; "
            + "fi; "
            + "[ -f \"$thumb\" ] && printf '%s' \"$thumb\""
        ]
        stdout: SplitParser {
            onRead: line => {
                const path = line.trim();
                if (path && root.videoPath)
                    root.thumbPath = path;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            id: thumbHost
            Layout.fillWidth: true
            Layout.preferredWidth:  root.contentWidth
            Layout.preferredHeight: root.previewHeight

            Item {
                id: thumbClip
                anchors {
                    fill:   parent
                    margins: 1
                }

                Rectangle {
                    id: imageMask
                    anchors.fill: parent
                    radius: root.thumbRadius
                    color:  "white"
                    opacity: 0
                    layer.enabled: true
                    layer.smooth: true
                }

                Rectangle {
                    id: imageBounds
                    anchors.fill: parent
                    radius: root.thumbRadius
                    clip:   Perf.lightweight
                    color:  "transparent"

                    Rectangle {
                        anchors.fill: parent
                        visible: !root.thumbPath
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    Image {
                        id: previewImage
                        anchors.fill: parent
                        visible: !!root.thumbPath
                        source: root.thumbPath
                                 ? (root.thumbPath.startsWith("file://")
                                    ? root.thumbPath
                                    : "file://" + root.thumbPath)
                                 : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: !Perf.lightweight
                        cache: false
                        layer.enabled: true
                        layer.smooth: !Perf.lightweight
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource:  imageMask
                        }

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
                }

                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: {
                    "text/uri-list": root.fileUri ? (root.fileUri + "\r\n") : "",
                    "text/plain": root.fileUri,
                    "x-special/gnome-copied-files": root.videoPath
                                                    ? ("copy\n" + root.videoPath + "\n")
                                                    : ""
                }
                Drag.onDragFinished: {
                    const next = DragPolicy.onDragFinished();
                    root._dragSession = next.dragSession;
                    root._qtDragStarted = next.qtDragStarted;
                    if (next.action === "dismiss")
                        root._dismissAfterDrag();
                }

                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    gesturePolicy:   TapHandler.DragWithinBounds
                    onDoubleTapped:  DynamicIslandService.openRecordingVideo(root.videoPath)
                }

                Rectangle {
                    z: 1
                    anchors {
                        left:   parent.left
                        right:  parent.right
                        bottom: parent.bottom
                    }
                    height: root.scrimHeight
                    radius: root.thumbRadius
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
                    z: 2
                    anchors {
                        left:   parent.left
                        right:  parent.right
                        bottom: parent.bottom
                    }
                    height: root.scrimHeight
                    spacing: 2

                    Item { Layout.preferredWidth: 28 }

                    RowLayout {
                        spacing: 3
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignHCenter

                        Text {
                            Layout.fillWidth: true
                            text:           "Drag out"
                            color:          "#ffffff"
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            renderType: Text.NativeRendering
                            elide:          Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    Rectangle {
                        id: closeBtn
                        Layout.preferredWidth:  28
                        Layout.preferredHeight: 28
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
                            color:          "#ffffff"
                            font.family:    "JetBrainsMono Nerd Font"
                            font.pixelSize: 14
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            id: closeBtnArea
                            anchors.fill:   parent
                            hoverEnabled:   true
                            enabled:        !root._qtDragStarted
                            cursorShape:    Qt.PointingHandCursor
                            onClicked: DynamicIslandService.dismissRecording(root.activityId)
                        }
                    }
                }

                Rectangle {
                    z: 3
                    anchors.fill: parent
                    radius: root.thumbRadius
                    color:  "transparent"
                    border.width: dragHandler.active ? 1 : 0
                    border.color: Qt.rgba(
                        Theme.islandAccent.r, Theme.islandAccent.g, Theme.islandAccent.b, 0.5)

                    Behavior on border.width {
                        enabled: Perf.animationsEnabled
                        NumberAnimation { duration: Perf.msHalf(80) }
                    }
                }

                DragHandler {
                    id: dragHandler
                    target: null
                    acceptedButtons: Qt.LeftButton

                    onActiveChanged: {
                        const next = DragPolicy.onHandlerActiveChanged(
                            root._dragSession, root._qtDragStarted, active);
                        root._dragSession = next.dragSession;
                        root._qtDragStarted = next.qtDragStarted;
                        if (next.action === "start") {
                            root._beginPreviewDrag();
                            return;
                        }
                        // Never clear Drag.active here — that re-enters QDrag::exec.
                        if (next.action === "dismiss")
                            root._dismissAfterDrag();
                    }
                }
            }
        }
    }
}
