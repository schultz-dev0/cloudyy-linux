import QtQuick
import ".."

FocusScope {
    id: control

    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 40
    implicitHeight: 22
    activeFocusOnTab: enabled
    opacity: enabled ? 1 : 0.38

    function flip() {
        if (!enabled) return;
        checked = !checked;
        toggled(checked);
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        clip: true
        color: control.checked ? Theme.primary : Theme.surface_container_high
        border {
            width: control.activeFocus ? 1 : 0
            color: control.checked ? Theme.on_primary_container : Theme.primary
        }
        Behavior on color { ColorAnimation { duration: 120 } }

        // Dots material — faint texture on the track.
        DotTexture {
            anchors.fill: parent
            tint: control.checked ? Theme.on_primary_container : Theme.accent
            dotAlpha: 0.16
            cell: 5
            dotRadius: 0.7
        }

        Rectangle {
            width: 16; height: 16; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            x: control.checked ? parent.width - width - 3 : 3
            color: control.checked ? Theme.on_primary : Theme.surface_container_lowest
            border { width: 1; color: Theme.hairline }
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        HoverHandler { id: switchHover }
        TapHandler { onTapped: control.flip() }
    }

    Keys.onSpacePressed: flip()
    Keys.onReturnPressed: flip()
}
