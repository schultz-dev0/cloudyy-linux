pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "../.."

// Fan-deck carousel: one focused card, up to two peeking out on each side,
// tilted/scaled/dimmed with distance. Shared visual for the theme picker and
// its per-theme wallpaper strip — feed it {image, label} items and an index.
Item {
    id: root

    required property var items   // [{image, label}, ...]
    property int currentIndex: 0

    // Sizing/tuning knobs — defaults roughly match the approved mockup, not
    // exact CSS px; instances (e.g. the smaller wallpaper sub-deck) override.
    property int centerWidth: 460
    property int centerHeight: 259
    property int sideWidth: 380
    property int sideHeight: 214
    property int stepOffset: 160
    property real stepScale: 0.14
    property real stepTilt: 28
    property real stepDim: 0.35
    property int maxVisibleSteps: 2

    function next() { if (items.length > 0) currentIndex = (currentIndex + 1) % items.length; }
    function previous() { if (items.length > 0) currentIndex = (currentIndex - 1 + items.length) % items.length; }

    Repeater {
        model: root.items

        delegate: Item {
            id: card
            required property var modelData
            required property int index

            // Shortest signed distance from the focused card, wrapping
            // around the deck (so cycling past the end feels continuous).
            readonly property int rawDelta: index - root.currentIndex
            readonly property int wrapped: rawDelta > root.items.length / 2
                ? rawDelta - root.items.length
                : rawDelta < -root.items.length / 2 ? rawDelta + root.items.length : rawDelta
            readonly property int delta: Math.abs(wrapped) <= Math.abs(rawDelta) ? wrapped : rawDelta
            readonly property bool isCenter: delta === 0
            readonly property bool hidden: Math.abs(delta) > root.maxVisibleSteps

            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            width: isCenter ? root.centerWidth : root.sideWidth
            height: isCenter ? root.centerHeight : root.sideHeight
            z: 100 - Math.abs(delta)
            visible: opacity > 0.01
            opacity: hidden ? 0 : 1
            scale: isCenter ? 1 : Math.max(0.4, 1 - Math.abs(delta) * root.stepScale)
            x: (parent ? parent.width / 2 : 0) - width / 2 + delta * root.stepOffset

            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160 } }

            transform: Rotation {
                origin.x: card.width / 2
                origin.y: card.height / 2
                axis { x: 0; y: 1; z: 0 }
                angle: card.isCenter ? 0 : (card.delta > 0 ? -root.stepTilt : root.stepTilt)

                Behavior on angle { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                anchors.fill: parent
                radius: 3
                color: Theme.background
                border.width: card.isCenter ? 2 : 0
                border.color: Theme.accent
                antialiasing: true
                clip: true

                Image {
                    anchors.fill: parent
                    source: card.modelData.image && card.modelData.image.length > 0
                        ? "file://" + card.modelData.image : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    smooth: true
                    // Cached and fixed-size on purpose: this used to key
                    // sourceSize off card.delta (bigger when near-center),
                    // which forced a full redecode — visible as a blank
                    // flash — on every single scroll step, since almost
                    // every card's delta changes each time. A theme's own
                    // wallpaper set is small, so decoding every card once at
                    // the center's resolution and reusing it costs nothing.
                    // The 1.5x is overscan headroom for PreserveAspectCrop
                    // (source and card aspect ratios rarely match exactly);
                    // devicePixelRatio on top of that is what actually keeps
                    // this sharp instead of soft — without it, a HiDPI
                    // screen decodes at logical-pixel resolution and the
                    // GPU stretches it out to physical pixels, same as
                    // upscaling a too-small source. Both multiply together
                    // and adapt automatically to whatever screen this is on.
                    sourceSize.width: root.centerWidth * 1.5 * Screen.devicePixelRatio
                    sourceSize.height: root.centerHeight * 1.5 * Screen.devicePixelRatio
                    // A cache miss (e.g. switching to a theme whose
                    // wallpapers were never decoded before) still takes real
                    // time; fade in on Ready instead of popping straight
                    // from the Rectangle's background color once it lands.
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    opacity: card.isCenter ? 0 : Math.min(0.75, Math.abs(card.delta) * root.stepDim)
                }
            }
        }
    }
}
