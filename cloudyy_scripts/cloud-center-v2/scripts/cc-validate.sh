#!/usr/bin/env bash
# Phase-1 validation per the frontend spec. Run with the window CLOSED.
#
# Uses `qs -p ~/.config/quickshell/cloud-center` (never `qs -c`) and matches
# cloud-center instances via `qs list --all` / hyprctl clients rather than
# raw pgrep, since a bare `pgrep -f qs` self-matches this script's own
# invocation and any other qs config. The resident shell daemon is the
# exact process `/usr/bin/qs -n` (quickshell.service) — never touched here.
set -uo pipefail
QML_DIR="$HOME/.config/quickshell/cloud-center"
CC_ROOT="$HOME/cloudyy_scripts/cloud-center-v2"
fail=0

# Resolve the PID of a running cloud-center instance via `qs list --all`
# (Config path line ends in cloud-center/shell.qml), with a hyprctl
# cross-check (class org.quickshell + title "Cloud Center") as fallback
# in case the qs list output format drifts. Never raw pgrep.
cc_instance_pid() {
  local pid
  unset __QUICKSHELL_CRASH_DUMP_PID __QUICKSHELL_CRASH_INFO_FD __QUICKSHELL_CRASH_SIGNAL || true
  pid=$(qs list --all -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for row in data if isinstance(data, list) else []:
    path = str(row.get("config_path") or "")
    if path.endswith("/cloud-center/shell.qml"):
        print(row.get("pid") or ""); break
' 2>/dev/null)
  if [[ -z "$pid" ]]; then
    pid=$(hyprctl -j clients 2>/dev/null | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c.get("class") == "org.quickshell" and c.get("title") == "Cloud Center":
        print(c["pid"]); break' 2>/dev/null)
  fi
  echo "$pid"
}

# Whatever we backgrounded dies with the script, even on Ctrl-C.
qs_bg=""
cleanup() { [[ -n "$qs_bg" ]] && kill "$qs_bg" 2>/dev/null; }
trap cleanup EXIT INT TERM

echo "1) qmllint…"
# shell.qml crashes qmllint with exit 255 (known engine issue, not a lint
# finding) — skip it and lint everything else.
find "$QML_DIR" -name '*.qml' ! -name 'shell.qml' -print0 \
  | xargs -0 qmllint 2>&1 | grep -i error && fail=1
echo "  (shell.qml skipped — known qmllint exit-255 crash)"

echo "2) backend suite…"
(cd "$CC_ROOT" && python3 -m pytest tests/ -q) || fail=1

echo "3) fake-sidecar smoke (5s render)…"
CC_BACKEND_CMD="python3 $CC_ROOT/scripts/fake-ccd.py" \
  timeout 5 qs -p "$QML_DIR" >/dev/null 2>&1
[[ $? -eq 124 ]] || { echo "  smoke run exited early"; fail=1; }
# timeout kills the process group leader but qs's own child processes can
# linger a moment; make sure nothing of ours survives before section 4.
pid=$(cc_instance_pid)
[[ -n "$pid" ]] && kill "$pid" 2>/dev/null
sleep 1

echo "4) open-RSS/PSS check…"
qs -p "$QML_DIR" >/dev/null 2>&1 &
qs_bg=$!
sleep 4
pid=$(cc_instance_pid)
if [[ -z "$pid" ]]; then
  echo "  could not resolve cloud-center instance pid"; fail=1
else
  rss=$(awk '/VmRSS/{print int($2/1024)}' "/proc/$pid/status")
  pss=$(awk '/^Pss:/{print int($2/1024)}' "/proc/$pid/smaps_rollup")
  echo "  RSS: ${rss}MB  PSS: ${pss}MB (target: PSS ≤250, provisional)"
  [[ $pss -le 250 ]] || fail=1
  kill "$pid" 2>/dev/null; sleep 1
fi
# Belt and suspenders: kill the backgrounded job even if pid lookup failed.
kill "$qs_bg" 2>/dev/null; qs_bg=""

echo "5) zero survivors…"
qs_survivor=$(cc_instance_pid)
ccd_survivor=$(pgrep -f "python3 -m lib.ccd")
if [[ -n "$qs_survivor" || -n "$ccd_survivor" ]]; then
  echo "  survivors — qs: ${qs_survivor:-none}  ccd: ${ccd_survivor:-none}"
  fail=1
fi

echo "6) resident daemon untouched…"
daemon_pid=$(pgrep -xf "/usr/bin/qs -n" | head -1)
if [[ -n "$daemon_pid" ]]; then
  awk '/VmRSS/{print "  main qs daemon: " int($2/1024) "MB"}' "/proc/$daemon_pid/status"
else
  echo "  resident qs daemon not found (unexpected — not touched by this script either way)"
fi

[[ $fail -eq 0 ]] && echo "PASS" || { echo "FAIL"; exit 1; }
