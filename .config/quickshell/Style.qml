pragma Singleton
import QtQuick

// =============================================================================
// cloudyyOS Quickshell — Style
// =============================================================================
// EDIT ME FREELY. Every size, spacing, radius, timing, and font in the shell
// is sourced from this file. Group-by-component below.
//
//   Sizes / margins / radii  →  pixels (int)
//   Durations / intervals    →  milliseconds (int)
//   Alphas / ratios          →  0.0 — 1.0 (real)
//   Colors                   →  see Theme.qml (matugen-generated, do not edit)
//
// To rebrand spacing globally, search-and-replace within this file. To add a
// new tunable, just declare it as another `readonly property` and reference it
// from shell.qml / Notifications.qml.
// =============================================================================

QtObject {

    // ===========================================================
    // Typography & Global Effects
    // ===========================================================
    readonly property string fontFamily:        "Monocraft"
    readonly property color  textShadowColor:   Qt.rgba(0, 0, 0, 0.6)
    readonly property int    textShadowRadius:  4
    readonly property int    textShadowOffsetY: 1

    // ===========================================================
    // Top bar (Segmented macOS Style)
    // ===========================================================
    readonly property int  barHeight:           38
    readonly property int  barExclusiveZone:    46
    readonly property int  barMarginTop:         6
    readonly property int  barMarginSide:       12
    readonly property int  barInnerPadding:     12
    readonly property int  barContentSpacing:   12
    readonly property int  barRadius:           18
    readonly property int  pillPaddingX:        14
    readonly property int  pillPaddingY:        6
    readonly property int  pillSpacing:         8

    // ===========================================================
    // Pills (clock, status pills, cloud button)
    // ===========================================================
    readonly property int  pillHeight:          26
    readonly property int  pillRadius:          13
    readonly property int  pillIconSize:        14
    readonly property int  pillTextSize:        12
    readonly property int  pillRowSpacing:       6

    // ===========================================================
    // Cloud button (top-left launcher)
    // ===========================================================
    readonly property int  cloudButtonWidth:    34
    readonly property int  cloudButtonHeight:   26
    readonly property int  cloudButtonRadius:   13
    readonly property int  cloudButtonIconSize: 16

    // ===========================================================
    // Clock
    // ===========================================================
    readonly property int    clockTextSize:     13
    readonly property int    clockPaddingX:     24
    readonly property int    clockRefreshMs: 15000
    readonly property string clockFormat:       "ddd  HH:mm"

    // ===========================================================
    // Workspace dots
    // ===========================================================
    readonly property int  workspaceCount:           5
    readonly property int  workspaceDotSize:        12
    readonly property int  workspaceDotActiveWidth: 22
    readonly property int  workspaceDotRadius:       6
    readonly property int  workspaceSpacing:         4
    readonly property int  workspaceAnimMs:        180

    // ===========================================================
    // Control center panel
    // ===========================================================
    readonly property int  centerWidth:          380
    readonly property int  centerMarginTop:       56
    readonly property int  centerMarginSide:      12
    readonly property int  centerMarginBottom:    12
    readonly property int  centerRadius:          18
    readonly property int  centerPadding:         14
    readonly property int  centerSpacing:         12
    readonly property int  centerSheenHeight:     70
    readonly property int  centerTitleSize:       16

    // ===========================================================
    // Quick-action buttons (4×2 grid in the control center)
    // ===========================================================
    readonly property int  quickActionHeight:     52
    readonly property int  quickActionRadius:     14
    readonly property int  quickActionIconSize:   20
    readonly property int  quickActionGridCols:    4
    readonly property int  quickActionGridSpacing: 8

    // ===========================================================
    // DND row (Do Not Disturb)
    // ===========================================================
    readonly property int  dndRowHeight:          36
    readonly property int  dndRowRadius:          12
    readonly property int  dndRowPaddingLeft:     12
    readonly property int  dndRowPaddingRight:     8
    readonly property int  dndTextSize:           13

    // ===========================================================
    // Toggle switch
    // ===========================================================
    readonly property int  toggleWidth:    40
    readonly property int  toggleHeight:   22
    readonly property int  toggleRadius:   11
    readonly property int  toggleKnobSize: 16
    readonly property int  toggleKnobInset: 3
    readonly property int  toggleAnimMs:  150

    // ===========================================================
    // Notification cards
    // ===========================================================
    readonly property int  notifCardRadius:    14
    readonly property int  notifCardPadding:    8
    readonly property int  notifCardSpacing:   10
    readonly property int  notifCardVPadding:  16   // implicitHeight = row.implicitHeight + this
    readonly property int  notifIconSize:      40
    readonly property int  notifIconRadius:    10
    readonly property int  notifIconImagePad:   2
    readonly property int  notifIconFallbackSize: 18

    readonly property int  notifSummarySize:   13
    readonly property int  notifBodySize:      12
    readonly property int  notifAppSize:       10
    readonly property int  notifTimeSize:      10
    readonly property int  notifBodyMaxLines:   3

    readonly property int  notifCloseSize:     18
    readonly property int  notifCloseRadius:    9
    readonly property int  notifCloseFontSize: 14

    // ===========================================================
    // Popup overlay (toasts)
    // ===========================================================
    readonly property int  popupWidth:        360
    readonly property int  popupMarginTop:     56
    readonly property int  popupMarginRight:   16
    readonly property int  popupSpacing:        8
    readonly property int  popupMaxCount:       4
    readonly property int  popupTimeoutMs:   5000   // urgency 2 (critical) ignores this and stays sticky

    // ===========================================================
    // Notification history
    // ===========================================================
    readonly property int  historyMax:           50
    readonly property int  historyCardSpacing:   6
    readonly property int  historyHeaderSize:   12

    // ===========================================================
    // Glossy "Aero" sheens & surface opacities
    // ===========================================================
    readonly property real cardSheenRatio:        0.45
    readonly property real barSheenRatio:         0.50
    readonly property real quickActionSheenRatio: 0.50

    readonly property real sheenAlphaTop:         0.70
    readonly property real sheenAlphaTopStrong:   0.55  // bar variant
    readonly property real sheenAlphaBottom:      0.05
    readonly property real sheenAlphaBottomZero:  0.00

    readonly property real surfaceAlphaIdle:      0.45
    readonly property real surfaceAlphaHover:     0.85
    readonly property real surfaceAlphaPressed:   0.30
    readonly property real cardGradientTopAlpha:  0.78
    readonly property real cardGradientBotAlpha:  0.55

    readonly property real panelGradientTopAlpha: 0.85
    readonly property real panelGradientBotAlpha: 0.78
    readonly property real barGradientTopAlpha:   0.55
    readonly property real barGradientBotAlpha:   0.40

    readonly property real accentTintHover:       0.30
    readonly property real accentTintActive:      0.20
    readonly property real accentTintIcon:        0.25
    readonly property real accentToggleAlpha:     0.85
    readonly property real accentQuickActionHover: 0.40
    readonly property real workspaceOccupiedAlpha: 0.45

    // ===========================================================
    // Misc accents not driven by matugen (semantic flat colors)
    // ===========================================================
    readonly property color criticalBorder:  Qt.rgba(1, 0.4, 0.4, 0.7)
    readonly property color closeHoverBg:    Qt.rgba(1, 0.4, 0.4, 0.85)
    readonly property color powerDangerText: "#c43c3c"
    readonly property color toggleKnobColor: "white"

    // ===========================================================
    // Animations
    // ===========================================================
    readonly property int  hoverAnimMs: 120

    // ===========================================================
    // Battery polling
    // ===========================================================
    readonly property int  batteryPollMs: 30000
}
