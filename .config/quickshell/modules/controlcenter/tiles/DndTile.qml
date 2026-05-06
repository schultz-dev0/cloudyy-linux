// modules/controlcenter/tiles/DndTile.qml
import QtQuick

BaseTile {
    id: root

    property bool dnd: false
    signal dndToggle()

    icon:       "󰂛"
    label:      "Do Not Disturb"
    statusText: dnd ? "On" : "Off"
    active:     dnd

    onClicked: root.dndToggle()
}
