pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../.."

Item {
    id: root

    property string activityId: ""

    readonly property int contentWidth: 240

    implicitWidth:  contentWidth
    implicitHeight: headerHeight + 6 + (optionHeight * 3) + optionSpacing * 2

    readonly property int headerHeight: 22
    readonly property int optionHeight: 36
    readonly property int optionSpacing: 4

    readonly property color _btnFill: Qt.rgba(
        Theme.surface_container_high.r,
        Theme.surface_container_high.g,
        Theme.surface_container_high.b, 0.55)
    readonly property color _btnFillHover: Qt.rgba(
        Theme.surface_container_high.r,
        Theme.surface_container_high.g,
        Theme.surface_container_high.b, 0.82)

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 6

            Text {
                text:           "󰕧"
                color:          Theme.on_surface_variant
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Text {
                text:               "RECORD"
                color:              Theme.on_surface_variant
                font.family:        "JetBrainsMono Nerd Font"
                font.pixelSize:     9
                font.letterSpacing: 0.8
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
                    color:          Theme.on_surface_variant
                    font.family:    "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
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
            label:      "Area (draw region)"
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
                text:           icon
                color:          Theme.on_surface
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 14
            }

            Text {
                Layout.fillWidth: true
                text:           label
                color:          Theme.on_surface
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 11
            }

            Text {
                text:           "󰅀"
                color:          Theme.on_surface_variant
                font.family:    "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                opacity:        0.7
            }
        }

        MouseArea {
            id: optArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            onClicked: DynamicIslandService.beginRecording(selection, activityId)
        }
    }
}
