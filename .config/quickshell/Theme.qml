pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Stable Cloudyy curated-theme loader. Activation swaps the current stage;
// FileView watches the stable state path and the reload IPC handles pointer swaps.
QtObject {
    id: theme

    readonly property string stateHome: {
        const configured = Quickshell.env("XDG_STATE_HOME") || "";
        if (configured)
            return configured;
        const home = Quickshell.env("HOME") || "";
        return home ? home + "/.local/state" : "";
    }
    readonly property string colorsPath: {
        return stateHome ? stateHome + "/cloudyy/current/theme/theme.json" : "";
    }

    readonly property var _colorKeys: [
        "background", "surface", "surfaceRaised", "surfaceOverlay", "text", "textMuted",
        "accent", "accentMuted", "accentAlt", "onAccent", "border", "selection",
        "success", "warning", "error", "info", "shadow"
    ]

    property string mode: "dark"

    // Official Nord values are a complete, legible fallback if active state is
    // temporarily unavailable. Invalid updates retain the last complete theme.
    property color background: "#2E3440"
    property color surface: "#3B4252"
    property color surfaceRaised: "#434C5E"
    property color surfaceOverlay: "#4C566A"
    property color text: "#ECEFF4"
    property color textMuted: "#E5E9F0"
    property color accent: "#88C0D0"
    property color accentMuted: "#5E81AC"
    property color accentAlt: "#8FBCBB"
    // QML reserves on<Name> for signal handlers, so JSON's onAccent role is
    // exposed as accentText at this boundary.
    property color accentText: "#2E3440"
    property color border: "#4C566A"
    property color selection: "#434C5E"
    property color success: "#A3BE8C"
    property color warning: "#EBCB8B"
    property color error: "#BF616A"
    property color info: "#81A1C1"
    property color shadow: "#2E3440"

    property var colorsFile: FileView {
        path: theme.colorsPath
        watchChanges: true
        onFileChanged: theme.reload()
        onLoaded: theme._applyJson(text())
        onLoadFailed: error => console.warn("[Theme] failed to load active theme:", error)
    }

    property var reloadIpc: IpcHandler {
        target: "theme"
        function reload(): void { theme.reload(); }
    }

    Component.onCompleted: {
        if (colorsFile.loaded)
            theme._applyJson(colorsFile.text());
    }

    function reload() {
        colorsFile.reload();
    }

    function _validColor(value) {
        return typeof value === "string" && /^#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?$/.test(value);
    }

    function _qmlColor(value) {
        if (value.length === 7)
            return value;
        // Cloudyy packages use CSS-style #RRGGBBAA; Qt QColor expects #AARRGGBB.
        return "#" + value.slice(7, 9) + value.slice(1, 7);
    }

    function _validTheme(data) {
        if (typeof data !== "object" || data === null || Array.isArray(data))
            return false;
        if (data.mode !== "dark" && data.mode !== "light")
            return false;
        if (typeof data.colors !== "object" || data.colors === null || Array.isArray(data.colors))
            return false;
        for (let i = 0; i < theme._colorKeys.length; i++) {
            if (!theme._validColor(data.colors[theme._colorKeys[i]]))
                return false;
        }
        return true;
    }

    function _applyJson(raw) {
        let data = null;
        try {
            data = JSON.parse(raw);
        } catch (e) {
            console.warn("[Theme] invalid active theme JSON:", e);
            return;
        }
        if (!theme._validTheme(data)) {
            console.warn("[Theme] active theme does not satisfy the semantic color contract");
            return;
        }
        for (let i = 0; i < theme._colorKeys.length; i++) {
            const key = theme._colorKeys[i];
            if (key === "onAccent")
                theme.accentText = theme._qmlColor(data.colors[key]);
            else
                theme[key] = theme._qmlColor(data.colors[key]);
        }
        theme.mode = data.mode;
    }

    // Frutiger Aero / cloudy accents derived from curated semantic roles.
    readonly property color glassTint:        withAlpha(accentMuted, 0.35)
    readonly property color glassHighlight:   Qt.rgba(1, 1, 1, 0.55)
    readonly property color glassEdge:        Qt.rgba(1, 1, 1, 0.75)
    readonly property color glassShadow:      Qt.rgba(0, 0, 0, 0.18)
    readonly property color skyTop:           Qt.lighter(accentMuted, 1.15)
    readonly property color skyBottom:        Qt.lighter(accentAlt, 1.05)

    // Frosted glass — Hypr layer blur shows through these (see dock/calculator panels).
    readonly property real glassShellAlpha:       0.72
    readonly property real glassSectionAlpha:     0.48
    readonly property real glassSectionHighAlpha: 0.58
    function withAlpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount)
    }
    function glass(color, alpha) {
        return withAlpha(color, alpha)
    }
    readonly property color glassShell:       glass(surface, glassShellAlpha)
    readonly property color glassSection:     glass(surfaceRaised, glassSectionAlpha)
    readonly property color glassSectionHigh: glass(surfaceOverlay, glassSectionHighAlpha)

    // Resin material — a real theme-hue tint at real saturation, not a
    // neutral glass tint. Inspired by translucent resin keycaps: color
    // deepens with the material's own thickness, and a faint inner shape
    // suggests structure underneath rather than showing the desktop behind
    // it. Clamped to BOTH a floor and a ceiling — unlike islandAccent's
    // floor-only clamp, this fill sits directly behind existing light-toned
    // text, so a naturally pale/pastel accent (light
    // wallpapers) needs pulling back down into "deep resin" range just as
    // much as a too-dark one needs lifting up. Used sparingly — hero
    // surfaces only, not every panel.
    //
    // The clamp range itself is mode-aware, not just the accent: light
    // mode's dark text reads fine against a medium-toned fill, but dark
    // mode's light text needs the fill pulled meaningfully darker for the
    // same contrast — same lightness range read as "fine" in one mode and
    // "rough" in the other.
    function _clampLightness(c, min, max) {
        const l = Math.min(max, Math.max(min, c.hslLightness))
        return Qt.hsla(c.hslHue, c.hslSaturation, l, c.a)
    }
    readonly property color resinTint: isLightTheme
        ? _clampLightness(accent, 0.24, 0.42)
        : _clampLightness(accent, 0.14, 0.22)
    readonly property real resinFillAlpha: 0.34
    function resin(alpha) {
        return Qt.rgba(resinTint.r, resinTint.g, resinTint.b, alpha)
    }
    readonly property color resinBorder: Qt.rgba(resinTint.r, resinTint.g, resinTint.b, 0.55)
    readonly property color resinGloss:  Qt.rgba(1, 1, 1, 0.16)
    readonly property color resinGlow:   Qt.rgba(1, 1, 1, 0.14)

    // Floating panel chrome (macOS-style light rim on dark, border on light).
    readonly property bool isLightTheme: mode === "light"
    readonly property int glassPanelRadius: 20
    readonly property color glassPanelBorder: isLightTheme
        ? withAlpha(border, 0.38)
        : Qt.rgba(1, 1, 1, 0.22)

    // Flat instrument-panel divider — thin low-contrast rule used to separate
    // groups instead of boxing every tile in its own bordered card.
    readonly property color hairline: withAlpha(border, 0.4)

    // Persistent top-attached island chrome and motion.
    readonly property int islandRestWidth: 176
    readonly property int islandTimerRestWidth: 240
    readonly property int islandRestHeight: 24
    readonly property int islandCarouselWidth: 610
    readonly property int islandCarouselHeight: 142
    readonly property int islandExpandedMaxHeight: 536
    // Top stays square/flush where the island meets the screen edge — "
    // attached to the bezel," not floating — but the lower corners are
    // rounded again, comfortable/capsule-like the way the dock's pill is,
    // after the square-cornered bracket-readout experiment didn't land.
    readonly property int islandShoulderRadius: 0
    readonly property int islandRestLowerRadius: 12
    readonly property int islandOpenLowerRadius: 26
    readonly property int islandOpenDuration: 220
    readonly property int islandExpandDuration: 260
    readonly property int islandCloseDuration: 180
    readonly property int islandOpacityDuration: 120
    // Island chrome is always black, independent of light/dark theme mode.
    // Fully opaque (no wallpaper bleed-through) so it reads as a distinctly
    // darker surface than the bar, which follows the live theme's surface
    // tone instead of a fixed black.
    readonly property color islandSurface: Qt.rgba(0, 0, 0, 1.0)
    readonly property color islandBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property color islandOnSurface: Qt.rgba(1, 1, 1, 1)
    readonly property color islandOnSurfaceVariant: Qt.rgba(1, 1, 1, 0.6)
    readonly property color islandHover: Qt.rgba(1, 1, 1, 0.07)
    readonly property color islandPressed: Qt.rgba(1, 1, 1, 0.12)
    // Theme accents may be authored for a light surface and land too dark for
    // the island's always-black surface. Clamp their lightness so island-only
    // accent use stays visible; islandOnAccent is
    // the fixed dark counterpart for text/icons drawn on a filled accent.
    function _minLightness(c, floor) {
        return c.hslLightness < floor
            ? Qt.hsla(c.hslHue, c.hslSaturation, floor, c.a)
            : c;
    }
    readonly property color islandAccent: _minLightness(accent, 0.55)
    readonly property color islandAccentAlt: _minLightness(accentAlt, 0.55)
    readonly property color islandOnAccent: Qt.rgba(0, 0, 0, 0.85)
    readonly property color islandFocus: islandAccent

    // Screenshot/recording preview sizing retained for transient activities.
    readonly property int islandShellWidth: 280
    readonly property int islandShellHeight: 64
    readonly property int islandShellRadius: 28
    readonly property int islandShellHMargin: 16
    readonly property int islandPreviewInset: 7
    readonly property int islandPreviewContentWidth: islandShellWidth - islandPreviewInset * 2
    readonly property int islandPreviewRadius: Math.max(0, islandShellRadius - islandPreviewInset - 1)
}
