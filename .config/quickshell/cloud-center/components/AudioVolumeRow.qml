import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: row

    required property string label
    required property int value
    required property bool muted
    property bool busy: false
    property int generation: 0
    property string targetId: ""
    property string targetKind: ""
    property string editedTargetId: ""
    property string editedTargetKind: ""
    property int editedValue: 0
    signal volumeEdited(int value, int generation)
    signal muteEdited(bool muted)

    implicitHeight: 54
    height: implicitHeight

    Timer {
        id: commitTimer
        interval: 120
        onTriggered: {
            row.generation += 1;
            row.volumeEdited(row.editedValue, row.generation);
        }
    }

    function captureVolumeEdit() {
        editedTargetId = targetId;
        editedTargetKind = targetKind;
        editedValue = Math.round(volumeSlider.value);
        commitTimer.restart();
    }

    Text {
        id: labelText
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        width: 150
        text: row.label
        elide: Text.ElideRight
        color: Theme.text
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
               hintingPreference: Font.PreferVerticalHinting }
    }

    Slider {
        id: volumeSlider
        anchors { left: labelText.right; leftMargin: 12; right: percentText.left; rightMargin: 10
                  verticalCenter: parent.verticalCenter }
        height: 28
        from: 0
        to: 150
        stepSize: 1
        value: Math.max(from, Math.min(to, Number(row.value)))
        enabled: !row.busy
        onMoved: row.captureVolumeEdit()
        background: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4
            radius: 2
            color: Theme.border
            Rectangle {
                width: volumeSlider.visualPosition * parent.width
                height: parent.height
                radius: 2
                color: Theme.accent
            }
        }
        handle: Rectangle {
            x: volumeSlider.visualPosition * (volumeSlider.width - width)
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: Theme.background
            border { width: 1; color: Theme.border }
        }
    }

    Text {
        id: percentText
        anchors { right: muteSwitch.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: 38
        horizontalAlignment: Text.AlignRight
        text: Math.round(volumeSlider.value) + "%"
        color: row.busy ? Theme.textMuted : Theme.text
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
               hintingPreference: Font.PreferVerticalHinting }
    }

    CloudSwitch {
        id: muteSwitch
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        checked: row.muted
        enabled: !row.busy
        onToggled: checked => row.muteEdited(checked)
    }
}
