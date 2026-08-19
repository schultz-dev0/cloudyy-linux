import QtQuick
import Quickshell
import "modules/island" as QuickIsland

ShellRoot {
    id: root

    property int failures: 0
    property var timerLoaderBefore: null
    property var timerItemBefore: null

    function check(condition, label) {
        if (condition)
            return;
        root.failures++;
        console.error("TASK4_CAROUSEL_RUNTIME_FAIL " + label);
    }

    function pageComponent(id) {
        if (id === "media") return mediaPage;
        if (id === "timer") return timerPage;
        if (id === "notifications") return notificationsPage;
        return agentsPage;
    }

    function activation(id) {
        if (id === "timer" || id === "agents") return "expand";
        if (id === "notifications") return "controlCenter";
        return "stayCompact";
    }

    function integration(id, available, tick) {
        return {
            id: id,
            displayName: id,
            detected: true,
            hasData: available,
            pageComponent: root.pageComponent(id),
            activation: root.activation(id),
            restingSummary: null,
            restingPriority: 0,
            statusText: "tick " + tick
        };
    }

    function findByName(item, name) {
        if (!item)
            return null;
        if (item.objectName === name)
            return item;
        const children = item.children ?? [];
        for (let i = 0; i < children.length; i++) {
            const found = root.findByName(children[i], name);
            if (found)
                return found;
        }
        return null;
    }

    QtObject {
        id: registry

        property var integrations: []
        property var availablePages: []
        property var availablePageIds: []
        property int revision: 0

        function integrationById(id) {
            for (let i = 0; i < integrations.length; i++) {
                if (integrations[i].id === id)
                    return integrations[i];
            }
            return null;
        }

        function publish(ids, tick) {
            const order = ["media", "timer", "notifications", "agents"];
            const nextIntegrations = [];
            const nextPages = [];
            for (let i = 0; i < order.length; i++) {
                const available = ids.indexOf(order[i]) !== -1;
                const item = root.integration(order[i], available, tick);
                nextIntegrations.push(item);
                if (available)
                    nextPages.push(item);
            }
            integrations = nextIntegrations;
            availablePageIds = ids.slice();
            availablePages = nextPages;
            revision++;
        }
    }

    Component { id: mediaPage; Item { objectName: "media-content" } }
    Component { id: timerPage; Item { objectName: "timer-content" } }
    Component { id: notificationsPage; Item { objectName: "notifications-content" } }
    Component { id: agentsPage; Item { objectName: "agents-content" } }

    QuickIsland.IslandNavigationState {
        id: navigationState
        registry: registry
    }

    Item {
        width: 400
        height: 120

        QuickIsland.IslandCarousel {
            id: carousel
            anchors.fill: parent
            registry: registry
            navigationState: navigationState
        }
    }

    Timer {
        id: initialTimer
        interval: 30
        onTriggered: {
            root.timerLoaderBefore = root.findByName(carousel, "island-page-loader-timer");
            root.timerItemBefore = root.timerLoaderBefore?.item ?? null;
            root.check(root.timerLoaderBefore !== null, "initial timer delegate exists");
            root.check(root.timerItemBefore !== null, "initial timer content exists");
            registry.publish(["media", "timer", "notifications", "agents"], 2);
            Qt.callLater(root.verifyDataPublication);
        }
    }

    function verifyDataPublication() {
        const timerLoaderAfter = root.findByName(carousel, "island-page-loader-timer");
        root.check(timerLoaderAfter === root.timerLoaderBefore,
            "data-only publication preserves delegate identity");
        root.check(timerLoaderAfter?.item === root.timerItemBefore,
            "data-only publication preserves page object identity");
        navigationState.showPage("timer", "test");
        animationTimer.start();
    }

    Timer {
        id: animationTimer
        interval: 40
        onTriggered: {
            const row = root.findByName(carousel, "island-page-row");
            root.check(row !== null, "animated page row exists");
            root.check(row && row.x < 0 && row.x > -carousel.width,
                "page transition is in flight");
            registry.publish(["media", "notifications", "agents"], 3);
            Qt.callLater(root.verifyRemoval);
        }
    }

    function verifyRemoval() {
        const row = root.findByName(carousel, "island-page-row");
        const currentLoader = root.findByName(
            carousel, "island-page-loader-notifications");
        root.check(navigationState.currentPage === "notifications",
            "removed timer repairs to configured right neighbor");
        root.check(navigationState.rememberedPage === "timer",
            "removed timer stays remembered");
        root.check(carousel.pageCount === 3, "removal keeps nonempty carousel");
        root.check(currentLoader?.item !== null,
            "repaired current page has live content");
        root.check(row && Number.isFinite(row.x)
                && row.x <= 0
                && row.x >= -carousel.width * (carousel.pageCount - 1),
            "animation remains within carousel bounds");
        settleTimer.start();
    }

    Timer {
        id: settleTimer
        interval: 260
        onTriggered: {
            const row = root.findByName(carousel, "island-page-row");
            root.check(row && Math.abs(row.x + carousel.width) < 1,
                "repaired animation settles on current page");
            registry.publish(["media", "timer", "notifications", "agents"], 4);
            returnTimer.start();
        }
    }

    Timer {
        id: returnTimer
        interval: 260
        onTriggered: {
            const currentLoader = root.findByName(carousel, "island-page-loader-timer");
            root.check(navigationState.currentPage === "timer",
                "remembered page returns when available");
            root.check(currentLoader?.item !== null,
                "returned page has live content");
            if (root.failures === 0)
                console.info("TASK4_CAROUSEL_RUNTIME_PASS");
            Qt.callLater(Qt.quit);
        }
    }

    Component.onCompleted: {
        registry.publish(["media", "timer", "notifications", "agents"], 1);
        navigationState.showPage("media", "test");
        initialTimer.start();
    }
}
