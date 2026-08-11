pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string activityId: ""

    readonly property int contentWidth: Theme.islandPreviewContentWidth
    readonly property int contentPad: 2
    readonly property int headerHeight: 22
    readonly property int optionHeight: 34
    readonly property int layoutSpacing: 5

    implicitWidth:  contentWidth
    implicitHeight: contentPad * 2
                    + headerHeight
                    + layoutSpacing * 3
                    + optionHeight * 3

    readonly property color _btnFill: Qt.rgba(1, 1, 1, 0.1)
    readonly property color _btnFillHover: Qt.rgba(1, 1, 1, 0.18)

    anchors.fill: parent

    ColumnLayout {
        anchors {
            fill:   parent
            margins: root.contentPad
        }
        spacing: root.layoutSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 6

            Text {
                text:           "󰕧"
                color:          "#ffffff"
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                renderType: Text.NativeRendering
            }

            Text {
                text:               "RECORD"
                color:              Qt.rgba(1, 1, 1, 0.55)
                font.family:        "JetBrainsMono Nerd Font"
                font.pixelSize:     9
                font.letterSpacing: 0.8
                renderType: Text.NativeRendering
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth:  22
                Layout.preferredHeight: 22
                radius: 6
                color:  closeArea.containsMouse ? root._btnFillHover : root._btnFill

                Text {
                    anchors.centerIn: parent
                    text:           "󰅖"
                    color:          "#ffffff"
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    renderType: Text.NativeRendering
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: DynamicIslandService.dismissRecordPicker(root.activityId)
                }
            }
        }

        RecordOption {
            label:      "Area"
            icon:       "󰆞"
            selection:  "region"
            activityId: root.activityId
        }

        RecordOption {
            label:      "Active monitor"
            icon:       "󰍹"
            selection:  "monitor:active"
            activityId: root.activityId
        }

        RecordOption {
            label:      "Choose monitor"
            icon:       "󰍹"
            selection:  "monitor"
            activityId: root.activityId
        }
    }

    component RecordOption: Rectangle {
        id: opt
        required property string label
        required property string icon
        required property string selection
        required property string activityId

        Layout.fillWidth: true
        Layout.preferredHeight: root.optionHeight
        radius: 10
        color:  optArea.containsMouse ? root._btnFillHover : root._btnFill

        RowLayout {
            anchors {
                fill:           parent
                leftMargin:     10
                rightMargin:    10
            }
            spacing: 8

            Text {
                text:           opt.icon
                color:          "#ffffff"
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                renderType: Text.NativeRendering
            }

            Text {
                Layout.fillWidth: true
                text:           opt.label
                color:          "#ffffff"
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                renderType: Text.NativeRendering
            }

            Text {
                text:           "󰅀"
                color:          Qt.rgba(1, 1, 1, 0.7)
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                renderType: Text.NativeRendering
                opacity:        0.7
            }
        }

        MouseArea {
            id: optArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked: DynamicIslandService.beginRecording(opt.selection, opt.activityId)
        }
    }
}
