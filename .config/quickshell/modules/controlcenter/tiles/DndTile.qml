// modules/controlcenter/tiles/DndTile.qml
import QtQuick

BaseTile {
    id: root

    property bool dnd: false
    signal dndToggle()

    icon:       "󰂛"
    label:      "DND"
    active:     dnd

    onClicked: root.dndToggle()
}
