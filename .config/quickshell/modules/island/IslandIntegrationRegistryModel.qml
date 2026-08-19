import QtQuick
import "IslandRegistryPolicy.js" as Policy

Item {
    id: root

    required property var notificationService
    required property var timerService
    required property var mprisFocus
    required property var agentsService
    required property var dynamicIslandService
    required property int mediaPlayingState
    required property var notificationsPageComponent
    required property var mediaPageComponent
    required property var agentsPageComponent

    property var integrations: []
    property var availablePages: []
    property var availablePageIds: []
    property var activeRestingSummary: ({ kind: "neutral" })
    property int revision: 0
    property string settingsError: ""
    property var _lastPageIds: []
    property var _settings: Policy.defaultSettings()

    visible: false

    function integrationById(id) {
        for (let i = 0; i < root.integrations.length; i++) {
            if (root.integrations[i].id === id)
                return root.integrations[i];
        }
        return null;
    }

    function isPageAvailable(id) {
        return root.availablePageIds.indexOf(id) !== -1;
    }

    function _buildIntegrations() {
        const unreadCount = root.notificationService.unreadCount;
        const latestNotification = root.notificationService.latestNotification;
        const hasNotifications = root.notificationService.unreadCount > 0;
        const hasTimers = root.timerService.timers.count > 0;
        const countdown = root.timerService.nearestCountdown;
        const player = root.mprisFocus.activePlayer;
        const hasMedia = root.mprisFocus.activePlayer !== null;
        const mediaPlaying = hasMedia
            && player.playbackState === root.mediaPlayingState;
        const hasAgents = root.agentsService.hasData;
        const oldestSession = root.agentsService.oldestSession;

        return [
            {
                id: "notifications",
                displayName: "Notifications",
                detected: true,
                hasData: hasNotifications,
                pageComponent: root.notificationsPageComponent,
                activation: "controlCenter",
                restingSummary: hasNotifications ? {
                    kind: "notification",
                    unreadCount: unreadCount,
                    appName: latestNotification?.appName ?? "Notifications",
                    summary: latestNotification?.summary ?? ""
                } : null,
                restingPriority: 10,
                statusText: hasNotifications ? "Detected" : "Waiting for activity"
            },
            {
                id: "timer",
                displayName: "Timers",
                detected: root.timerService.loaded,
                hasData: hasTimers,
                // No island page at all — Command Center (Trigger > Timer)
                // owns create/pause/reset/stop entirely. pageComponent: null
                // means availablePageIds (see IslandRegistryPolicy.js) never
                // includes "timer", so it's never cyclable/pinnable; it only
                // ever surfaces via the resting-pill countdown summary below.
                pageComponent: null,
                activation: "stayCompact",
                restingSummary: countdown ? {
                    kind: "countdown",
                    active: true,
                    label: countdown.label,
                    remainingSeconds: root.timerService.displaySeconds(countdown)
                } : null,
                restingPriority: 40,
                statusText: !root.timerService.loaded ? "Shell status unavailable"
                    : hasTimers ? "Detected" : "Waiting for activity"
            },
            {
                id: "media",
                displayName: "Media",
                detected: hasMedia,
                hasData: hasMedia,
                pageComponent: root.mediaPageComponent,
                activation: "stayCompact",
                restingSummary: mediaPlaying ? {
                    kind: "media",
                    playing: true,
                    title: player.trackTitle || "Unknown track",
                    artist: player.trackArtist || "Unknown artist"
                } : null,
                restingPriority: 30,
                statusText: hasMedia ? "Detected" : "Waiting for activity"
            },
            {
                id: "agents",
                displayName: "Agents",
                detected: true,
                hasData: hasAgents,
                pageComponent: root.agentsPageComponent,
                activation: "expand",
                restingSummary: oldestSession ? {
                    kind: "agent",
                    live: true,
                    startedAt: Date.parse(oldestSession.startedAt),
                    agentName: oldestSession.agentName,
                    projectName: oldestSession.projectName
                } : null,
                restingPriority: 20,
                statusText: hasAgents ? "Detected" : "Waiting for activity"
            }
        ];
    }

    function _selectRestingSummary(nextIntegrations) {
        const summaries = [];
        if (root.dynamicIslandService.recordingActive) {
            summaries.push({
                kind: "recording",
                active: true,
                startedAt: root.dynamicIslandService.recordingStartedAt
            });
        }
        for (let i = 0; i < nextIntegrations.length; i++) {
            if (nextIntegrations[i].restingSummary)
                summaries.push(nextIntegrations[i].restingSummary);
        }
        return Policy.highestRestingSummary(summaries) || { kind: "neutral" };
    }

    function publish() {
        const builtIntegrations = root._buildIntegrations();
        const integrationsById = {};
        for (let i = 0; i < builtIntegrations.length; i++)
            integrationsById[builtIntegrations[i].id] = builtIntegrations[i];
        const nextIntegrations = [];
        for (let i = 0; i < root._settings.order.length; i++) {
            const id = root._settings.order[i];
            nextIntegrations.push(integrationsById[id]);
        }
        const nextPageIds = Policy.availablePageIds(root._settings, nextIntegrations);
        const pageIdsChanged = root._lastPageIds.length !== nextPageIds.length
            || nextPageIds.join(",") !== root._lastPageIds.join(",");
        root._lastPageIds = nextPageIds.slice();
        const nextPages = [];
        for (let i = 0; i < nextPageIds.length; i++) {
            for (let j = 0; j < nextIntegrations.length; j++) {
                if (nextIntegrations[j].id === nextPageIds[i]) {
                    nextPages.push(nextIntegrations[j]);
                    break;
                }
            }
        }
        root.integrations = nextIntegrations.slice();
        root.activeRestingSummary = root._selectRestingSummary(nextIntegrations);
        if (pageIdsChanged) {
            root.availablePageIds = nextPageIds.slice();
            root.availablePages = nextPages.slice();
            root.revision++;
        }
    }

    function republishPresentation() {
        const builtIntegrations = root._buildIntegrations();
        const integrationsById = {};
        for (let i = 0; i < builtIntegrations.length; i++)
            integrationsById[builtIntegrations[i].id] = builtIntegrations[i];
        const nextIntegrations = [];
        for (let i = 0; i < root._settings.order.length; i++) {
            const id = root._settings.order[i];
            nextIntegrations.push(integrationsById[id]);
        }
        root.integrations = nextIntegrations.slice();
        root.activeRestingSummary = root._selectRestingSummary(nextIntegrations);
    }

    function applySettings(raw) {
        let parsed;
        try {
            parsed = JSON.parse(raw);
        } catch (error) {
            root.settingsError = "Invalid island integration settings";
            root.publish();
            return;
        }
        if (!Policy.validSettings(parsed)) {
            root.settingsError = "Invalid island integration settings";
            root.publish();
            return;
        }
        root._settings = Policy.normalizeSettings(parsed, root._settings);
        root.settingsError = "";
        root.publish();
    }

    function settingsLoadFailed() {
        root.settingsError = "Could not load island integration settings";
        root.publish();
    }

    Connections {
        target: root.notificationService
        function onUnreadCountChanged() { root.publish(); }
        function onLatestNotificationChanged() { root.publish(); }
    }

    Connections {
        target: root.timerService
        function onLoadedChanged() { root.publish(); }
        function onPresentationEpochChanged() { root.republishPresentation(); }
    }

    Connections {
        target: root.timerService.timers
        ignoreUnknownSignals: true
        function onCountChanged() { root.publish(); }
        function onDataChanged() { root.publish(); }
        function onRowsInserted() { root.publish(); }
        function onRowsRemoved() { root.publish(); }
        function onModelReset() { root.publish(); }
    }

    Connections {
        target: root.mprisFocus
        function onActivePlayerChanged() { root.publish(); }
    }

    Connections {
        target: root.mprisFocus.activePlayer
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { root.republishPresentation(); }
        function onTrackArtistChanged() { root.republishPresentation(); }
        function onPlaybackStateChanged() { root.republishPresentation(); }
    }

    Connections {
        target: root.agentsService
        function onUsageRecordsChanged() { root.publish(); }
        function onLiveSessionsChanged() { root.publish(); }
    }

    Connections {
        target: root.dynamicIslandService
        function onRecordingActiveChanged() { root.republishPresentation(); }
        function onRecordingStartedAtChanged() { root.republishPresentation(); }
    }

    Component.onCompleted: root.publish()
}
