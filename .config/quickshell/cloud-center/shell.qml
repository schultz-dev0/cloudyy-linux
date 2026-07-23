//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import "."   // shared Theme.qml singleton (stable loader); symlinked into this dir since
             // Quickshell's per-config import sandbox does not resolve ".." across config roots
import "services" as S
import "components"
import "pages"

FloatingWindow {
    id: root
    title: "Cloud Center"
    implicitWidth: 1100
    implicitHeight: 760
    color: "transparent"

    // `cloud-center <page>` targets a page in the running instance:
    //   qs ipc -p ~/.config/quickshell/cloud-center call nav page <id>
    IpcHandler {
        target: "nav"
        function page(id: string): void { S.Nav.navigate(id); }
    }

    property string currentPageId: ""
    readonly property int sidebarStripWidth: 240

    // Near-transparent glass strip; Hyprland blurs the desktop behind it.
    Rectangle {
        id: glassStrip
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: root.sidebarStripWidth
        color: Theme.glass(Theme.surface_container, 0.30)

        GlassPanel {
            anchors { fill: parent; margins: 10 }

            Column {
                id: sidebarColumn
                anchors { fill: parent; topMargin: 10 }

                // Search field (filter wired in Task 7)
                Rectangle {
                    width: parent.width - 16; height: 30
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: 8; color: Theme.glass(Theme.surface_container_high, 0.7)
                    TextInput {
                        id: searchInput
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.textPrimary
                        renderType: TextInput.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 13
                               hintingPreference: Font.PreferVerticalHinting }
                        onTextChanged: S.Nav.searchQuery = text
                        Text { visible: !parent.text; text: "⌕ Search settings…"
                               anchors.verticalCenter: parent.verticalCenter
                               color: Theme.textMuted; font: parent.font
                               renderType: Text.NativeRendering }
                    }
                }

                // Categories
                Repeater {
                    model: S.Nav.model ? S.Nav.model.categories : []
                    delegate: Column {
                        width: sidebarColumn.width
                        required property var modelData
                        Text {
                            text: modelData.title.toUpperCase()
                            color: Theme.textMuted
                            renderType: Text.NativeRendering
                            font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                                   letterSpacing: 1; hintingPreference: Font.PreferVerticalHinting }
                            leftPadding: 14; topPadding: 10; bottomPadding: 3
                        }
                        Repeater {
                            model: modelData.pages
                            delegate: SidebarItem {
                                required property string modelData
                                readonly property var page: S.Nav.pageById(modelData)
                                visible: page !== null
                                width: sidebarColumn.width - 12
                                x: 6
                                pageId: modelData
                                title: page ? page.title : ""
                                glyph: page ? page.icon : ""
                                selected: S.Nav.currentPageId === modelData
                                onClicked: S.Nav.navigate(modelData)
                            }
                        }
                    }
                }
            }

            // Pinned System Overview
            SidebarItem {
                anchors { bottom: parent.bottom; bottomMargin: 8; horizontalCenter: parent.horizontalCenter }
                width: parent.width - 12
                pageId: "home"; title: "System Overview"
                glyph: S.Nav.pageById("home") ? S.Nav.pageById("home").icon : ""
                selected: S.Nav.currentPageId === "home"
                onClicked: S.Nav.navigate("home")
            }
        }
    }

    // Opaque content pane.
    Rectangle {
        id: contentPane
        anchors { left: glassStrip.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        color: Theme.background

        Item {
            id: contentArea
            anchors.fill: parent

            Loader {
                id: pageLoader
                anchors.fill: parent
                visible: !S.Backend.failed
                readonly property var page: S.Nav.pageById(S.Nav.currentPageId)
                sourceComponent: S.Nav.searchQuery !== "" ? searchComponent
                    : !page ? null
                    : page.kind === "keybinds" ? keybindsComponent
                    : page.kind === "monitors" ? monitorsComponent
                    : page.kind === "cursor" ? cursorComponent
                    : page.kind === "rules_startup" ? rulesStartupComponent
                    : page.kind === "audio" ? audioComponent
                    : page.kind === "bluetooth" ? bluetoothComponent
                    : page.kind === "wifi" ? wifiComponent
                    : page.kind === "battery" ? batteryComponent
                    : page.kind === "region" ? regionComponent
                    : yamlComponent
            }
            Component { id: searchComponent; SearchResults {} }
            Component { id: yamlComponent; YamlPage { page: pageLoader.page } }
            Component { id: keybindsComponent; KeybindManager { page: pageLoader.page } }
            Component { id: monitorsComponent; MonitorsEditor { page: pageLoader.page } }
            Component { id: cursorComponent; CursorEditor { page: pageLoader.page } }
            Component { id: rulesStartupComponent; RulesStartupEditor { page: pageLoader.page } }
            Component { id: audioComponent; AudioEditor { page: pageLoader.page } }
            Component { id: bluetoothComponent; BluetoothEditor { page: pageLoader.page } }
            Component { id: wifiComponent; WifiEditor { page: pageLoader.page } }
            Component { id: batteryComponent; BatteryEditor { page: pageLoader.page } }
            Component { id: regionComponent; RegionTimeEditor { page: pageLoader.page } }

            Text {
                anchors.centerIn: parent
                visible: S.Backend.failed
                text: "⚠ " + S.Backend.failureText
                color: Theme.error
                font.family: "JetBrainsMono Nerd Font"
            }
        }
    }

    ToastOverlay { id: toasts }
    BezierEditorDialog { id: bezierEditor }

    Connections {
        target: S.Backend
        function onToastEvent(text) { toasts.show(text) }
        function onBezierEditorRequested() { bezierEditor.open() }
    }
    Connections {
        target: S.Nav
        function onSearchQueryChanged() { if (S.Nav.searchQuery === "") searchInput.text = "" }
    }
}
