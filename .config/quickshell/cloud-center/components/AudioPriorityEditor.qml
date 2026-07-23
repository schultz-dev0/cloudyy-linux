import QtQuick
import "../services" as S
import ".."

Item {
    id: root

    property var automation: ({})
    property var service: ({})
    property var sinks: []
    property var automationPending: ({})

    signal updated(var snapshot)
    signal error(string message)

    readonly property var priority: (automation || {}).output_priority || []
    readonly property bool bluetoothEnabled: (automation || {}).bluetooth_auto_switch !== false
    readonly property bool wiredEnabled: (automation || {}).enabled === true
    readonly property bool serviceActive: (service || {}).enabled === true
        && (service || {}).active === true

    implicitHeight: editorColumn.implicitHeight

    function serviceWanted() {
        return bluetoothEnabled || wiredEnabled;
    }

    function availableSinks() {
        const next = [];
        for (const sink of (sinks || [])) {
            if (priority.indexOf(sink.name) < 0)
                next.push(sink);
        }
        return next;
    }

    function priorityLabel(name) {
        for (const sink of (sinks || [])) {
            if (sink.name === name)
                return sink.description || name;
        }
        const labels = (automation || {}).output_priority_labels || ({});
        const saved = labels[name];
        if (saved)
            return String(saved) + " (disconnected)";
        return name + " (disconnected)";
    }

    function messageFor(result, fallback) {
        if (!result) return fallback;
        return String(result.message || result.error || fallback);
    }

    function isAutomationPending(key) {
        return automationPending[key] === true;
    }

    function setAutomationPending(key, pending) {
        const next = Object.assign({}, automationPending);
        if (pending)
            next[key] = true;
        else
            delete next[key];
        automationPending = next;
    }

    function restoreAutomationBinding(key) {
        if (key === "bluetooth_auto_switch")
            bluetoothSwitch.checked = Qt.binding(function() { return root.bluetoothEnabled; });
        else if (key === "enabled")
            wiredSwitch.checked = Qt.binding(function() { return root.wiredEnabled; });
    }

    function reconcile(result, fallback) {
        if (result && result.snapshot)
            updated(result.snapshot);
        else if (result && result.sinks !== undefined)
            updated(result);
        else
            error(messageFor(result, fallback));
    }

    function finishAutomation(key, result) {
        restoreAutomationBinding(key);
        setAutomationPending(key, false);
        reconcile(result, "Could not update automatic switching");
    }

    function finishAutomationError(key, reason) {
        restoreAutomationBinding(key);
        setAutomationPending(key, false);
        error(messageFor(reason, "Could not update automatic switching"));
    }

    function setAutomation(key, value) {
        if (isAutomationPending(key)) return;
        restoreAutomationBinding(key);
        setAutomationPending(key, true);
        const params = {};
        params[key] = value;
        try {
            S.Backend.request("set_audio_automation", params,
                function(result) { root.finishAutomation(key, result); },
                function(reason) { root.finishAutomationError(key, reason); });
        } catch (reason) {
            finishAutomationError(key, reason);
        }
    }

    function setPriority(next) {
        try {
            S.Backend.request("set_audio_priority", { priority: next },
                function(result) { root.reconcile(result, "Could not update output priority"); },
                function(reason) { root.error(root.messageFor(reason, "Could not update output priority")); });
        } catch (reason) {
            root.error(String(reason));
        }
    }

    function movePriority(index, offset) {
        const destination = index + offset;
        if (destination < 0 || destination >= priority.length) return;
        const next = priority.slice();
        const moved = next[index];
        next[index] = next[destination];
        next[destination] = moved;
        setPriority(next);
    }

    function removePriority(index) {
        setPriority(priority.slice(0, index).concat(priority.slice(index + 1)));
    }

    function addPriority(name) {
        setPriority(priority.concat([name]));
    }

    function enableService() {
        try {
            S.Backend.request("enable_audio_autoswitch_service", {
                enable: true,
                dismiss_prompt: false,
            }, function(result) {
                root.reconcile(result, "Could not enable audio service");
            }, function(reason) {
                root.error(root.messageFor(reason, "Could not enable audio service"));
            });
        } catch (reason) {
            root.error(String(reason));
        }
    }

    Column {
        id: editorColumn
        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: 52
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Bluetooth output switching"
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                anchors { left: parent.left; leftMargin: 14; top: parent.verticalCenter; topMargin: 5 }
                text: "Prefer a newly connected Bluetooth output"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 9
                       hintingPreference: Font.PreferVerticalHinting }
            }
            CloudSwitch {
                id: bluetoothSwitch
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                checked: root.bluetoothEnabled
                enabled: !root.isAutomationPending("bluetooth_auto_switch")
                onToggled: checked => {
                    const desired = checked;
                    root.restoreAutomationBinding("bluetooth_auto_switch");
                    root.setAutomation("bluetooth_auto_switch", desired);
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.glass(Theme.outline_variant, 0.46) }

        Item {
            width: parent.width
            height: 52
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Wired output priority"
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 11
                       hintingPreference: Font.PreferVerticalHinting }
            }
            Text {
                anchors { left: parent.left; leftMargin: 14; top: parent.verticalCenter; topMargin: 5 }
                text: "Use the ordered list below when Bluetooth is unavailable"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 9
                       hintingPreference: Font.PreferVerticalHinting }
            }
            CloudSwitch {
                id: wiredSwitch
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                checked: root.wiredEnabled
                enabled: !root.isAutomationPending("enabled")
                onToggled: checked => {
                    const desired = checked;
                    root.restoreAutomationBinding("enabled");
                    root.setAutomation("enabled", desired);
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.glass(Theme.outline_variant, 0.46) }

        Item {
            width: parent.width
            height: 38
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Wired output order"
                color: Theme.textPrimary
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10; weight: Font.Medium
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Repeater {
            model: root.priority
            delegate: Item {
                required property string modelData
                required property int index
                width: editorColumn.width
                height: 40
                Rectangle {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 2; bottomMargin: 2 }
                    radius: 7
                    color: Theme.surface_container_low
                    border { width: 1; color: Theme.glass(Theme.outline_variant, 0.50) }
                }
                Text {
                    anchors { left: parent.left; leftMargin: 18; right: actionRow.left; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    text: root.priorityLabel(parent.modelData)
                    elide: Text.ElideMiddle
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Row {
                    id: actionRow
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 4
                    CloudButton {
                        text: "↑"
                        compact: true
                        enabled: parent.parent.index > 0
                        onClicked: root.movePriority(parent.parent.index, -1)
                    }
                    CloudButton {
                        text: "↓"
                        compact: true
                        enabled: parent.parent.index + 1 < root.priority.length
                        onClicked: root.movePriority(parent.parent.index, 1)
                    }
                    CloudButton {
                        text: "Remove"
                        compact: true
                        danger: true
                        onClicked: root.removePriority(parent.parent.index)
                    }
                }
            }
        }

        Item {
            visible: root.priority.length === 0
            width: parent.width
            height: 40
            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "No wired outputs are prioritized"
                color: Theme.textMuted
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                       hintingPreference: Font.PreferVerticalHinting }
            }
        }

        Repeater {
            model: root.availableSinks()
            delegate: Item {
                required property var modelData
                width: editorColumn.width
                height: 40
                Text {
                    anchors { left: parent.left; leftMargin: 14; right: addButton.left; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    text: parent.modelData.description || parent.modelData.name
                    elide: Text.ElideRight
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           hintingPreference: Font.PreferVerticalHinting }
                }
                CloudButton {
                    id: addButton
                    anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                    text: "Add"
                    compact: true
                    onClicked: root.addPriority(parent.modelData.name)
                }
            }
        }

        Item {
            visible: root.serviceWanted()
            width: parent.width
            height: root.serviceActive ? 40 : 66
            Rectangle {
                anchors { fill: parent; margins: 10 }
                radius: 8
                color: root.serviceActive ? Theme.glass(Theme.primary, 0.10)
                    : Theme.glass(Theme.error_container, 0.44)
                border { width: 1; color: root.serviceActive
                    ? Theme.glass(Theme.primary, 0.30) : Theme.glass(Theme.error, 0.36) }
            }
            Text {
                anchors { left: parent.left; leftMargin: 18; right: serviceButton.left; rightMargin: 10
                          verticalCenter: parent.verticalCenter }
                text: root.serviceActive ? "Audio switching service is active"
                    : String((root.service || {}).error || "Audio switching is not persistent yet")
                wrapMode: Text.WordWrap
                color: root.serviceActive ? Theme.textPrimary : Theme.error
                renderType: Text.NativeRendering
                font { family: "JetBrainsMono Nerd Font"; pixelSize: 9
                       hintingPreference: Font.PreferVerticalHinting }
            }
            CloudButton {
                id: serviceButton
                visible: !root.serviceActive
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Enable Service"
                compact: true
                primary: true
                onClicked: root.enableService()
            }
        }
    }
}
