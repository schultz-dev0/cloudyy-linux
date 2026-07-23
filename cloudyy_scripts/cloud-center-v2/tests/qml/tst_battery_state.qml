import QtQuick
import QtTest
import "../../../../.config/quickshell/cloud-center/components/BatteryState.js" as BatteryState

TestCase {
    name: "BatteryState"

    function test_empty_snapshot_is_absent() {
        const snap = BatteryState.emptySnapshot();
        compare(snap.present, false);
        compare(BatteryState.percentage(snap), 0);
        compare(BatteryState.hasCapability(snap, "threshold"), false);
    }

    function test_display_helpers() {
        const snap = {
            present: true,
            capabilities: { threshold: true, asus_mode: false },
            info: { percentage: 72, charge_end_threshold: 80, charge_mode: null },
            display: { percentage_label: "72%", power_label: "12.40 W" },
        };
        compare(BatteryState.percentage(snap), 72);
        compare(BatteryState.displayValue(snap, "percentage_label", "—"), "72%");
        compare(BatteryState.thresholdValue(snap), 80);
        compare(BatteryState.hasCapability(snap, "threshold"), true);
        compare(BatteryState.chargeModeIndex(snap), -1);
    }
}
