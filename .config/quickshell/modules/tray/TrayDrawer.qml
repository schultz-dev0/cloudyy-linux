pragma ComponentBehavior: Bound

// Inline system tray: hover the chevron and it flips as the tray icons slide out.
// Opens toward the bar's centre (left on a top/bottom bar, up on a side bar).

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../.."
import "../../overview/services"

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

    // ── Tray item -> window ──────────────────────────────────────────────
    // Tray items don't expose a window or pid, so match by name: the item's
    // id / title / tooltip tokens against each window's class ("trcc" ->
    // "trcc-linux", "openrgb" -> "org.openrgb.OpenRGB").
    function norm(s) {
        return `${s ?? ""}`.toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function nameTokens(item) {
        const tokens = [];
        const sources = [item.id, item.title, item.tooltipTitle];
        for (const src of sources) {
            const raw = `${src ?? ""}`;
            if (!raw.length)
                continue;
            for (const part of [raw].concat(raw.split(/[_.\s]+/))) {
                const t = norm(part);
                if (t.length >= 3 && tokens.indexOf(t) < 0)
                    tokens.push(t);
            }
        }
        return tokens;
    }

    function windowFor(item) {
        const tokens = nameTokens(item);
        if (!tokens.length)
            return null;
        const windows = (HyprlandData.windowList || []).filter(w => w.mapped !== false);
        let best = null;
        let bestScore = 0;
        for (const w of windows) {
            const cls = norm(w.class || w.initialClass);
            if (!cls.length)
                continue;
            let score = 0;
            for (const t of tokens) {
                if (cls === t)
                    score = Math.max(score, 3);
                else if (cls.indexOf(t) >= 0 || (cls.length >= 4 && t.indexOf(cls) >= 0))
                    score = Math.max(score, 2);
            }
            // Ties go to the most recently focused window.
            if (score > bestScore || (score === bestScore && score > 0 && best
                    && (w.focusHistoryID ?? 9999) < (best.focusHistoryID ?? 9999))) {
                best = w;
                bestScore = score;
            }
        }
        return best;
    }

    function showMenu(item, x, y) {
        if (item.hasMenu)
            item.display(root.window, x, y);
    }

    // Left click: jump to the app's window if it has one (switches workspace,
    // including special ones). Otherwise ask the app to open itself, then
    // follow its new window, or fall back to its menu if nothing appeared.
    function activateItem(item, x, y) {
        const win = windowFor(item);
        if (win) {
            HyprDispatch.focusWindow(win);
            return;
        }
        if (item.onlyMenu) {
            showMenu(item, x, y);
            return;
        }
        pending.item = item;
        pending.x = x;
        pending.y = y;
        item.activate();
        HyprlandData.updateAll();
        pending.restart();
    }

    Timer {
        id: pending
        property var item: null
        property real x: 0
        property real y: 0
        interval: 900
        onTriggered: {
            const item = pending.item;
            pending.item = null;
            if (!item)
                return;
            const win = root.windowFor(item);
            if (win)
                HyprDispatch.focusWindow(win);
            else
                root.showMenu(item, x, y);
        }
    }

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
                            else if (mouse.button === Qt.RightButton)
                                root.showMenu(item, p.x, p.y);
                            else
                                root.activateItem(item, p.x, p.y);
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
