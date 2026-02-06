#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Original creator: Dusk
# -----------------------------------------------------------------------------
# Architecture: Atomic Writes + Robust Input Engine + Power Saver Features
# New Features:
#   - Power Profiles: Performance, Balanced, Power Saver modes
#   - CPU Governor control
#   - Screen brightness management
#   - Wi-Fi power saving
#   - USB autosuspend
#   - SATA power management
# -----------------------------------------------------------------------------

set -euo pipefail
export LC_NUMERIC=C

# =============================================================================
# ▼ ANSI DEFINITIONS ▼
# =============================================================================

readonly C_RESET=$'\033[0m'
readonly C_CYAN=$'\033[1;36m'
readonly C_GREEN=$'\033[1;32m'
readonly C_MAGENTA=$'\033[1;35m'
readonly C_RED=$'\033[1;31m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_WHITE=$'\033[1;37m'
readonly C_GREY=$'\033[1;30m'
readonly C_BLUE=$'\033[1;34m'
readonly C_INVERSE=$'\033[7m'

# =============================================================================
# ▼ AUTO-ELEVATION ▼
# =============================================================================

if [[ ${EUID} -ne 0 ]]; then
  printf '%s[PRIVILEGE ESCALATION]%s This script requires root privileges.\n' \
    "${C_YELLOW}" "${C_RESET}"
  exec sudo -- "$0" "$@"
fi

# =============================================================================
# ▼ CONFIGURATION ▼
# =============================================================================

readonly CONFIG_FILE="/etc/systemd/logind.conf"
readonly POWER_CONFIG="/etc/dusky-power.conf"
readonly APP_TITLE="Dusky Power Manager Enhanced"
readonly APP_VERSION="v3.0"

declare -ri MAX_DISPLAY_ROWS=12
declare -ri BOX_INNER_WIDTH=76
declare -ri ITEM_PADDING=32

# Internal marker for unset values
readonly UNSET_MARKER='«unset»'

# Generate horizontal line
declare _h_line_buf
printf -v _h_line_buf '%*s' "${BOX_INNER_WIDTH}" ''
readonly H_LINE="${_h_line_buf// /─}"
unset _h_line_buf

# Terminal Control
readonly CLR_EOL=$'\033[K'
readonly CLR_SCREEN=$'\033[2J'
readonly CURSOR_HOME=$'\033[H'
readonly CURSOR_HIDE=$'\033[?25l'
readonly CURSOR_SHOW=$'\033[?25h'
readonly MOUSE_ON=$'\033[?1000h\033[?1002h\033[?1006h'
readonly MOUSE_OFF=$'\033[?1000l\033[?1002l\033[?1006l'

# =============================================================================
# ▼ STATE MANAGEMENT ▼
# =============================================================================

declare -i SELECTED_ROW=0
declare -i CURRENT_TAB=0
declare -i SCROLL_OFFSET=0
declare -i UNSAVED_CHANGES=0

declare -a TABS=("Power Keys" "Lid & Idle" "Session" "Power Saver")
declare -ri TAB_COUNT=${#TABS[@]}

# Data Structures
declare -A ITEM_SCHEMA=()    # label -> "key|type|opts"
declare -A VALUE_CACHE=()    # label -> current UI value
declare -A FILE_CACHE=()     # key   -> original disk value
declare -A DEFAULTS=()       # label -> default value
declare -A POWER_CACHE=()    # key   -> power config value
declare -A TAB_REGISTRY=()   # "tab:row" -> label
declare -a TAB_ROW_COUNTS=() # tab_idx -> row count
declare -a TAB_ZONES=()      # click zones for tabs
declare ORIGINAL_STTY=""

for ((i = 0; i < TAB_COUNT; i++)); do
  TAB_ROW_COUNTS[i]=0
done

# =============================================================================
# ▼ UTILITY FUNCTIONS ▼
# =============================================================================

log_err() {
  printf '%s[ERROR]%s %s\n' "${C_RED}" "${C_RESET}" "$1" >&2
}

log_info() {
  printf '%s[INFO]%s %s\n' "${C_CYAN}" "${C_RESET}" "$1"
}

cleanup() {
  printf '%s%s%s\n' "${MOUSE_OFF}" "${CURSOR_SHOW}" "${C_RESET}"
  [[ -n ${ORIGINAL_STTY:-} ]] && stty "${ORIGINAL_STTY}" 2>/dev/null || true
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# =============================================================================
# ▼ POWER MANAGEMENT DETECTION ▼
# =============================================================================

detect_cpu_governors() {
  local cpu_dir="/sys/devices/system/cpu/cpu0/cpufreq"
  if [[ -f "${cpu_dir}/scaling_available_governors" ]]; then
    cat "${cpu_dir}/scaling_available_governors" 2>/dev/null || echo "performance powersave"
  else
    echo "performance powersave"
  fi
}

detect_brightness_devices() {
  local count=0
  if [[ -d /sys/class/backlight ]]; then
    count=$(find /sys/class/backlight -mindepth 1 -maxdepth 1 -type l 2>/dev/null | wc -l)
  fi
  echo "${count}"
}

has_wifi() {
  [[ -d /sys/class/net ]] && find /sys/class/net -type l -name 'wl*' 2>/dev/null | grep -q . && return 0
  return 1
}

has_battery() {
  [[ -d /sys/class/power_supply ]] && find /sys/class/power_supply -name 'BAT*' 2>/dev/null | grep -q . && return 0
  return 1
}

# =============================================================================
# ▼ CORE ENGINE ▼
# =============================================================================

register() {
  local -i tab_idx=$1
  local label=$2
  local config=$3
  local default_val=${4:-}

  # Type Safety Validation
  local key type opts
  IFS='|' read -r key type opts <<<"$config"
  case "$type" in
  bool | int | float | cycle | power) ;;
  *)
    printf '%s[FATAL]%s Invalid type "%s" for "%s".\n' \
      "${C_RED}" "${C_RESET}" "$type" "$label" >&2
    exit 1
    ;;
  esac

  ITEM_SCHEMA["${label}"]="${config}"
  DEFAULTS["${label}"]="${default_val}"

  local -i row=${TAB_ROW_COUNTS[tab_idx]}
  TAB_REGISTRY["${tab_idx}:${row}"]="${label}"
  ((TAB_ROW_COUNTS[tab_idx]++)) || true

  VALUE_CACHE["${label}"]="${UNSET_MARKER}"
}

init_items() {
  local acts="ignore,poweroff,reboot,halt,suspend,hibernate,hybrid-sleep,suspend-then-hibernate,lock"
  local cpu_govs
  cpu_govs=$(detect_cpu_governors | tr ' ' ',')

  # Tab 0: Power Keys
  register 0 "Power Key" "HandlePowerKey|cycle|${acts}" "poweroff"
  register 0 "Reboot Key" "HandleRebootKey|cycle|${acts}" "reboot"
  register 0 "Suspend Key" "HandleSuspendKey|cycle|${acts}" "suspend"
  register 0 "Long Press" "HandlePowerKeyLongPress|cycle|${acts}" "ignore"

  # Tab 1: Lid & Idle
  register 1 "Lid Switch" "HandleLidSwitch|cycle|${acts}" "suspend"
  register 1 "Lid (Ext)" "HandleLidSwitchExternalPower|cycle|${acts}" "suspend"
  register 1 "Lid (Docked)" "HandleLidSwitchDocked|cycle|${acts}" "ignore"
  register 1 "Idle Action" "IdleAction|cycle|${acts}" "ignore"
  register 1 "Idle Timeout" "IdleActionSec|cycle|15min,30min,45min,1h,2h,infinity" "30min"

  # Tab 2: Session
  register 2 "Kill User Procs" "KillUserProcesses|cycle|yes,no" "no"
  register 2 "Reserve VTs" "ReserveVT|int|0 12" "6"

  # Tab 3: Power Saver
  register 3 "Power Profile" "POWER_PROFILE|cycle|performance,balanced,powersave" "balanced"
  register 3 "CPU Governor" "CPU_GOVERNOR|cycle|${cpu_govs}" "powersave"
  register 3 "CPU Boost" "CPU_BOOST|cycle|enabled,disabled" "enabled"
  register 3 "Screen Brightness" "SCREEN_BRIGHTNESS|int|10 100" "80"

  if has_wifi; then
    register 3 "WiFi Power Save" "WIFI_POWERSAVE|cycle|enabled,disabled" "disabled"
  fi

  register 3 "USB Autosuspend" "USB_AUTOSUSPEND|cycle|enabled,disabled" "disabled"
  register 3 "SATA Link Power" "SATA_LINK_POWER|cycle|max_performance,medium_power,min_power" "medium_power"
  register 3 "NMI Watchdog" "NMI_WATCHDOG|cycle|enabled,disabled" "enabled"
  register 3 "Laptop Mode" "LAPTOP_MODE|cycle|enabled,disabled" "disabled"
}

parse_config() {
  local line key val
  FILE_CACHE=()

  if [[ ! -f ${CONFIG_FILE} ]]; then
    log_err "Config file not found: ${CONFIG_FILE}"
    return 1
  fi

  while IFS= read -r line || [[ -n ${line} ]]; do
    [[ -z ${line} || ${line} == "["* ]] && continue

    if [[ ${line} =~ ^#?([A-Za-z]+)=(.*)$ ]]; then
      key=${BASH_REMATCH[1]}
      val=${BASH_REMATCH[2]}
      val=${val%%#*}
      val=${val// /}
      FILE_CACHE["${key}"]="${val}"
    fi
  done <"${CONFIG_FILE}"
}

parse_power_config() {
  POWER_CACHE=()

  [[ ! -f ${POWER_CONFIG} ]] && return 0

  local line key val
  while IFS='=' read -r key val || [[ -n ${key} ]]; do
    [[ -z ${key} || ${key} == "#"* ]] && continue
    key=${key// /}
    val=${val// /}
    POWER_CACHE["${key}"]="${val}"
  done <"${POWER_CONFIG}"
}

load_values_to_ui() {
  local tab row label key type opts

  for ((tab = 0; tab < TAB_COUNT; tab++)); do
    for ((row = 0; row < TAB_ROW_COUNTS[tab]; row++)); do
      label=${TAB_REGISTRY["${tab}:${row}"]}
      IFS='|' read -r key type opts <<<"${ITEM_SCHEMA[${label}]}"

      if [[ ${type} == "power" ]] || [[ ${tab} == 3 ]]; then
        # Power saver items
        if [[ -n ${POWER_CACHE[${key}]:-} ]]; then
          VALUE_CACHE["${label}"]="${POWER_CACHE[${key}]}"
        else
          VALUE_CACHE["${label}"]="${UNSET_MARKER}"
        fi
      else
        # Logind items
        if [[ -n ${FILE_CACHE[${key}]:-} ]]; then
          VALUE_CACHE["${label}"]="${FILE_CACHE[${key}]}"
        else
          VALUE_CACHE["${label}"]="${UNSET_MARKER}"
        fi
      fi
    done
  done
}

# =============================================================================
# ▼ VALUE MUTATION ▼
# =============================================================================

modify_value() {
  local label=$1
  local -i direction=$2
  local key type opts current new_val
  local -a opt_arr

  IFS='|' read -r key type opts <<<"${ITEM_SCHEMA[${label}]}"
  current=${VALUE_CACHE[${label}]}

  # Handle UNSET values
  if [[ "${current}" == "${UNSET_MARKER}" ]]; then
    current=${DEFAULTS[${label}]}
  fi

  if [[ ${type} == "int" ]]; then
    local -i min max int_val step
    min=${opts%% *}
    max=${opts##* }
    [[ ! ${current} =~ ^-?[0-9]+$ ]] && current=${min}
    int_val=${current}

    # Adjust step size for brightness
    if [[ ${label} == "Screen Brightness" ]]; then
      step=5
      ((int_val += direction * step)) || true
    else
      ((int_val += direction)) || true
    fi

    ((int_val < min)) && int_val=${min}
    ((int_val > max)) && int_val=${max}
    new_val=${int_val}
  else
    IFS=',' read -r -a opt_arr <<<"${opts}"
    local -i idx=0 arr_len=${#opt_arr[@]}
    for ((i = 0; i < arr_len; i++)); do
      [[ ${opt_arr[i]} == "${current}" ]] && {
        idx=${i}
        break
      }
    done
    ((idx += direction)) || true
    ((idx < 0)) && idx=$((arr_len - 1))
    ((idx >= arr_len)) && idx=0
    new_val=${opt_arr[idx]}
  fi

  if [[ ${current} != "${new_val}" ]]; then
    VALUE_CACHE["${label}"]="${new_val}"
    UNSAVED_CHANGES=1
  fi
}

reset_defaults() {
  local -i count=${TAB_ROW_COUNTS[CURRENT_TAB]}
  local row label def_val

  for ((row = 0; row < count; row++)); do
    label=${TAB_REGISTRY["${CURRENT_TAB}:${row}"]}
    def_val=${DEFAULTS["${label}"]:-}

    if [[ -n "${def_val}" && "${VALUE_CACHE[${label}]}" != "${def_val}" ]]; then
      VALUE_CACHE["${label}"]="${def_val}"
      UNSAVED_CHANGES=1
    fi
  done
}

# =============================================================================
# ▼ POWER SAVER APPLY FUNCTIONS ▼
# =============================================================================

apply_cpu_governor() {
  local governor=$1
  local cpu

  for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -f ${cpu} ]] && echo "${governor}" >"${cpu}" 2>/dev/null || true
  done
}

apply_cpu_boost() {
  local state=$1
  local boost_file="/sys/devices/system/cpu/cpufreq/boost"
  local intel_boost="/sys/devices/system/cpu/intel_pstate/no_turbo"

  if [[ -f ${boost_file} ]]; then
    [[ ${state} == "enabled" ]] && echo "1" >"${boost_file}" || echo "0" >"${boost_file}"
  elif [[ -f ${intel_boost} ]]; then
    [[ ${state} == "enabled" ]] && echo "0" >"${intel_boost}" || echo "1" >"${intel_boost}"
  fi
}

apply_screen_brightness() {
  local -i brightness=$1
  local device max_brightness current

  for device in /sys/class/backlight/*/brightness; do
    [[ -f ${device} ]] || continue
    max_brightness=$(cat "${device%/brightness}/max_brightness" 2>/dev/null) || continue
    current=$((max_brightness * brightness / 100))
    echo "${current}" >"${device}" 2>/dev/null || true
  done
}

apply_wifi_powersave() {
  local state=$1
  local iface

  command -v iw >/dev/null 2>&1 || return 0

  for iface in /sys/class/net/wl*; do
    [[ -d ${iface} ]] || continue
    iface=${iface##*/}
    if [[ ${state} == "enabled" ]]; then
      iw dev "${iface}" set power_save on 2>/dev/null || true
    else
      iw dev "${iface}" set power_save off 2>/dev/null || true
    fi
  done
}

apply_usb_autosuspend() {
  local state=$1
  local level device

  [[ ${state} == "enabled" ]] && level="auto" || level="on"

  for device in /sys/bus/usb/devices/*/power/control; do
    [[ -f ${device} ]] && echo "${level}" >"${device}" 2>/dev/null || true
  done
}

apply_sata_power() {
  local policy=$1
  local host

  for host in /sys/class/scsi_host/host*/link_power_management_policy; do
    [[ -f ${host} ]] && echo "${policy}" >"${host}" 2>/dev/null || true
  done
}

apply_nmi_watchdog() {
  local state=$1
  local nmi_file="/proc/sys/kernel/nmi_watchdog"

  [[ -f ${nmi_file} ]] || return 0
  [[ ${state} == "enabled" ]] && echo "1" >"${nmi_file}" || echo "0" >"${nmi_file}"
}

apply_laptop_mode() {
  local state=$1
  local lm_file="/proc/sys/vm/laptop_mode"

  [[ -f ${lm_file} ]] || return 0
  [[ ${state} == "enabled" ]] && echo "5" >"${lm_file}" || echo "0" >"${lm_file}"
}

apply_power_profile() {
  local profile=$1

  case ${profile} in
  performance)
    apply_cpu_governor "performance"
    apply_cpu_boost "enabled"
    apply_screen_brightness 100
    has_wifi && apply_wifi_powersave "disabled"
    apply_usb_autosuspend "disabled"
    apply_sata_power "max_performance"
    apply_nmi_watchdog "enabled"
    apply_laptop_mode "disabled"
    ;;
  balanced)
    apply_cpu_governor "schedutil"
    apply_cpu_boost "enabled"
    apply_screen_brightness 80
    has_wifi && apply_wifi_powersave "disabled"
    apply_usb_autosuspend "disabled"
    apply_sata_power "medium_power"
    apply_nmi_watchdog "enabled"
    apply_laptop_mode "disabled"
    ;;
  powersave)
    apply_cpu_governor "powersave"
    apply_cpu_boost "disabled"
    apply_screen_brightness 60
    has_wifi && apply_wifi_powersave "enabled"
    apply_usb_autosuspend "enabled"
    apply_sata_power "min_power"
    apply_nmi_watchdog "disabled"
    apply_laptop_mode "enabled"
    ;;
  esac
}

# =============================================================================
# ▼ ATOMIC CONFIGURATION SAVE ▼
# =============================================================================

save_config() {
  local tab row label key type opts val
  local -i changes=0
  local -a pending_changes=()
  local -a pending_power_changes=()

  for ((tab = 0; tab < TAB_COUNT; tab++)); do
    for ((row = 0; row < TAB_ROW_COUNTS[tab]; row++)); do
      label=${TAB_REGISTRY["${tab}:${row}"]}
      IFS='|' read -r key type opts <<<"${ITEM_SCHEMA[${label}]}"
      val=${VALUE_CACHE[${label}]}

      [[ "${val}" == "${UNSET_MARKER}" ]] && continue

      if [[ ${tab} == 3 ]]; then
        # Power saver tab
        [[ "${val}" == "${POWER_CACHE[${key}]:-}" ]] && continue
        pending_power_changes+=("${key}=${val}")
        ((changes++)) || true
      else
        # Logind tabs
        [[ "${val}" == "${FILE_CACHE[${key}]:-}" ]] && continue
        pending_changes+=("${key}=${val}")
        ((changes++)) || true
      fi
    done
  done

  ((changes == 0)) && return 1

  # Save logind.conf changes
  if ((${#pending_changes[@]} > 0)); then
    local tmpfile
    tmpfile=$(mktemp) || {
      log_err "Failed to create temp file"
      return 1
    }
    trap 'rm -f "${tmpfile}" 2>/dev/null' RETURN

    cp -- "${CONFIG_FILE}" "${tmpfile}"

    local change_key change_val escaped_val
    for change in "${pending_changes[@]}"; do
      change_key=${change%%=*}
      change_val=${change#*=}

      escaped_val=${change_val//\\/\\\\}
      escaped_val=${escaped_val//&/\\&}
      escaped_val=${escaped_val//|/\\|}
      escaped_val=${escaped_val//$'\n'/\\n}
      escaped_val=${escaped_val//-/\\-}

      if grep -q -E "^#?${change_key}=" "${tmpfile}"; then
        sed -i -E "s|^#?(${change_key}=).*|\1${escaped_val}|" "${tmpfile}"
      elif grep -q '^\[Login\]' "${tmpfile}"; then
        sed -i "/^\[Login\]/a ${change_key}=${escaped_val}" "${tmpfile}"
      else
        printf '\n[Login]\n%s=%s\n' "${change_key}" "${escaped_val}" >>"${tmpfile}"
      fi

      FILE_CACHE["${change_key}"]="${change_val}"
    done

    mv -- "${tmpfile}" "${CONFIG_FILE}" || {
      log_err "Failed to write config"
      return 1
    }
    pkill -HUP -x systemd-logind 2>/dev/null || true
  fi

  # Save power config changes
  if ((${#pending_power_changes[@]} > 0)); then
    {
      echo "# Dusky Power Manager Configuration"
      echo "# Generated: $(date)"
      echo ""
      for change in "${pending_power_changes[@]}"; do
        echo "${change}"
      done
    } >"${POWER_CONFIG}"

    # Apply power settings immediately
    for change in "${pending_power_changes[@]}"; do
      local pkey pval
      pkey=${change%%=*}
      pval=${change#*=}
      POWER_CACHE["${pkey}"]="${pval}"

      case ${pkey} in
      POWER_PROFILE) apply_power_profile "${pval}" ;;
      CPU_GOVERNOR) apply_cpu_governor "${pval}" ;;
      CPU_BOOST) apply_cpu_boost "${pval}" ;;
      SCREEN_BRIGHTNESS) apply_screen_brightness "${pval}" ;;
      WIFI_POWERSAVE) apply_wifi_powersave "${pval}" ;;
      USB_AUTOSUSPEND) apply_usb_autosuspend "${pval}" ;;
      SATA_LINK_POWER) apply_sata_power "${pval}" ;;
      NMI_WATCHDOG) apply_nmi_watchdog "${pval}" ;;
      LAPTOP_MODE) apply_laptop_mode "${pval}" ;;
      esac
    done
  fi

  UNSAVED_CHANGES=0
  return 0
}

# =============================================================================
# ▼ UI RENDERING ▼
# =============================================================================

draw_ui() {
  local buf="" pad_buf="" padded_item="" item val display
  local -i i current_col=3 zone_start len count pad_needed
  local -i visible_len left_pad right_pad

  buf+="${CURSOR_HOME}"
  buf+="${C_MAGENTA}┌${H_LINE}┐${C_RESET}"$'\n'

  local status_txt="${APP_VERSION}"
  local status_clr="${C_CYAN}"
  if ((UNSAVED_CHANGES)); then
    status_txt="UNSAVED"
    status_clr="${C_YELLOW}"
  fi

  visible_len=$((${#APP_TITLE} + ${#status_txt} + 1))
  left_pad=$(((BOX_INNER_WIDTH - visible_len) / 2))
  right_pad=$((BOX_INNER_WIDTH - visible_len - left_pad))

  printf -v pad_buf '%*s' "${left_pad}" ''
  buf+="${C_MAGENTA}│${pad_buf}${C_WHITE}${APP_TITLE} ${status_clr}${status_txt}${C_MAGENTA}"
  printf -v pad_buf '%*s' "${right_pad}" ''
  buf+="${pad_buf}│${C_RESET}"$'\n'

  local tab_line="${C_MAGENTA}│ "
  TAB_ZONES=()
  for ((i = 0; i < TAB_COUNT; i++)); do
    local name=${TABS[i]}
    len=${#name}
    zone_start=${current_col}

    if ((i == CURRENT_TAB)); then
      tab_line+="${C_CYAN}${C_INVERSE} ${name} ${C_RESET}${C_MAGENTA}│ "
    else
      tab_line+="${C_GREY} ${name} ${C_MAGENTA}│ "
    fi

    TAB_ZONES+=("${zone_start}:$((zone_start + len + 1))")
    ((current_col += len + 4)) || true
  done

  pad_needed=$((BOX_INNER_WIDTH - current_col + 2))
  ((pad_needed > 0)) && {
    printf -v pad_buf '%*s' "${pad_needed}" ''
    tab_line+="${pad_buf}"
  }
  tab_line+="${C_MAGENTA}│${C_RESET}"
  buf+="${tab_line}"$'\n'
  buf+="${C_MAGENTA}└${H_LINE}┘${C_RESET}"$'\n'

  count=${TAB_ROW_COUNTS[CURRENT_TAB]}

  if ((count == 0)); then
    SELECTED_ROW=0
  else
    ((SELECTED_ROW >= count)) && SELECTED_ROW=$((count - 1))
    ((SELECTED_ROW < 0)) && SELECTED_ROW=0
  fi

  ((SELECTED_ROW < SCROLL_OFFSET)) && SCROLL_OFFSET=${SELECTED_ROW}
  ((SELECTED_ROW >= SCROLL_OFFSET + MAX_DISPLAY_ROWS)) &&
    SCROLL_OFFSET=$((SELECTED_ROW - MAX_DISPLAY_ROWS + 1))

  ((SCROLL_OFFSET > 0)) && buf+="  ${C_GREY}▲${C_RESET}"$'\n' || buf+=$'\n'

  for ((i = SCROLL_OFFSET; i < SCROLL_OFFSET + MAX_DISPLAY_ROWS; i++)); do
    if ((i >= count)); then
      buf+="${CLR_EOL}"$'\n'
      continue
    fi

    item=${TAB_REGISTRY["${CURRENT_TAB}:${i}"]}
    val=${VALUE_CACHE[${item}]}

    case ${val} in
    yes | true | enabled) display="${C_GREEN}${val}${C_RESET}" ;;
    no | false | disabled) display="${C_RED}${val}${C_RESET}" ;;
    "${UNSET_MARKER}") display="${C_YELLOW}⚠ UNSET${C_RESET}" ;;
    poweroff) display="${C_RED}${val}${C_RESET}" ;;
    suspend) display="${C_CYAN}${val}${C_RESET}" ;;
    ignore) display="${C_GREY}${val}${C_RESET}" ;;
    performance) display="${C_RED}${val}${C_RESET}" ;;
    balanced) display="${C_BLUE}${val}${C_RESET}" ;;
    powersave) display="${C_GREEN}${val}${C_RESET}" ;;
    max_performance) display="${C_RED}${val}${C_RESET}" ;;
    medium_power) display="${C_BLUE}${val}${C_RESET}" ;;
    min_power) display="${C_GREEN}${val}${C_RESET}" ;;
    *) display="${C_WHITE}${val}${C_RESET}" ;;
    esac

    printf -v padded_item "%-${ITEM_PADDING}s" "${item:0:ITEM_PADDING}"

    if ((i == SELECTED_ROW)); then
      buf+="${C_CYAN} ➤ ${C_INVERSE}${padded_item}${C_RESET} : ${display}${CLR_EOL}"$'\n'
    else
      buf+="    ${padded_item} : ${display}${CLR_EOL}"$'\n'
    fi
  done

  ((count > SCROLL_OFFSET + MAX_DISPLAY_ROWS)) && buf+="  ${C_GREY}▼${C_RESET}"$'\n' || buf+=$'\n'

  buf+=$'\n'"${C_CYAN} [Tab] Switch  [r]eset  [s] Save  [a]pply  [Arrows] Nav  [q] Quit${C_RESET}"$'\n'
  printf '%s' "${buf}"
}

# =============================================================================
# ▼ INPUT HANDLING ▼
# =============================================================================

navigate() {
  local -i dir=$1
  local -i count=${TAB_ROW_COUNTS[CURRENT_TAB]}
  ((count == 0)) && return 0
  ((SELECTED_ROW += dir)) || true
  ((SELECTED_ROW < 0)) && SELECTED_ROW=$((count - 1))
  ((SELECTED_ROW >= count)) && SELECTED_ROW=0
  return 0
}

navigate_page() {
  local -i dir=$1
  local -i count=${TAB_ROW_COUNTS[CURRENT_TAB]}
  ((count == 0)) && return 0
  ((SELECTED_ROW += dir * MAX_DISPLAY_ROWS)) || true
  ((SELECTED_ROW < 0)) && SELECTED_ROW=0
  ((SELECTED_ROW >= count)) && SELECTED_ROW=$((count - 1))
  return 0
}

navigate_end() {
  local -i target=$1
  local -i count=${TAB_ROW_COUNTS[CURRENT_TAB]}
  ((count == 0)) && return 0
  ((target == 0)) && SELECTED_ROW=0 || SELECTED_ROW=$((count - 1))
  return 0
}

switch_tab() {
  local -i dir=${1:-1}
  ((CURRENT_TAB += dir)) || :
  ((CURRENT_TAB >= TAB_COUNT)) && CURRENT_TAB=0
  ((CURRENT_TAB < 0)) && CURRENT_TAB=$((TAB_COUNT - 1))

  SELECTED_ROW=0
  SCROLL_OFFSET=0
  load_values_to_ui
}

handle_mouse() {
  local input=$1
  local -i button x y i start end
  local match_type zone
  local regex='^\[<([0-9]+);([0-9]+);([0-9]+)([Mm])$'

  [[ ! ${input} =~ ${regex} ]] && return 0

  button=${BASH_REMATCH[1]}
  x=${BASH_REMATCH[2]}
  y=${BASH_REMATCH[3]}
  match_type=${BASH_REMATCH[4]}

  ((button == 64)) && {
    navigate -1
    return 0
  }
  ((button == 65)) && {
    navigate 1
    return 0
  }

  [[ ${match_type} != "M" ]] && return 0

  if ((y == 3)); then
    for ((i = 0; i < TAB_COUNT; i++)); do
      zone=${TAB_ZONES[i]}
      start=${zone%%:*}
      end=${zone##*:}
      if ((x >= start && x <= end)); then
        CURRENT_TAB=${i}
        SELECTED_ROW=0
        SCROLL_OFFSET=0
        load_values_to_ui
        return 0
      fi
    done
  fi
}

apply_current_profile() {
  ((CURRENT_TAB != 3)) && return 0

  local label key
  label=${TAB_REGISTRY["3:0"]}
  IFS='|' read -r key _ _ <<<"${ITEM_SCHEMA[${label}]}"

  local profile=${VALUE_CACHE[${label}]}
  [[ ${profile} == "${UNSET_MARKER}" ]] && profile="balanced"

  apply_power_profile "${profile}"
  log_info "Applied ${profile} profile"
  sleep 1
}

# =============================================================================
# ▼ MAIN ▼
# =============================================================================

main() {
  if ((BASH_VERSINFO[0] < 5)); then
    log_err "Bash 5.0+ required (found: ${BASH_VERSION})"
    exit 1
  fi

  local -a required_cmds=(sed pkill grep)
  local cmd
  for cmd in "${required_cmds[@]}"; do
    command -v "${cmd}" >/dev/null 2>&1 || {
      log_err "Required: ${cmd}"
      exit 1
    }
  done

  init_items
  parse_config || exit 1
  parse_power_config
  load_values_to_ui

  command -v stty >/dev/null 2>&1 && ORIGINAL_STTY=$(stty -g 2>/dev/null) || ORIGINAL_STTY=""

  printf '%s%s%s%s' "${MOUSE_ON}" "${CURSOR_HIDE}" "${CLR_SCREEN}" "${CURSOR_HOME}"

  local key seq char
  while true; do
    draw_ui
    IFS= read -rsn1 key || break

    if [[ ${key} == $'\x1b' ]]; then
      seq=""
      while IFS= read -rsn1 -t 0.01 char; do seq+="${char}"; done
      case ${seq} in
      '[Z') switch_tab -1 ;;
      '[A' | 'OA') navigate -1 ;;
      '[B' | 'OB') navigate 1 ;;
      '[C' | 'OC') modify_value "${TAB_REGISTRY["${CURRENT_TAB}:${SELECTED_ROW}"]}" 1 ;;
      '[D' | 'OD') modify_value "${TAB_REGISTRY["${CURRENT_TAB}:${SELECTED_ROW}"]}" -1 ;;
      '[5~') navigate_page -1 ;;
      '[6~') navigate_page 1 ;;
      '[H' | '[1~') navigate_end 0 ;;
      '[F' | '[4~') navigate_end 1 ;;
      '['*'<'*) handle_mouse "${seq}" ;;
      esac
    else
      case ${key} in
      k | K) navigate -1 ;;
      j | J) navigate 1 ;;
      l | L) modify_value "${TAB_REGISTRY["${CURRENT_TAB}:${SELECTED_ROW}"]}" 1 ;;
      h | H) modify_value "${TAB_REGISTRY["${CURRENT_TAB}:${SELECTED_ROW}"]}" -1 ;;
      g) navigate_end 0 ;;
      G) navigate_end 1 ;;
      s | S) save_config || true ;;
      a | A) apply_current_profile ;;
      r | R) reset_defaults ;;
      $'\t') switch_tab 1 ;;
      q | Q | $'\x03') break ;;
      esac
    fi
  done

  if ((UNSAVED_CHANGES)); then
    printf '%s%s%s' "${MOUSE_OFF}" "${CURSOR_SHOW}" "${C_RESET}"
    clear
    printf '%sUnsaved changes detected. Save? [Y/n] %s' "${C_YELLOW}" "${C_RESET}"
    local yn=""
    read -r -n 1 yn
    printf '\n'
    [[ ! ${yn} =~ ^[Nn]$ ]] && save_config
  fi
}

main "$@"
