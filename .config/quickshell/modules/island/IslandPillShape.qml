import QtQuick
import QtQuick.Shapes

// Vector pill chrome — smooth anti-aliased border without MultiEffect.
Shape {
    id: root

    property real outerRadius: 28
    property real strokeWidth: 2
    property color strokeColor: Qt.rgba(1, 1, 1, 0.12)
    property color fillColor: Qt.rgba(0, 0, 0, 0.95)

    readonly property real pw: width
    readonly property real ph: height
    readonly property real r: Math.min(outerRadius, Math.floor(ph / 2))
    readonly property real ir: Math.max(0, r - strokeWidth)
    readonly property real m: strokeWidth

    antialiasing: true
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
        strokeWidth: 0
        fillColor: root.strokeColor
        startX: root.r
        startY: 0
        PathLine { x: root.pw - root.r; y: 0 }
        PathArc {
            x: root.pw
            y: root.r
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: root.pw; y: root.ph - root.r }
        PathArc {
            x: root.pw - root.r
            y: root.ph
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: root.r; y: root.ph }
        PathArc {
            x: 0
            y: root.ph - root.r
            radiusX: root.r
            radiusY: root.r
        }
        PathLine { x: 0; y: root.r }
        PathArc {
            x: root.r
            y: 0
            radiusX: root.r
            radiusY: root.r
        }
    }

    ShapePath {
        strokeWidth: 0
        fillColor: root.fillColor
        startX: root.m + root.ir
        startY: root.m
        PathLine { x: root.pw - root.m - root.ir; y: root.m }
        PathArc {
            x: root.pw - root.m
            y: root.m + root.ir
            radiusX: root.ir
            radiusY: root.ir
        }
        PathLine { x: root.pw - root.m; y: root.ph - root.m - root.ir }
        PathArc {
            x: root.pw - root.m - root.ir
            y: root.ph - root.m
            radiusX: root.ir
            radiusY: root.ir
        }
        PathLine { x: root.m + root.ir; y: root.ph - root.m }
        PathArc {
            x: root.m
            y: root.ph - root.m - root.ir
            radiusX: root.ir
            radiusY: root.ir
        }
        PathLine { x: root.m; y: root.m + root.ir }
        PathArc {
            x: root.m + root.ir
            y: root.m
            radiusX: root.ir
            radiusY: root.ir
        }
    }
}
