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
    onRightClicked: tempPopup.open()

    Popup {
        id: tempPopup
        parent:      root
        x:           root.width - width
        y:           -(implicitHeight + 6)
        width:       188
        padding:     12
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape

        background: Rectangle {
            radius:       12
            color:        Qt.rgba(Theme.surface_container_high.r,
                                  Theme.surface_container_high.g,
                                  Theme.surface_container_high.b, 0.97)
            border.color: Qt.rgba(Theme.tertiary.r, Theme.tertiary.g, Theme.tertiary.b, 0.4)
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text:           "󰖙  Night Light"
                    color:          Theme.tertiary
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    font.weight:    Font.Bold
                    Layout.fillWidth: true
                }

                Text {
                    text:           (root.sliderController
                        ? root.sliderController.nightLightTemp : 3500) + "K"
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                }
            }

            Slider {
                id:             tempSlider
                Layout.fillWidth: true
                from:           1000
                to:             6500
                stepSize:       100
                value:          root.sliderController
                    ? root.sliderController.nightLightTemp : 3500
                live:           true

                onMoved: if (root.sliderController)
                    root.sliderController.setNightLightTemp(value)

                background: Rectangle {
                    x:      tempSlider.leftPadding
                    y:      tempSlider.topPadding + tempSlider.availableHeight / 2 - height / 2
                    width:  tempSlider.availableWidth
                    height: 6
                    radius: 999
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0;  color: "#ff8c42" }
                        GradientStop { position: 0.45; color: "#ffe0b3" }
                        GradientStop { position: 1.0;  color: "#afc9e7" }
                    }
                }

                handle: Rectangle {
                    x:      tempSlider.leftPadding
                            + tempSlider.visualPosition
                            * (tempSlider.availableWidth - width)
                    y:      tempSlider.topPadding
                            + tempSlider.availableHeight / 2 - height / 2
                    width:  14
                    height: 14
                    radius: 7
                    color:  "#ffffff"
                    border.color: Qt.rgba(0, 0, 0, 0.2)
                    border.width: 1
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "warm"; color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 7
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: "cool"; color: Theme.on_surface_variant
                    font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 7
                }
            }
        }
    }
}
