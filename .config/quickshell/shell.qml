pragma ComponentBehavior: Bound

// shell.qml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import "overview/modules/overview" as QuickOverview
import "modules/dock" as QuickDock
import "modules/sliders" as QuickSliders
import "modules/calendar" as QuickCalendar
import "modules/spotlight" as QuickSpotlight
import "modules/calculator" as QuickCalculator

ShellRoot {
    id: root

    // ── Global state ────────────────────────────────────────────────────────
    property bool notifOpen: false
    property bool dnd: false
    property bool calendarOpen: false
    property bool calculatorOpen: false

    // ── Notification service ─────────────────────────────────────────────────
    NotificationServer {
        id: notifServer
        keepOnReload: true
        onNotification: notif => {
            if (root.dnd) {
                notif.expire();
                return;
            }

            notif.tracked = true;

            if (notif.lastGeneration)
                return;
            const popupKey = notifPopups.enqueueNotification(notif);
            notif.closed.connect(() => notifPopups.removePopup(popupKey));
        }
    }

    // ── IPC — called by bindings.conf ────────────────────────────────────────
    IpcHandler {
        target: "notifs"
        function toggle() {
            root.notifOpen = !root.notifOpen;
        }
        function dnd() {
            root.dnd = !root.dnd;
        }
        function dismissLast() {
            const list = notifServer.trackedNotifications.values;
            if (list.length > 0)
                list[list.length - 1].dismiss();
        }
        function clearAll() {
            const list = notifServer.trackedNotifications.values.slice();
            for (const notif of list)
                notif.dismiss();
        }
    }

    IpcHandler {
        target: "calendar"
        function toggle() {
            root.calendarOpen = !root.calendarOpen;
        }
        function nextMonth() {
            calendarPanel.nextMonth();
        }
        function prevMonth() {
            calendarPanel.prevMonth();
        }
        function today() {
            calendarPanel.jumpToToday();
        }
    }

    IpcHandler {
        target: "calculator"
        function toggle() {
            root.calculatorOpen = !root.calculatorOpen;
        }
        function show() {
            root.calculatorOpen = true;
        }
        function hide() {
            root.calculatorOpen = false;
        }
    }

    // The overview repo manages its own IPC ("overview") inside its modules!
    // So we don't need the custom IPC handler here anymore.

    // ── Components ───────────────────────────────────────────────────────────
    Bar {
        notifOpen: root.notifOpen
        dnd: root.dnd
        onNotifToggle: root.notifOpen = !root.notifOpen
        onCalendarToggle: root.calendarOpen = !root.calendarOpen
    }

    QuickSliders.Sliders {
        id: sliderController
    }

    NotifPanel {
        open: root.notifOpen
        dnd: root.dnd
        calculatorOpen: root.calculatorOpen
        notifServer: notifServer
        sliderController: sliderController
        onClose: root.notifOpen = false
        onDndToggle: root.dnd = !root.dnd
        onCalculatorToggle: root.calculatorOpen = !root.calculatorOpen
    }

    NotificationPopups {
        id: notifPopups
        notifServer: notifServer
    }

    QuickOverview.Overview {}

    QuickDock.Dock {}

    QuickCalendar.CalendarPanel {
        id: calendarPanel
        open: root.calendarOpen
    }

    QuickCalculator.Calculator {
        id: calcWindow
        open: root.calculatorOpen
        onRequestClose: root.calculatorOpen = false
    }

    QuickSpotlight.Spotlight {}
}
