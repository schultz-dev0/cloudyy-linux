pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "overview/modules/overview" as QuickOverview
import "modules/dock" as QuickDock
import "modules/spotlight" as QuickSpotlight

ShellRoot {
    id: root

    // ── Global state ────────────────────────────────────────────────────────
    property bool notifOpen: false
    property bool dnd: false

    // ── Notification service ─────────────────────────────────────────────────
    NotificationServer {
        id: notifServer
        keepOnReload: true
        onNotification: notif => {
            if (root.dnd) notif.expire()
        }
    }

    // ── IPC — called by bindings.conf ────────────────────────────────────────
    IpcHandler {
        target: "notifs"
        function toggle()      { root.notifOpen = !root.notifOpen }
        function dnd()         { root.dnd = !root.dnd }
        function dismissLast() {
            const list = notifServer.trackedNotifications.values
            if (list.length > 0) list[list.length - 1].dismiss()
        }
    }

    // The overview repo manages its own IPC ("overview") inside its modules!
    // So we don't need the custom IPC handler here anymore.

    // ── Components ───────────────────────────────────────────────────────────
    Bar {
        notifOpen: root.notifOpen
        dnd:       root.dnd
        onNotifToggle: root.notifOpen = !root.notifOpen
    }

    NotifPanel {
        open:          root.notifOpen
        dnd:           root.dnd
        notifServer:   notifServer
        onClose:       root.notifOpen = false
        onDndToggle:   root.dnd = !root.dnd
    }

    QuickOverview.Overview {}

    QuickDock.Dock {}

    QuickSpotlight.Spotlight {}
}
