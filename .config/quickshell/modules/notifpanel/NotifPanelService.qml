pragma Singleton

import QtQuick

QtObject {
    id: service

    property var latestNotification: null
    property var _unreadIds: ({})
    property var _notifications: []
    readonly property int unreadCount: Object.keys(_unreadIds).length

    signal notificationAdded(var notification)

    function track(notif) {
        if (!notif)
            return;

        notif.tracked = true;
        latestNotification = notif;
        const notifications = _notifications.filter(notification => notification !== notif);
        notifications.push(notif);
        _notifications = notifications;

        const unreadIds = Object.assign({}, _unreadIds);
        unreadIds[String(notif.id)] = true;
        _unreadIds = unreadIds;

        notif.closed.connect(() => {
            const remaining = service._notifications.filter(notification => notification !== notif);
            service._notifications = remaining;
            const unreadIds = Object.assign({}, service._unreadIds);
            const replacement = remaining.some(notification => String(notification.id) === String(notif.id));
            if (!replacement)
                delete unreadIds[String(notif.id)];
            service._unreadIds = unreadIds;
            if (service.latestNotification === notif)
                service.latestNotification = remaining.length
                    ? remaining[remaining.length - 1]
                    : null;
        });
        notificationAdded(notif);
    }

    function markAllRead() {
        _unreadIds = ({});
    }

    function invokeAction(notification, actionId) {
        if (!notification)
            return false;

        const actions = notification.actions;
        for (let i = 0; i < actions.length; i++) {
            const action = actions[i];
            if (action.identifier !== actionId)
                continue;
            action.invoke();
            return true;
        }
        return false;
    }
}
