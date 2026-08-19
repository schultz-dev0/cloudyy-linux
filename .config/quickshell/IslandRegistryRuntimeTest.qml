import QtQuick
import Quickshell
import "modules/island" as QuickIsland

ShellRoot {
    id: root

    property int failures: 0

    function check(condition, label) {
        if (condition)
            return;
        root.failures++;
        console.error("TASK3_REGISTRY_RUNTIME_FAIL " + label);
    }

    function validSettings(order, enabled) {
        return JSON.stringify({ version: 1, order: order, enabled: enabled });
    }

    QtObject {
        id: notificationService
        property int unreadCount: 0
        property var latestNotification: null
    }

    QtObject {
        id: timerRecords
        property int count: 0
    }

    QtObject {
        id: timerService
        property bool loaded: true
        property int presentationEpoch: 0
        property var timers: timerRecords
        property var nearestCountdown: null
        function displaySeconds(timer) { return timer.remainingSeconds; }
    }

    QtObject {
        id: firstPlayer
        property int playbackState: 1
        property string trackTitle: "First title"
        property string trackArtist: "First artist"
    }

    QtObject {
        id: secondPlayer
        property int playbackState: 1
        property string trackTitle: "Second title"
        property string trackArtist: "Second artist"
    }

    QtObject {
        id: mprisFocus
        property var activePlayer: firstPlayer
    }

    QtObject {
        id: agentsService
        property bool hasData: false
        property var usageRecords: []
        property var liveSessions: []
        property var oldestSession: null
    }

    QtObject {
        id: dynamicIslandService
        property bool recordingActive: false
        property double recordingStartedAt: 0
    }

    Component { id: emptyPage; Item {} }

    QuickIsland.IslandIntegrationRegistryModel {
        id: registry
        notificationService: notificationService
        timerService: timerService
        mprisFocus: mprisFocus
        agentsService: agentsService
        dynamicIslandService: dynamicIslandService
        mediaPlayingState: 1
        notificationsPageComponent: emptyPage
        mediaPageComponent: emptyPage
        agentsPageComponent: emptyPage
    }

    function runContracts() {
        notificationService.unreadCount = 1;
        notificationService.latestNotification = {
            appName: "Mail", summary: "Message"
        };
        registry.applySettings(root.validSettings(
            ["media", "timer", "notifications", "agents"],
            { notifications: true, timer: false, media: true, agents: false }
        ));
        root.check(registry.availablePageIds.join(",") === "media,notifications",
            "valid settings order");
        root.check(registry.integrations.map(item => item.id).join(",")
                === "media,timer,notifications,agents",
            "full integrations use configured order");

        let revisionBefore = registry.revision;
        registry.applySettings("{malformed");
        root.check(registry.availablePageIds.join(",") === "media,notifications",
            "malformed settings retain last valid order");
        root.check(registry.settingsError === "Invalid island integration settings",
            "malformed settings publish safe error");
        root.check(registry.revision === revisionBefore,
            "malformed settings retain revision");

        const integrationsBefore = registry.integrations;
        const pagesBefore = registry.availablePages;
        const idsBefore = registry.availablePageIds;
        revisionBefore = registry.revision;
        registry.applySettings(root.validSettings(
            ["notifications", "media", "timer", "agents"],
            { notifications: true, timer: false, media: false, agents: false }
        ));
        root.check(registry.integrations !== integrationsBefore,
            "valid settings replace integrations array");
        root.check(registry.availablePages !== pagesBefore,
            "valid settings replace pages array");
        root.check(registry.availablePageIds !== idsBefore,
            "valid settings replace page ids array");
        root.check(registry.revision === revisionBefore + 1,
            "valid settings increment revision");

        notificationService.unreadCount = 0;
        registry.applySettings(root.validSettings(
            ["notifications", "timer", "media", "agents"],
            { notifications: false, timer: false, media: false, agents: false }
        ));
        root.check(registry.availablePageIds.length === 0,
            "all pages disabled for hidden media test");

        revisionBefore = registry.revision;
        const hiddenIntegrationsBefore = registry.integrations;
        firstPlayer.trackTitle = "<b>Literal title</b>";
        root.check(registry.revision === revisionBefore,
            "hidden media metadata signal does not increment revision");
        root.check(registry.integrations !== hiddenIntegrationsBefore,
            "hidden media metadata replaces integrations array");
        root.check(registry.activeRestingSummary.title === "<b>Literal title</b>",
            "hidden media metadata republishes resting summary");

        revisionBefore = registry.revision;
        mprisFocus.activePlayer = secondPlayer;
        root.check(registry.revision === revisionBefore,
            "active player replacement retains revision");
        root.check(registry.activeRestingSummary.title === "Second title",
            "active player replacement republishes metadata");

        revisionBefore = registry.revision;
        secondPlayer.playbackState = 0;
        root.check(registry.revision === revisionBefore,
            "playback signal retains revision");
        root.check(registry.activeRestingSummary.kind === "neutral",
            "paused hidden player clears media resting summary");

        if (root.failures === 0)
            console.info("TASK3_REGISTRY_RUNTIME_PASS");
        Qt.callLater(Qt.quit);
    }

    Component.onCompleted: Qt.callLater(root.runContracts)
}
