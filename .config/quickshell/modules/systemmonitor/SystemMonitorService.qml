pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property int historyMax: 60
    readonly property int pollIntervalMs: 2000

    property bool open: false
    property bool stale: false
    property bool daemonManaged: false

    property int cpuPercent: 0
    property int cpuAvgPercent: 0
    property int cpuTempC: 0
    property real cpuFreqGhz: 0
    property string cpuModel: ""
    property int cpuCores: 0
    property var cpuHistory: []

    property int ramPercent: 0
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real swapUsedGb: 0
    property real swapTotalGb: 0
    property int swapPercent: 0
    property var ramHistory: []

    property bool gpuAvailable: false
    property int gpuPercent: 0
    property int gpuPowerW: 0
    property int gpuTempC: 0
    property real gpuVramUsedGb: 0
    property real gpuVramTotalGb: 0
    property string gpuName: ""
    property var gpuHistory: []

    property var disks: []
    property string networkIface: ""
    property int networkRxBps: 0
    property int networkTxBps: 0
    property string networkIp: ""
    property var sensors: []
    property var fans: []

    property string _resolvedBinary: ""

    readonly property string monitorBinary: {
        if (_resolvedBinary.length > 0)
            return _resolvedBinary;
        const env = Quickshell.env("CLOUDYY_SYSTEM_MONITOR_BIN");
        if (env && env.length > 0)
            return env;
        const home = Quickshell.env("HOME") || "";
        if (home.length > 0)
            return home + "/cloudyy_scripts/cloudyy-other/cloudyy-system-monitor";
        return "cloudyy-system-monitor";
    }

    readonly property Process _resolveBinaryProc: Process {
        running: false
        stdout: StdioCollector {
            id: resolveOut
            onStreamFinished: {
                const path = resolveOut.text.trim();
                if (path.length > 0) {
                    root._resolvedBinary = path;
                    root.ensureDaemon();
                    root.pollSnapshot();
                } else {
                    root.stale = true;
                    console.warn("SystemMonitorService: cloudyy-system-monitor not found in PATH or cloudyy_scripts");
                }
            }
        }
    }

    readonly property Timer _pollTimer: Timer {
        interval: root.pollIntervalMs
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.pollSnapshot()
    }

    readonly property Process _snapshotProc: Process {
        id: snapshotProc
        running: false
        stdout: StdioCollector {
            id: snapshotOut
            onStreamFinished: {
                const text = snapshotOut.text.trim();
                if (text.length)
                    root.ingestLine(text);
                else
                    root.stale = true;
            }
        }
        onExited: {
            if (!snapshotOut.text.trim().length)
                root.stale = true;
        }
    }

    readonly property Process _ensureDaemonProc: Process {
        running: false
        stdout: StdioCollector {
            id: ensureOut
            onStreamFinished: {
                const msg = ensureOut.text.trim();
                root.daemonManaged = msg === "started" || msg === "running";
                if (msg === "missing")
                    root.stale = true;
            }
        }
    }

    Component.onCompleted: resolveBinaryPath()

    function resolveBinaryPath() {
        const env = Quickshell.env("CLOUDYY_SYSTEM_MONITOR_BIN");
        if (env && env.length > 0) {
            _resolvedBinary = env;
            ensureDaemon();
            pollSnapshot();
            return;
        }
        const home = Quickshell.env("HOME") || "";
        _resolveBinaryProc.command = [
            "bash", "-c",
            "home=" + shellQuote(home) + "; "
                + "for c in "
                + "\"$home/cloudyy_scripts/cloudyy-other/cloudyy-system-monitor\" "
                + "\"$home/.local/bin/cloudyy-system-monitor\" "
                + "\"$home/cloudyy-linux/.config/quickshell/cloudyy-system-monitor/target/release/cloudyy-system-monitor\" "
                + "cloudyy-system-monitor; do "
                + "[ -x \"$c\" ] && echo \"$c\" && exit 0; done; exit 1",
        ];
        _resolveBinaryProc.running = false;
        _resolveBinaryProc.running = true;
    }

    function ensureDaemon() {
        _ensureDaemonProc.command = [
            "bash", "-c",
            "bin=" + shellQuote(root.monitorBinary) + "; "
                + "if [ ! -x \"$bin\" ]; then echo missing; exit 0; fi; "
                + "for p in /proc/[0-9]*; do "
                + "  [ -r \"$p/cmdline\" ] || continue; "
                + "  cmd=$(tr '\\0' ' ' <\"$p/cmdline\" 2>/dev/null); "
                + "  case \"$cmd\" in \"$bin\"|\"$bin \"*) echo running; exit 0 ;; esac; "
                + "done; "
                + "nohup \"$bin\" </dev/null >/dev/null 2>&1 & disown; echo started",
        ];
        _ensureDaemonProc.running = false;
        _ensureDaemonProc.running = true;
    }

    function pollSnapshot() {
        if (_snapshotProc.running)
            return;
        _snapshotProc.command = [root.monitorBinary, "--once"];
        _snapshotProc.running = true;
    }

    function restartMonitor() {
        stale = false;
        ensureDaemon();
        pollSnapshot();
    }

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function ingestLine(line) {
        const trimmed = line.trim();
        if (!trimmed.length || trimmed[0] !== "{")
            return;

        let data;
        try {
            data = JSON.parse(trimmed);
        } catch (e) {
            console.warn("SystemMonitorService: invalid JSON", e, trimmed.slice(0, 80));
            stale = true;
            return;
        }

        stale = false;

        const cpu = data.cpu || {};
        const rawCpu = num(cpu.percent, -1);
        cpuAvgPercent = num(cpu.avg_percent, cpuAvgPercent);
        // --once without cache can still report 0; avg_percent tracks recent samples in the daemon.
        cpuPercent = rawCpu > 0 ? rawCpu : (cpuAvgPercent > 0 ? cpuAvgPercent : (rawCpu === 0 ? 0 : cpuPercent));
        cpuTempC = num(cpu.temp_c, 0);
        cpuFreqGhz = real(cpu.freq_ghz, 0);
        cpuModel = str(cpu.model, cpuModel);
        cpuCores = num(cpu.cores, cpuCores);
        cpuHistory = pushHistory(cpuHistory, cpuPercent);

        const ram = data.ram || {};
        ramPercent = num(ram.percent, ramPercent);
        ramUsedGb = real(ram.used_gb, ramUsedGb);
        ramTotalGb = real(ram.total_gb, ramTotalGb);
        swapUsedGb = real(ram.swap_used_gb, swapUsedGb);
        swapTotalGb = real(ram.swap_total_gb, swapTotalGb);
        swapPercent = num(ram.swap_percent, swapPercent);
        ramHistory = pushHistory(ramHistory, ramPercent);

        const gpu = data.gpu || {};
        gpuAvailable = !!gpu.available;
        if (gpuAvailable) {
            gpuPercent = num(gpu.percent, gpuPercent);
            gpuPowerW = num(gpu.power_w, 0);
            gpuTempC = num(gpu.temp_c, 0);
            gpuVramUsedGb = real(gpu.vram_used_gb, 0);
            gpuVramTotalGb = real(gpu.vram_total_gb, 0);
            gpuName = str(gpu.name, gpuName);
            gpuHistory = pushHistory(gpuHistory, gpuPercent);
        }

        disks = Array.isArray(data.disks) ? data.disks : [];

        const net = data.network || {};
        networkIface = str(net.iface, networkIface);
        networkRxBps = num(net.rx_bps, 0);
        networkTxBps = num(net.tx_bps, 0);
        networkIp = str(net.ip, networkIp);

        sensors = Array.isArray(data.sensors) ? data.sensors : [];
        fans = Array.isArray(data.fans) ? data.fans : [];
    }

    function pushHistory(arr, value) {
        const next = arr.slice();
        next.push(Math.max(0, Math.min(100, value)));
        while (next.length > historyMax)
            next.shift();
        return next;
    }

    function num(v, fallback) {
        if (v === undefined || v === null)
            return fallback;
        const n = parseInt(v, 10);
        return isNaN(n) ? fallback : n;
    }

    function real(v, fallback) {
        if (v === undefined || v === null)
            return fallback;
        const n = parseFloat(v);
        return isNaN(n) ? fallback : n;
    }

    function str(v, fallback) {
        if (v === undefined || v === null)
            return fallback;
        return String(v);
    }

    function formatRate(bps) {
        if (bps >= 1_073_741_824)
            return (bps / 1_073_741_824).toFixed(1) + " GB/s";
        if (bps >= 1_048_576)
            return (bps / 1_048_576).toFixed(1) + " MB/s";
        if (bps >= 1024)
            return (bps / 1024).toFixed(1) + " KB/s";
        return bps + " B/s";
    }

    function toggleOpen() {
        open = !open;
    }
}
