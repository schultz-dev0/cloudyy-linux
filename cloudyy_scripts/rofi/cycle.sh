#!/usr/bin/env bash
# =============================================================================
# cycle.sh — Wallpaper Cycle & Auto Light/Dark Menu
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# --- PATHS ---
readonly CYCLE_CONF="${HOME}/.config/hypr/theme_state/cycle.conf"
readonly SVC_DIR="${HOME}/.config/systemd/user"
readonly AUTOMODE_HELPER="${ROFI_DIR}/lib/automode_switch.sh"

# --- STATE VARS (populated by read_cycle_conf) ---
CYCLE_ENABLED="false"
CYCLE_INTERVAL="1800"
CYCLE_ORDER="random"
AUTOMODE_ENABLED="false"
AUTOMODE_LIGHT_HOUR="7"
AUTOMODE_DARK_HOUR="20"

# =============================================================================
# CONFIG READ / WRITE
# =============================================================================

read_cycle_conf() {
  [[ -f "$CYCLE_CONF" ]] || return 0
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ $key =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      CYCLE_ENABLED)       CYCLE_ENABLED="$value" ;;
      CYCLE_INTERVAL)      CYCLE_INTERVAL="$value" ;;
      CYCLE_ORDER)         CYCLE_ORDER="$value" ;;
      AUTOMODE_ENABLED)    AUTOMODE_ENABLED="$value" ;;
      AUTOMODE_LIGHT_HOUR) AUTOMODE_LIGHT_HOUR="$value" ;;
      AUTOMODE_DARK_HOUR)  AUTOMODE_DARK_HOUR="$value" ;;
    esac
  done < "$CYCLE_CONF"
}

save_cycle_conf() {
  mkdir -p "$(dirname "$CYCLE_CONF")"
  cat > "$CYCLE_CONF" <<EOF
CYCLE_ENABLED="$CYCLE_ENABLED"
CYCLE_INTERVAL="$CYCLE_INTERVAL"
CYCLE_ORDER="$CYCLE_ORDER"
AUTOMODE_ENABLED="$AUTOMODE_ENABLED"
AUTOMODE_LIGHT_HOUR="$AUTOMODE_LIGHT_HOUR"
AUTOMODE_DARK_HOUR="$AUTOMODE_DARK_HOUR"
EOF
}

# =============================================================================
# SYSTEMD UNIT MANAGEMENT
# =============================================================================

seconds_to_systemd() {
  local secs="$1"
  if (( secs < 60 )); then
    echo "${secs}s"
  elif (( secs < 3600 )); then
    echo "$((secs / 60))min"
  else
    echo "$((secs / 3600))h"
  fi
}

write_cycle_units() {
  mkdir -p "$SVC_DIR"
  local order_cmd
  [[ "$CYCLE_ORDER" == "random" ]] && order_cmd="random" || order_cmd="next"
  local interval
  interval="$(seconds_to_systemd "$CYCLE_INTERVAL")"

  cat > "${SVC_DIR}/theme-cycle.service" <<EOF
[Unit]
Description=Cloudyy — cycle wallpaper
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=${THEME_CTL} ${order_cmd}
EOF

  cat > "${SVC_DIR}/theme-cycle.timer" <<EOF
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

write_automode_units() {
  mkdir -p "$SVC_DIR"

  cat > "${SVC_DIR}/theme-automode.service" <<EOF
[Unit]
Description=Cloudyy — auto light/dark mode switcher
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=${AUTOMODE_HELPER}
EOF

  cat > "${SVC_DIR}/theme-automode.timer" <<EOF
[Unit]
Description=Cloudyy — auto mode check timer

[Timer]
OnCalendar=*:0/5
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF
}

# Write the small helper script that the automode service runs
write_automode_helper() {
  mkdir -p "$(dirname "$AUTOMODE_HELPER")"
  cat > "$AUTOMODE_HELPER" <<'HELPER'
#!/usr/bin/env bash
# automode_switch.sh — Called by theme-automode.service every 5 minutes.
# Reads cycle.conf and switches light/dark based on the hour.
set -uo pipefail

CYCLE_CONF="${HOME}/.config/hypr/theme_state/cycle.conf"
THEME_CTL="${HOME}/cloudyy_scripts/theme_controller.sh"

AUTOMODE_ENABLED="false"
AUTOMODE_LIGHT_HOUR="7"
AUTOMODE_DARK_HOUR="20"

[[ -f "$CYCLE_CONF" ]] && \
  while IFS='=' read -r k v || [[ -n "$k" ]]; do
    v="${v%\"}"; v="${v#\"}";
    case "$k" in
      AUTOMODE_ENABLED)    AUTOMODE_ENABLED="$v" ;;
      AUTOMODE_LIGHT_HOUR) AUTOMODE_LIGHT_HOUR="$v" ;;
      AUTOMODE_DARK_HOUR)  AUTOMODE_DARK_HOUR="$v" ;;
    esac
  done < "$CYCLE_CONF"

[[ "$AUTOMODE_ENABLED" != "true" ]] && exit 0

NOW=$(date +%-H)
CURRENT_MODE=$("$THEME_CTL" get-mode 2>/dev/null || echo "dark")

if (( NOW >= AUTOMODE_LIGHT_HOUR && NOW < AUTOMODE_DARK_HOUR )); then
  TARGET="light"
else
  TARGET="dark"
fi

[[ "$CURRENT_MODE" == "$TARGET" ]] && exit 0
"$THEME_CTL" set --mode "$TARGET"
HELPER
  chmod +x "$AUTOMODE_HELPER"
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

apply_automode() {
  write_automode_units
  systemctl --user daemon-reload
  if [[ "$AUTOMODE_ENABLED" == "true" ]]; then
    systemctl --user enable --now theme-automode.timer
    # Run immediately so the switch happens now, not in 5 min
    systemctl --user start theme-automode.service 2>/dev/null || true
  else
    systemctl --user disable --now theme-automode.timer 2>/dev/null || true
    systemctl --user stop theme-automode.timer 2>/dev/null || true
  fi
}

# =============================================================================
# DISPLAY HELPERS
# =============================================================================

interval_label() {
  case "$1" in
    300)   echo "5 min" ;;
    600)   echo "10 min" ;;
    900)   echo "15 min" ;;
    1800)  echo "30 min" ;;
    3600)  echo "1 hour" ;;
    7200)  echo "2 hours" ;;
    14400) echo "4 hours" ;;
    *)     echo "${1}s" ;;
  esac
}

bool_label() {
  [[ "$1" == "true" ]] && echo "ON" || echo "OFF"
}

fmt_hour() {
  printf "%02d:00" "$1"
}

# =============================================================================
# INTERVAL SUBMENU
# =============================================================================

show_interval_menu() {
  local choice
  choice=$(menu "Cycle Interval" \
    "5 minutes\n10 minutes\n15 minutes\n30 minutes\n1 hour\n2 hours\n4 hours")

  case "$choice" in
    "5 minutes")  CYCLE_INTERVAL="300" ;;
    "10 minutes") CYCLE_INTERVAL="600" ;;
    "15 minutes") CYCLE_INTERVAL="900" ;;
    "30 minutes") CYCLE_INTERVAL="1800" ;;
    "1 hour")     CYCLE_INTERVAL="3600" ;;
    "2 hours")    CYCLE_INTERVAL="7200" ;;
    "4 hours")    CYCLE_INTERVAL="14400" ;;
    *) show_cycle_menu; return ;;
  esac

  save_cycle_conf
  [[ "$CYCLE_ENABLED" == "true" ]] && apply_cycle
  notify-send "Cycle" "Interval → $(interval_label "$CYCLE_INTERVAL")" -t 2000
  show_cycle_menu
}

# =============================================================================
# ORDER SUBMENU
# =============================================================================

show_order_menu() {
  local choice
  choice=$(menu "Cycle Order" \
    "󰒝 Random     — shuffle each step\n󰒼 Sequential  — alphabetical order")

  case "$choice" in
    *"Random"*)     CYCLE_ORDER="random" ;;
    *"Sequential"*) CYCLE_ORDER="sequential" ;;
    *) show_cycle_menu; return ;;
  esac

  save_cycle_conf
  [[ "$CYCLE_ENABLED" == "true" ]] && apply_cycle
  notify-send "Cycle" "Order → $CYCLE_ORDER" -t 2000
  show_cycle_menu
}

# =============================================================================
# AUTO MODE — TIME SUBMENU
# =============================================================================

show_automode_time_menu() {
  local which="$1"  # "light" or "dark"
  local label
  [[ "$which" == "light" ]] && label="Light Mode Start" || label="Dark Mode Start"

  local choice
  choice=$(menu "$label" \
    "05:00  Very early morning\n06:00  Dawn\n07:00  Morning\n08:00  Late morning\n09:00  Mid-morning\n17:00  Late afternoon\n18:00  Evening\n19:00  Dusk\n20:00  Night\n21:00  Late night\n22:00  Near midnight")

  [[ -z "$choice" ]] && { show_automode_menu; return; }

  # Extract HH from "HH:MM  label"
  local raw_hour="${choice%%:*}"
  raw_hour="${raw_hour// /}"
  raw_hour="${raw_hour#0}"  # strip leading zero (bash arithmetic safe)
  [[ -z "$raw_hour" ]] && raw_hour="0"

  if [[ "$which" == "light" ]]; then
    AUTOMODE_LIGHT_HOUR="$raw_hour"
  else
    AUTOMODE_DARK_HOUR="$raw_hour"
  fi

  save_cycle_conf
  [[ "$AUTOMODE_ENABLED" == "true" ]] && apply_automode
  notify-send "Auto Mode" "${label} → $(fmt_hour "$raw_hour")" -t 2000
  show_automode_menu
}

# =============================================================================
# AUTO MODE MENU
# =============================================================================

show_automode_menu() {
  local status light_fmt dark_fmt toggle_label
  status="$(bool_label "$AUTOMODE_ENABLED")"
  light_fmt="$(fmt_hour "$AUTOMODE_LIGHT_HOUR")"
  dark_fmt="$(fmt_hour "$AUTOMODE_DARK_HOUR")"

  if [[ "$AUTOMODE_ENABLED" == "true" ]]; then
    toggle_label="󰨙 Disable Auto Switch"
  else
    toggle_label="󰨙 Enable Auto Switch"
  fi

  local choice
  choice=$(menu "Auto Mode — ${status}  ☀ ${light_fmt} ☾ ${dark_fmt}" \
    "${toggle_label}\n☀  Light Starts → ${light_fmt}\n☾  Dark Starts  → ${dark_fmt}\n Back to Cycle")

  case "$choice" in
    *"Enable Auto Switch"*)
      AUTOMODE_ENABLED="true"
      save_cycle_conf
      apply_automode
      notify-send "Auto Mode" "Enabled — ☀ ${light_fmt} / ☾ ${dark_fmt}" -t 2000
      show_automode_menu
      ;;
    *"Disable Auto Switch"*)
      AUTOMODE_ENABLED="false"
      save_cycle_conf
      apply_automode
      notify-send "Auto Mode" "Disabled" -t 2000
      show_automode_menu
      ;;
    *"Light Starts"*)     show_automode_time_menu "light" ;;
    *"Dark Starts"*)      show_automode_time_menu "dark" ;;
    *"Back to Cycle"*)    show_cycle_menu ;;
    *)                    show_cycle_menu ;;
  esac
}

# =============================================================================
# MAIN CYCLE MENU
# =============================================================================

show_cycle_menu() {
  local cycle_status interval_lbl order_icon auto_status toggle_label

  cycle_status="$(bool_label "$CYCLE_ENABLED")"
  interval_lbl="$(interval_label "$CYCLE_INTERVAL")"
  [[ "$CYCLE_ORDER" == "random" ]] && order_icon="󰒝" || order_icon="󰒼"
  auto_status="$(bool_label "$AUTOMODE_ENABLED")"

  if [[ "$CYCLE_ENABLED" == "true" ]]; then
    toggle_label="󰏤 Disable Cycling"
  else
    toggle_label="󰐊 Enable Cycling"
  fi

  local choice
  choice=$(menu "Cycle — ${cycle_status}  ${interval_lbl}  ${order_icon}" \
    "${toggle_label}\n󱑶 Set Interval   → ${interval_lbl}\n${order_icon} Set Order      → ${CYCLE_ORDER}\n󰸘 Auto Light/Dark → ${auto_status}\n Back")

  case "$choice" in
    *"Enable Cycling"*)
      CYCLE_ENABLED="true"
      save_cycle_conf
      apply_cycle
      notify-send "Cycle" "Wallpaper cycling ON — every $(interval_label "$CYCLE_INTERVAL")" -t 2000
      show_cycle_menu
      ;;
    *"Disable Cycling"*)
      CYCLE_ENABLED="false"
      save_cycle_conf
      apply_cycle
      notify-send "Cycle" "Wallpaper cycling OFF" -t 2000
      show_cycle_menu
      ;;
    *"Set Interval"*)    show_interval_menu ;;
    *"Set Order"*)       show_order_menu ;;
    *"Auto Light/Dark"*) show_automode_menu ;;
    *"Back"*)            exec "${ROFI_DIR}/appearance.sh" ;;
    *)                   exec "${ROFI_DIR}/appearance.sh" ;;
  esac
}

# =============================================================================
# ENTRY POINT
# =============================================================================

init_dirs
read_cycle_conf
write_automode_helper

show_cycle_menu
