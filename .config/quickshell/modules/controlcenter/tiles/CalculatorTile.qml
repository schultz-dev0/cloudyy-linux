pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/CalculatorTile.qml
import QtQuick
import "../../.."

BaseTile {
    id: root

    property bool open: false

    icon:       "󰃬"
    label:      "Calculator"
    statusText: open ? "Open" : "Closed"
    active:     open

    onClicked: root.clicked()
}
