// modules/controlcenter/TileGrid.qml
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    default property alias tiles: grid.data

    implicitHeight: grid.implicitHeight

    GridLayout {
        id: grid
        anchors { left: parent.left; right: parent.right }
        columns:       2
        rowSpacing:    6
        columnSpacing: 6
    }
}
