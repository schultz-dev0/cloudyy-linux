pragma ComponentBehavior: Bound

// Inline system tray: hover the chevron and it flips as the tray icons slide out.
// Opens toward the bar's centre (left on a top/bottom bar, up on a side bar).

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../.."

Item {
    id: root

    // Supplied by the bar so this file stays free of Bar.qml internals.
    required property var window
    property bool vertical: false
    property int cross: 20          // size across the bar
    property color fg: Theme.text
    property color fgMuted: Theme.textMuted

    property bool open: false
    readonly property int count: SystemTray.items.values.length
    readonly property int cell: 20
    readonly property int gap: 4
    readonly property int arrowLen: 16
    readonly property int fullLen: count > 0 ? count * cell + (count - 1) * gap + gap : 0
    property real drawerLen: open ? fullLen : 0

    visible: count > 0
    onCountChanged: if (count === 0) open = false

    Behavior on drawerLen {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    width: vertical ? cross : drawerLen + arrowLen
    height: vertical ? drawerLen + arrowLen : cross

    // Clipped strip the icons slide inside; anchored to the arrow side.
    Item {
        id: strip
        clip: true
        x: 0
        y: 0
        width: root.vertical ? root.cross : root.drawerLen
        height: root.vertical ? root.drawerLen : root.cross

        Flow {
            id: icons
            flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
            spacing: root.gap
            // Pinned to the arrow end so the icons emerge from it.
            x: root.vertical ? (strip.width - width) / 2 : strip.width - width - root.gap
            y: root.vertical ? strip.height - height - root.gap : (strip.height - height) / 2
            opacity: root.fullLen > 0 ? Math.min(1, root.drawerLen / root.fullLen) : 0

            Repeater {
                model: SystemTray.items

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: root.cell
                    height: root.cell

                    Image {
                        anchors.centerIn: parent
                        width: 14
                        height: 14
                        sourceSize: Qt.size(28, 28)
                        smooth: true
                        source: cell.modelData.icon
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mouse => {
                            const item = cell.modelData;
                            const p = mapToItem(null, width / 2, height);
                            if (mouse.button === Qt.MiddleButton)
                                item.secondaryActivate();
                            else if (mouse.button === Qt.RightButton || item.onlyMenu) {
                                if (item.hasMenu)
                                    item.display(root.window, p.x, p.y);
                            } else
                                item.activate();
                        }
                        onWheel: wheel => cell.modelData.scroll(wheel.angleDelta.y, false)
                    }
                }
            }
        }
    }

    // Arrow: a real Y-axis flip of the glyph; the outer item turns it to
    // point up/down on a vertical bar.
    Item {
        id: arrow
        x: root.vertical ? 0 : root.drawerLen
        y: root.vertical ? root.drawerLen : 0
        width: root.vertical ? root.cross : root.arrowLen
        height: root.vertical ? root.arrowLen : root.cross
        rotation: root.vertical ? 90 : 0

        // Drawn, not a font glyph: "‹" sits low in the line box and can't be centred.
        Canvas {
            id: chevron
            anchors.centerIn: parent
            width: 7
            height: 10
            readonly property color tint: root.open ? root.fg : root.fgMuted
            onTintChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                ctx.reset();
                ctx.strokeStyle = tint;
                ctx.lineWidth = 1.6;
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.beginPath();
                ctx.moveTo(width - 1.5, 1);
                ctx.lineTo(1.5, height / 2);
                ctx.lineTo(width - 1.5, height - 1);
                ctx.stroke();
            }

            transform: Rotation {
                origin.x: chevron.width / 2
                origin.y: chevron.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: root.open ? 180 : 0
                Behavior on angle {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    // Hover over the arrow or the open drawer keeps it open; a short delay on
    // leave stops it flickering shut while the pointer crosses the gap.
    // Tall margins make the thin bar easy to hit; NoButton lets clicks reach the icons.
    MouseArea {
        id: hoverArea
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: {
            closeDelay.stop();
            root.open = true;
        }
        onExited: closeDelay.restart()
    }

    Timer {
        id: closeDelay
        interval: 250
        onTriggered: {
            if (!hoverArea.containsMouse)
                root.open = false;
        }
    }
}
