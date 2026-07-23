import QtQuick
import QtQuick.Controls
import "../components"
import "../components/BluetoothState.js" as BluetoothState
import "../services" as S
import ".."

Flickable {
    id: bluetoothPage
    required property var page

    contentWidth: width
    contentHeight: content.implicitHeight + 54
    clip: true

    property var snapshot: ({ powered: false, scanning: false, devices: [], error: "" })
    property var pending: ({})
    property var busyTargets: ({})
    property string selectedAddress: ""
    property int nextActionId: 1
    property int nextGeneration: 1
    property string statusMessage: "Loading Bluetooth…"
    property bool watchStarted: false
    property var actionMeta: ({})
    property bool powerPending: false
    property var contextDevice: null

    readonly property var devices: BluetoothState.sortDevices(snapshot.devices || [])
    readonly property var selectedDevice: deviceFor(selectedAddress)
    readonly property int connectedCount: devices.filter(item => item.connected).length
    readonly property bool initialRetryAvailable: snapshot.stale === true
        && devices.length === 0 && String(snapshot.error || "") !== ""

    function clone(value) {
        return BluetoothState.clone(value);
    }

    function deviceFor(address) {
        const list = devices;
        for (let index = 0; index < list.length; index++) {
            if (String(list[index].address) === String(address))
                return list[index];
        }
        return null;
    }

    function applySnapshot(next) {
        if (!next)
            return;
        if (next.stale === true) {
            if (devices.length === 0)
                snapshot = clone(next);
            statusMessage = String(next.error || "Bluetooth could not be refreshed");
            return;
        }

        snapshot = clone(next);
        selectedAddress = BluetoothState.stableSelection(
            BluetoothState.sortDevices(snapshot.devices || []),
            selectedAddress,
            "address"
        );
        powerPending = false;
        statusMessage = String(snapshot.error || BluetoothState.statusSummary(snapshot));
    }

    function serviceMessage(value, fallback) {
        if (!value)
            return fallback;
        return String(value.message || value.error || fallback);
    }

    function requestSnapshot(startWatchAfter) {
        S.Backend.request("get_bluetooth_snapshot", {}, function(result) {
            bluetoothPage.applySnapshot(result);
            if (startWatchAfter && !bluetoothPage.watchStarted) {
                bluetoothPage.watchStarted = true;
                S.Backend.request("start_bluetooth_watch", {}, function(watchSnapshot) {
                    bluetoothPage.applySnapshot(watchSnapshot);
                }, function(error) {
                    bluetoothPage.statusMessage = bluetoothPage.serviceMessage(
                        error, "Bluetooth live updates could not start"
                    );
                });
            }
        }, function(error) {
            bluetoothPage.statusMessage = bluetoothPage.serviceMessage(
                error, "Bluetooth could not be refreshed"
            );
        });
    }

    function retrySnapshot() {
        statusMessage = "Refreshing Bluetooth…";
        requestSnapshot(!watchStarted);
    }

    function refreshSnapshotQuietly() {
        requestSnapshot(!watchStarted);
    }

    function allocateGeneration() {
        return nextGeneration++;
    }

    function setBusyTarget(target, actionId) {
        const next = clone(busyTargets);
        const key = String(target);
        const actions = next[key] === undefined ? ({}) : clone(next[key]);
        actions[String(actionId)] = true;
        next[key] = actions;
        busyTargets = next;
    }

    function clearBusyTarget(target, actionId) {
        const next = clone(busyTargets);
        const key = String(target);
        if (next[key] === undefined)
            return;
        const actions = clone(next[key]);
        delete actions[String(actionId)];
        if (Object.keys(actions).length === 0)
            delete next[key];
        else
            next[key] = actions;
        busyTargets = next;
    }

    function sendAction(action, target, value, fieldKey) {
        const actionId = String(nextActionId++);
        const actionGeneration = allocateGeneration();
        const isBusyAction = action !== "trust";
        pending = BluetoothState.setPending(pending, fieldKey, actionGeneration, value);
        const nextMeta = clone(actionMeta);
        nextMeta[actionId] = {
            fieldKey: fieldKey,
            target: String(target),
            generation: actionGeneration,
            busy: isBusyAction,
            action: action,
        };
        actionMeta = nextMeta;
        if (isBusyAction)
            setBusyTarget(target, actionId);
        if (action === "set_power")
            powerPending = true;
        try {
            S.Backend.request("run_bluetooth_action", {
                action: action,
                target: target,
                value: value,
                action_id: actionId,
                generation: actionGeneration,
            }, function(result) {
                bluetoothPage.handleActionReply(actionId, result);
            }, function(error) {
                bluetoothPage.handleActionError(actionId, error);
            });
        } catch (error) {
            rejectAction(actionId, false, String(error));
        }
    }

    function handleActionReply(actionId, result) {
        if (result && (result.queued === true || result.ok === true))
            return;
        const staleTarget = Boolean(result && (result.stale_target === true || result.staleTarget === true));
        const message = result && (result.message || result.error)
            ? String(result.message || result.error) : "Bluetooth action was rejected";
        rejectAction(actionId, staleTarget, message);
    }

    function handleActionError(actionId, error) {
        const staleTarget = Boolean(error && (error.stale_target === true || error.staleTarget === true));
        const message = error && (error.message || error.error)
            ? String(error.message || error.error) : "Bluetooth action was rejected";
        rejectAction(actionId, staleTarget, message);
    }

    function rejectAction(actionId, staleTarget, message) {
        const meta = actionMeta[String(actionId)];
        if (meta === undefined)
            return;
        finishAction(actionId, meta.target, meta.generation, false, staleTarget, message);
    }

    function finishAction(actionId, target, generation, ok, staleTarget, message) {
        const id = String(actionId);
        const meta = actionMeta[id];
        if (meta === undefined
            || String(target) !== String(meta.target)
            || Number(generation) !== Number(meta.generation))
            return;
        pending = BluetoothState.clearCompleted(pending, meta.fieldKey, generation);
        if (meta.busy)
            clearBusyTarget(meta.target, id);
        if (meta.action === "set_power")
            powerPending = false;
        if (meta.action === "remove" && ok)
            selectedAddress = "";
        const nextMeta = clone(actionMeta);
        delete nextMeta[id];
        actionMeta = nextMeta;
        if (!ok && !staleTarget)
            statusMessage = String(message || "Bluetooth action failed");
        if (staleTarget)
            refreshSnapshotQuietly();
    }

    function togglePower() {
        const next = !(snapshot.powered === true);
        sendAction("set_power", "adapter", next, "adapter:power");
    }

    function startScan() {
        if (!snapshot.powered || snapshot.scanning)
            return;
        statusMessage = "Scanning for nearby devices…";
        sendAction("start_scan", "adapter", 8, "adapter:scan");
    }

    function deviceActionOptions(device) {
        const items = [];
        if (!device)
            return items;
        if (device.connected)
            items.push({ id: "disconnect", label: "Disconnect" });
        else
            items.push({ id: "connect", label: "Connect" });
        if (device.paired)
            items.push({ id: "remove", label: "Remove" });
        return items;
    }

    function runDeviceAction(device, actionId) {
        if (!device || !actionId)
            return;
        const field = actionId === "remove" ? "removed" : "connected";
        sendAction(actionId, String(device.address), null,
            "device:" + String(device.address) + ":" + field);
    }

    function toggleDeviceConnection(device) {
        if (!device)
            return;
        runDeviceAction(device, device.connected ? "disconnect" : "connect");
    }

    function openDeviceMenu(device, anchorItem, localX, localY) {
        if (!device || !anchorItem)
            return;
        selectedAddress = String(device.address);
        contextDevice = device;
        const pos = anchorItem.mapToItem(
            Overlay.overlay,
            localX === undefined ? anchorItem.width / 2 : localX,
            localY === undefined ? anchorItem.height / 2 : localY
        );
        deviceMenu.x = pos.x;
        deviceMenu.y = pos.y;
        deviceMenu.open();
        deviceMenu.forceActiveFocus();
    }

    function moveDeviceSelection(delta) {
        const list = devices;
        if (!list.length)
            return;
        let index = -1;
        for (let i = 0; i < list.length; i++) {
            if (String(list[i].address) === String(selectedAddress)) {
                index = i;
                break;
            }
        }
        if (index < 0)
            index = delta > 0 ? -1 : 0;
        const next = Math.max(0, Math.min(list.length - 1, index + delta));
        selectedAddress = String(list[next].address);
    }

    Component.onCompleted: requestSnapshot(true)
    Component.onDestruction: S.Backend.request("stop_bluetooth_watch", {}, null)

    Connections {
        target: S.Backend
        function onBluetoothSnapshotEvent(next) {
            bluetoothPage.applySnapshot(next);
        }
        function onBluetoothActionDoneEvent(actionId, target, generation, ok,
                                            staleTarget, message) {
            bluetoothPage.finishAction(actionId, target, generation, ok,
                                       staleTarget, message);
            if (ok && message)
                bluetoothPage.statusMessage = String(message);
        }
    }

    Column {
        id: content
        width: Math.min(bluetoothPage.width - 56, 760)
        x: (bluetoothPage.width - width) / 2
        y: 24
        spacing: 14

        Item {
            width: content.width
            height: 46
            Column {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                spacing: 2
                Text {
                    text: bluetoothPage.page.title
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 20
                        weight: Font.Bold
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
                Text {
                    text: BluetoothState.statusSummary(bluetoothPage.snapshot)
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 10
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
            }
            Row {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8
                CloudButton {
                    text: "Scan"
                    glyph: "󰍉"
                    subtle: true
                    compact: true
                    enabled: bluetoothPage.snapshot.powered === true
                        && bluetoothPage.snapshot.scanning !== true
                    onClicked: bluetoothPage.startScan()
                }
                CloudButton {
                    text: "Refresh"
                    glyph: "󰑐"
                    subtle: true
                    compact: true
                    onClicked: bluetoothPage.retrySnapshot()
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Adapter" })

            Item {
                width: parent.width
                height: 52
                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Bluetooth"
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font {
                        family: "JetBrainsMono Nerd Font"
                        pixelSize: 12
                        hintingPreference: Font.PreferVerticalHinting
                    }
                }
                CloudSwitch {
                    id: powerSwitch
                    anchors {
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    checked: bluetoothPage.snapshot.powered === true
                    enabled: !bluetoothPage.powerPending
                    onToggled: checked => {
                        const desired = checked;
                        powerSwitch.checked = Qt.binding(function() {
                            return bluetoothPage.snapshot.powered === true;
                        });
                        if (desired === (bluetoothPage.snapshot.powered === true))
                            return;
                        bluetoothPage.sendAction(
                            "set_power", "adapter", desired, "adapter:power"
                        );
                    }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Devices" })

            FocusScope {
                id: deviceListFocus
                width: parent.width
                height: deviceListColumn.implicitHeight
                activeFocusOnTab: true
                focus: true

                Keys.onPressed: event => {
                    if (deviceMenu.opened && event.key === Qt.Key_Escape) {
                        deviceMenu.close();
                        event.accepted = true;
                        return;
                    }
                    if (bluetoothPage.devices.length === 0)
                        return;
                    if (event.key === Qt.Key_Down) {
                        bluetoothPage.moveDeviceSelection(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        bluetoothPage.moveDeviceSelection(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                               || event.key === Qt.Key_Menu) {
                        const device = bluetoothPage.selectedDevice;
                        if (device)
                            bluetoothPage.openDeviceMenu(device, deviceListFocus);
                        event.accepted = true;
                    }
                }

                Column {
                    id: deviceListColumn
                    width: parent.width

                    Repeater {
                        model: bluetoothPage.devices
                        delegate: BluetoothDeviceRow {
                            id: deviceRow
                            required property var modelData
                            required property int index
                            width: parent.width
                            device: modelData
                            selected: String(modelData.address) === bluetoothPage.selectedAddress
                            busy: Boolean(bluetoothPage.busyTargets[String(modelData.address)])
                            showDivider: index < bluetoothPage.devices.length - 1
                            onClicked: {
                                bluetoothPage.selectedAddress = String(modelData.address);
                                deviceListFocus.forceActiveFocus();
                            }
                            onDoubleClicked: {
                                bluetoothPage.selectedAddress = String(modelData.address);
                                bluetoothPage.toggleDeviceConnection(modelData);
                            }
                            onContextMenuRequested: (x, y) => {
                                bluetoothPage.openDeviceMenu(modelData, deviceRow, x, y);
                            }
                        }
                    }

                    Item {
                        visible: bluetoothPage.devices.length === 0
                        width: parent.width
                        height: 86
                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 14
                                right: retryButton.left
                                rightMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            text: bluetoothPage.initialRetryAvailable
                                ? String(bluetoothPage.snapshot.error)
                                : BluetoothState.emptyListMessage(bluetoothPage.snapshot)
                            wrapMode: Text.WordWrap
                            color: bluetoothPage.initialRetryAvailable ? Theme.error : Theme.textMuted
                            renderType: Text.NativeRendering
                            font {
                                family: "JetBrainsMono Nerd Font"
                                pixelSize: 11
                                hintingPreference: Font.PreferVerticalHinting
                            }
                        }
                        CloudButton {
                            id: retryButton
                            visible: bluetoothPage.initialRetryAvailable
                            anchors {
                                right: parent.right
                                rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: "Retry"
                            compact: true
                            primary: true
                            onClicked: bluetoothPage.retrySnapshot()
                        }
                    }
                }
            }
        }

        SectionCard {
            width: content.width
            section: ({ title: "Details" })

            BluetoothDevicePanel {
                width: parent.width
                device: bluetoothPage.selectedDevice
                pending: bluetoothPage.pending
                busyTargets: bluetoothPage.busyTargets
                onActionRequested: (action, target, value, fieldKey, generation) =>
                    bluetoothPage.sendAction(action, target, value, fieldKey)
            }
        }

        Text {
            visible: bluetoothPage.statusMessage !== "" && !bluetoothPage.initialRetryAvailable
            width: content.width
            text: bluetoothPage.statusMessage
            wrapMode: Text.WordWrap
            color: bluetoothPage.snapshot.stale === true ? Theme.error : Theme.textMuted
            renderType: Text.NativeRendering
            font {
                family: "JetBrainsMono Nerd Font"
                pixelSize: 10
                hintingPreference: Font.PreferVerticalHinting
            }
            leftPadding: 4
        }
    }

    Popup {
        id: deviceMenu
        modal: true
        dim: false
        focus: true
        padding: 4
        enter: null
        exit: null
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 8
            color: Theme.surface_container
            border {
                width: 1
                color: Theme.outline_variant
            }
        }
        contentItem: FocusScope {
            focus: true
            Keys.onEscapePressed: deviceMenu.close()
            Column {
                spacing: 2
                Repeater {
                    model: bluetoothPage.deviceActionOptions(bluetoothPage.contextDevice)
                    delegate: Rectangle {
                        required property var modelData
                        width: 168
                        height: 28
                        radius: 6
                        color: menuHover.hovered
                            ? Theme.glass(Theme.primary, 0.14)
                            : "transparent"
                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: modelData.label
                            color: modelData.id === "remove" ? Theme.error : Theme.textPrimary
                            renderType: Text.NativeRendering
                            font {
                                family: "JetBrainsMono Nerd Font"
                                pixelSize: 11
                                hintingPreference: Font.PreferVerticalHinting
                            }
                        }
                        HoverHandler { id: menuHover }
                        TapHandler {
                            onTapped: {
                                bluetoothPage.runDeviceAction(
                                    bluetoothPage.contextDevice, modelData.id
                                );
                                deviceMenu.close();
                            }
                        }
                    }
                }
            }
        }
        onOpened: forceActiveFocus()
    }
}