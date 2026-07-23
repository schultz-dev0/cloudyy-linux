import QtQuick
import QtQuick.Controls
import "../services" as S
import ".."

RowBase {
    id: selectRow
    readonly property var options: item.options ?? []
    ComboBox {
        id: combo
        width: 160
        model: selectRow.options
        currentIndex: Math.max(0, selectRow.options.indexOf(selectRow.item.value))
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
        onActivated: index => S.Backend.request("run_action",
            { item: selectRow.item.id, value: model[index] }, null)

        contentItem: Text {
            leftPadding: 8
            text: combo.displayText
            color: Theme.textPrimary
            verticalAlignment: Text.AlignVCenter
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
        }
        background: Rectangle {
            implicitWidth: 160; implicitHeight: 26; radius: 7
            color: Theme.surface_container
            border { width: 1; color: Theme.outline_variant }
        }
        delegate: ItemDelegate {
            width: combo.width
            highlighted: combo.highlightedIndex === index
            contentItem: Text {
                text: modelData
                color: Theme.textPrimary
                verticalAlignment: Text.AlignVCenter
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11 }
            }
            background: Rectangle {
                color: highlighted ? Theme.glass(Theme.primary, 0.14) : "transparent"
            }
        }
        popup: Popup {
            y: combo.height
            width: combo.width
            padding: 4
            // Motion budget: no popup fade — everything but knobs/hovers is instant.
            enter: null
            exit: null
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: combo.popup.visible ? combo.delegateModel : null
                currentIndex: combo.highlightedIndex
            }
            background: Rectangle {
                radius: 8
                color: Theme.surface_container
                border { width: 1; color: Theme.outline_variant }
            }
        }
    }
}
