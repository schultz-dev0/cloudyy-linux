import QtQuick
import QtTest
import "../../../../.config/quickshell/cloud-center/components/RegionTimeState.js" as RegionTimeState

TestCase {
    name: "RegionTimeState"

    function test_empty_snapshot() {
        const snap = RegionTimeState.emptySnapshot();
        compare(snap.ntp_enabled, true);
        compare(snap.manual_location, false);
        compare(RegionTimeState.formatClock(snap.clock).indexOf("1970") !== -1, true);
    }

    function test_filter_timezones() {
        const zones = [
            { id: "Europe/London", offset: "UTC+01:00" },
            { id: "America/New_York", offset: "UTC-04:00" },
            { id: "UTC", offset: "UTC+00:00" },
        ];
        compare(RegionTimeState.filterTimezones(zones, "").length, 3);
        compare(RegionTimeState.filterTimezones(zones, "london").length, 1);
        compare(RegionTimeState.filterTimezones(zones, "utc-04").length, 1);
    }

    function test_tick_clock() {
        const next = RegionTimeState.tickClock({
            year: 2026, month: 7, day: 23, hour: 23, minute: 59, second: 59,
        });
        compare(next.year, 2026);
        compare(next.month, 7);
        compare(next.day, 24);
        compare(next.hour, 0);
        compare(next.minute, 0);
        compare(next.second, 0);
    }

    function test_location_coords() {
        const coords = RegionTimeState.locationCoords({
            location: { latitude: 51.5, longitude: -0.1, accuracy: 100 },
        });
        compare(coords.latitude, "51.5");
        compare(coords.longitude, "-0.1");
        compare(coords.accuracy, "100");
    }
}
