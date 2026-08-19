pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../notifpanel" as QuickNotifPanel
import "../timer" as QuickTimer
import "." as QuickIsland

Singleton {
    id: root

    property alias integrations: registry.integrations
    property alias availablePages: registry.availablePages
    property alias availablePageIds: registry.availablePageIds
    property alias activeRestingSummary: registry.activeRestingSummary
    property alias revision: registry.revision
    property alias settingsError: registry.settingsError
    readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") || "") + "/.config")
        + "/cloud-center/settings/quickshell/island-integrations.json"

    function integrationById(id) {
        return registry.integrationById(id);
    }

    function isPageAvailable(id) {
        return registry.isPageAvailable(id);
    }

    function reloadSettings() {
        settingsFile.reload();
    }

    Component {
        id: notificationsPageComponent
        QuickIsland.NotificationsPage {}
    }

    Component {
        id: mediaPageComponent
        QuickIsland.MediaPage {}
    }

    Component {
        id: agentsPageComponent
        QuickIsland.AgentsPage {}
    }

    IslandIntegrationRegistryModel {
        id: registry
        notificationService: QuickNotifPanel.NotifPanelService
        timerService: QuickTimer.TimerService
        mprisFocus: QuickIsland.MprisFocus
        agentsService: QuickIsland.AgentsService
        dynamicIslandService: QuickIsland.DynamicIslandService
        mediaPlayingState: MprisPlaybackState.Playing
        notificationsPageComponent: notificationsPageComponent
        mediaPageComponent: mediaPageComponent
        agentsPageComponent: agentsPageComponent
    }

    FileView {
        id: settingsFile
        path: root.settingsPath
        watchChanges: true
        onFileChanged: root.reloadSettings()
        onLoaded: registry.applySettings(text())
        onLoadFailed: registry.settingsLoadFailed()
    }
}
