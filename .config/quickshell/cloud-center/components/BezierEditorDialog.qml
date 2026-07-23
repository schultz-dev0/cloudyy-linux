import QtQuick
import QtQuick.Controls
import "../services" as S
import "BezierMath.js" as BezierMath
import ".."

CloudDialog {
    id: dialog

    property var curves: []
    property var chips: []
    property string curveName: "myBezier1"
    property real x1: 0.33
    property real y1: 1.0
    property real x2: 0.68
    property real y2: 1.0
    property var basePoints: [0.33, 1.0, 0.68, 1.0]
    property string baseId: "easeOutCubic"
    property string selectedChip: "easeOutCubic"
    property bool fineTuneOpen: false
    property bool moreOpen: false
    property string statusMessage: ""
    property bool busy: false
    property real previewProgress: 0

    readonly property var currentPoints: [x1, y1, x2, y2]
    readonly property bool modified: !BezierMath.pointsEqual(currentPoints, basePoints)
    readonly property bool isUserCurve: {
        const found = curves.find(c => c.id === baseId);
        return found ? found.builtin !== true : true;
    }

    width: 520
    height: fineTuneOpen ? 640 : 560
    heading: "Window animation feel"
    supportingText: "Drag the handles to change how windows open and close. Preview updates live."
    primaryText: "Save & use on windows"
    secondaryText: "Close"
    primaryEnabled: !busy && curveName.trim() !== ""
    showFooter: true

    onPrimaryClicked: dialog.saveAndApply()
    onSecondaryClicked: dialog.close()
    onOpened: {
        fineTuneOpen = false;
        moreOpen = false;
        statusMessage = "";
        dialog.reload();
        previewAnim.restart();
    }
    onClosed: {
        moreOpen = false;
        previewAnim.stop();
    }

    function reload() {
        S.Backend.request("list_bezier_curves", {}, function(result) {
            if (!result) {
                dialog.statusMessage = "Could not load curves";
                return;
            }
            dialog.curves = result.curves || [];
            dialog.chips = result.chips || [];
            dialog.curveName = result.next_name || "myBezier1";
            const defId = result.default_id || "easeOutCubic";
            dialog.selectChip(defId);
            if (!dialog.selectedChip) {
                dialog.applyPreset(defId, false);
            }
        }, function(error) {
            dialog.statusMessage = String(
                (error && (error.message || error.error)) || "Could not load curves"
            );
        });
    }

    function findCurve(id) {
        return curves.find(c => c.id === id) || null;
    }

    function applyPreset(id, useCurveName) {
        const curve = findCurve(id);
        if (!curve || !curve.points || curve.points.length !== 4)
            return;
        x1 = Number(curve.points[0]);
        y1 = Number(curve.points[1]);
        x2 = Number(curve.points[2]);
        y2 = Number(curve.points[3]);
        basePoints = [x1, y1, x2, y2];
        baseId = id;
        selectedChip = chips.some(c => c.id === id) ? id : "";
        if (useCurveName && curve.builtin !== true)
            curveName = curve.name || id;
        canvas.requestPaint();
        previewAnim.restart();
    }

    function selectChip(id) {
        const curve = findCurve(id);
        if (!curve)
            return;
        selectedChip = id;
        x1 = Number(curve.points[0]);
        y1 = Number(curve.points[1]);
        x2 = Number(curve.points[2]);
        y2 = Number(curve.points[3]);
        basePoints = [x1, y1, x2, y2];
        baseId = id;
        canvas.requestPaint();
        previewAnim.restart();
    }

    function saveAndApply() {
        const name = curveName.trim();
        if (!name) {
            statusMessage = "Enter a name for this feel";
            return;
        }
        busy = true;
        statusMessage = "Applying…";
        const points = [x1, y1, x2, y2];
        const finish = function(result) {
            dialog.busy = false;
            dialog.statusMessage = String((result && result.message) || "");
            if (result && result.ok) {
                dialog.basePoints = points.slice();
                dialog.baseId = name;
                dialog.reload();
            }
        };
        // Save custom names first when not builtin, then apply (apply also saves).
        S.Backend.request("apply_bezier_curve", {
            name: name,
            points: points,
        }, finish, function(error) {
            dialog.busy = false;
            dialog.statusMessage = String(
                (error && (error.message || error.error)) || "Apply failed"
            );
        });
    }

    function revertChanges() {
        x1 = Number(basePoints[0]);
        y1 = Number(basePoints[1]);
        x2 = Number(basePoints[2]);
        y2 = Number(basePoints[3]);
        canvas.requestPaint();
        previewAnim.restart();
    }

    function deleteCurrent() {
        if (!isUserCurve)
            return;
        busy = true;
        S.Backend.request("delete_bezier_curve", { name: baseId }, function(result) {
            dialog.busy = false;
            dialog.statusMessage = String((result && result.message) || "");
            dialog.reload();
        }, function(error) {
            dialog.busy = false;
            dialog.statusMessage = String(
                (error && (error.message || error.error)) || "Delete failed"
            );
        });
    }

    Timer {
        id: previewAnim
        interval: 16
        repeat: true
        running: false
        property real t: 0
        onTriggered: {
            t += 0.012;
            if (t > 1.35)
                t = 0;
            dialog.previewProgress = Math.max(0, Math.min(1, t <= 1 ? t : 0));
        }
    }

    Flickable {
        anchors { fill: parent; margins: 16 }
        contentHeight: bodyCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: bodyCol
            width: parent.width
            spacing: 10

            Item {
                width: parent.width
                height: 200

                Rectangle {
                    anchors.fill: parent
                    radius: 12
                    color: Theme.glass(Theme.surface_container_lowest, 0.9)
                    border { width: 1; color: Theme.glass(Theme.outline_variant, 0.5) }

                    Canvas {
                        id: canvas
                        anchors { fill: parent; margins: 10 }
                        property real pad: 18
                        property real viewYLo: Math.min(0, dialog.y1, dialog.y2) - 0.12
                        property real viewYHi: Math.max(1, dialog.y1, dialog.y2) + 0.12
                        property string dragTarget: ""

                        function metrics() {
                            const ySpan = Math.max(0.001, viewYHi - viewYLo);
                            const scale = Math.min(
                                (width - 2 * pad) / 1.0,
                                (height - 2 * pad) / ySpan
                            );
                            return {
                                scale: scale,
                                xOff: (width - scale) / 2,
                                yOff: (height - ySpan * scale) / 2,
                                ySpan: ySpan,
                            };
                        }

                        function toPx(bx, by) {
                            const m = metrics();
                            return Qt.point(
                                m.xOff + bx * m.scale,
                                m.yOff + (viewYHi - by) * m.scale
                            );
                        }

                        function fromPx(cx, cy) {
                            const m = metrics();
                            return Qt.point(
                                (cx - m.xOff) / m.scale,
                                viewYHi - (cy - m.yOff) / m.scale
                            );
                        }

                        function hit(cx, cy) {
                            const r2 = 14 * 14;
                            const p1 = toPx(dialog.x1, dialog.y1);
                            const p2 = toPx(dialog.x2, dialog.y2);
                            if ((cx - p1.x) * (cx - p1.x) + (cy - p1.y) * (cy - p1.y) <= r2)
                                return "p1";
                            if ((cx - p2.x) * (cx - p2.x) + (cy - p2.y) * (cy - p2.y) <= r2)
                                return "p2";
                            return "";
                        }

                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.reset();
                            const w = width;
                            const h = height;
                            ctx.clearRect(0, 0, w, h);

                            const origin = toPx(0, 0);
                            const one = toPx(1, 1);
                            ctx.strokeStyle = Theme.glass(Theme.outline_variant, 0.55);
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(origin.x, origin.y);
                            ctx.lineTo(one.x, origin.y);
                            ctx.moveTo(origin.x, origin.y);
                            ctx.lineTo(origin.x, one.y);
                            ctx.stroke();

                            const p0 = toPx(0, 0);
                            const p1 = toPx(dialog.x1, dialog.y1);
                            const p2 = toPx(dialog.x2, dialog.y2);
                            const p3 = toPx(1, 1);

                            ctx.strokeStyle = Theme.glass(Theme.primary, 0.35);
                            ctx.setLineDash([4, 3]);
                            ctx.beginPath();
                            ctx.moveTo(p0.x, p0.y);
                            ctx.lineTo(p1.x, p1.y);
                            ctx.moveTo(p3.x, p3.y);
                            ctx.lineTo(p2.x, p2.y);
                            ctx.stroke();
                            ctx.setLineDash([]);

                            ctx.strokeStyle = Theme.primary;
                            ctx.lineWidth = 2.5;
                            ctx.beginPath();
                            ctx.moveTo(p0.x, p0.y);
                            for (let i = 1; i <= 48; i++) {
                                const t = i / 48;
                                const y = BezierMath.ease(t, dialog.x1, dialog.y1, dialog.x2, dialog.y2);
                                const pt = toPx(t, y);
                                ctx.lineTo(pt.x, pt.y);
                            }
                            ctx.stroke();

                            function drawHandle(pt) {
                                ctx.beginPath();
                                ctx.fillStyle = Theme.primary;
                                ctx.arc(pt.x, pt.y, 6, 0, Math.PI * 2);
                                ctx.fill();
                                ctx.beginPath();
                                ctx.strokeStyle = Theme.on_primary;
                                ctx.lineWidth = 1.5;
                                ctx.arc(pt.x, pt.y, 6, 0, Math.PI * 2);
                                ctx.stroke();
                            }
                            drawHandle(p1);
                            drawHandle(p2);
                        }

                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: {
                                if (canvas.dragTarget !== "")
                                    return Qt.ClosedHandCursor;
                                return canvas.hit(mouseX, mouseY) !== ""
                                    ? Qt.OpenHandCursor : Qt.ArrowCursor;
                            }
                            onPressed: mouse => {
                                canvas.dragTarget = canvas.hit(mouse.x, mouse.y);
                            }
                            onPositionChanged: mouse => {
                                if (canvas.dragTarget === "")
                                    return;
                                const pt = canvas.fromPx(mouse.x, mouse.y);
                                const bx = BezierMath.round3(BezierMath.clamp01(pt.x));
                                const by = BezierMath.round3(pt.y);
                                if (canvas.dragTarget === "p1") {
                                    dialog.x1 = bx;
                                    dialog.y1 = by;
                                } else {
                                    dialog.x2 = bx;
                                    dialog.y2 = by;
                                }
                                canvas.viewYLo = Math.min(0, dialog.y1, dialog.y2) - 0.12;
                                canvas.viewYHi = Math.max(1, dialog.y1, dialog.y2) + 0.12;
                                canvas.requestPaint();
                                dialog.selectedChip = "";
                            }
                            onReleased: canvas.dragTarget = ""
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "Tip: pull a handle past the box for a slight bounce."
                color: Theme.tertiary
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 10
                    hintingPreference: Font.PreferVerticalHinting
                }
            }

            Rectangle {
                width: parent.width
                height: 34
                radius: 8
                color: Theme.glass(Theme.surface_container_low, 0.75)
                border { width: 1; color: Theme.glass(Theme.outline_variant, 0.45) }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Preview"
                    color: Theme.textMuted
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 10
                    }
                }
                Rectangle {
                    anchors {
                        left: parent.left
                        leftMargin: 70
                        right: parent.right
                        rightMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    height: 4
                    radius: 2
                    color: Theme.glass(Theme.outline_variant, 0.45)
                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.primary
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, (parent.width - width)
                            * BezierMath.ease(
                                dialog.previewProgress,
                                dialog.x1, dialog.y1, dialog.x2, dialog.y2
                            ))
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: dialog.chips
                    delegate: Rectangle {
                        required property var modelData
                        height: 28
                        radius: 999
                        width: chipLabel.implicitWidth + 20
                        color: dialog.selectedChip === modelData.id
                            ? Theme.glass(Theme.primary, 0.18)
                            : Theme.glass(Theme.surface_container_high, 0.7)
                        border {
                            width: 1
                            color: dialog.selectedChip === modelData.id
                                ? Theme.primary
                                : Theme.glass(Theme.outline_variant, 0.5)
                        }
                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: dialog.selectedChip === modelData.id
                                ? Theme.primary : Theme.textMuted
                            font {
                                family: "JetBrainsMono Nerd Font"
                                pixelSize: 10
                            }
                        }
                        TapHandler {
                            onTapped: dialog.selectChip(modelData.id)
                        }
                    }
                }

                Rectangle {
                    height: 28
                    radius: 999
                    width: moreLabel.implicitWidth + 20
                    color: Theme.glass(Theme.surface_container_high, 0.7)
                    border { width: 1; color: Theme.glass(Theme.outline_variant, 0.5) }
                    Text {
                        id: moreLabel
                        anchors.centerIn: parent
                        text: "+ more"
                        color: Theme.textMuted
                        font {
                            family: "JetBrainsMono Nerd Font"
                            pixelSize: 10
                        }
                    }
                    TapHandler {
                        onTapped: {
                            dialog.moreOpen = true;
                            morePopup.open();
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: "Name this feel"
                    color: Theme.textMuted
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 10
                    }
                }
                CloudTextField {
                    width: parent.width
                    text: dialog.curveName
                    placeholderText: "myBezier1"
                    onTextEdited: value => dialog.curveName = value
                }
            }

            Row {
                spacing: 8
                CloudButton {
                    text: dialog.fineTuneOpen ? "Hide fine-tune" : "Fine-tune…"
                    subtle: true
                    compact: true
                    onClicked: dialog.fineTuneOpen = !dialog.fineTuneOpen
                }
                CloudButton {
                    visible: dialog.modified
                    text: "Undo changes"
                    subtle: true
                    compact: true
                    onClicked: dialog.revertChanges()
                }
                CloudButton {
                    visible: dialog.isUserCurve
                    text: "Delete"
                    danger: true
                    subtle: true
                    compact: true
                    enabled: !dialog.busy
                    onClicked: dialog.deleteCurrent()
                }
            }

            Column {
                visible: dialog.fineTuneOpen
                width: parent.width
                spacing: 8

                Row {
                    spacing: 8
                    width: parent.width
                    Text {
                        width: 70
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Point 1"
                        color: Theme.textMuted
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                    }
                    CloudTextField {
                        width: 70
                        compact: true
                        text: dialog.x1.toFixed(3)
                        onAccepted: {
                            dialog.x1 = BezierMath.round3(BezierMath.clamp01(parseFloat(text) || 0));
                            canvas.requestPaint();
                        }
                        onTextEdited: value => {
                            const n = parseFloat(value);
                            if (!isNaN(n)) {
                                dialog.x1 = BezierMath.round3(BezierMath.clamp01(n));
                                canvas.requestPaint();
                            }
                        }
                    }
                    CloudTextField {
                        width: 70
                        compact: true
                        text: dialog.y1.toFixed(3)
                        onTextEdited: value => {
                            const n = parseFloat(value);
                            if (!isNaN(n)) {
                                dialog.y1 = BezierMath.round3(n);
                                canvas.requestPaint();
                            }
                        }
                    }
                }
                Row {
                    spacing: 8
                    width: parent.width
                    Text {
                        width: 70
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Point 2"
                        color: Theme.textMuted
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10 }
                    }
                    CloudTextField {
                        width: 70
                        compact: true
                        text: dialog.x2.toFixed(3)
                        onTextEdited: value => {
                            const n = parseFloat(value);
                            if (!isNaN(n)) {
                                dialog.x2 = BezierMath.round3(BezierMath.clamp01(n));
                                canvas.requestPaint();
                            }
                        }
                    }
                    CloudTextField {
                        width: 70
                        compact: true
                        text: dialog.y2.toFixed(3)
                        onTextEdited: value => {
                            const n = parseFloat(value);
                            if (!isNaN(n)) {
                                dialog.y2 = BezierMath.round3(n);
                                canvas.requestPaint();
                            }
                        }
                    }
                }
            }

            Text {
                visible: dialog.statusMessage !== ""
                width: parent.width
                text: dialog.statusMessage
                color: Theme.textMuted
                wrapMode: Text.WordWrap
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 10
                }
            }
        }
    }

    Popup {
        id: morePopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 360
        height: 420
        padding: 12
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 14
            color: Theme.glass(Theme.surface_container, 0.96)
            border { width: 1; color: Theme.glass(Theme.outline_variant, 0.55) }
        }

        Column {
            anchors.fill: parent
            spacing: 8
            Text {
                text: "All feels"
                color: Theme.textPrimary
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 13
                    weight: Font.Bold
                }
            }
            ListView {
                width: parent.width
                height: parent.height - 36
                clip: true
                model: dialog.curves
                delegate: SelectableRow {
                    required property var modelData
                    width: ListView.view.width
                    title: modelData.name
                    subtitle: modelData.builtin ? "Built-in" : "Saved"
                    leadingGlyph: "󰐊"
                    selected: modelData.id === dialog.baseId
                    onClicked: {
                        dialog.applyPreset(modelData.id, true);
                        morePopup.close();
                    }
                }
            }
        }
    }

    Connections {
        target: dialog
        function onX1Changed() { canvas.requestPaint() }
        function onY1Changed() { canvas.requestPaint() }
        function onX2Changed() { canvas.requestPaint() }
        function onY2Changed() { canvas.requestPaint() }
    }
}
