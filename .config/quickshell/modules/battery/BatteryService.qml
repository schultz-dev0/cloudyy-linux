pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property int historyMax: 60

    readonly property var device: UPower.displayDevice

    readonly property bool available: {
        const d = root.device;
        return d !== null && d.isPresent && d.isLaptopBattery;
    }

    readonly property real percent: root.available ? root.device.percentage * 100 : 0

    readonly property int state: {
        if (!root.available)
            return UPowerDeviceState.Unknown;
        return root.device.state;
    }

    readonly property bool charging: state === UPowerDeviceState.Charging
        || state === UPowerDeviceState.PendingCharge

    readonly property bool discharging: state === UPowerDeviceState.Discharging
        || state === UPowerDeviceState.PendingDischarge

    readonly property bool full: state === UPowerDeviceState.FullyCharged

    readonly property real timeToEmptySec: root.available ? root.device.timeToEmpty : 0

    readonly property real timeToFullSec: root.available ? root.device.timeToFull : 0

    readonly property real changeRateW: {
        if (!root.available)
            return 0;
        const r = root.device.changeRate;
        return r > 0 ? r : 0;
    }

    readonly property real healthPercent: root.available ? root.device.healthPercentage * 100 : 0

    readonly property string statusLabel: {
        if (full)
            return "Fully charged";
        if (charging)
            return "Charging";
        if (discharging)
            return "Discharging";
        if (state === UPowerDeviceState.Empty)
            return "Empty";
        if (state === UPowerDeviceState.PendingCharge)
            return "Pending charge";
        if (state === UPowerDeviceState.PendingDischarge)
            return "Pending discharge";
        return "On battery";
    }

    readonly property string etaLabel: {
        if (full)
            return "—";
        if (charging) {
            const t = formatDuration(timeToFullSec);
            return t === "—" ? "Calculating…" : t + " to 100%";
        }
        if (discharging) {
            const t = formatDuration(timeToEmptySec);
            return t === "—" ? "Calculating…" : t + " to empty";
        }
        return "—";
    }

    readonly property string rateEtaLabel: {
        if (full)
            return "Fully charged";
        const parts = [];
        if (charging)
            parts.push("↑");
        else if (discharging)
            parts.push("↓");
        if (changeRateW > 0)
            parts.push(changeRateW.toFixed(1) + " W");
        if (charging) {
            const t = formatDuration(timeToFullSec);
            parts.push(t === "—" ? "Calculating… to full" : t + " to full");
        } else if (discharging) {
            const t = formatDuration(timeToEmptySec);
            parts.push(t === "—" ? "Calculating… to empty" : t + " to empty");
        }
        return parts.length > 0 ? parts.join(" ") : "—";
    }

    readonly property string usageLabel: {
        if (changeRateW <= 0)
            return "—";
        return (charging ? "+" : "−") + changeRateW.toFixed(1) + " W";
    }

    readonly property string barLabel: {
        if (full)
            return "󰁹 Full";
        if (charging)
            return "󰂄 " + Math.round(percent) + "%";
        const icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂"];
        return icons[Math.min(Math.floor(percent / 11), 9)] + " " + Math.round(percent) + "%";
    }

    property var percentHistory: []

    Connections {
        target: root.device
        enabled: root.available
        function onPercentageChanged() { root._pushHistory(); }
    }

    Timer {
        interval: 5000
        running: root.available
        repeat: true
        triggeredOnStart: true
        onTriggered: root._pushHistory()
    }

    function formatDuration(sec) {
        const s = Math.round(sec);
        if (!s || s <= 0)
            return "—";
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (h > 0)
            return h + " h " + m + " m";
        if (m > 0)
            return m + " min";
        return "< 1 min";
    }

    function _pushHistory() {
        const p = Math.round(root.percent);
        const next = root.percentHistory.slice(-(root.historyMax - 1));
        next.push(p);
        root.percentHistory = next;
    }
}
