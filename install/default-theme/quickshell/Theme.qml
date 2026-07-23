#pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Same as .config/quickshell/Theme.qml — kept for install fallback reference.
// Live config uses the dotfiles copy; matugen writes quickshell-colors.json only.
QtObject {
    id: theme

    readonly property string colorsPath: {
        const home = Quickshell.env("HOME") || "";
        return home ? home + "/.config/matugen/generated/quickshell-colors.json" : "";
    }

    readonly property var _colorKeys: [
        "background", "error", "error_container", "inverse_on_surface", "inverse_primary",
        "inverse_surface", "on_background", "on_error", "on_error_container", "on_primary",
        "on_primary_container", "on_primary_fixed", "on_primary_fixed_variant", "on_secondary",
        "on_secondary_container", "on_secondary_fixed", "on_secondary_fixed_variant",
        "on_surface", "on_surface_variant", "on_tertiary", "on_tertiary_container",
        "on_tertiary_fixed", "on_tertiary_fixed_variant", "outline", "outline_variant",
        "primary", "primary_container", "primary_fixed", "primary_fixed_dim", "scrim",
        "secondary", "secondary_container", "secondary_fixed", "secondary_fixed_dim", "shadow",
        "source_color", "surface", "surface_bright", "surface_container",
        "surface_container_high", "surface_container_highest", "surface_container_low",
        "surface_container_lowest", "surface_dim", "surface_tint", "surface_variant",
        "tertiary", "tertiary_container", "tertiary_fixed", "tertiary_fixed_dim"
    ]

    property string mode: "auto"

    property color background: "#161217"
    property color error: "#ffb4ab"
    property color error_container: "#93000a"
    property color inverse_on_surface: "#342f34"
    property color inverse_primary: "#765085"
    property color inverse_surface: "#e9e0e7"
    property color on_background: "#e9e0e7"
    property color on_error: "#690005"
    property color on_error_container: "#ffdad6"
    property color on_primary: "#442253"
    property color on_primary_container: "#f8d8ff"
    property color on_primary_fixed: "#2d0b3d"
    property color on_primary_fixed_variant: "#5c386b"
    property color on_secondary: "#392c3d"
    property color on_secondary_container: "#f1dcf4"
    property color on_secondary_fixed: "#231728"
    property color on_secondary_fixed_variant: "#504255"
    property color on_surface: "#e9e0e7"
    property color on_surface_variant: "#cec3cd"
    property color on_tertiary: "#4c2524"
    property color on_tertiary_container: "#ffdad8"
    property color on_tertiary_fixed: "#331111"
    property color on_tertiary_fixed_variant: "#663b3a"
    property color outline: "#978e97"
    property color outline_variant: "#4c444d"
    property color primary: "#e4b7f3"
    property color primary_container: "#5c386b"
    property color primary_fixed: "#f8d8ff"
    property color primary_fixed_dim: "#e4b7f3"
    property color scrim: "#000000"
    property color secondary: "#d4c0d7"
    property color secondary_container: "#504255"
    property color secondary_fixed: "#f1dcf4"
    property color secondary_fixed_dim: "#d4c0d7"
    property color shadow: "#000000"
    property color source_color: "#211824"
    property color surface: "#161217"
    property color surface_bright: "#3d373d"
    property color surface_container: "#231e23"
    property color surface_container_high: "#2d282e"
    property color surface_container_highest: "#383339"
    property color surface_container_low: "#1f1a1f"
    property color surface_container_lowest: "#110d12"
    property color surface_dim: "#161217"
    property color surface_tint: "#e4b7f3"
    property color surface_variant: "#4c444d"
    property color tertiary: "#f5b7b5"
    property color tertiary_container: "#663b3a"
    property color tertiary_fixed: "#ffdad8"
    property color tertiary_fixed_dim: "#f5b7b5"

    property var colorsFile: FileView {
        path: theme.colorsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme._applyJson(text())
        onLoadFailed: error => console.warn("[Theme] failed to load quickshell-colors.json:", error)
    }

    Component.onCompleted: {
        if (colorsFile.loaded)
            theme._applyJson(colorsFile.text());
    }

    function _applyJson(raw) {
        if (!raw)
            return;
        let data;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            console.warn("[Theme] invalid quickshell-colors.json:", e);
            return;
        }
        if (data.mode !== undefined && data.mode !== "") {
            const m = String(data.mode).toLowerCase();
            theme.mode = (m === "light") ? "light" : "auto";
        }
        const colors = data.colors || {};
        for (let i = 0; i < theme._colorKeys.length; i++) {
            const key = theme._colorKeys[i];
            if (colors[key] !== undefined)
                theme[key] = colors[key];
        }
    }

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

    readonly property real glassShellAlpha:       0.72
    readonly property real glassSectionAlpha:     0.48
    readonly property real glassSectionHighAlpha: 0.58
    function glass(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }
    readonly property color glassShell:       glass(surface, glassShellAlpha)
    readonly property color glassSection:     glass(surface_container, glassSectionAlpha)
    readonly property color glassSectionHigh: glass(surface_container_high, glassSectionHighAlpha)

    readonly property bool isLightTheme: mode === "light"
    readonly property int glassPanelRadius: 20
    readonly property color glassPanelBorder: isLightTheme
        ? Qt.rgba(outline.r, outline.g, outline.b, 0.38)
        : Qt.rgba(1, 1, 1, 0.22)

    readonly property int islandShellWidth: 280
    readonly property int islandShellHeight: 64
    readonly property int islandShellRadius: 28
    readonly property int islandShellHMargin: 16
    readonly property int islandPreviewInset: 7
    readonly property int islandPreviewContentWidth: islandShellWidth - islandPreviewInset * 2
    readonly property int islandPreviewRadius: Math.max(0, islandShellRadius - islandPreviewInset - 1)
}
