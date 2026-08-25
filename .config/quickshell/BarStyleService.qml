pragma Singleton

import QtQuick

// Two coordinated bar states — solid (Omarchy-style) and transparent
// (floating). Legibility comes from Theme.text in both states now,
// not a vignette — see Bar.qml's barFg* tokens. Single source of truth so
// nothing can drift out of sync. Double-click the bar to toggle.
QtObject {
    id: root

    property bool solid: true

    readonly property int solidBarHeight: 28
    readonly property int solidTopGap: 0
    readonly property real solidBgOpacity: 0.96

    readonly property int transparentBarHeight: 10
    readonly property int transparentTopGap: 5
    readonly property real transparentBgOpacity: 0.0

    readonly property int barHeight: root.solid ? root.solidBarHeight : root.transparentBarHeight
    readonly property int topGap: root.solid ? root.solidTopGap : root.transparentTopGap
    readonly property real bgOpacity: root.solid ? root.solidBgOpacity : root.transparentBgOpacity

    function toggle() {
        root.solid = !root.solid;
    }
}
