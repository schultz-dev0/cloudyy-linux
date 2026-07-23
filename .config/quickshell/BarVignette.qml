pragma ComponentBehavior: Bound

// Top wallpaper vignette for the system bar (BarVignette.qml).
// Separate PanelWindow on WlrLayer.Bottom — above windows, under the bar (Top layer).
// Pure black gradient — not tied to matugen / Theme colors.

import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: vignette

    property var assignedScreen: null

    readonly property var resolvedScreen: {
        const pref = assignedScreen;
        const all = Quickshell.screens;
        if (!all.length)
            return null;
        if (!pref)
            return all[0];
        const name = pref.name;
        for (let i = 0; i < all.length; i++) {
            if (all[i].name === name)
                return all[i];
        }
        return all[0];
    }

    screen: resolvedScreen

    // ── Tunables ──────────────────────────────────────────────────────────────
    readonly property int stripHeight: 104
    readonly property real strength: 0.7

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: 0
        left: 0
        right: 0
    }
    implicitHeight: stripHeight
    // Do not participate in top-edge panel stacking (bar's exclusive zone was pushing this down).
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Bottom layer: above tiled/floating windows, below the bar (defaults to Top).
    aboveWindows: false

    WlrLayershell.namespace: "quickshell:bar-vignette"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop {
                position: 0.0
                color: Qt.rgba(0, 0, 0, vignette.strength)
            }
            GradientStop {
                position: 0.22
                color: Qt.rgba(0, 0, 0, vignette.strength * 0.72)
            }
            GradientStop {
                position: 0.48
                color: Qt.rgba(0, 0, 0, vignette.strength * 0.38)
            }
            GradientStop {
                position: 0.72
                color: Qt.rgba(0, 0, 0, vignette.strength * 0.12)
            }
            GradientStop {
                position: 1.0
                color: "transparent"
            }
        }
    }
}
