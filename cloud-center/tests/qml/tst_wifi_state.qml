import QtQuick
import QtTest
import "../../../../.config/quickshell/cloud-center/components/WifiState.js" as WifiState

TestCase {
    name: "WifiState"

    function sampleNetworks() {
        return [
            { ssid: "Home", signal: 80, connected: true, saved: true, is_open: false,
              is_enterprise: false, security: "WPA2", frequency: "5180 MHz" },
            { ssid: "Campus", signal: 60, connected: false, saved: true, is_open: false,
              is_enterprise: true, security: "WPA2 802.1X", frequency: "2437 MHz" },
            { ssid: "Cafe", signal: 40, connected: false, saved: false, is_open: true,
              is_enterprise: false, security: "--", frequency: "2412 MHz" },
        ];
    }

    function test_filter_networks_is_case_insensitive() {
        const networks = sampleNetworks();
        compare(WifiState.filterNetworks(networks, "cam").length, 1);
        compare(WifiState.filterNetworks(networks, "CAM")[0].ssid, "Campus");
        compare(WifiState.filterNetworks(networks, "").length, 3);
    }

    function test_stable_selection_keeps_current_then_connected() {
        const networks = sampleNetworks();
        compare(WifiState.stableSelection(networks, "Cafe"), "Cafe");
        compare(WifiState.stableSelection(networks, "missing"), "Home");
        compare(WifiState.stableSelection([], "Home"), "");
    }

    function test_connect_mode_routes_open_saved_psk_and_enterprise() {
        compare(WifiState.connectMode({ is_enterprise: true }), "enterprise");
        compare(WifiState.connectMode({ is_open: true, saved: false }), "direct");
        compare(WifiState.connectMode({ saved: true, is_open: false }), "direct");
        compare(WifiState.connectMode({ saved: false, is_open: false }), "password");
    }

    function test_status_and_empty_messages_are_newbie_friendly() {
        compare(WifiState.statusLine({ enabled: false }, 0), "Wi-Fi is turned off");
        compare(WifiState.statusLine({ enabled: true, active_ssid: "Home" }, 4),
                "Connected to Home  ·  4 visible");
        compare(WifiState.emptyListMessage(false, "", 0, 0),
                "Turn Wi-Fi on to see nearby networks");
        compare(WifiState.emptyListMessage(true, "zzz", 0, 3),
                "No networks match “zzz”");
        compare(WifiState.emptyListMessage(true, "", 0, 0),
                "No networks found — try Rescan");
    }

    function test_pending_helpers_match_audio_pattern() {
        const pending = WifiState.setPending({}, "connect:Home", 2, "secret");
        compare(WifiState.displayValue(pending, "connect:Home", null), "secret");
        verify(WifiState.clearCompleted(pending, "connect:Home", 1)["connect:Home"] !== undefined);
        verify(WifiState.clearCompleted(pending, "connect:Home", 2)["connect:Home"] === undefined);
    }
}
