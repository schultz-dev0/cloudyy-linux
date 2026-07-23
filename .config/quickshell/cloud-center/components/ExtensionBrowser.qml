import QtQuick
import "../services" as S
import "ExtensionBrowserState.js" as ExtensionBrowserState
import ".."

Column {
    id: browser
    width: parent ? parent.width : 0
    required property var item

    property string query: ""
    property bool enabledOnly: false
    property var plugins: []
    property string statusMessage: ""
    property bool loading: false
    property var pending: ({})

    padding: 10
    spacing: 10

    readonly property var visiblePlugins: ExtensionBrowserState.filterPlugins(
        plugins, query, enabledOnly
    )

    function applyList(result) {
        loading = false;
        if (!result) {
            statusMessage = "Could not load plugins";
            return;
        }
        plugins = result.plugins || [];
        if (result.error)
            statusMessage = String(result.error);
        else if (plugins.length === 0)
            statusMessage = "No plugins found";
        else if (result.truncated)
            statusMessage = "Showing first 100 matches";
        else
            statusMessage = "";
    }

    function reload() {
        loading = true;
        S.Backend.request("list_zsh_plugins", {
            query: "",
            enabled_only: false,
            limit: 0,
        }, function(result) {
            browser.applyList(result);
        }, function(error) {
            browser.loading = false;
            browser.statusMessage = String(
                (error && (error.message || error.error))
                || "Could not load plugins"
            );
        });
    }

    function setEnabled(name, enabled) {
        const nextPending = ExtensionBrowserState.clone(pending);
        nextPending[name] = true;
        pending = nextPending;
        S.Backend.request("set_zsh_plugin", {
            name: name,
            enabled: enabled,
        }, function(result) {
            const cleared = ExtensionBrowserState.clone(browser.pending);
            delete cleared[name];
            browser.pending = cleared;
            if (!result || result.ok !== true) {
                browser.statusMessage = String(
                    (result && (result.message || result.error))
                    || "Could not update plugin"
                );
                browser.reload();
                return;
            }
            const next = ExtensionBrowserState.clone(browser.plugins);
            for (let i = 0; i < next.length; i++) {
                if (next[i].name === name) {
                    next[i].enabled = enabled;
                    break;
                }
            }
            next.sort((a, b) => {
                if (a.enabled !== b.enabled)
                    return a.enabled ? -1 : 1;
                return String(a.name).localeCompare(String(b.name));
            });
            browser.plugins = next;
            browser.statusMessage = String(result.message || "");
        }, function(error) {
            const cleared = ExtensionBrowserState.clone(browser.pending);
            delete cleared[name];
            browser.pending = cleared;
            browser.statusMessage = String(
                (error && (error.message || error.error))
                || "Could not update plugin"
            );
            browser.reload();
        });
    }

    Component.onCompleted: reload()

    Row {
        width: parent.width - browser.padding * 2
        spacing: 8

        Column {
            width: parent.width - filterBtn.width - 8
            spacing: 2
            Text {
                width: parent.width
                text: browser.item.title || "Zsh Extension Browser"
                color: Theme.textPrimary
                elide: Text.ElideRight
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 13
                    weight: Font.Medium
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
            Text {
                width: parent.width
                text: browser.item.description
                      || "Browse and manage Zsh extensions"
                color: Theme.textMuted
                wrapMode: Text.WordWrap
                renderType: Text.NativeRendering
                font {
                    family: "JetBrainsMono Nerd Font"
                    pixelSize: 10
                    hintingPreference: Font.PreferVerticalHinting
                }
            }
        }

        CloudButton {
            id: filterBtn
            anchors.verticalCenter: parent.verticalCenter
            text: "Enabled Only"
            compact: true
            subtle: !browser.enabledOnly
            primary: browser.enabledOnly
            onClicked: browser.enabledOnly = !browser.enabledOnly
        }
    }

    CloudTextField {
        width: parent.width - browser.padding * 2
        placeholderText: "Search Zsh plugins…"
        text: browser.query
        onTextEdited: value => browser.query = value
    }

    ListView {
        id: pluginList
        width: parent.width - browser.padding * 2
        height: Math.min(400, Math.max(120, count * 52))
        clip: true
        model: browser.visiblePlugins
        boundsBehavior: Flickable.StopAtBounds
        interactive: true

        delegate: SelectableRow {
            required property var modelData
            required property int index
            width: pluginList.width
            title: modelData.name || ""
            subtitle: ExtensionBrowserState.description(modelData)
            leadingGlyph: modelData.enabled === true ? "󰄬" : "󰏖"
            leadingColor: modelData.enabled === true ? Theme.accent : Theme.textMuted
            showDivider: index < pluginList.count - 1
            busy: browser.pending[modelData.name] === true
            selected: false

            CloudSwitch {
                checked: modelData.enabled === true
                enabled: browser.pending[modelData.name] !== true
                onToggled: checked => {
                    checked = Qt.binding(function() {
                        return modelData.enabled === true;
                    });
                    browser.setEnabled(modelData.name, checked);
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: pluginList.count === 0
            text: browser.loading ? "Loading plugins…" : (browser.statusMessage || "No plugins found")
            color: Theme.textMuted
            renderType: Text.NativeRendering
            font {
                family: "JetBrainsMono Nerd Font"
                pixelSize: 11
                hintingPreference: Font.PreferVerticalHinting
            }
        }
    }

    Text {
        visible: browser.statusMessage !== "" && pluginList.count > 0
        width: parent.width - browser.padding * 2
        text: browser.statusMessage
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
        font {
            family: "JetBrainsMono Nerd Font"
            pixelSize: 10
            hintingPreference: Font.PreferVerticalHinting
        }
    }
}
