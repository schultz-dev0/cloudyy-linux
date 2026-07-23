import QtQuick
import QtQuick.Controls
import "../services" as S
import ".."

RowBase {
    id: sliderRow
    readonly property real sliderStep: Number(item.step ?? 1)
    // RowBase's slot is a Row positioner, which always top-aligns children and
    // (being a positioner) won't accept anchors on them either — so the value
    // Text and the taller Slider need their own Item wrapper to share a center
    // line instead of both being direct children of slot.
    Item {
        width: valueText.implicitWidth + 8 + slider.width
        height: slider.height
        Text {
            id: valueText
            anchors.verticalCenter: parent.verticalCenter
            text: slider.value.toFixed(sliderRow.sliderStep < 1 ? 2 : 0)
            color: Theme.textMuted; font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
        }
        Slider {
            id: slider
            anchors { left: valueText.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: 150
            height: 24
            from: Number(sliderRow.item.min ?? 0)
            to: Number(sliderRow.item.max ?? 100)
            stepSize: sliderRow.sliderStep
            value: Number(sliderRow.item.value ?? from)
            onMoved: commitTimer.restart()
            background: Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 4; radius: 2
                color: Theme.outline_variant
                Rectangle { width: slider.visualPosition * parent.width; height: parent.height
                            radius: 2; color: Theme.primary }
            }
            handle: Rectangle {
                x: slider.visualPosition * (slider.width - width)
                anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7
                color: Theme.surface_container_lowest
                border { width: 1; color: Theme.outline }
            }
        }
    }
    Timer {
        id: commitTimer
        interval: 150
        onTriggered: S.Backend.request("run_action",
            { item: sliderRow.item.id, value: slider.value }, null)
    }
}
