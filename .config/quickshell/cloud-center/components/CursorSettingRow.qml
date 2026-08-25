import QtQuick
import QtQuick.Controls
import ".."

RowBase {
    id: settingRow

    required property var setting
    required property var currentValue
    property var monitors: []
    property bool controlEnabled: true
    signal valueEdited(string key, var value)

    item: ({
        icon: glyphFor(setting.key),
        title: setting.title,
        description: setting.description,
    })
    enabled: controlEnabled
    opacity: controlEnabled ? 1 : 0.42

    function glyphFor(key) {
        const glyphs = {
            enable_hyprcursor: "󰍽", no_warps: "󰆷", persistent_warps: "󰁪",
            warp_on_change_workspace: "󰒭", warp_on_toggle_special: "󰘸",
            default_monitor: "󰍹", warp_back_after_non_mouse_input: "󰑐",
            inactive_timeout: "󰔛", hide_on_key_press: "󰌌", hide_on_touch: "󰓀",
            hide_on_tablet: "󰓶", invisible: "󰈈", zoom_factor: "󰍉",
            zoom_rigid: "󰇀", zoom_detached_camera: "󰄀", zoom_disable_aa: "󰹑",
            sync_gsettings_theme: "󰒓", no_hardware_cursors: "󰍽",
            use_cpu_buffer: "󰘚", no_break_fs_vrr: "󰾆", min_refresh_rate: "󰓅",
            hotspot_padding: "󰆼",
        };
        return glyphs[key] ?? "󰒓";
    }

    Loader {
        sourceComponent: setting.key === "default_monitor" ? monitorControl
            : setting.type === "bool" ? boolControl
            : setting.type === "enum" ? enumControl
            : setting.type === "int" || setting.type === "float" ? numberControl
            : null
    }

    Component {
        id: boolControl
        CloudSwitch {
            checked: Boolean(settingRow.currentValue)
            onToggled: checked => settingRow.valueEdited(settingRow.setting.key, checked)
        }
    }

    Component {
        id: enumControl
        CloudSelect {
            width: 176
            compact: true
            options: settingRow.setting.labels ?? []
            currentIndex: Math.max(0, (settingRow.setting.values ?? []).indexOf(Number(settingRow.currentValue)))
            onActivated: index => settingRow.valueEdited(
                settingRow.setting.key, settingRow.setting.values[index])
        }
    }

    Component {
        id: monitorControl
        CloudSelect {
            width: 176
            compact: true
            options: ["System default"].concat(settingRow.monitors)
            currentIndex: settingRow.currentValue === ""
                ? 0 : Math.max(0, settingRow.monitors.indexOf(String(settingRow.currentValue)) + 1)
            onActivated: index => settingRow.valueEdited(
                settingRow.setting.key, index === 0 ? "" : settingRow.monitors[index - 1])
        }
    }

    Component {
        id: numberControl
        Item {
            width: 252
            height: 32

            Slider {
                id: numberSlider
                anchors { left: parent.left; right: numberField.left; rightMargin: 10
                          verticalCenter: parent.verticalCenter }
                height: 28
                from: Number(settingRow.setting.minimum ?? 0)
                to: Number(settingRow.setting.maximum ?? 100)
                stepSize: Number(settingRow.setting.step ?? 1)
                value: Number(settingRow.currentValue)
                onMoved: {
                    numberCommit.pendingValue = value;
                    numberCommit.restart();
                }
                background: Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 4; radius: 2
                    color: Theme.border
                    Rectangle {
                        width: numberSlider.visualPosition * parent.width
                        height: parent.height; radius: 2; color: Theme.accent
                    }
                }
                handle: Rectangle {
                    x: numberSlider.visualPosition * (numberSlider.width - width)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14; height: 14; radius: 7
                    color: Theme.background
                    border { width: 1; color: Theme.border }
                }
            }

            Rectangle {
                id: numberField
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 62; height: 30; radius: 8
                color: Theme.surfaceRaised
                border { width: 1; color: exactInput.activeFocus ? Theme.accent : Theme.border }
                TextInput {
                    id: exactInput
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    text: Number(settingRow.currentValue).toFixed(settingRow.setting.type === "int" ? 0 : 1)
                    color: Theme.text
                    selectByMouse: true
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    renderType: TextInput.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           hintingPreference: Font.PreferVerticalHinting }
                    validator: DoubleValidator {
                        bottom: Number(settingRow.setting.minimum ?? 0)
                        top: Number(settingRow.setting.maximum ?? 100)
                        decimals: settingRow.setting.type === "int" ? 0 : 2
                    }
                    onAccepted: {
                        const parsed = settingRow.setting.type === "int"
                            ? parseInt(text, 10) : parseFloat(text);
                        if (!isNaN(parsed)) settingRow.valueEdited(settingRow.setting.key, parsed);
                    }
                    onEditingFinished: accepted()
                }
            }

            Timer {
                id: numberCommit
                property real pendingValue: 0
                interval: 110
                onTriggered: settingRow.valueEdited(
                    settingRow.setting.key,
                    settingRow.setting.type === "int" ? Math.round(pendingValue) : pendingValue)
            }
        }
    }
}
