import QtQuick
import ".."
import "WifiState.js" as WifiState

Item {
    id: panel

    required property var network
    property bool busy: false

    signal connectRequested(var network)
    signal disconnectRequested(var network)
    signal forgetRequested(var network)

    implicitHeight: content.implicitHeight
    height: implicitHeight

    Column {
        id: content
        width: parent.width
        spacing: 0

        Item {
            visible: panel.network === null
            width: parent.width
            height: 120
            Text {
                anchors {
                    fill: parent
                    margins: 16
                }
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                text: "Select a network"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 11
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
        }

        Column {
            visible: panel.network !== null
            width: parent.width
            spacing: 0

            Item {
                width: parent.width
                height: 64
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    width: 28
                    text: WifiState.signalBars(panel.network ? panel.network.signal : 0)
                    color: Theme.accent
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 22
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
                Column {
                    anchors {
                        left: parent.left
                        leftMargin: 46
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 2
                    Text {
                        width: parent.width
                        text: String(panel.network && panel.network.ssid ? panel.network.ssid : "")
                        elide: Text.ElideRight
                        color: Theme.textPrimary
                        renderType: Text.NativeRendering
                        font {
                            family: "JetBrainsMono Nerd Font"
                            pixelSize: 14
                            weight: Font.Medium
                            hintingPreference: Font.PreferVerticalHinting
                        }
                    }
                    Text {
                        width: parent.width
                        text: WifiState.detailSummary(panel.network)
                        elide: Text.ElideRight
                        color: Theme.textMuted
                        renderType: Text.NativeRendering
                        font {
                            family: "JetBrainsMono Nerd Font"
                            pixelSize: 10
                            hintingPreference: Font.PreferVerticalHinting
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width - 20
                x: 10
                height: 1
                color: Theme.glass(Theme.outline_variant, 0.35)
            }

            Item {
                width: parent.width
                height: 56
                Row {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    CloudButton {
                        visible: panel.network && panel.network.connected !== true
                        text: "Connect"
                        primary: true
                        compact: true
                        enabled: !panel.busy
                        onClicked: panel.connectRequested(panel.network)
                    }
                    CloudButton {
                        visible: panel.network && panel.network.connected === true
                        text: "Disconnect"
                        danger: true
                        compact: true
                        enabled: !panel.busy
                        onClicked: panel.disconnectRequested(panel.network)
                    }
                    CloudButton {
                        visible: panel.network && panel.network.saved === true
                            && panel.network.connected !== true
                        text: "Forget"
                        subtle: true
                        compact: true
                        enabled: !panel.busy
                        onClicked: panel.forgetRequested(panel.network)
                    }
                }
            }
        }
    }
}
