import QtQuick
import QtTest
import "../../../../.config/quickshell/cloud-center/components/ExtensionBrowserState.js" as ExtensionBrowserState

TestCase {
    name: "ExtensionBrowserState"

    function test_filter_and_cap() {
        const plugins = [
            { name: "zsh-autosuggestions", desc: "Fish-like", enabled: true },
            { name: "docker", desc: "Containers", enabled: false },
            { name: "git", desc: "", enabled: true },
        ];
        compare(ExtensionBrowserState.filterPlugins(plugins, "", false).length, 3);
        compare(ExtensionBrowserState.filterPlugins(plugins, "auto", false).length, 1);
        compare(ExtensionBrowserState.filterPlugins(plugins, "", true).length, 2);
        compare(ExtensionBrowserState.description({ desc: "" }), "No description available.");
    }
}
