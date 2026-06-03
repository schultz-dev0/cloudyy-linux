pragma ComponentBehavior: Bound

// modules/controlcenter/tiles/NightLightTile.qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../../.."

BaseTile {
    id: root

    property var sliderController: null

    icon:       "󰖙"
    label:      "Night Light"
    statusText: (sliderController && sliderController.nightLightActive)
        ? ("On · " + sliderController.nightLightTemp + "K")
        : "Off"
    active: sliderController ? sliderController.nightLightActive : false

    onClicked:      if (sliderController) sliderController.toggleNightLight()
    onRightClicked: if (sliderController) sliderController.showNightLight()
}
