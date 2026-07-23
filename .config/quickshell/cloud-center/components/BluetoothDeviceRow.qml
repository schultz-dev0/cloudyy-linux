import QtQuick
import ".."
import "BluetoothState.js" as BluetoothState

SelectableRow {
    id: root

    required property var device

    title: String((device && (device.display_name || device.name))
                  || (device && device.address) || "Device")
    subtitle: BluetoothState.deviceSubtitle(device)
    leadingGlyph: "󰂯"
    leadingColor: device && device.connected ? Theme.accent : Theme.textMuted
    showDivider: true

    Text {
        visible: Boolean(root.device && root.device.connected)
        text: "✓"
        color: Theme.accent
        renderType: Text.NativeRendering
        font {
            family: "JetBrainsMono Nerd Font"
            pixelSize: 12
            hintingPreference: Font.PreferVerticalHinting
        }
    }
}
