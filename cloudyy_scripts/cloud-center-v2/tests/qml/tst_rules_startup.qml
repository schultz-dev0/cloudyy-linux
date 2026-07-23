import QtQuick
import QtTest

TestCase {
    name: "RulesStartup"
    when: windowShown

    readonly property url componentRoot: Qt.resolvedUrl(
        "../../../../.config/quickshell/cloud-center/components/")

    function createDrafts() {
        const component = Qt.createComponent(componentRoot + "RulesDraftModel.qml");
        verify(component.status === Component.Ready, component.errorString());
        if (component.status !== Component.Ready)
            return null;
        const object = component.createObject(this);
        verify(object !== null, component.errorString());
        return object;
    }

    function test_drafts_stay_clean_until_mutated() {
        const drafts = createDrafts();
        if (!drafts) return;
        drafts.load({
            window_rules: [{ name: "one", matchers: [], effects: {} }],
            layer_rules: [], autostart: [], env_vars: [],
        });
        compare(drafts.dirty, false);
        drafts.replace("window_rules", 0, { name: "changed", matchers: [], effects: {} });
        compare(drafts.dirty, true);
        compare(drafts.dirtySurfaces, ["windowrules"]);
        drafts.destroy();
    }

    function test_reordering_rules_marks_shared_window_surface_dirty() {
        const drafts = createDrafts();
        if (!drafts) return;
        drafts.load({
            window_rules: [{ name: "first" }, { name: "second" }],
            layer_rules: [{ name: "layer" }], autostart: [], env_vars: [],
        });
        drafts.move("window_rules", 0, 1);
        compare(drafts.windowRules[0].name, "second");
        compare(drafts.dirtySurfaces, ["windowrules"]);
        drafts.destroy();
    }

    function test_each_tab_maps_to_its_split_file() {
        const drafts = createDrafts();
        if (!drafts) return;
        drafts.load({ window_rules: [], layer_rules: [], autostart: [], env_vars: [] });
        drafts.append("layer_rules", { name: "panel" });
        drafts.append("autostart", { command: "waybar", exec_once: true });
        drafts.append("env_vars", { name: "EDITOR", value: "nvim" });
        compare(drafts.dirtySurfaces, ["windowrules", "autostart", "variables"]);
        drafts.destroy();
    }

    function test_discard_restores_opening_data() {
        const drafts = createDrafts();
        if (!drafts) return;
        drafts.load({
            window_rules: [{ name: "opening" }], layer_rules: [], autostart: [], env_vars: [],
        });
        drafts.remove("window_rules", 0);
        verify(drafts.dirty);
        drafts.discard();
        compare(drafts.windowRules.length, 1);
        compare(drafts.windowRules[0].name, "opening");
        compare(drafts.dirty, false);
        drafts.destroy();
    }
}
