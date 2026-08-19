pragma ComponentBehavior: Bound

import QtQuick
import "../services" as S
import ".."

Column {
    id: root

    required property var item
    property string errorText: ""
    property int mutationRevision: 0
    readonly property var definitions: [
        { id: "notifications", displayName: "Notifications", icon: "\u{f0a36}" },
        { id: "timer", displayName: "Timers", icon: "\u{f051b}" },
        { id: "media", displayName: "Media", icon: "\u{f075a}" },
        { id: "agents", displayName: "Agents", icon: "\u{f0d97}" },
    ]

    width: parent ? parent.width : 0
    spacing: 0

    function definitionFor(id) {
        for (let i = 0; i < root.definitions.length; i++) {
            if (root.definitions[i].id === id)
                return root.definitions[i];
        }
        return null;
    }

    function approvedStatus(status) {
        if (status === "Detected" || status === "Waiting for activity"
                || status === "Shell status unavailable")
            return status;
        return "Shell status unavailable";
    }

    function runtimeStatus(_id) {
        // Cloud Center and the shell are separate Quickshell processes. Until
        // the shell publishes runtime detection, do not infer availability.
        return "Shell status unavailable";
    }

    function replaceSettings(settings) {
        const order = settings && Array.isArray(settings.order)
            ? settings.order : [];
        const enabled = settings && settings.enabled ? settings.enabled : {};
        integrationsModel.clear();
        for (let i = 0; i < order.length; i++) {
            const definition = root.definitionFor(order[i]);
            if (!definition)
                continue;
            integrationsModel.append({
                integrationId: definition.id,
                displayName: definition.displayName,
                iconText: definition.icon,
                enabledState: enabled[definition.id] !== false,
                statusText: root.approvedStatus(root.runtimeStatus(definition.id)),
            });
        }
    }

    function currentDocument() {
        const order = [];
        const enabled = {};
        for (let i = 0; i < integrationsModel.count; i++) {
            const integration = integrationsModel.get(i);
            order.push(integration.integrationId);
            enabled[integration.integrationId] = integration.enabledState;
        }
        return {
            version: 1,
            order: order,
            enabled: enabled,
        };
    }

    function saveCurrentDocument() {
        const revision = ++root.mutationRevision;
        S.Backend.saveIslandIntegrations(root.currentDocument(), saved => {
            if (revision !== root.mutationRevision)
                return;
            root.errorText = "";
            root.replaceSettings(saved);
        }, error => {
            if (revision !== root.mutationRevision)
                return;
            root.errorText = error.message || "Could not save Island integrations";
            S.Backend.getIslandIntegrations(authoritative => {
                if (revision !== root.mutationRevision)
                    return;
                root.errorText = "";
                root.replaceSettings(authoritative);
            }, loadError => {
                if (revision === root.mutationRevision)
                    root.errorText = loadError.message
                        || "Could not reload Island integrations";
            });
        });
    }

    function setEnabled(index, enabled) {
        if (index < 0 || index >= integrationsModel.count)
            return;
        integrationsModel.setProperty(index, "enabledState", enabled);
        root.saveCurrentDocument();
    }

    function moveIntegration(from, to) {
        if (from < 0 || from >= integrationsModel.count || to < 0
                || to >= integrationsModel.count || from === to)
            return;
        integrationsModel.move(from, to, 1);
        root.saveCurrentDocument();
    }

    ListModel {
        id: integrationsModel
    }

    Text {
        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 8
        bottomPadding: 8
        text: root.item.description ?? ""
        color: Theme.textMuted
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
               hintingPreference: Font.PreferVerticalHinting }
    }

    Repeater {
        model: integrationsModel

        delegate: Rectangle {
            id: integrationRow

            required property int index
            required property string integrationId
            required property string displayName
            required property string iconText
            required property bool enabledState
            required property string statusText

            width: root.width
            height: 58
            color: rowHover.hovered ? Theme.glass(Theme.primary, 0.08) : "transparent"

            Row {
                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                spacing: 8

                Text {
                    id: dragGrip
                    width: 24
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "\u{f01db}"
                    color: dragHandler.active ? Theme.accent : Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 13
                           hintingPreference: Font.PreferVerticalHinting }

                    DragHandler {
                        id: dragHandler
                        target: null
                        xAxis.enabled: false
                        onActiveChanged: {
                            if (!active) {
                                const offset = Math.round(translation.y / integrationRow.height);
                                const destination = Math.max(0, Math.min(
                                    integrationsModel.count - 1, integrationRow.index + offset));
                                root.moveIntegration(integrationRow.index, destination);
                            }
                        }
                    }
                }

                Text {
                    width: 22
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: integrationRow.iconText
                    color: Theme.accent
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 15
                           hintingPreference: Font.PreferVerticalHinting }
                }

                Column {
                    width: parent.width - controls.width - dragGrip.width - 46
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: integrationRow.displayName
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 13
                               weight: Font.Medium
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                    Text {
                        width: parent.width
                        text: integrationRow.statusText
                        color: integrationRow.statusText === "Detected"
                            ? Theme.accent : Theme.textMuted
                        elide: Text.ElideRight
                        renderType: Text.NativeRendering
                        font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                               hintingPreference: Font.PreferVerticalHinting }
                    }
                }

                Row {
                    id: controls
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    CloudButton {
                        width: 28
                        compact: true
                        subtle: true
                        glyph: "\u{f0141}"
                        enabled: integrationRow.index > 0
                        onClicked: root.moveIntegration(
                            integrationRow.index, integrationRow.index - 1)
                    }
                    CloudButton {
                        width: 28
                        compact: true
                        subtle: true
                        glyph: "\u{f0140}"
                        enabled: integrationRow.index < integrationsModel.count - 1
                        onClicked: root.moveIntegration(
                            integrationRow.index, integrationRow.index + 1)
                    }
                    CloudSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: integrationRow.enabledState
                        onToggled: checked => root.setEnabled(integrationRow.index, checked)
                    }
                }
            }

            Rectangle {
                anchors { left: parent.left; leftMargin: 46; right: parent.right
                          rightMargin: 10; bottom: parent.bottom }
                height: 1
                color: Theme.hairline
            }

            HoverHandler { id: rowHover }
            activeFocusOnTab: true
            Keys.onUpPressed: event => {
                root.moveIntegration(index, index - 1);
                event.accepted = true;
            }
            Keys.onDownPressed: event => {
                root.moveIntegration(index, index + 1);
                event.accepted = true;
            }
        }
    }

    Text {
        visible: root.errorText !== ""
        width: parent.width
        leftPadding: 10
        rightPadding: 10
        topPadding: 8
        bottomPadding: 8
        text: root.errorText
        color: Theme.error
        wrapMode: Text.WordWrap
        renderType: Text.NativeRendering
        font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
               hintingPreference: Font.PreferVerticalHinting }
    }

    Component.onCompleted: S.Backend.getIslandIntegrations(settings => {
        root.errorText = "";
        root.replaceSettings(settings);
    }, error => {
        root.errorText = error.message || "Could not load Island integrations";
    })
}
