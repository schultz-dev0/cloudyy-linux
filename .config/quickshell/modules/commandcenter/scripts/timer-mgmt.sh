#!/usr/bin/env bash
# Timer creation + control helpers for Command Center (custom duration via
# zenity; pause/reset/stop act on the same "primary" timer the now-removed
# island controls used — see TimerProviderPolicy.js's pageTimer()).
set -euo pipefail

# Mirrors pageTimer() in modules/timer/TimerProviderPolicy.js: nearest
# running countdown, else the most recently started running stopwatch, else
# the most recently paused timer of either mode. Emits nothing (exit 1) if
# there's no timer to act on.
primary_timer() {
  cloudyy-timer list --json | jq -e '
    (.timers | map(select(.mode == "countdown" and .state == "running"))
             | sort_by(.remaining_seconds) | .[0]) as $countdown
    | if $countdown then $countdown
      else (.timers | map(select(.mode == "stopwatch" and .state == "running")) | .[-1]) as $stopwatch
      | if $stopwatch then $stopwatch
        else (.timers | map(select(.state == "paused")) | .[-1])
        end
      end
  '
}

run_pause_resume() {
  local timer id mode state
  timer=$(primary_timer) || { notify-send "Timer" "No active timer" 2>/dev/null || true; exit 0; }
  id=$(jq -r '.id' <<<"$timer")
  mode=$(jq -r '.mode' <<<"$timer")
  state=$(jq -r '.state' <<<"$timer")
  if [[ "$state" == "paused" ]]; then
    cloudyy-timer resume "$id" >/dev/null
  elif [[ "$mode" == "stopwatch" ]]; then
    cloudyy-timer stopwatch-pause "$id" >/dev/null
  else
    cloudyy-timer pause "$id" >/dev/null
  fi
}

run_reset() {
  local timer id mode
  timer=$(primary_timer) || { notify-send "Timer" "No active timer" 2>/dev/null || true; exit 0; }
  id=$(jq -r '.id' <<<"$timer")
  mode=$(jq -r '.mode' <<<"$timer")
  if [[ "$mode" == "stopwatch" ]]; then
    cloudyy-timer stopwatch-reset "$id" >/dev/null
  else
    cloudyy-timer reset "$id" >/dev/null
  fi
}

run_stop() {
  local timer id
  timer=$(primary_timer) || { notify-send "Timer" "No active timer" 2>/dev/null || true; exit 0; }
  id=$(jq -r '.id' <<<"$timer")
  cloudyy-timer stop "$id" --json >/dev/null
}

run_stopwatch_start() {
  cloudyy-timer stopwatch-start --label "Stopwatch" --json >/dev/null
  notify-send "Timer" "Stopwatch started" -t 3000 2>/dev/null || true
}

run_create_custom() {
  local minutes
  minutes=$(zenity --entry --title="Timer" --text="Duration in minutes" 2>/dev/null) || true
  [[ -z "$minutes" ]] && exit 0
  if ! [[ "$minutes" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    notify-send "Timer" "Enter a number of minutes, e.g. 20" -u critical 2>/dev/null || true
    exit 0
  fi

  local label
  label=$(zenity --entry --title="Timer" --text="Label (optional)" 2>/dev/null) || true
  [[ -z "$label" ]] && label="Timer"

  local seconds
  seconds=$(awk "BEGIN { printf \"%d\", $minutes * 60 }")
  if cloudyy-timer create --label "$label" --duration "$seconds" >/dev/null; then
    notify-send "Timer" "${label} — ${minutes}m started" -t 3000 2>/dev/null || true
  else
    notify-send "Timer" "Failed to create timer." -u critical 2>/dev/null || true
  fi
}

case "${1:-}" in
  create-custom) run_create_custom ;;
  pause-resume) run_pause_resume ;;
  reset) run_reset ;;
  stop) run_stop ;;
  stopwatch-start) run_stopwatch_start ;;
  *)
    echo "usage: timer-mgmt.sh {create-custom|pause-resume|reset|stop|stopwatch-start}" >&2
    exit 1
    ;;
esac
