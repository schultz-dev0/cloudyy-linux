pragma Singleton
import QtQuick

// Default quickshell theme (matches install/default-theme/matugen). Overwritten by matugen on wallpaper change.
QtObject {
    readonly property string mode: "#161217" === "#fff8f8" ? "light" : "auto"

    readonly property color background: "#161217"
    readonly property color error: "#ffb4ab"
    readonly property color error_container: "#93000a"
    readonly property color inverse_on_surface: "#342f34"
    readonly property color inverse_primary: "#765085"
    readonly property color inverse_surface: "#e9e0e7"
    readonly property color on_background: "#e9e0e7"
    readonly property color on_error: "#690005"
    readonly property color on_error_container: "#ffdad6"
    readonly property color on_primary: "#442253"
    readonly property color on_primary_container: "#f8d8ff"
    readonly property color on_primary_fixed: "#2d0b3d"
    readonly property color on_primary_fixed_variant: "#5c386b"
    readonly property color on_secondary: "#392c3d"
    readonly property color on_secondary_container: "#f1dcf4"
    readonly property color on_secondary_fixed: "#231728"
    readonly property color on_secondary_fixed_variant: "#504255"
    readonly property color on_surface: "#e9e0e7"
    readonly property color on_surface_variant: "#cec3cd"
    readonly property color on_tertiary: "#4c2524"
    readonly property color on_tertiary_container: "#ffdad8"
    readonly property color on_tertiary_fixed: "#331111"
    readonly property color on_tertiary_fixed_variant: "#663b3a"
    readonly property color outline: "#978e97"
    readonly property color outline_variant: "#4c444d"
    readonly property color primary: "#e4b7f3"
    readonly property color primary_container: "#5c386b"
    readonly property color primary_fixed: "#f8d8ff"
    readonly property color primary_fixed_dim: "#e4b7f3"
    readonly property color scrim: "#000000"
    readonly property color secondary: "#d4c0d7"
    readonly property color secondary_container: "#504255"
    readonly property color secondary_fixed: "#f1dcf4"
    readonly property color secondary_fixed_dim: "#d4c0d7"
    readonly property color shadow: "#000000"
    readonly property color source_color: "#211824"
    readonly property color surface: "#161217"
    readonly property color surface_bright: "#3d373d"
    readonly property color surface_container: "#231e23"
    readonly property color surface_container_high: "#2d282e"
    readonly property color surface_container_highest: "#383339"
    readonly property color surface_container_low: "#1f1a1f"
    readonly property color surface_container_lowest: "#110d12"
    readonly property color surface_dim: "#161217"
    readonly property color surface_tint: "#e4b7f3"
    readonly property color surface_variant: "#4c444d"
    readonly property color tertiary: "#f5b7b5"
    readonly property color tertiary_container: "#663b3a"
    readonly property color tertiary_fixed: "#ffdad8"
    readonly property color tertiary_fixed_dim: "#f5b7b5"

    // Frutiger Aero / cloudy accents derived from matugen tokens
    readonly property color glassTint:        Qt.rgba(primary_container.r, primary_container.g, primary_container.b, 0.35)
    readonly property color glassHighlight:   Qt.rgba(1, 1, 1, 0.55)
    readonly property color glassEdge:        Qt.rgba(1, 1, 1, 0.75)
    readonly property color glassShadow:      Qt.rgba(0, 0, 0, 0.18)
    readonly property color skyTop:           Qt.lighter(primary_container, 1.15)
    readonly property color skyBottom:        Qt.lighter(tertiary_container, 1.05)
    readonly property color accent:           primary
    readonly property color accentSoft:       inverse_primary
    readonly property color textPrimary:      on_surface
    readonly property color textMuted:        on_surface_variant

    // Frosted glass — Hypr layer blur shows through these (see dock/calculator panels).
    readonly property real glassShellAlpha:       0.72
    readonly property real glassSectionAlpha:     0.48
    readonly property real glassSectionHighAlpha: 0.58
    function glass(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }
    readonly property color glassShell:       glass(surface, glassShellAlpha)
    readonly property color glassSection:     glass(surface_container, glassSectionAlpha)
    readonly property color glassSectionHigh: glass(surface_container_high, glassSectionHighAlpha)

    // Floating panel chrome (macOS-style light rim on dark, outline on light).
    readonly property bool isLightTheme: mode === "light"
    readonly property int glassPanelRadius: 20
    readonly property color glassPanelBorder: isLightTheme
        ? Qt.rgba(outline.r, outline.g, outline.b, 0.38)
        : Qt.rgba(1, 1, 1, 0.22)
}
