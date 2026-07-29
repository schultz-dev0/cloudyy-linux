import QtQuick
import QtTest
import "../../../../.config/quickshell/cloud-center/components/AudioState.js" as AudioState

TestCase {
    name: "AudioState"

    function test_stable_selection_prefers_existing_then_default() {
        const devices = [{ name: "one", is_default: false }, { name: "two", is_default: true }];
        compare(AudioState.stableSelection(devices, "one", "name"), "one");
        compare(AudioState.stableSelection(devices, "missing", "name"), "two");
    }

    function test_stale_completion_does_not_clear_newer_pending_value() {
        const pending = { "sink:one:volume": { generation: 4, value: 72 } };
        compare(AudioState.clearCompleted(pending, "sink:one:volume", 3)["sink:one:volume"].value, 72);
        verify(AudioState.clearCompleted(pending, "sink:one:volume", 4)["sink:one:volume"] === undefined);
    }

    function test_pending_value_overrides_snapshot_until_completion() {
        const pending = { "sink:one:volume": { generation: 2, value: 80 } };
        compare(AudioState.displayValue(pending, "sink:one:volume", 30), 80);
        compare(AudioState.displayValue({}, "sink:one:volume", 30), 30);
    }

    function test_service_prompt_requires_active_policy_inactive_service_and_old_version() {
        verify(AudioState.shouldPromptService({
            automation: {},
            service: { enabled: false, active: false },
        }));
        verify(AudioState.shouldPromptService({
            automation: { bluetooth_auto_switch: false, enabled: true },
            service: { enabled: true, active: false },
        }));
        verify(!AudioState.shouldPromptService({
            automation: { bluetooth_auto_switch: false, enabled: false },
            service: { enabled: false, active: false },
        }));
        verify(!AudioState.shouldPromptService({
            automation: { service_prompt_version: 1 },
            service: { enabled: false, active: false },
        }));
        verify(!AudioState.shouldPromptService({
            automation: {},
            service: { enabled: true, active: true },
        }));
    }

    function makeToggleState() {
        return Qt.createQmlObject('import QtQuick\nQtObject {\n'
            + '    property bool bluetoothEnabled: false\n'
            + '    property bool wiredEnabled: false\n'
            + '    property bool bluetoothChecked: bluetoothEnabled\n'
            + '    property bool wiredChecked: wiredEnabled\n'
            + '    property var pending: ({})\n'
            + '    function setPending(key, value) {\n'
            + '        const next = Object.assign({}, pending);\n'
            + '        if (value) next[key] = true; else delete next[key];\n'
            + '        pending = next;\n'
            + '    }\n'
            + '    function restoreBluetooth() { bluetoothChecked = Qt.binding(function() { return bluetoothEnabled; }); }\n'
            + '    function restoreWired() { wiredChecked = Qt.binding(function() { return wiredEnabled; }); }\n'
            + '}', this);
    }

    function test_toggle_binding_restoration_tracks_authoritative_values() {
        const state = makeToggleState();
        state.bluetoothChecked = true;
        state.wiredChecked = true;
        state.restoreBluetooth();
        state.restoreWired();
        compare(state.bluetoothChecked, false);
        compare(state.wiredChecked, false);
        state.bluetoothEnabled = true;
        state.wiredEnabled = true;
        compare(state.bluetoothChecked, true);
        compare(state.wiredChecked, true);
        state.destroy();
    }

    function test_toggle_error_cleanup_preserves_the_other_pending_key() {
        const state = makeToggleState();
        state.setPending("bluetooth_auto_switch", true);
        state.setPending("enabled", true);
        state.bluetoothChecked = true;
        state.restoreBluetooth();
        state.setPending("bluetooth_auto_switch", false);
        verify(state.pending.bluetooth_auto_switch === undefined);
        verify(state.pending.enabled === true);
        compare(state.bluetoothChecked, false);
        state.destroy();
    }
}
