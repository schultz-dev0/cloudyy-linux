import QtQuick
import QtQuick.Controls
import "../components"
import "../components/CursorPolicy.js" as CursorPolicy
import "../services" as S
import ".."

Flickable {
    id: cursorPage
    required property var page

    contentHeight: content.implicitHeight + 54
    clip: true

    property var schema: []
    property var values: ({})
    property var themes: []
    property var monitors: []
    property string theme: ""
    property int cursorSize: 24
    property string baselineValues: "{}"
    property string baselineTheme: ""
    property int baselineSize: 24
    property bool sessionOpen: false
    property bool magnificationOpen: false
    property bool advancedOpen: false
    property string statusMessage: ""
    property string visibilityToken: ""
    property real visibilityDeadline: 0
    property int visibilitySeconds: 15

    readonly property bool dirty: sessionOpen && (
        JSON.stringify(values) !== baselineValues
        || theme !== baselineTheme
        || cursorSize !== baselineSize)
    readonly property bool visibilityConfirmationOpen: visibilityToken !== ""

    function clone(value) {
        return JSON.parse(JSON.stringify(value));
    }

    function settingsFor(section) {
        return schema.filter(setting => setting.section === section);
    }

    function settingValue(key) {
        return values[key];
    }

    function settingTitle(key) {
        const found = schema.find(item => item.key === key);
        return found ? found.title : key;
    }

    function replaceValue(key, value) {
        const next = clone(values);
        next[key] = value;
        values = next;
    }

    function reconcileState(result) {
        if (!result || result.values === undefined) return;
        values = clone(result.values);
        theme = result.theme ?? baselineTheme;
        cursorSize = Number(result.size ?? baselineSize);
        visibilityToken = "";
        visibilityClock.stop();
        visibilityDialog.close();
    }

    function openSession() {
        S.Backend.request("open_cursor_session", {}, function(result) {
            if (!result || !result.ok) {
                statusMessage = result ? result.message : "Could not open Cursor settings";
                return;
            }
            schema = result.schema ?? [];
            values = clone(result.values ?? {});
            themes = result.themes ?? [];
            monitors = result.monitors ?? [];
            theme = result.theme ?? "";
            cursorSize = Number(result.size ?? 24);
            baselineValues = JSON.stringify(values);
            baselineTheme = theme;
            baselineSize = cursorSize;
            sessionOpen = true;
            statusMessage = "Changes preview live and are written only when you apply";
        });
    }

    function previewOption(key, value) {
        if (!sessionOpen) return;
        S.Backend.request("preview_cursor_option", { key, value }, function(result) {
            if (!result || !result.ok) {
                statusMessage = result ? result.message : "Could not preview cursor setting";
                if (result && result.value !== undefined)
                    replaceValue(key, result.value);
                return;
            }
            replaceValue(key, result.value);
            statusMessage = "Previewing “" + settingTitle(key) + "”";
            if (result.confirmation_required) {
                visibilityToken = result.token;
                visibilityDeadline = Number(result.deadline);
                visibilitySeconds = 15;
                visibilityDialog.open();
                visibilityClock.start();
            }
        });
    }

    function previewAppearance(nextTheme, nextSize) {
        if (!sessionOpen || nextTheme === "") return;
        S.Backend.request("preview_cursor_appearance", {
            theme: nextTheme, size: Math.round(nextSize),
        }, function(result) {
            if (!result || !result.ok) {
                statusMessage = result ? result.message : "Could not preview cursor appearance";
                return;
            }
            theme = result.theme;
            cursorSize = Number(result.size);
            statusMessage = "Previewing " + theme + " at " + cursorSize + "px";
        });
    }

    function discard() {
        if (!sessionOpen) return;
        S.Backend.request("close_cursor_session", {}, function(result) {
            if (!result || !result.ok) {
                statusMessage = result ? result.message : "Could not discard cursor preview";
                return;
            }
            sessionOpen = false;
            visibilityToken = "";
            visibilityDialog.close();
            statusMessage = result ? result.message : "Cursor preview discarded";
            openSession();
        });
    }

    function applyChanges() {
        if (!dirty || visibilityConfirmationOpen) return;
        S.Backend.request("apply_cursor_settings", {}, function(result) {
            if (!result || !result.ok) {
                reconcileState(result);
                statusMessage = result ? result.message : "Could not save Cursor settings";
                return;
            }
            baselineValues = JSON.stringify(values);
            baselineTheme = theme;
            baselineSize = cursorSize;
            statusMessage = result.message;
        });
    }

    function keepInvisible() {
        const token = visibilityToken;
        S.Backend.request("keep_cursor_invisible", { token }, function(result) {
            if (!result || !result.ok) {
                statusMessage = result ? result.message : "Cursor visibility confirmation expired";
                return;
            }
            visibilityToken = "";
            visibilityClock.stop();
            visibilityDialog.close();
            statusMessage = result.message;
        });
    }

    function restoreVisibility() {
        visibilityToken = "";
        visibilityClock.stop();
        visibilityDialog.close();
        previewOption("invisible", false);
    }

    Component.onCompleted: openSession()
    Component.onDestruction: {
        if (sessionOpen)
            S.Backend.request("close_cursor_session", {}, null);
    }

    Connections {
        target: S.Backend
        function onCursorVisibilityEvent(state, value, message) {
            cursorPage.visibilityToken = "";
            cursorPage.visibilityClock.stop();
            cursorPage.visibilityDialog.close();
            cursorPage.replaceValue("invisible", value);
            cursorPage.statusMessage = message;
        }
    }

    Timer {
        id: visibilityClock
        interval: 250
        repeat: true
        onTriggered: {
            cursorPage.visibilitySeconds = Math.max(
                0, Math.ceil(cursorPage.visibilityDeadline - Date.now() / 1000));
            if (cursorPage.visibilitySeconds <= 0) stop();
        }
    }

    Column {
        id: content
        width: Math.min(cursorPage.width - 56, 760)
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 14
        topPadding: 24

        Item {
            width: content.width
            height: 46

            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    text: cursorPage.page.title
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; weight: Font.Bold
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Text {
                    text: "Pointer appearance, movement, visibility, and output behavior"
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 7
                CloudButton {
                    text: "Discard"
                    subtle: true
                    compact: true
                    enabled: cursorPage.dirty
                    onClicked: cursorPage.discard()
                }
                CloudButton {
                    text: "Apply"
                    primary: true
                    compact: true
                    enabled: cursorPage.dirty && !cursorPage.visibilityConfirmationOpen
                    onClicked: cursorPage.applyChanges()
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Appearance" })

            RowBase {
                width: parent.width
                enabled: CursorPolicy.appearanceEnabled(cursorPage.values) && cursorPage.themes.length > 0
                opacity: enabled ? 1 : 0.42
                item: ({ icon: "󰍽", title: "Hyprcursor theme",
                         description: cursorPage.themes.length
                             ? "Installed vector cursor themes" : "No Hyprcursor themes installed" })
                CloudSelect {
                    width: 210
                    compact: true
                    options: cursorPage.themes
                    textRole: "name"
                    currentIndex: Math.max(0, cursorPage.themes.findIndex(item => item.id === cursorPage.theme))
                    onActivated: index => cursorPage.previewAppearance(
                        cursorPage.themes[index].id, cursorPage.cursorSize)
                }
            }

            RowBase {
                width: parent.width
                enabled: CursorPolicy.appearanceEnabled(cursorPage.values) && cursorPage.theme !== ""
                opacity: enabled ? 1 : 0.42
                item: ({ icon: "󰔏", title: "Cursor size", description: "Vector cursor size in logical pixels" })
                Item {
                    width: 252; height: 32
                    Slider {
                        id: sizeSlider
                        anchors { left: parent.left; right: sizeField.left; rightMargin: 10
                                  verticalCenter: parent.verticalCenter }
                        height: 28; from: 8; to: 128; stepSize: 2
                        value: cursorPage.cursorSize
                        onMoved: {
                            sizeCommit.pendingSize = Math.round(value);
                            sizeCommit.restart();
                        }
                        background: Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 4; radius: 2; color: Theme.outline_variant
                            Rectangle { width: sizeSlider.visualPosition * parent.width
                                        height: parent.height; radius: 2; color: Theme.primary }
                        }
                        handle: Rectangle {
                            x: sizeSlider.visualPosition * (sizeSlider.width - width)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14; height: 14; radius: 7
                            color: Theme.surface_container_lowest
                            border { width: 1; color: Theme.outline }
                        }
                    }
                    Rectangle {
                        id: sizeField
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: 62; height: 30; radius: 8; color: Theme.surface_container
                        border { width: 1; color: sizeInput.activeFocus ? Theme.primary : Theme.outline_variant }
                        TextInput {
                            id: sizeInput
                            anchors.fill: parent
                            text: String(cursorPage.cursorSize)
                            color: Theme.textPrimary
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter
                            horizontalAlignment: TextInput.AlignHCenter
                            renderType: TextInput.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                                   hintingPreference: Font.PreferVerticalHinting }
                            validator: IntValidator { bottom: 8; top: 128 }
                            onAccepted: cursorPage.previewAppearance(cursorPage.theme, parseInt(text, 10))
                            onEditingFinished: accepted()
                        }
                    }
                    Timer {
                        id: sizeCommit
                        property int pendingSize: 24
                        interval: 110
                        onTriggered: cursorPage.previewAppearance(cursorPage.theme, pendingSize)
                    }
                }
            }

            Repeater {
                model: cursorPage.settingsFor("appearance")
                delegate: CursorSettingRow {
                    required property var modelData
                    width: parent.width
                    setting: modelData
                    currentValue: cursorPage.settingValue(modelData.key)
                    monitors: cursorPage.monitors
                    controlEnabled: CursorPolicy.settingEnabled(modelData.key, cursorPage.values)
                    onValueEdited: (key, value) => cursorPage.previewOption(key, value)
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Movement" })
            Repeater {
                model: cursorPage.settingsFor("movement")
                delegate: CursorSettingRow {
                    required property var modelData
                    width: parent.width
                    setting: modelData
                    currentValue: cursorPage.settingValue(modelData.key)
                    monitors: cursorPage.monitors
                    controlEnabled: CursorPolicy.settingEnabled(modelData.key, cursorPage.values)
                    onValueEdited: (key, value) => cursorPage.previewOption(key, value)
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Visibility" })
            Repeater {
                model: cursorPage.settingsFor("visibility")
                delegate: CursorSettingRow {
                    required property var modelData
                    width: parent.width
                    setting: modelData
                    currentValue: cursorPage.settingValue(modelData.key)
                    monitors: cursorPage.monitors
                    controlEnabled: CursorPolicy.settingEnabled(modelData.key, cursorPage.values)
                    onValueEdited: (key, value) => cursorPage.previewOption(key, value)
                }
            }
        }

        Rectangle {
            width: content.width; height: 52; radius: 2
            color: magnifyHover.hovered ? Theme.glass(Theme.primary, 0.07)
                : Theme.surface_container_lowest
            border { width: 1; color: Theme.hairline }
            Row {
                anchors { fill: parent; leftMargin: 15; rightMargin: 15 }
                spacing: 11
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: Theme.accent
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 } }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 54; spacing: 1
                    Text { text: "Magnification"; color: Theme.textPrimary; renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; weight: Font.Medium
                                  hintingPreference: Font.PreferVerticalHinting } }
                    Text { text: "Zoom behavior and camera tracking"; color: Theme.textMuted
                           renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                                  hintingPreference: Font.PreferVerticalHinting } }
                }
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: cursorPage.magnificationOpen ? "󰅀" : "󰅂"; color: Theme.textMuted
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 } }
            }
            HoverHandler { id: magnifyHover }
            TapHandler { onTapped: cursorPage.magnificationOpen = !cursorPage.magnificationOpen }
        }

        SectionCard {
            visible: cursorPage.magnificationOpen
            width: content.width
            section: ({ title: "" })
            Repeater {
                model: cursorPage.settingsFor("magnification")
                delegate: CursorSettingRow {
                    required property var modelData
                    width: parent.width
                    setting: modelData
                    currentValue: cursorPage.settingValue(modelData.key)
                    monitors: cursorPage.monitors
                    controlEnabled: CursorPolicy.settingEnabled(modelData.key, cursorPage.values)
                    onValueEdited: (key, value) => cursorPage.previewOption(key, value)
                }
            }
        }

        Rectangle {
            width: content.width; height: 52; radius: 2
            color: advancedHover.hovered ? Theme.glass(Theme.primary, 0.07)
                : Theme.surface_container_lowest
            border { width: 1; color: Theme.hairline }
            Row {
                anchors { fill: parent; leftMargin: 15; rightMargin: 15 }
                spacing: 11
                Text { anchors.verticalCenter: parent.verticalCenter; text: "󰒓"; color: Theme.accent
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 15 } }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 54; spacing: 1
                    Text { text: "Advanced cursor"; color: Theme.textPrimary; renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 13; weight: Font.Medium
                                  hintingPreference: Font.PreferVerticalHinting } }
                    Text { text: "Hardware cursors, VRR, synchronization, and edge behavior"; color: Theme.textMuted
                           renderType: Text.NativeRendering
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                                  hintingPreference: Font.PreferVerticalHinting } }
                }
                Text { anchors.verticalCenter: parent.verticalCenter
                       text: cursorPage.advancedOpen ? "󰅀" : "󰅂"; color: Theme.textMuted
                       font { family: "JetBrainsMono Nerd Font"; pixelSize: 12 } }
            }
            HoverHandler { id: advancedHover }
            TapHandler { onTapped: cursorPage.advancedOpen = !cursorPage.advancedOpen }
        }

        SectionCard {
            visible: cursorPage.advancedOpen
            width: content.width
            section: ({ title: "" })
            Repeater {
                model: cursorPage.settingsFor("advanced")
                delegate: CursorSettingRow {
                    required property var modelData
                    width: parent.width
                    setting: modelData
                    currentValue: cursorPage.settingValue(modelData.key)
                    monitors: cursorPage.monitors
                    controlEnabled: CursorPolicy.settingEnabled(modelData.key, cursorPage.values)
                    onValueEdited: (key, value) => cursorPage.previewOption(key, value)
                }
            }
        }

        Item {
            width: content.width; height: 34
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                width: parent.width - 150
                text: cursorPage.statusMessage
                color: cursorPage.statusMessage.startsWith("Could not") ? Theme.error : Theme.textMuted
                elide: Text.ElideRight
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: cursorPage.dirty ? "Live preview · not saved" : "Saved configuration"
                color: cursorPage.dirty ? Theme.accent : Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }
    }

    CloudDialog {
        id: visibilityDialog
        width: 480; height: 252
        heading: "Keep the cursor hidden?"
        supportingText: "Visibility restores automatically in " + cursorPage.visibilitySeconds + " seconds"
        primaryText: "Keep hidden"
        secondaryText: "Restore cursor"
        showClose: false
        onPrimaryClicked: cursorPage.keepInvisible()
        onSecondaryClicked: cursorPage.restoreVisibility()

        Item {
            anchors.fill: parent
            Row {
                anchors { fill: parent; margins: 20 }
                spacing: 14
                Rectangle {
                    width: 42; height: 42; radius: 2
                    color: Theme.glass(Theme.error, 0.13)
                    Text { anchors.centerIn: parent; text: "󰈈"; color: Theme.error
                           font { family: "JetBrainsMono Nerd Font"; pixelSize: 18 } }
                }
                Text {
                    width: parent.width - 56
                    text: "The pointer is no longer rendered. Use this countdown or press Enter on “Keep hidden” only if that is intentional."
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }
        }
    }
}
