pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.."

PanelWindow {
    id: root

    readonly property var svc: ThemePickerService
    readonly property int rowHeight: 68
    // Matches ThemeRow.stripHeight — reserved so the active theme's wallpaper
    // strip is always visible without scrolling, whichever row it lands on.
    readonly property int wallpaperStripHeight: 38
    readonly property int rowSpacing: 6
    readonly property int visibleRows: 4
    readonly property int listViewportHeight:
        visibleRows * rowHeight + (visibleRows - 1) * rowSpacing + wallpaperStripHeight
    readonly property int panelWidth: {
        const screens = Quickshell.screens;
        const sw = screens.length > 0 ? screens[0].width : 1920;
        return Math.min(460, Math.round(sw * 0.4));
    }
    readonly property int panelHeight: 48 + 1 + 8 + listViewportHeight + 14

    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    visible: svc.visible
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell:command"
    WlrLayershell.keyboardFocus: svc.keyboardGrab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea {
        anchors.fill: parent
        visible: svc.visible
        onClicked: svc.close()
    }

    Item {
        id: panel
        anchors.centerIn: parent
        width: root.panelWidth
        height: root.panelHeight
        visible: svc.visible

        MouseArea {
            anchors.fill: parent
            onClicked: mouse.accepted = true
        }

        // Resin material — same family as the other command-center overlays
        // (WallpaperPicker, Spotlight, AppLibrary). See Theme.qml's resin().
        Rectangle {
            id: panelShell
            anchors.fill: parent
            radius: 0
            color: Theme.resin(Theme.resinFillAlpha)
            border.width: 1
            border.color: Theme.resinBorder
            antialiasing: true
            clip: true

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: parent.height * 0.4
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.resinGloss }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }

            Rectangle {
                width: parent.width * 0.3
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

        FocusScope {
            id: keyNav
            anchors.fill: parent
            anchors.margins: 2
            focus: true

            Keys.onDownPressed: event => { root.moveSelection(1); event.accepted = true; }
            Keys.onUpPressed: event => { root.moveSelection(-1); event.accepted = true; }
            Keys.onLeftPressed: event => { svc.moveWallpaperFocus(-1); event.accepted = true; }
            Keys.onRightPressed: event => { svc.moveWallpaperFocus(1); event.accepted = true; }
            Keys.onReturnPressed: event => { svc.activateSelection(); event.accepted = true; }
            Keys.onEscapePressed: event => { svc.close(); event.accepted = true; }

            Column {
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 48

                    Row {
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 16
                            rightMargin: 16
                        }
                        spacing: 10

                        Text {
                            text: "󰸌"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                            color: Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "Theme"
                            color: Theme.text
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 15
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.hairline
                }

                Item {
                    width: parent.width
                    height: root.listViewportHeight + 8

                    ListView {
                        id: themeList
                        anchors {
                            top: parent.top
                            topMargin: 8
                            left: parent.left
                            right: parent.right
                        }
                        height: root.listViewportHeight
                        clip: true
                        model: svc.themes
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: root.rowHeight
                        spacing: root.rowSpacing

                        delegate: ThemeRow {
                            required property var modelData
                            required property int index
                            width: themeList.width
                            name: modelData.name
                            mode: modelData.mode
                            colors: modelData.colors
                            preview: modelData.preview
                            wallpapers: modelData.wallpapers || []
                            focusedWallpaperIndex: svc.selectedWallpaperIndex
                            selected: svc.selectedIndex === index
                            isCurrent: modelData.slug === svc.currentSlug
                            onActivated: svc.activateIndex(index)
                            onWallpaperActivated: idx => svc.applyWallpaperAt(index, idx)
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: svc.themes.length === 0
                        text: svc.loading ? "Loading themes…" : "No themes found"
                        color: Theme.textMuted
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    function moveSelection(delta) {
        const count = svc.themes.length;
        if (count === 0)
            return;
        let idx = svc.selectedIndex < 0 ? 0 : svc.selectedIndex + delta;
        idx = Math.max(0, Math.min(count - 1, idx));
        svc.selectedIndex = idx;
        themeList.positionViewAtIndex(idx, ListView.Contain);
    }

    Connections {
        target: svc
        function onRequestFocus() {
            keyNav.forceActiveFocus();
        }
    }

    IpcHandler {
        target: "themepicker"
        function open() { svc.open(); }
        function hide() { svc.close(); }
        function toggle() { svc.toggle(); }
    }
}
