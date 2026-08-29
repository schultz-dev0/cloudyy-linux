pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."
import "../carousel"

PanelWindow {
    id: root

    readonly property var svc: ThemePickerService
    readonly property var centeredTheme: svc.selectedIndex >= 0 && svc.selectedIndex < svc.themes.length
        ? svc.themes[svc.selectedIndex] : null
    // Shown for whichever theme is centered, not just the active one — this
    // is browsing/preview, not a commitment. Enter only actually applies a
    // wallpaper when the centered theme is the active one (see
    // ThemePickerService.activateSelection); on any other theme it switches
    // to that theme instead, regardless of which wallpaper is focused here.
    readonly property bool showWallpaperDeck: centeredTheme !== null
        && (centeredTheme.wallpapers || []).length > 1

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    visible: svc.visible
    color: "transparent"
    // Overlay, not Top: the bar is also a Top-layer surface and wins that
    // layer's stacking order, so a Top-layer scrim here left it floating
    // undimmed above the rest of the dimmed desktop. Overlay sits above it,
    // matching IdleScene's precedent for full-screen coverage.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:command"
    WlrLayershell.keyboardFocus: svc.keyboardGrab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Dims the real desktop behind the carousel, bar included.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: svc.close()
    }

    FocusScope {
        id: keyNav
        anchors.fill: parent
        focus: true

        Keys.onLeftPressed: event => { svc.moveThemeFocus(-1); event.accepted = true; }
        Keys.onRightPressed: event => { svc.moveThemeFocus(1); event.accepted = true; }
        Keys.onDownPressed: event => { svc.moveWallpaperFocus(1); event.accepted = true; }
        Keys.onUpPressed: event => { svc.moveWallpaperFocus(-1); event.accepted = true; }
        Keys.onReturnPressed: event => { svc.activateSelection(); event.accepted = true; }
        Keys.onEscapePressed: event => { svc.close(); event.accepted = true; }

        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted = true
            propagateComposedEvents: false
        }

        Column {
            anchors.centerIn: parent
            spacing: 18

            CarouselDeck {
                id: themeDeck
                width: 700
                height: 430
                anchors.horizontalCenter: parent.horizontalCenter
                items: svc.themes.map(t => ({ image: t.preview, label: t.name }))
                currentIndex: svc.selectedIndex
                // Square, not the previous ~16:9 box: preview.png is meant
                // to be square (see themes/*/preview.png convention) — a
                // wide box cropped a square source on the top/bottom for
                // no reason. Same visual area as before (460x259), reshaped.
                centerWidth: 345
                centerHeight: 345
                sideWidth: 285
                sideHeight: 285
                // stepOffset is the real lever here — it's what pushes
                // side cards further from center. The outer width/height
                // above don't clip anything (only the per-card Rectangle
                // does), so they don't visibly affect spacing on their own.
                stepOffset: 190
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.centeredTheme ? root.centeredTheme.name : ""
                    color: Theme.text
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.centeredTheme !== null
                    text: (root.centeredTheme
                        ? (root.centeredTheme.slug === svc.currentSlug ? "current · " : "") + root.centeredTheme.mode
                        : "")
                    color: Theme.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.letterSpacing: 1
                    opacity: 0.85
                }
            }

            CarouselDeck {
                id: wallpaperDeck
                visible: root.showWallpaperDeck
                width: 320
                height: 130
                anchors.horizontalCenter: parent.horizontalCenter
                // wallpaperThumbnails (pre-shrunk, engine-side — see
                // package.sh's _theme_display_thumbnail) are what get
                // displayed here, not the raw wallpapers array: decoding a
                // small cached copy is fast regardless of the source
                // photo's size. Applying a wallpaper still goes through
                // ThemePickerService using the real wallpapers path.
                items: root.showWallpaperDeck
                    ? (root.centeredTheme.wallpaperThumbnails || []).map(p => ({ image: p, label: "" }))
                    : []
                currentIndex: svc.selectedWallpaperIndex
                centerWidth: 130
                centerHeight: 74
                sideWidth: 100
                sideHeight: 56
                stepOffset: 70
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: svc.themes.length === 0
                text: svc.loading ? "Loading themes…" : "No themes found"
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.showWallpaperDeck
                    ? "← → theme · ↑ ↓ wallpaper · enter apply · esc close"
                    : "← → theme · enter apply · esc close"
                color: Theme.textMuted
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                opacity: 0.6
            }
        }
    }

    Connections {
        target: svc
        function onRequestFocus() {
            keyNav.forceActiveFocus();
        }
    }

    IpcHandler {
        target: "themepicker"
        function open() { svc.open(); }
        function hide() { svc.close(); }
        function toggle() { svc.toggle(); }
    }
}
