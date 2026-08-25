import QtQuick
import "RecordingState.js" as RecordingState
import ".."

// Mic + Desktop are independent tick boxes (not a single toggle) — ticking
// both asks recording_core to build a PipeWire combine-mix source. See
// docs/superpowers/specs/2026-08-10-recording-page-design.md.
Column {
    id: picker
    required property var settings
    required property var audioInputs
    signal settingChanged(string key, var value)

    spacing: 10

    readonly property bool micEnabled: settings.rec_audio_mic === true
    readonly property bool desktopEnabled: settings.rec_audio_desktop === true

    component AudioBox: Rectangle {
        id: box
        required property string glyph
        required property string title
        required property bool boxEnabled
        required property var devices
        required property string selectedDevice
        property string deviceSettingKey: ""
        property string enabledSettingKey: ""

        width: parent ? parent.width : 0
        height: content.implicitHeight + 20
        radius: 0
        color: Theme.surfaceRaised
        border { width: 1; color: Theme.hairline }

        Column {
            id: content
            x: 12
            y: 10
            width: box.width - 24
            spacing: 10

            Item {
                width: parent.width
                height: 30
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Text {
                        text: box.glyph
                        color: Theme.accent
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 14
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                    Text {
                        text: box.title
                        color: Theme.text
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 12; weight: Font.Medium
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                }
                CloudSwitch {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    checked: box.boxEnabled
                    onToggled: checked => picker.settingChanged(box.enabledSettingKey, checked)
                }
            }

            CloudSelect {
                width: parent.width
                compact: true
                visible: box.boxEnabled
                options: RecordingState.deviceOptions(box.devices)
                textRole: "description"
                currentIndex: RecordingState.deviceIndex(box.devices, box.selectedDevice)
                onActivated: index => {
                    const chosen = RecordingState.deviceOptions(box.devices)[index];
                    picker.settingChanged(box.deviceSettingKey, chosen ? chosen.name : "");
                }
            }
        }
    }

    AudioBox {
        glyph: "\u{f036c}"
        title: "Microphone"
        boxEnabled: picker.micEnabled
        devices: picker.audioInputs.mics || []
        selectedDevice: picker.settings.rec_mic_device || ""
        enabledSettingKey: "rec_audio_mic"
        deviceSettingKey: "rec_mic_device"
    }

    AudioBox {
        glyph: "\u{f0379}"
        title: "Desktop Audio"
        boxEnabled: picker.desktopEnabled
        devices: picker.audioInputs.desktops || []
        selectedDevice: picker.settings.rec_desktop_device || ""
        enabledSettingKey: "rec_audio_desktop"
        deviceSettingKey: "rec_desktop_device"
    }
}
