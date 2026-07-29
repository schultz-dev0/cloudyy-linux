import QtQuick
import QtTest

TestCase {
    name: "DockFitMetrics"

    function createMetrics(properties) {
        const component = Qt.createComponent(
            "../../../../.config/quickshell/modules/dock/fit/DockFitMetrics.qml");
        compare(component.status, Component.Ready, component.errorString());
        const object = component.createObject(this, properties);
        verify(object !== null);
        return object;
    }

    function test_unconstrained_dock_keeps_base_metrics() {
        const metrics = createMetrics({
            screenWidth: 1000,
            appCount: 10,
            folderCount: 0
        });
        compare(metrics.fitScale, 1);
        compare(metrics.iconSize, 48);
        compare(metrics.iconSpacing, 25);
        compare(metrics.paddingH, 14);
        compare(metrics.paddingV, 12);
        compare(metrics.dockWidth, metrics.naturalDockWidth);
        metrics.destroy();
    }

    function test_constrained_dock_fills_width_inside_edge_margins() {
        const metrics = createMetrics({
            screenWidth: 800,
            appCount: 10,
            folderCount: 0
        });
        verify(metrics.fitScale < 1);
        fuzzyCompare(metrics.dockWidth, 800 - 24, 0.001);
        fuzzyCompare(metrics.iconSize / 48, metrics.fitScale, 0.001);
        fuzzyCompare(metrics.iconSpacing / 25, metrics.fitScale, 0.001);
        fuzzyCompare(metrics.paddingH / 14, metrics.fitScale, 0.001);
        fuzzyCompare(metrics.paddingV / 12, metrics.fitScale, 0.001);
        metrics.destroy();
    }

    function test_monitor_instances_fit_independently() {
        const wide = createMetrics({
            screenWidth: 1920,
            appCount: 20,
            folderCount: 0
        });
        const narrow = createMetrics({
            screenWidth: 1280,
            appCount: 20,
            folderCount: 0
        });
        compare(wide.fitScale, 1);
        verify(narrow.fitScale < wide.fitScale);
        fuzzyCompare(narrow.dockWidth, 1280 - 24, 0.001);
        wide.destroy();
        narrow.destroy();
    }

    function test_invalid_screen_geometry_preserves_base_size() {
        const metrics = createMetrics({
            screenWidth: 0,
            appCount: 20,
            folderCount: 0
        });
        compare(metrics.fitScale, 1);
        compare(metrics.dockWidth, metrics.naturalDockWidth);
        metrics.destroy();
    }

    function test_content_growth_only_shrinks_the_affected_instance() {
        const small = createMetrics({
            screenWidth: 1280,
            appCount: 8,
            folderCount: 0
        });
        const large = createMetrics({
            screenWidth: 1280,
            appCount: 20,
            folderCount: 0
        });
        compare(small.fitScale, 1);
        verify(large.fitScale < small.fitScale);
        verify(small.fitsAvailableWidth);
        verify(large.fitsAvailableWidth);
        verify(small.dockWidth <= 1256);
        verify(large.dockWidth <= 1256);
        small.destroy();
        large.destroy();
    }
}
