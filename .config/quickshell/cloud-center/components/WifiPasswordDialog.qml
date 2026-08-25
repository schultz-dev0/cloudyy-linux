import QtQuick
import ".."

CloudDialog {
    id: dialog

    property string ssid: ""
    property bool enterprise: false
    property string identity: ""
    property string password: ""
    property bool showPassword: false

    signal submitted(string ssid, string identity, string password)

    width: 440
    height: enterprise ? 286 : 236
    heading: ssid === "" ? "Connect to Wi-Fi" : ("Connect to " + ssid)
    supportingText: enterprise
        ? "This network needs a username and password (school or work Wi-Fi)"
        : "Enter the Wi-Fi password"
    primaryText: "Connect"
    secondaryText: "Cancel"
    primaryEnabled: enterprise
        ? (identity.trim() !== "" && password !== "")
        : (password !== "")

    onPrimaryClicked: {
        dialog.submitted(dialog.ssid, dialog.identity.trim(), dialog.password);
        dialog.close();
    }
    onSecondaryClicked: dialog.close()
    onOpened: {
        if (enterprise)
            identityField.forceActiveFocus();
        else
            passwordField.forceActiveFocus();
    }
    onClosed: {
        password = "";
        if (!enterprise)
            identity = "";
        showPassword = false;
    }

    Column {
        anchors { fill: parent; margins: 20 }
        spacing: 12

        Column {
            visible: dialog.enterprise
            width: parent.width
            spacing: 6
            Text {
                text: "Username"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
            CloudTextField {
                id: identityField
                width: parent.width
                text: dialog.identity
                placeholderText: "user@university.edu"
                onTextEdited: value => dialog.identity = value
                onAccepted: passwordField.forceActiveFocus()
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Text {
                text: "Password"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Item {
                width: parent.width
                height: 36
                Rectangle {
                    anchors.fill: parent
                    radius: 2
                    color: passwordField.activeFocus
                        ? Theme.background
                        : Theme.surface
                    border {
                        width: passwordField.activeFocus ? 1.5 : 1
                        color: passwordField.activeFocus ? Theme.accent : Theme.hairline
                    }
                    TextInput {
                        id: passwordField
                        anchors {
                            left: parent.left; right: revealButton.left
                            top: parent.top; bottom: parent.bottom
                            leftMargin: 11; rightMargin: 8
                        }
                        text: dialog.password
                        echoMode: dialog.showPassword ? TextInput.Normal : TextInput.Password
                        selectByMouse: true
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text
                        renderType: TextInput.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                               hintingPreference: Font.PreferVerticalHinting }
                        onTextEdited: dialog.password = text
                        onAccepted: {
                            if (dialog.primaryEnabled)
                                dialog.primaryClicked();
                        }
                        Text {
                            visible: passwordField.text === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Password"
                            color: Theme.textMuted
                            opacity: 0.72
                            renderType: Text.NativeRendering
                            font: passwordField.font
                        }
                    }
                    Rectangle {
                        id: revealButton
                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                        width: 28; height: 28; radius: 2
                        color: revealHover.hovered
                            ? Theme.glass(Theme.accent, 0.12) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: dialog.showPassword ? "󰈉" : "󰈈"
                            color: Theme.textMuted
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                                   hintingPreference: Font.PreferVerticalHinting }
                        }
                        HoverHandler { id: revealHover }
                        TapHandler { onTapped: dialog.showPassword = !dialog.showPassword }
                    }
                }
            }
        }
    }

    function openFor(network, prefillIdentity) {
        if (!network) return;
        ssid = String(network.ssid || "");
        enterprise = network.is_enterprise === true;
        identity = String(prefillIdentity || "");
        password = "";
        showPassword = false;
        open();
    }
}
