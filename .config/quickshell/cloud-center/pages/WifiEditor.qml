import QtQuick
import "../components"
import "../components/WifiState.js" as WifiState
import "../services" as S
import ".."

Flickable {
    id: wifiPage
    required property var page

    contentWidth: width
    contentHeight: wifiContent.implicitHeight + 54
    clip: true

    property var snapshot: ({ enabled: false, active_ssid: "", device: "", networks: [] })
    property string selectedSsid: ""
    property string searchQuery: ""
    property var pending: ({})
    property var busyTargets: ({})
    property var actionMeta: ({})
    property int nextActionId: 1
    property int nextGeneration: 1
    property string statusMessage: "Loading Wi-Fi…"
    property bool watchStarted: false
    property bool radioPending: false
    property bool radioChecked: false

    readonly property var networks: snapshot.networks || []
    readonly property var filteredNetworks: WifiState.filterNetworks(networks, searchQuery)
    readonly property var selectedNetwork: WifiState.networkFor(filteredNetworks.length
        ? filteredNetworks : networks, selectedSsid)
    readonly property bool wifiEnabled: snapshot.enabled === true
    readonly property bool pageBusy: Object.keys(busyTargets).length > 0 || radioPending
    readonly property string emptyMessage: WifiState.emptyListMessage(
        wifiEnabled, searchQuery, filteredNetworks.length, networks.length)

    function clone(value) {
        return WifiState.clone(value);
    }

    function applySnapshot(next) {
        if (!next) return;
        if (next.stale === true) {
            if ((snapshot.networks || []).length === 0)
                snapshot = clone(next);
            statusMessage = String(next.error || "Wi-Fi could not be refreshed");
            return;
        }
        snapshot = clone(next);
        const nextNetworks = snapshot.networks || [];
        const visible = WifiState.filterNetworks(nextNetworks, searchQuery);
        selectedSsid = WifiState.stableSelection(
            visible.length ? visible : nextNetworks, selectedSsid);
        if (!radioPending)
            radioChecked = snapshot.enabled === true;
        const line = WifiState.statusLine(snapshot, nextNetworks.length);
        statusMessage = String(snapshot.error || line);
    }

    function requestSnapshot(startWatchAfter) {
        S.Backend.request("get_wifi_snapshot", {}, function(result) {
            wifiPage.applySnapshot(result);
            if (startWatchAfter && !wifiPage.watchStarted) {
                wifiPage.watchStarted = true;
                S.Backend.request("start_wifi_watch", {}, function(watchSnapshot) {
                    wifiPage.applySnapshot(watchSnapshot);
                }, function(error) {
                    wifiPage.statusMessage = wifiPage.errorMessage(
                        error, "Live Wi-Fi updates could not start");
                });
            }
        }, function(error) {
            wifiPage.statusMessage = wifiPage.errorMessage(error, "Wi-Fi could not be refreshed");
        });
    }

    function errorMessage(error, fallback) {
        if (!error) return fallback;
        return String(error.message || error.error || fallback);
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
        if (next[key] === undefined) return;
        const actions = clone(next[key]);
        delete actions[String(actionId)];
        if (Object.keys(actions).length === 0)
            delete next[key];
        else
            next[key] = actions;
        busyTargets = next;
    }

    function targetBusy(target) {
        return busyTargets[String(target)] !== undefined;
    }

    function sendAction(action, target, value, fieldKey) {
        const actionId = String(nextActionId++);
        const actionGeneration = allocateGeneration();
        pending = WifiState.setPending(pending, fieldKey, actionGeneration, value);
        const nextMeta = clone(actionMeta);
        nextMeta[actionId] = {
            fieldKey: fieldKey,
            target: String(target),
            generation: actionGeneration,
            busy: true,
            action: action,
        };
        actionMeta = nextMeta;
        setBusyTarget(target, actionId);
        if (action === "set_radio")
            radioPending = true;
        try {
            S.Backend.request("run_wifi_action", {
                action: action,
                target: target,
                value: value,
                action_id: actionId,
                generation: actionGeneration,
            }, function(result) { wifiPage.handleActionReply(actionId, result); },
            function(error) { wifiPage.handleActionError(actionId, error); });
        } catch (error) {
            rejectAction(actionId, false, String(error));
        }
    }

    function handleActionReply(actionId, result) {
        if (result && (result.queued === true || result.ok === true)) return;
        const staleTarget = Boolean(result && (result.stale_target === true || result.staleTarget === true));
        const message = result && (result.message || result.error)
            ? String(result.message || result.error) : "Wi-Fi action was rejected";
        rejectAction(actionId, staleTarget, message);
    }

    function handleActionError(actionId, error) {
        const staleTarget = Boolean(error && (error.stale_target === true || error.staleTarget === true));
        const message = error && (error.message || error.error)
            ? String(error.message || error.error) : "Wi-Fi action was rejected";
        rejectAction(actionId, staleTarget, message);
    }

    function rejectAction(actionId, staleTarget, message) {
        const meta = actionMeta[String(actionId)];
        if (meta === undefined) return;
        finishAction(actionId, meta.target, meta.generation, false, staleTarget, message);
    }

    function finishAction(actionId, target, generation, ok, staleTarget, message) {
        const id = String(actionId);
        const meta = actionMeta[id];
        if (meta === undefined
            || String(target) !== String(meta.target)
            || Number(generation) !== Number(meta.generation)) return;
        pending = WifiState.clearCompleted(pending, meta.fieldKey, generation);
        if (meta.busy)
            clearBusyTarget(meta.target, id);
        if (meta.action === "set_radio") {
            radioPending = false;
            radioChecked = snapshot.enabled === true;
        }
        const nextMeta = clone(actionMeta);
        delete nextMeta[id];
        actionMeta = nextMeta;
        if (!ok && !staleTarget)
            statusMessage = String(message || "Wi-Fi action failed");
        else if (ok && message)
            statusMessage = String(message);
    }

    function toggleRadio(checked) {
        radioChecked = checked;
        statusMessage = checked ? "Turning Wi-Fi on…" : "Turning Wi-Fi off…";
        sendAction("set_radio", "wifi", checked, "radio:wifi");
    }

    function rescanNetworks() {
        statusMessage = "Scanning for networks…";
        sendAction("rescan", "wifi", null, "rescan:wifi");
    }

    function tryConnect(network) {
        if (!network) return;
        const mode = WifiState.connectMode(network);
        if (mode === "enterprise") {
            passwordDialog.openFor(network, String(network.identity || ""));
            return;
        }
        if (mode === "password") {
            passwordDialog.openFor(network, "");
            return;
        }
        statusMessage = "Connecting to " + network.ssid + "…";
        sendAction("connect", network.ssid, null, "connect:" + network.ssid);
    }

    function submitCredentials(ssid, identity, password) {
        statusMessage = "Connecting to " + ssid + "…";
        if (passwordDialog.enterprise) {
            sendAction("connect_enterprise", ssid, {
                identity: identity,
                password: password,
            }, "connect:" + ssid);
            return;
        }
        sendAction("connect", ssid, password, "connect:" + ssid);
    }

    function disconnectNetwork(network) {
        statusMessage = "Disconnecting…";
        sendAction("disconnect", network ? network.ssid : "wifi", null,
            "disconnect:" + (network ? network.ssid : "wifi"));
    }

    function forgetNetwork(network) {
        if (!network) return;
        statusMessage = "Forgetting " + network.ssid + "…";
        sendAction("forget", network.ssid, null, "forget:" + network.ssid);
    }

    Component.onCompleted: {
        radioChecked = false;
        requestSnapshot(true);
    }
    Component.onDestruction: S.Backend.request("stop_wifi_watch", {}, null)

    Connections {
        target: S.Backend
        function onWifiSnapshotEvent(next) { wifiPage.applySnapshot(next); }
        function onWifiActionDoneEvent(actionId, target, generation, ok,
                                       staleTarget, message) {
            wifiPage.finishAction(actionId, target, generation, ok,
                                  staleTarget, message);
        }
    }

    WifiPasswordDialog {
        id: passwordDialog
        onSubmitted: (ssid, identity, password) =>
            wifiPage.submitCredentials(ssid, identity, password)
    }

    Column {
        id: wifiContent
        width: Math.min(wifiPage.width - 56, 760)
        x: (wifiPage.width - width) / 2
        y: 24
        spacing: 14

        Item {
            width: parent.width
            height: 46
            Column {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    text: wifiPage.page.title || "Wi-Fi"
                    color: Theme.textPrimary
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 20; weight: Font.Bold
                           hintingPreference: Font.PreferVerticalHinting }
                }
                Text {
                    text: wifiPage.statusMessage
                    color: Theme.textMuted
                    renderType: Text.NativeRendering
                    font { family: "JetBrainsMono Nerd Font"; pixelSize: 10
                           hintingPreference: Font.PreferVerticalHinting }
                }
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                CloudButton {
                    text: "Rescan"
                    glyph: "󰑐"
                    subtle: true
                    compact: true
                    enabled: wifiPage.wifiEnabled && !wifiPage.pageBusy
                    onClicked: wifiPage.rescanNetworks()
                }
                CloudSwitch {
                    id: radioSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    checked: wifiPage.radioChecked
                    enabled: !wifiPage.radioPending
                    onToggled: checked => {
                        radioSwitch.checked = Qt.binding(function() {
                            return wifiPage.radioChecked;
                        });
                        wifiPage.toggleRadio(checked);
                    }
                }
            }
        }

        SectionCard {
            width: parent.width
            section: ({ title: "Networks" })

            Column {
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 48
                    CloudTextField {
                        anchors {
                            fill: parent
                            leftMargin: 8
                            rightMargin: 8
                            topMargin: 8
                            bottomMargin: 8
                        }
                        placeholderText: "Search networks…"
                        text: wifiPage.searchQuery
                        onTextEdited: value => wifiPage.searchQuery = value
                    }
                }

                Rectangle {
                    width: parent.width - 16
                    x: 8
                    height: 1
                    color: Theme.glass(Theme.outline_variant, 0.35)
                }

                Column {
                    width: parent.width
                    Repeater {
                        model: wifiPage.filteredNetworks
                        delegate: WifiNetworkRow {
                            required property var modelData
                            required property int index
                            width: parent.width
                            network: modelData
                            selected: String(modelData.ssid) === wifiPage.selectedSsid
                            busy: wifiPage.targetBusy(modelData.ssid)
                            showDivider: index < wifiPage.filteredNetworks.length - 1
                            onClicked: wifiPage.selectedSsid = String(modelData.ssid)
                        }
                    }

                    Item {
                        visible: wifiPage.filteredNetworks.length === 0
                        width: parent.width
                        height: 86
                        Text {
                            anchors {
                                fill: parent
                                margins: 14
                            }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                            text: wifiPage.emptyMessage
                            color: Theme.textMuted
                            renderType: Text.NativeRendering
                            font {
                                family: "JetBrainsMono Nerd Font"
                                pixelSize: 11
                                hintingPreference: Font.PreferVerticalHinting
                            }
                        }
                    }
                }
            }
        }

        SectionCard {
            width: parent.width
            section: ({ title: "Details" })

            WifiDetailPanel {
                width: parent.width
                network: wifiPage.selectedNetwork
                busy: wifiPage.selectedNetwork
                    ? wifiPage.targetBusy(wifiPage.selectedNetwork.ssid)
                    : wifiPage.pageBusy
                onConnectRequested: network => wifiPage.tryConnect(network)
                onDisconnectRequested: network => wifiPage.disconnectNetwork(network)
                onForgetRequested: network => wifiPage.forgetNetwork(network)
            }
        }
    }
}
