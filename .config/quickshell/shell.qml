pragma ComponentBehavior: Bound

// shell.qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import "modules/dock" as QuickDock
import "modules/sliders" as QuickSliders
import "modules/calendar" as QuickCalendar
import "modules/spotlight" as QuickSpotlight
import "modules/calculator" as QuickCalculator
import "modules/timer" as QuickTimer
import "modules/systemmonitor" as QuickSystemMonitor
import "modules/island" as QuickIsland
import "modules/notifpanel" as QuickNotifPanel
import "overview/modules/overview" as QuickOverview

ShellRoot {
    id: root

    // Suppress built-in "config updated" reload toasts (also set QS_NO_RELOAD_POPUP=1 at launch).
    Connections {
        target: Quickshell
        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup()
        }
        function onReloadFailed(errorString) {
            Quickshell.inhibitReloadPopup()
        }
    }

    // ── Global state ────────────────────────────────────────────────────────
    property bool notifOpen: false
    property bool dnd: false
    property bool calendarOpen: false
    property bool calculatorOpen: false

    // ── Multi-monitor shell layout (Cloud Center → quickshell.json) ─────────
    property bool barOnAllScreens: false
    property bool dockOnAllScreens: false

    function targetScreens(allScreens) {
        const screens = Quickshell.screens;
        if (allScreens || screens.length === 0)
            return screens;

        const focused = Hyprland.focusedMonitor;
        if (focused) {
            for (let i = 0; i < screens.length; i++) {
                if (Hyprland.monitorFor(screens[i])?.name === focused.name)
                    return [screens[i]];
            }
        }
        return [screens[0]];
    }

    readonly property var barScreens: targetScreens(barOnAllScreens)
    readonly property var dockScreens: {
        const _fm = Hyprland.focusedMonitor; // register as dep so binding re-evaluates on monitor focus change
        return root.targetScreens(root.dockOnAllScreens);
    }

    function barIpcEnabled(screen) {
        if (!barOnAllScreens)
            return true;
        const monitor = Hyprland.monitorFor(screen);
        return monitor?.id === Hyprland.focusedMonitor?.id;
    }

    function dockIpcEnabled(screen) {
        if (!dockOnAllScreens)
            return true;
        const monitor = Hyprland.monitorFor(screen);
        return monitor?.id === Hyprland.focusedMonitor?.id;
    }

    Process {
        id: loadShellSettings
        command: [
            "python3",
            "-c",
            "import json, os\n"
                + "from pathlib import Path\n"
                + "cfg = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))\n"
                + "base = cfg / 'cloud-center/settings/monitors/quickshell'\n"
                + "legacy = cfg / 'cloud-center/settings/monitors/quickshell.json'\n"
                + "def read_bool(path):\n"
                + "    if not path.is_file():\n"
                + "        return False\n"
                + "    return path.read_text().strip().lower() in ('true', 'yes', '1', 'on')\n"
                + "bar = read_bool(base / 'bar_on_all_screens')\n"
                + "dock = read_bool(base / 'dock_on_all_screens')\n"
                + "if legacy.is_file() and not (base / 'bar_on_all_screens').is_file():\n"
                + "    data = json.loads(legacy.read_text())\n"
                + "    bar = bool(data.get('bar_on_all_screens', False))\n"
                + "    dock = bool(data.get('dock_on_all_screens', False))\n"
                + "print(json.dumps({'bar_on_all_screens': bar, 'dock_on_all_screens': dock}))",
        ]
        stdout: StdioCollector {
            id: shellSettingsCollector
            onStreamFinished: {
                const payload = shellSettingsCollector.text.trim();
                if (!payload)
                    return;

                try {
                    const parsed = JSON.parse(payload);
                    if (typeof parsed !== "object" || parsed === null)
                        return;
                    if (typeof parsed.bar_on_all_screens === "boolean")
                        root.barOnAllScreens = parsed.bar_on_all_screens;
                    if (typeof parsed.dock_on_all_screens === "boolean")
                        root.dockOnAllScreens = parsed.dock_on_all_screens;
                } catch (error) {
                    console.warn("shell: failed to parse shell display settings", error);
                }
            }
        }
    }

    readonly property string screenshotPendingPathFile: "/tmp/cloudyy-screenshot.path"
    readonly property string recordingPendingPathFile: "/tmp/cloudyy-recording.path"

    Component {
        id: screenshotActivityComp
        QuickIsland.ScreenshotActivity {}
    }

    Component {
        id: recordingActivityComp
        QuickIsland.RecordingActivity {}
    }

    Component {
        id: recordPickerActivityComp
        QuickIsland.RecordPickerActivity {}
    }

    readonly property string recordingsDir: {
        const home = Quickshell.env("HOME") || "";
        const videos = Quickshell.env("XDG_VIDEOS_DIR") || (home ? home + "/Videos" : "");
        return videos ? (videos + "/Captures") : "";
    }

    readonly property string playSoundScript: {
        const home = Quickshell.env("HOME") || "";
        return home ? (home + "/.config/quickshell/play_sound.sh") : "";
    }

    Component {
        id: shellProcProto
        Process {}
    }

    Process {
        id: screenshotPathReader
        running: false
        stdout: SplitParser {
            onRead: line => {
                const path = line.trim();
                if (path)
                    QuickIsland.DynamicIslandService.showScreenshotPreview(path, screenshotActivityComp);
            }
        }
    }

    Process {
        id: recordingPathReader
        running: false
        stdout: SplitParser {
            onRead: line => {
                const path = line.trim();
                if (path)
                    QuickIsland.DynamicIslandService.showRecordingPreview(path, recordingActivityComp);
            }
        }
    }

    Component.onCompleted: {
        QuickIsland.DynamicIslandService.procFactory = shellProcProto;
        QuickIsland.DynamicIslandService.recordPickerComponent = recordPickerActivityComp;
        QuickIsland.DynamicIslandService.recordingPreviewComponent = recordingActivityComp;
        QuickIsland.DynamicIslandService.recordingsDir = root.recordingsDir;
        QuickIsland.DynamicIslandService.playSoundScript = root.playSoundScript;
        loadShellSettings.running = true;
    }

    // ── Notification service ─────────────────────────────────────────────────
    NotificationServer {
        id: notifServer
        keepOnReload: true
        persistenceSupported: true
        onNotification: notif => {
            if (root.dnd) {
                notif.expire();
                return;
            }

            // NotifPanel reads trackedNotifications — persist before island/lastGeneration checks.
            QuickNotifPanel.NotifPanelService.track(notif);

            if (notif.lastGeneration)
                return;

            QuickIsland.DynamicIslandService.playNotifSound();

            const islandId = QuickIsland.DynamicIslandService.push({
                priority:   10,
                durationMs: QuickIsland.DynamicIslandService.notificationIslandDurationMs(
                                  notif.expireTimeout),
                data: {
                    notificationId: notif.id,
                    appName:        notif.appName || "",
                    summary:        notif.summary || "",
                    body:           notif.body || "",
                    urgency:        notif.urgency
                }
            });

            // Island timeout is visual-only; panel keeps the notification until dismiss/clearAll.
            notif.closed.connect(() => {
                QuickIsland.DynamicIslandService.remove(islandId);
                QuickIsland.DynamicIslandService.removeForNotification(notif.id);
            });
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

    IpcHandler {
        target: "timer"
        function toggle() { QuickTimer.TimerService.open = !QuickTimer.TimerService.open }
        function show()   { QuickTimer.TimerService.open = true }
        function hide()   { QuickTimer.TimerService.open = false }
    }

    IpcHandler {
        target: "system"
        function toggle() { QuickSystemMonitor.SystemMonitorService.toggleOpen() }
        function show()   { QuickSystemMonitor.SystemMonitorService.open = true }
        function hide()   { QuickSystemMonitor.SystemMonitorService.open = false }
    }

    IpcHandler {
        target: "screenshot"
        function showLatest() {
            screenshotPathReader.command = ["cat", root.screenshotPendingPathFile];
            screenshotPathReader.running = true;
        }
        function show(path: string) {
            QuickIsland.DynamicIslandService.showScreenshotPreview(path, screenshotActivityComp);
        }
        function dismiss() {
            QuickIsland.DynamicIslandService.dismissCurrentScreenshot();
        }
    }

    IpcHandler {
        target: "record"
        function toggle() {
            QuickIsland.DynamicIslandService.toggleRecording();
        }
        function showLatest() {
            recordingPathReader.command = ["cat", root.recordingPendingPathFile];
            recordingPathReader.running = true;
        }
        function show(path: string) {
            QuickIsland.DynamicIslandService.showRecordingPreview(path, recordingActivityComp);
        }
        function dismiss() {
            QuickIsland.DynamicIslandService.dismissCurrentRecording();
        }
    }

    // Overview owns its own IPC ("overview") inside QuickOverview.Overview.

    // ── Components ───────────────────────────────────────────────────────────
    Variants {
        id: barVariants
        model: root.barScreens

        Bar {
            required property var modelData
            assignedScreen: modelData
            ipcEnabled: root.barIpcEnabled(modelData)
            notifOpen: root.notifOpen
            dnd: root.dnd
            onNotifToggle: root.notifOpen = !root.notifOpen
            onCalendarToggle: root.calendarOpen = !root.calendarOpen
        }
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

    QuickIsland.DynamicIsland {}

    Variants {
        id: dockVariants
        model: root.dockScreens

        QuickDock.Dock {
            required property var modelData
            assignedScreen: modelData
            ipcEnabled: root.dockIpcEnabled(modelData)
        }
    }

    QuickOverview.Overview {}

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

    QuickTimer.TimerPanel {}

    QuickSystemMonitor.SystemOverviewPanel {
        notifOpen: root.notifOpen
    }
}
