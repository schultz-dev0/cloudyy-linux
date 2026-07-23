import QtQuick
import ".."
import "WifiState.js" as WifiState

SelectableRow {
    id: row

    required property var network

    title: String(network && network.ssid ? network.ssid : "Unknown network")
    subtitle: WifiState.networkSubtitle(network)
    leadingGlyph: WifiState.signalBars(network ? network.signal : 0)
    leadingColor: Theme.accent
    showDivider: true
    dividerInset: 46
    opacity: busy ? 0.72 : 1

    Text {
        visible: row.network && row.network.connected === true
        text: "󰄬"
        color: Theme.accent
        renderType: Text.NativeRendering
        font {
            family: "JetBrainsMono Nerd Font"
            pixelSize: 13
            hintingPreference: Font.PreferVerticalHinting
        }
    }
}
