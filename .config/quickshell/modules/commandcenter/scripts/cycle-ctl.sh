#!/usr/bin/env bash
# Wallpaper cycle control for Command Center.
set -euo pipefail

USER_HOME="${HOME:-$(printf '%s' ~)}"
CYCLE_CONF="${USER_HOME}/.config/hypr/theme_state/cycle.conf"
SVC_DIR="${USER_HOME}/.config/systemd/user"
THEME_CTL="${USER_HOME}/cloudyy-linux/bin/cloudyy-theme"

CYCLE_ENABLED="false"
CYCLE_INTERVAL="1800"
CYCLE_ORDER="random"
LOCK_FD=9

acquire_cycle_lock() {
  mkdir -p "$(dirname "$CYCLE_CONF")"
  eval "exec $LOCK_FD>\"${CYCLE_CONF}.lock\""
  flock "$LOCK_FD"
}

release_cycle_lock() {
  flock -u "$LOCK_FD" 2>/dev/null || true
}

read_cycle_conf() {
  [[ -f "$CYCLE_CONF" ]] || return 0
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ $key =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      CYCLE_ENABLED) CYCLE_ENABLED="$value" ;;
      CYCLE_INTERVAL) CYCLE_INTERVAL="$value" ;;
      CYCLE_ORDER) CYCLE_ORDER="$value" ;;
    esac
  done < "$CYCLE_CONF"
}

save_cycle_conf() {
  mkdir -p "$(dirname "$CYCLE_CONF")"
  cat >"$CYCLE_CONF" <<EOF
CYCLE_ENABLED="$CYCLE_ENABLED"
CYCLE_INTERVAL="$CYCLE_INTERVAL"
CYCLE_ORDER="$CYCLE_ORDER"
EOF
}

seconds_to_systemd() {
  local secs="$1"
  if (( secs < 60 )); then echo "${secs}s"
  elif (( secs < 3600 )); then echo "$((secs / 60))min"
  else echo "$((secs / 3600))h"; fi
}

write_cycle_units() {
  mkdir -p "$SVC_DIR"
  local order_cmd interval
  [[ "$CYCLE_ORDER" == "random" ]] && order_cmd="random" || order_cmd="next"
  interval="$(seconds_to_systemd "$CYCLE_INTERVAL")"
  cat >"${SVC_DIR}/theme-cycle.service" <<EOF
[Unit]
Description=Cloudyy — cycle wallpaper
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=${THEME_CTL} ${order_cmd}
EOF
  cat >"${SVC_DIR}/theme-cycle.timer" <<EOF
[Unit]
Description=Cloudyy — wallpaper cycle timer

[Timer]
OnActiveSec=${interval}
OnUnitActiveSec=${interval}
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
}

apply_cycle() {
  write_cycle_units
  systemctl --user daemon-reload
  if [[ "$CYCLE_ENABLED" == "true" ]]; then
    systemctl --user enable --now theme-cycle.timer
  else
    systemctl --user disable --now theme-cycle.timer 2>/dev/null || true
    systemctl --user stop theme-cycle.timer 2>/dev/null || true
  fi
}

interval_label() {
  case "$1" in
    300) echo "5 min" ;;
    600) echo "10 min" ;;
    900) echo "15 min" ;;
    1800) echo "30 min" ;;
    3600) echo "1 hour" ;;
    7200) echo "2 hours" ;;
    14400) echo "4 hours" ;;
    *) echo "${1}s" ;;
  esac
}

cmd="${1:-state}"
acquire_cycle_lock
trap release_cycle_lock EXIT
read_cycle_conf

case "$cmd" in
  state)
    jq -cn \
      --arg ce "$CYCLE_ENABLED" \
      --arg ci "$CYCLE_INTERVAL" \
      --arg co "$CYCLE_ORDER" \
      '{
        cycle_enabled: ($ce == "true"),
        cycle_interval: ($ci | tonumber),
        cycle_order: $co
      }'
    ;;
  toggle-cycle)
    [[ "$CYCLE_ENABLED" == "true" ]] && CYCLE_ENABLED="false" || CYCLE_ENABLED="true"
    save_cycle_conf
    apply_cycle
    ;;
  set-interval)
    CYCLE_INTERVAL="${2:-1800}"
    save_cycle_conf
    [[ "$CYCLE_ENABLED" == "true" ]] && apply_cycle
    ;;
  set-order)
    CYCLE_ORDER="${2:-random}"
    save_cycle_conf
    [[ "$CYCLE_ENABLED" == "true" ]] && apply_cycle
    ;;
  *)
    echo "usage: cycle-ctl.sh {state|toggle-cycle|set-interval|set-order}" >&2
    exit 1
    ;;
esac
