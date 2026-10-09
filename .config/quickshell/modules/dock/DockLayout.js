.pragma library
// modules/dock/DockLayout.js — pure sizing and naming rules for the dock rail.
// Kept free of QML so test_dock_layout.js can run it under node. The dock font
// is monospace, so a name's width is chars × charW (one glyph advance): layout
// is arithmetic, no text measuring, no width-depends-on-width binding loop.

var ICON_H = 18, ICON_V = 20;   // icon size on top/bottom vs side edges
var PAD_H = 13, PAD_V = 12;     // segment side padding
var GAP_H = 8, GAP_V = 10;      // icon-name and name-LED gaps
var ROW_V = 34;                 // side-edge row height
var STRIP = 32;                 // top/bottom rail thickness, rim included
var RIM = 2;                    // the panel's 1px rim on both sides
var LED = 5, LED_GAP = 2, LED_MAX = 3;
var NAME_CAP_OVERFLOW = 6, NAME_CAP_SIDE = 10;

// Lower-case, cut to `cap` characters INCLUDING the ellipsis. cap <= 0: no cut.
function shortName(name, cap) {
    var n = ("" + (name || "")).toLowerCase();
    if (cap <= 0 || n.length <= cap)
        return n;
    return n.slice(0, cap - 1) + "…";
}

// One LED per window, at most three; none for a closed app.
function ledCount(windowCount, isRunning) {
    if (!isRunning)
        return 0;
    return Math.min(Math.max(windowCount | 0, 1), LED_MAX);
}

function ledsWidth(n) {
    return n > 0 ? n * LED + (n - 1) * LED_GAP : 0;
}

// Top/bottom segment: padding, icon, gap, name, [gap, LEDs], and 1px for the
// leading divider (the first segment reserves it without drawing it).
function segmentWidth(shown, leds, charW) {
    return 2 * PAD_H + ICON_H + GAP_H + shown.length * charW
        + (leds > 0 ? GAP_H + ledsWidth(leds) : 0) + 1;
}

// Whole rail length along the edge, rim included.
function railLength(entries, cap, charW, vertical) {
    if (vertical)
        return RIM + entries.length * ROW_V;
    var total = RIM;
    for (var i = 0; i < entries.length; i++)
        total += segmentWidth(shortName(entries[i].name, cap), entries[i].leds, charW);
    return total;
}

// Fixed side-edge column width: the widest row (10-char name, 3 LEDs) plus rim.
function sideThickness(charW) {
    return 2 * PAD_V + ICON_V + GAP_V + NAME_CAP_SIDE * charW + GAP_V + ledsWidth(LED_MAX) + RIM;
}

// 0 while the full-name rail fits `available`, else the overflow cap. An unknown
// width (0 or negative, e.g. before the screen resolves) never truncates.
function pickNameCap(entries, available, charW) {
    if (available <= 0)
        return 0;
    return railLength(entries, 0, charW, false) <= available ? 0 : NAME_CAP_OVERFLOW;
}
