pragma Singleton

import QtQuick

// Persists notifications for NotifPanel (NotificationServer.trackedNotifications).
// Island display is separate; call track() for every non-DND notification.
QtObject {
    function track(notif) {
        if (notif)
            notif.tracked = true;
    }
}
