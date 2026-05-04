pragma Singleton
pragma ComponentBehavior: Bound

// modules/calendar/CalendarService.qml
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // ── State ─────────────────────────────────────────────────────────────────
    property var    events:         []
    property var    markedDays:     ({})
    property bool   loaded:         false

    // ── Date helpers ──────────────────────────────────────────────────────────
    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd")
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    // Returns 0=Mon … 6=Sun for the first day of a given month
    function firstWeekday(year, month) {
        return (new Date(year, month, 1).getDay() + 6) % 7
    }

    function dateKey(year, month, day) {
        return Qt.formatDate(new Date(year, month, day), "yyyy-MM-dd")
    }

    function monthLabel(year, month) {
        return Qt.formatDate(new Date(year, month, 1), "MMMM yyyy")
    }

    function dayOfWeekLabel(year, month, day) {
        return Qt.formatDate(new Date(year, month, day), "dddd d MMMM")
    }

    function friendlyDate(dateStr) {
        const t = today()
        const d = new Date(dateStr + "T00:00:00")
        if (dateStr === t) return "Today"
        const tomorrow = new Date(); tomorrow.setDate(tomorrow.getDate() + 1)
        if (dateStr === Qt.formatDate(tomorrow, "yyyy-MM-dd")) return "Tomorrow"
        return Qt.formatDate(d, "ddd d MMM")
    }

    function generateId() {
        return Math.random().toString(36).substr(2, 9) + Date.now().toString(36)
    }

    // ── Queries ───────────────────────────────────────────────────────────────
    function eventsForDate(dateStr) {
        return root.events.filter(e => e.date === dateStr).sort((a, b) => {
            if (a.allDay && !b.allDay) return -1
            if (!a.allDay && b.allDay) return 1
            return (a.startTime || "00:00").localeCompare(b.startTime || "00:00")
        })
    }

    function hasEventsOnDate(dateStr) {
        return root.events.some(e => e.date === dateStr)
    }

    // Returns up to n upcoming events from today onwards, sorted by date/time
    function upcomingEvents(n) {
        const t = today()
        return root.events
            .filter(e => e.date >= t)
            .sort((a, b) => {
                const dc = a.date.localeCompare(b.date)
                if (dc !== 0) return dc
                return (a.startTime || "").localeCompare(b.startTime || "")
            })
            .slice(0, n)
    }

    // Returns up to 3 color-tag strings for dot indicators on a grid cell
    function dotsForDate(dateStr) {
        return eventsForDate(dateStr).slice(0, 3).map(e => e.color || "primary")
    }

    // ── CRUD ──────────────────────────────────────────────────────────────────
    function addEvent(ev) {
        const e = Object.assign({ id: generateId(), color: "primary", allDay: false, description: "" }, ev)
        root.events = [...root.events, e]
        save()
        return e.id
    }

    function updateEvent(id, changes) {
        root.events = root.events.map(e => e.id === id ? Object.assign({}, e, changes) : e)
        save()
    }

    function removeEvent(id) {
        root.events = root.events.filter(e => e.id !== id)
        save()
    }

    function setMarkedDay(dateStr, color, note) {
        const m = Object.assign({}, root.markedDays)
        m[dateStr] = { color: color || "primary", note: note || "" }
        root.markedDays = m
        save()
    }

    function clearMarkedDay(dateStr) {
        const m = Object.assign({}, root.markedDays)
        delete m[dateStr]
        root.markedDays = m
        save()
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    function save() {
        const payload = JSON.stringify({ events: root.events, markedDays: root.markedDays })
        saveProc.environment = ({ "QS_DATA": payload })
        saveProc.running = false
        saveProc.running = true
    }

    // ── Processes ─────────────────────────────────────────────────────────────
    Process {
        id: initProc
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/calendar\";" +
            "mkdir -p \"$dir\";" +
            "[ -r \"$dir/events.json\" ] && cat \"$dir/events.json\" || echo '{}'"
        ]
        stdout: StdioCollector {
            id: initCollector
            onStreamFinished: {
                const text = initCollector.text.trim()
                if (!text || text === "{}") { root.loaded = true; return }
                try {
                    const parsed    = JSON.parse(text)
                    root.events     = parsed.events     || []
                    root.markedDays = parsed.markedDays || {}
                } catch (err) {
                    console.warn("calendar: failed to parse events.json:", err)
                }
                root.loaded = true
            }
        }
    }

    Process {
        id: saveProc
        running: false
        command: [
            "sh", "-lc",
            "dir=\"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/calendar\";" +
            "printf '%s' \"$QS_DATA\" > \"$dir/events.json\""
        ]
    }

    Component.onCompleted: {
        initProc.running = true
    }
}
