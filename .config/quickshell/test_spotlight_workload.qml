import QtQuick
import Quickshell
import QtTest
import "modules/spotlight" as Spotlight
import "overview/services" as Services
import "modules/commandcenter/applibrary" as Apps

// Run with QT_QPA_PLATFORM=offscreen qs -p .config/quickshell/test_spotlight_workload.qml.
// Success is the WORKLOAD COMPLETE marker; no windows or app launches are created.
ShellRoot {
    id: root
    readonly property var glyphs: ["󰓃", "󰍹", "󰌌", "󰒓"]
    property int stage: 0
    property int attempts: 0
    property int launches: 0
    property int updates: 0
    property var fileProcess: null

    TestCase { id: test; when: false }

    function check(condition, message) {
        if (!condition) {
            console.error("WORKLOAD FAIL: " + message);
            Qt.quit();
            throw new Error(message);
        }
        console.log("WORKLOAD PASS: " + message);
    }

    function countAppIcons(item) {
        let count = String(item).startsWith("AppIcon_") ? 1 : 0;
        for (const child of item.children || [])
            count += countAppIcons(child);
        return count;
    }

    Item {
        id: rows
        Spotlight.SpotlightRow {
            rowWidth: 640
            isSelected: false
            resultData: ({ type: "app", name: "Probe app", icon: "utilities-terminal" })
        }
        Repeater {
            model: root.glyphs
            delegate: Spotlight.SpotlightRow {
                required property string modelData
                rowWidth: 640
                isSelected: false
                resultData: ({ type: "command", name: "Probe", icon: modelData })
            }
        }
    }

    Timer {
        running: true
        interval: 15000
        onTriggered: root.check(false, "workload checks finish before timeout")
    }
    Timer {
        id: step
        running: true
        repeat: true
        interval: 100
        onTriggered: {
            const svc = Spotlight.SpotlightService;
            if (root.stage === 0) {
                if (!svc.registryLoaded || !svc.settingsRegistry.length || !Apps.AppLibraryService.catalogLoaded) {
                    if (++root.attempts >= 150)
                        root.check(false, "catalogs load before timeout");
                    return;
                }
                const attempted = root.glyphs.filter(glyph => Services.IconResolver.attemptedNames[glyph]);
                root.check(attempted.length === 0, "command glyphs cause zero app-icon lookups");
                root.check(root.countAppIcons(rows) === 1, "only app rows instantiate an app-icon loader");
                // Singleton.children is a reload-propagation list, not its QObject children.
                root.fileProcess = test.qtest_results.findChild(svc, "spotlightFileSearch");
                root.check(root.fileProcess !== null, "file search process is observable");
                root.fileProcess.runningChanged.connect(() => {
                    if (root.fileProcess.running)
                        root.launches++;
                });
                svc.resultsChanged.connect(() => root.updates++);
                svc.visible = true;
                svc.query = Apps.AppLibraryService.catalog[0].name;
                root.check(svc.results.some(row => row.type === "app"), "app hits return immediately");
                root.updates = 0;
                for (let i = 0; i < 10; i++)
                    svc.appendSearchResult({ type: "file", name: "probe" + i, path: "/tmp/probe" + i });
                root.check(root.updates === 0, "file arrivals do not rebuild rows individually");
                root.stage = 1;
                step.interval = 50;
            } else if (root.stage === 1) {
                root.check(root.updates === 1, "ten file results use one UI update");
                root.check(svc.results.filter(row => row.type === "file").length === 10, "batched results are retained");
                root.stage = 2;
                step.interval = 300;
            } else if (root.stage === 2) {
                root.check(root.launches === 0, "app queries do not scan files during the launch window");
                svc.close();
                root.stage = 3;
                step.interval = 750;
            } else if (root.stage === 3) {
                root.check(root.launches === 0, "closing app search cancels deferred traversal");
                svc.visible = true;
                svc.activeCategory = "apps";
                svc.query = Apps.AppLibraryService.catalog[0].name;
                root.stage = 4;
            } else if (root.stage === 4) {
                root.check(root.launches === 0, "apps-only category never traverses files");
                svc.activeCategory = "";
                svc.query = "zzznomatch921";
                root.stage = 5;
                step.interval = 50;
            } else {
                if (!root.launches)
                    return;
                root.check(root.launches === 1, "unfiltered file lookup still starts after idle");
                svc.finishClose();
                console.log("WORKLOAD COMPLETE");
                Qt.quit();
            }
        }
    }
}
