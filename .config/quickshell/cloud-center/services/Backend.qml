pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: backend

    readonly property string ccRoot: Quickshell.env("HOME") + "/cloudyy-linux/cloud-center"
    readonly property string backendOverride: Quickshell.env("CC_BACKEND_CMD") ?? ""

    property bool ready: false
    property bool failed: false
    property string failureText: ""
    property int nextId: 1
    property var pending: ({})      // id -> callback or { success, error }
    property int crashCount: 0

    signal stateEvent(string item, string key, bool value)
    signal labelEvent(string item, string text)
    signal wallpapersEvent(string item, var wallpapers)
    signal toastEvent(string text)
    signal actionDone(string item, bool ok)
    signal modelLoaded(var model)
    signal monitorLayoutEvent(string state, string message)
    signal cursorVisibilityEvent(string state, bool value, string message)
    signal audioSnapshotEvent(var snapshot)
    signal audioActionDoneEvent(string actionId, string target, int generation, bool ok, bool staleTarget, string message)
    signal audioServiceStatusEvent(var status, string message)
    signal bluetoothSnapshotEvent(var snapshot)
    signal bluetoothActionDoneEvent(string actionId, string target, int generation, bool ok, bool staleTarget, string message)
    signal wifiSnapshotEvent(var snapshot)
    signal wifiActionDoneEvent(string actionId, string target, int generation, bool ok, bool staleTarget, string message)
    signal batterySnapshotEvent(var snapshot)
    signal batteryActionDoneEvent(string actionId, string target, int generation, bool ok, bool staleTarget, string message)
    signal regionSnapshotEvent(var snapshot)
    signal regionActionDoneEvent(string actionId, string target, int generation, bool ok, bool staleTarget, string message)
    signal bezierEditorRequested()

    function requestBezierEditor() {
        bezierEditorRequested();
    }

    // The fourth callback is deliberately optional. Existing callers retain
    // their function-valued pending entries and success-only behavior.
    function request(method, params, callback, errorCallback) {
        const id = nextId++;
        if (typeof errorCallback === "function")
            pending[id] = { success: callback, error: errorCallback };
        else if (typeof callback === "function")
            pending[id] = callback;
        const line = JSON.stringify({ id: id, method: method, params: params ?? {} });
        proc.write(line + "\n");
    }

    function normalizeError(error) {
        if (error && typeof error === "object") {
            const normalized = {};
            for (const key in error)
                normalized[key] = error[key];
            if (!normalized.message)
                normalized.message = String(normalized.error || "Unknown backend error");
            return normalized;
        }
        return { message: String(error || "Unknown backend error"), error: error };
    }

    function handleLine(line) {
        let msg;
        try { msg = JSON.parse(line); } catch (e) { console.warn("ccd: bad line", line); return; }
        if (msg.id !== undefined) {
            const entry = pending[msg.id];
            delete pending[msg.id];
            if (msg.ok) {
                if (typeof entry === "function")
                    entry(msg.result);
                else if (entry && typeof entry.success === "function")
                    entry.success(msg.result);
            } else {
                const error = normalizeError(msg.error);
                if (entry && typeof entry !== "function" && typeof entry.error === "function")
                    entry.error(error);
                else
                    console.warn("ccd error:", error.message);
            }
            return;
        }
        switch (msg.event) {
        case "state":  stateEvent(msg.item, msg.key, msg.value); break;
        case "label":  labelEvent(msg.item, msg.text); break;
        case "wallpapers": wallpapersEvent(msg.item, msg.wallpapers); break;
        case "toast":  toastEvent(msg.text); break;
        case "action_done": actionDone(msg.item, msg.ok); break;
        case "monitor_layout": monitorLayoutEvent(msg.state ?? "", msg.message ?? ""); break;
        case "cursor_visibility": cursorVisibilityEvent(msg.state ?? "", msg.value ?? false, msg.message ?? ""); break;
        case "audio_snapshot":
            audioSnapshotEvent(msg.snapshot ?? ({})); break;
        case "audio_action_done":
            audioActionDoneEvent(String(msg.action_id ?? ""), String(msg.target ?? ""),
                Number(msg.generation ?? 0), msg.ok ?? false, msg.stale_target ?? false,
                msg.message ?? ""); break;
        case "audio_service_status":
            audioServiceStatusEvent(msg.status ?? ({}), msg.message ?? ""); break;
        case "bluetooth_snapshot":
            bluetoothSnapshotEvent(msg.snapshot ?? ({})); break;
        case "bluetooth_action_done":
            bluetoothActionDoneEvent(String(msg.action_id ?? ""), String(msg.target ?? ""),
                Number(msg.generation ?? 0), msg.ok ?? false, msg.stale_target ?? false,
                msg.message ?? ""); break;
        case "wifi_snapshot":
            wifiSnapshotEvent(msg.snapshot ?? ({})); break;
        case "wifi_action_done":
            wifiActionDoneEvent(String(msg.action_id ?? ""), String(msg.target ?? ""),
                Number(msg.generation ?? 0), msg.ok ?? false, msg.stale_target ?? false,
                msg.message ?? ""); break;
        case "battery_snapshot":
            batterySnapshotEvent(msg.snapshot ?? ({})); break;
        case "battery_action_done":
            batteryActionDoneEvent(String(msg.action_id ?? ""), String(msg.target ?? ""),
                Number(msg.generation ?? 0), msg.ok ?? false, msg.stale_target ?? false,
                msg.message ?? ""); break;
        case "region_snapshot":
            regionSnapshotEvent(msg.snapshot ?? ({})); break;
        case "region_action_done":
            regionActionDoneEvent(String(msg.action_id ?? ""), String(msg.target ?? ""),
                Number(msg.generation ?? 0), msg.ok ?? false, msg.stale_target ?? false,
                msg.message ?? ""); break;
        }
    }

    function loadModel() {
        request("get_model", null, function(result) {
            ready = true;
            // A served model means the backend is healthy again — restore the
            // full respawn-once allowance for the next outage.
            crashCount = 0;
            modelLoaded(result);
        });
    }

    // Dev convenience: config.yaml is plain data read by the Python sidecar,
    // not a QML file Quickshell's own reload watches, so nothing normally
    // reacts to editing it short of relaunching. Same FileView+watchChanges
    // pattern Theme.qml (../../Theme.qml) already uses to hot-reload colors —
    // Quickshell's own inotify-backed watcher, not a hand-rolled poll loop.
    // load_model() re-parses config.yaml fresh on every get_model call, so
    // this just needs to ask again; no separate reload-only backend path.
    FileView {
        path: backend.ccRoot + "/config.yaml"
        watchChanges: true
        onFileChanged: backend.loadModel()
    }

    Process {
        id: proc
        command: backend.backendOverride !== ""
            ? ["bash", "-c", backend.backendOverride]
            : ["python3", "-m", "lib.ccd"]
        workingDirectory: backend.ccRoot
        running: true
        stdinEnabled: true
        stdout: SplitParser { onRead: line => backend.handleLine(line) }
        // Process startup is async (setRunning(true) kicks off the OS spawn but
        // `running` only flips true once QProcess actually enters the Running
        // state); writing from Component.onCompleted races that and the very
        // first request gets silently dropped. Send it from onStarted instead,
        // which also doubles as the respawn trigger below.
        onStarted: backend.loadModel()
        onExited: (code, status) => {
            // Detach first so error callbacks may issue fresh requests without
            // touching this exit generation's callbacks.
            const detachedPending = backend.pending;
            backend.pending = ({});
            const dropped = Object.keys(detachedPending).length;
            if (dropped > 0)
                console.warn("ccd exited with", dropped, "request(s) in flight");
            const exitError = backend.normalizeError({
                error: "backend-exited",
                message: "Backend exited (code " + code + ")",
                code: code,
                status: String(status),
            });
            for (const id in detachedPending) {
                const entry = detachedPending[id];
                // Function entries predate opt-in error callbacks, so retain
                // their success-only behavior on backend exit.
                if (entry && typeof entry !== "function" && typeof entry.error === "function") {
                    try { entry.error(exitError); } catch (error) {
                        console.warn("ccd exit error callback failed:", error);
                    }
                }
            }
            backend.crashCount++;
            if (backend.crashCount <= 1) {
                console.warn("ccd exited, respawning once");
                proc.running = true;
            } else {
                backend.failed = true;
                backend.failureText = "Backend exited twice (code " + code + ")";
            }
        }
    }
}
