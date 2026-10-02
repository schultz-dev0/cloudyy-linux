import QtQuick

// Panel material — resin fill, top gloss, 1px rim, optional grain.
// Every floating shell panel uses this (VISUAL-LANGUAGE.md §3). Square on
// purpose: no radius property. Grain sits under content: children declared
// by the user are created after these, so they draw on top.
Rectangle {
    id: root

    property bool grain: false   // rule 5: only panels you stay in

    color: Theme.resin(Theme.resinFillAlpha)
    border.width: 1
    border.color: Theme.panelRim
    clip: true

    // Gloss — light catching the material's upper edge.
    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: parent.height * 0.4
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.resinGloss }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    GrainOverlay {
        visible: root.grain
        z: 0   // GrainOverlay defaults to z 1000 (last-on-top); here it's material
    }
}
