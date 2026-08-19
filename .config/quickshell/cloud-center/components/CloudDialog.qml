import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import ".."

Popup {
    id: dialog

    property string heading: ""
    property string supportingText: ""
    property string primaryText: ""
    property string secondaryText: "Cancel"
    property bool primaryEnabled: true
    property bool showFooter: true
    property bool showClose: true
    default property alias body: bodyHost.data

    signal primaryClicked()
    signal secondaryClicked()

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    dim: true
    focus: true
    padding: 0
    closePolicy: Popup.NoAutoClose
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 110 } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 90 } }

    Overlay.modal: Rectangle {
        color: Theme.glass(Theme.scrim, Theme.isLightTheme ? 0.22 : 0.38)
    }

    background: Rectangle {
        id: dialogShell
        radius: 0
        color: Theme.resin(Theme.resinFillAlpha)
        border { width: 1; color: Theme.resinBorder }
        clip: true

        // Gloss — light catching the material's upper edge.
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: parent.height * 0.3
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.resinGloss }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Inner glow — a hint of structure beneath the material. Actually
        // blurred, not just low-opacity, so it reads as soft light rather
        // than a defined shape. Corner-anchored with the center pushed past
        // the edge (clipped by dialogShell) instead of a percentage-of-
        // height position, so it never lands under the dialog's body text.
        Rectangle {
            width: parent.width * 0.28
            height: width
            radius: width / 2
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: -width * 0.5
                bottomMargin: -height * 0.5
            }
            color: Theme.resinGlow
            opacity: 0.5
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 80 }
        }
    }

    contentItem: Column {
        spacing: 0

        Item {
            width: parent.width
            height: dialog.supportingText === "" ? 60 : 72

            Column {
                anchors { left: parent.left; right: closeButton.left; leftMargin: 20; rightMargin: 12
                          verticalCenter: parent.verticalCenter }
                spacing: 3
                Text {
                    width: parent.width
                    text: dialog.heading
                    color: Theme.textPrimary
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 16; weight: Font.Bold
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Text {
                    visible: dialog.supportingText !== ""
                    width: parent.width
                    text: dialog.supportingText
                    color: Theme.textMuted
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }

            Rectangle {
                id: closeButton
                visible: dialog.showClose
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                width: 28; height: 28; radius: 2
                color: closeHover.hovered ? Theme.glass(Theme.primary, 0.12)
                    : Theme.surface_container_high
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 16
                           hintingPreference: Font.PreferVerticalHinting }
                }
                HoverHandler { id: closeHover }
                TapHandler { onTapped: { dialog.secondaryClicked(); dialog.close(); } }
            }
        }

        Rectangle {
            width: parent.width; height: 1
            color: Theme.hairline
        }

        Item {
            id: bodyHost
            width: parent.width
            height: parent.height - (dialog.supportingText === "" ? 61 : 73)
                - (dialog.showFooter ? 59 : 0)
        }

        Rectangle {
            visible: dialog.showFooter
            width: parent.width; height: 59
            color: Theme.surface_container_low
            Rectangle {
                anchors.top: parent.top
                width: parent.width; height: 1
                color: Theme.hairline
            }
            Row {
                anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                spacing: 8
                CloudButton {
                    text: dialog.secondaryText
                    onClicked: { dialog.secondaryClicked(); dialog.close(); }
                }
                CloudButton {
                    visible: dialog.primaryText !== ""
                    text: dialog.primaryText
                    primary: true
                    enabled: dialog.primaryEnabled
                    onClicked: dialog.primaryClicked()
                }
            }
        }
    }
}
