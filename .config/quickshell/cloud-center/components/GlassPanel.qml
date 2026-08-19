import QtQuick
import QtQuick.Effects
import ".."   // Theme via parent dir of components/ = config root; adjust to "../.." if symlink route was taken

// Base chrome for cloud-center's own app-window surfaces — Resin material,
// real theme-hue tint. See Theme.qml's resin() comment for the keycap
// reasoning.
Rectangle {
    id: panel
    radius: 0
    color: Theme.resin(Theme.resinFillAlpha)
    border.width: 1
    border.color: Theme.resinBorder
    clip: true

    // Gloss — light catching the material's upper edge.
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: parent.height * 0.35
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.resinGloss }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Inner glow — a hint of structure beneath the material. Actually
    // blurred, not just low-opacity, so it reads as soft light rather than
    // a defined shape. Corner-anchored with the center pushed past the edge
    // (clipped by this panel) instead of a percentage-of-height position,
    // so it never lands under whatever content is placed inside.
    Rectangle {
        width: parent.width * 0.35
        height: width
        radius: width / 2
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: -width * 0.5
            bottomMargin: -height * 0.5
        }
        color: Theme.resinGlow
        opacity: 0.5
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 80 }
    }
}
