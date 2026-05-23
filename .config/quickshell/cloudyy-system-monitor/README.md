Single static binary for Quickshell System Overview. Prints **one JSON object per line** (NDJSON) to stdout.

# binary: target/release/cloudyy-system-monitor (~400–500 KB)

Optional symlink: `~/.local/bin/cloudyy-system-monitor`

## Usage

cloudyy-system-monitor                  # loop every 2s (daemon)
cloudyy-system-monitor --interval-ms 1000
cloudyy-system-monitor --once | jq .   # one snapshot (what Quickshell polls)

## Quickshell integration

`SystemMonitorService`:

1. On load, starts the daemon in the background **only if** no matching `/proc/*/cmdline` is already running (exact binary path — no fragile `pgrep -f`).
2. Polls `cloudyy-system-monitor --once` every **2s** via `StdioCollector` (full JSON blob, reliable parse).

Search order: `CLOUDYY_SYSTEM_MONITOR_BIN` env → `~/cloudyy_scripts/cloudyy-other/` → `~/.local/bin/` → crate `target/release/`

## Dependencies (runtime)
- `/proc`, `/sys` — CPU, RAM, temps, fans, network counters
- `df` — disk usage
- `ip` — default interface IPv4
- `nvidia-smi` — NVIDIA GPU (optional; `gpu.available: false` if missing)


