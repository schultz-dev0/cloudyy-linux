// lock/LockSurface.qml
pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var lockService
    readonly property color mutedText: Qt.lighter(Theme.textMuted, 1.28)
    readonly property string workspaceAnimation: root.lockService.workspaceAnimation
    readonly property bool usesFade: workspaceAnimation === "fade"
        || workspaceAnimation === "slidefade"
        || workspaceAnimation === "slidefadevert"
    readonly property bool usesHorizontalMotion: workspaceAnimation === "slide"
        || workspaceAnimation === "slidefade"
    readonly property bool usesVerticalMotion: workspaceAnimation === "slidevert"
        || workspaceAnimation === "slidefadevert"
    readonly property int transitionDuration: workspaceAnimation === "none" ? 0 : 180
    color: "transparent"

    Image {
        id: wallpaper
        anchors.fill: parent
        source: "file://" + root.lockService.wallpaperPath
        sourceSize.width: Math.ceil(width * 1.15)
        sourceSize.height: Math.ceil(height * 1.15)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
    }

    FastBlur {
        anchors.fill: parent
        source: wallpaper
        radius: 64
        cached: true
    }

    Item {
        id: lockContent
        anchors.fill: parent
        opacity: !root.lockService.secure ? 0
            : root.lockService.unlocking && root.usesFade ? 0 : 1
        transform: Translate {
            id: contentShift
            x: root.usesHorizontalMotion
                ? !root.lockService.secure ? -root.width * 0.045
                : root.lockService.unlocking ? root.width * 0.045 : 0
                : 0
            y: root.usesVerticalMotion
                ? !root.lockService.secure ? -root.height * 0.045
                : root.lockService.unlocking ? root.height * 0.045 : 0
                : 0

            Behavior on x {
                NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
            }
            Behavior on y {
                NumberAnimation { duration: root.transitionDuration; easing.type: Easing.OutCubic }
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: root.usesFade ? root.transitionDuration : 0
                easing.type: Easing.OutCubic
            }
        }

    Column {
        anchors.centerIn: parent
        spacing: 12

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.lockService.now, "HH:mm")
            color: Theme.textPrimary
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: Math.max(38, root.width * 0.052)
                   hintingPreference: Font.PreferVerticalHinting }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.lockService.now, "dddd, d MMMM").toUpperCase()
            color: root.mutedText
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                   hintingPreference: Font.PreferVerticalHinting }
        }
    }

    Column {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Math.max(72, parent.height * 0.14) }
        width: Math.min(440, parent.width - 48)
        spacing: 10
        visible: root.lockService.secure && root.lockService.isPromptScreen(root.screen)

        Text {
            text: root.lockService.user + "@cloudyy"
            color: root.mutedText
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                   hintingPreference: Font.PreferVerticalHinting }
        }

        Rectangle {
            width: parent.width
            height: 40
            radius: 10
            color: passwordInput.activeFocus
                ? Theme.glass(Theme.surface_container_lowest, 0.96)
                : Theme.glass(Theme.surface_container_low, 0.82)
            border {
                width: passwordInput.activeFocus ? 1.5 : 1
                color: passwordInput.activeFocus
                    ? Theme.primary : Theme.glass(Theme.outline_variant, 0.56)
            }

            TextInput {
                id: passwordInput
                anchors { fill: parent; leftMargin: 11; rightMargin: 11 }
                verticalAlignment: TextInput.AlignVCenter
                color: Theme.textPrimary
                selectionColor: Theme.glass(Theme.primary, 0.24)
                selectedTextColor: Theme.on_primary
                renderType: Text.NativeRendering
                echoMode: TextInput.Password
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                focus: root.lockService.secure
                enabled: root.lockService.secure
                    && root.lockService.responseRequired
                    && !root.lockService.responseVisible
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 12
                       hintingPreference: Font.PreferVerticalHinting }

                Keys.onReturnPressed: root.submitPassword()
                Keys.onEnterPressed: root.submitPassword()

                Text {
                    visible: passwordInput.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Password"
                    color: root.mutedText
                    opacity: 0.72
                    renderType: Text.NativeRendering
                    font: passwordInput.font
                }
            }
        }

        Text {
            width: parent.width
            height: 16
            text: root.lockService.errorMessage.length > 0
                ? root.lockService.errorMessage
                : root.lockService.authenticating && !root.lockService.responseRequired
                    ? "Checking authentication..."
                    : ""
            color: root.lockService.errorMessage.length > 0 ? Theme.error : root.mutedText
            renderType: Text.NativeRendering
            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                   hintingPreference: Font.PreferVerticalHinting }
        }
    }

    Text {
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 52; bottomMargin: 35 }
        text: "CLOUDYY"
        color: root.mutedText
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
               hintingPreference: Font.PreferVerticalHinting }
    }
    }

    function submitPassword() {
        if (!root.lockService.responseRequired || root.lockService.responseVisible)
            return;
        root.lockService.respond(passwordInput.text);
    }

    Connections {
        target: root.lockService
        function onErrorMessageChanged() {
            if (root.lockService.errorMessage.length > 0)
                passwordInput.text = "";
        }
        function onSecureChanged() {
            if (root.lockService.secure)
                focusTimer.restart();
        }
    }

    Timer {
        id: focusTimer
        interval: 0
        repeat: false
        onTriggered: {
            if (passwordInput.enabled)
                passwordInput.forceActiveFocus();
        }
    }

    Connections {
        target: root.lockService
        function onResponseRequiredChanged() {
            if (root.lockService.responseRequired && !root.lockService.responseVisible)
                focusTimer.restart();
        }
    }
}
