#!/usr/bin/env bash
# ==============================================================================
# THEME CONTROLLER
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION ---
readonly BASE_WALL_DIR="${HOME}/Wallpapers"
readonly LIGHT_DIR="${BASE_WALL_DIR}/Light"
readonly DARK_DIR="${BASE_WALL_DIR}/Dark"

readonly STATE_DIR="${HOME}/.config/hypr/theme_state"
readonly STATE_FILE="${STATE_DIR}/state.conf"
readonly PUBLIC_STATE="${STATE_DIR}/state"
readonly LOCK_FILE="/tmp/theme_ctl.lock"
readonly TRACK_LIGHT="${STATE_DIR}/light_last"
readonly TRACK_DARK="${STATE_DIR}/dark_last"

# Defaults
THEME_MODE="dark"
CURRENT_WALL=""

# Cleanup tracking
_TEMP_FILE=""

cleanup() {
  local exit_code=$?
  [[ -n "${_TEMP_FILE:-}" && -e "$_TEMP_FILE" ]] && rm -f "$_TEMP_FILE"
  exit "$exit_code"
}
trap cleanup EXIT

# --- LOGGING & LOCKING ---
log() { printf '\033[1;34m[THEME]\033[0m %s\n' "$*" >&2; }
die() {
  log "ERROR: $*"
  notify-send "Theme Error" "$*" -u critical 2>/dev/null || true
  exit 1
}

# Check dependencies
check_deps() {
  local missing=()
  command -v matugen >/dev/null 2>&1 || missing+=("matugen")
  command -v swww >/dev/null 2>&1 || missing+=("swww")

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing dependencies: ${missing[*]}"
  fi
}

# Clean stale locks
clean_stale_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    # Check if the process holding the lock still exists
    if [[ -s "$LOCK_FILE" ]]; then
      local lock_pid
      lock_pid=$(lsof -t "$LOCK_FILE" 2>/dev/null || echo "")

      if [[ -n "$lock_pid" ]]; then
        # Check if that PID is actually our script
        if ps -p "$lock_pid" -o comm= 2>/dev/null | grep -q "theme_ctl\|bash"; then
          local lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
          if [[ $lock_age -gt 30 ]]; then
            log "Lock held by PID $lock_pid for ${lock_age}s, removing stale lock"
            rm -f "$LOCK_FILE"
          else
            log "Active lock held by PID $lock_pid (${lock_age}s old)"
            return 1
          fi
        else
          log "Lock file exists but process $lock_pid is not theme_ctl, removing"
          rm -f "$LOCK_FILE"
        fi
      else
        log "Lock file exists but no process holds it, removing"
        rm -f "$LOCK_FILE"
      fi
    else
      # Empty lock file
      log "Empty lock file found, removing"
      rm -f "$LOCK_FILE"
    fi
  fi
  return 0
}

# Atomic Lock
acquire_lock() {
  local force_unlock="${1:-}"

  if [[ "$force_unlock" == "--force" ]]; then
    log "Force unlock requested"
    rm -f "$LOCK_FILE"
  fi

  if ! clean_stale_lock; then
    log "Could not acquire lock (another instance may be running)"
    return 1
  fi

  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    log "Locked: Another instance is running"
    return 1
  fi

  return 0
}

# --- STATE MANAGEMENT (ATOMIC) ---

read_state() {
  THEME_MODE="dark"
  CURRENT_WALL=""

  [[ -f "$STATE_FILE" ]] || return 0

  local key value
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    [[ -z "$key" || "${key:0:1}" == "#" ]] && continue

    # Strip quotes if present on both sides
    if [[ ${#value} -ge 2 ]]; then
      if [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
        value="${value:1:-1}"
      elif [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]]; then
        value="${value:1:-1}"
      fi
    fi

    case "$key" in
    THEME_MODE) THEME_MODE="$value" ;;
    CURRENT_WALL) CURRENT_WALL="$value" ;;
    esac
  done <"$STATE_FILE"

  # Validate state against actual wallpaper location
  if [[ -n "$CURRENT_WALL" && -f "$CURRENT_WALL" ]]; then
    if [[ "$CURRENT_WALL" == "$LIGHT_DIR"/* ]]; then
      if [[ "$THEME_MODE" != "light" ]]; then
        log "Warning: State mismatch detected. Correcting to light."
        THEME_MODE="light"
      fi
    elif [[ "$CURRENT_WALL" == "$DARK_DIR"/* ]]; then
      if [[ "$THEME_MODE" != "dark" ]]; then
        log "Warning: State mismatch detected. Correcting to dark."
        THEME_MODE="dark"
      fi
    fi
  fi

  log "State loaded: mode=$THEME_MODE, wall=${CURRENT_WALL##*/}"
}

save_state() {
  mkdir -p "$STATE_DIR"

  # Use atomic write with temp file
  _TEMP_FILE=$(mktemp "${STATE_DIR}/state.conf.XXXXXX")

  cat <<EOF >"$_TEMP_FILE"
# Theme Controller State
THEME_MODE="$THEME_MODE"
CURRENT_WALL="$CURRENT_WALL"
EOF

  # Atomic move
  mv -f "$_TEMP_FILE" "$STATE_FILE"
  _TEMP_FILE=""

  # Write public state
  if [[ "$THEME_MODE" == "light" ]]; then
    echo 1 >"$PUBLIC_STATE"
  else
    echo 0 >"$PUBLIC_STATE"
  fi

  log "State saved: $THEME_MODE -> ${CURRENT_WALL##*/}"
}

# --- WALLPAPER TRACKING (SEQUENTIAL) ---

select_next_wallpaper() {
  local target_dir="$1"
  local track_file

  if [[ "$THEME_MODE" == "light" ]]; then
    track_file="$TRACK_LIGHT"
  else
    track_file="$TRACK_DARK"
  fi

  # Find all wallpapers, sorted naturally
  local -a wallpapers
  mapfile -d '' wallpapers < <(
    find "$target_dir" -type f \( \
      -iname "*.jpg" -o \
      -iname "*.jpeg" -o \
      -iname "*.png" -o \
      -iname "*.webp" \
      \) -print0 | sort -zV
  )

  ((${#wallpapers[@]} > 0)) || return 1

  # Get last wallpaper
  local last_wal=""
  [[ -f "$track_file" ]] && last_wal=$(<"$track_file")

  # Find next index
  local next_index=0
  if [[ -n "$last_wal" ]]; then
    local i
    for i in "${!wallpapers[@]}"; do
      if [[ "${wallpapers[$i]##*/}" == "$last_wal" ]]; then
        next_index=$((i + 1))
        break
      fi
    done
  fi

  # Wrap around
  ((next_index >= ${#wallpapers[@]})) && next_index=0

  local selected="${wallpapers[$next_index]}"

  # Update tracking file
  mkdir -p "${track_file%/*}"
  printf '%s' "${selected##*/}" >"$track_file"

  printf '%s' "$selected"
}

# --- SERVICE MANAGEMENT ---

wait_for_process() {
  local proc_name="$1"
  local attempts=0
  local max_attempts=50

  while ! pgrep -x "$proc_name" &>/dev/null; do
    ((++attempts > max_attempts)) && return 1
    sleep 0.1
  done
  return 0
}

ensure_swww_ready() {
  # Check if already running
  if pgrep -x swww-daemon >/dev/null 2>&1; then
    # Verify it's responsive
    if swww query >/dev/null 2>&1; then
      log "swww-daemon already running"
      return 0
    else
      log "swww-daemon unresponsive, restarting"
      pkill -9 swww-daemon 2>/dev/null || true
      sleep 0.3
    fi
  fi

  log "Starting swww-daemon"

  # Use UWSM if available for proper systemd integration
  if command -v uwsm-app >/dev/null 2>&1; then
    uwsm-app -- swww-daemon --format xrgb >/dev/null 2>&1 &
    disown
  else
    swww-daemon --format xrgb >/dev/null 2>&1 &
    disown
  fi

  # Wait for daemon to be ready
  if ! wait_for_process "swww-daemon"; then
    die "swww-daemon failed to start"
  fi

  # Wait for it to be responsive
  local attempts=0
  while ! swww query >/dev/null 2>&1; do
    ((++attempts > 25)) && die "swww-daemon not responding"
    sleep 0.2
  done

  log "swww-daemon ready"
}

# --- APP SYNC ---

update_apps() {
  local scheme='prefer-dark'
  [[ "$THEME_MODE" == "light" ]] && scheme='prefer-light'

  log "Updating apps to $scheme"

  # GTK
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface color-scheme "$scheme" 2>/dev/null || {
      log "Warning: gsettings failed (non-critical)"
    }
  fi
}

reload_ui() {
  log "Reloading UI components"

  "$HOME/cloudyy_scripts/restart_waybar.sh" >/dev/null 2>&1 &

  # SwayNC - restart for theme
  if pgrep -x swaync >/dev/null 2>&1; then
    log "Restarting SwayNC"
    pkill -9 swaync 2>/dev/null || true
    sleep 0.3
    if command -v uwsm-app >/dev/null 2>&1; then
      uwsm-app -- swaync >/dev/null 2>&1 &
    else
      swaync >/dev/null 2>&1 &
    fi
    disown
  fi

  # Thunar - reload theme only (send USR1 signal to reload config)
  if pgrep -x thunar >/dev/null 2>&1; then
    log "Reloading Thunar theme"
    # Send SIGUSR1 to reload GTK theme without killing process
    pkill -SIGUSR1 thunar 2>/dev/null || true
    # If that fails, try HUP
    sleep 0.2
    pkill -HUP thunar 2>/dev/null || true
  fi

  # Kitty - reload config for all running instances
  if pgrep -x kitty >/dev/null 2>&1; then
    log "Reloading Kitty instances"
    # Send SIGUSR1 to all kitty instances to reload config
    pkill -SIGUSR1 kitty 2>/dev/null || true
    # Also update kitty color scheme via remote control if available
    if command -v kitty >/dev/null 2>&1; then
      kitty @ --to unix:/tmp/kitty set-colors --all --configured ~/.config/kitty/current-theme.conf 2>/dev/null || true
    fi
  fi

  # Alacritty - reload config
  if pgrep -x alacritty >/dev/null 2>&1; then
    log "Reloading Alacritty instances"
    # Alacritty watches config file and auto-reloads
    touch ~/.config/alacritty/alacritty.toml 2>/dev/null || touch ~/.config/alacritty/alacritty.yml 2>/dev/null || true
  fi

  # Wezterm - reload config
  if pgrep -x wezterm-gui >/dev/null 2>&1 || pgrep -x wezterm >/dev/null 2>&1; then
    log "Reloading Wezterm instances"
    # Wezterm reloads on SIGHUP
    pkill -HUP wezterm-gui 2>/dev/null || true
    pkill -HUP wezterm 2>/dev/null || true
  fi

  # Foot - reload config
  if pgrep -x foot >/dev/null 2>&1; then
    log "Reloading Foot instances"
    # Foot doesn't have live reload, but respects new instances
    # Just ensure config is touched for next launch
    touch ~/.config/foot/foot.ini 2>/dev/null || true
  fi

  # Btop - reload config
  if pgrep -x btop >/dev/null 2>&1; then
    log "Reloading Btop instances"
    # Btop reloads on SIGUSR1
    pkill -SIGUSR1 btop 2>/dev/null || true
  fi

  # Htop - reload config (limited support)
  if pgrep -x htop >/dev/null 2>&1; then
    log "Reloading Htop instances"
    # Htop doesn't support live reload well, but touch config
    touch ~/.config/htop/htoprc 2>/dev/null || true
  fi

  # Tmux - reload config for all sessions
  if command -v tmux >/dev/null 2>&1 && tmux list-sessions >/dev/null 2>&1; then
    log "Reloading Tmux sessions"
    # Reload tmux config for all sessions
    tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null ||
      tmux source-file ~/.tmux.conf 2>/dev/null || true
  fi

  # Zellij - reload config
  if pgrep -x zellij >/dev/null 2>&1; then
    log "Reloading Zellij instances"
    # Zellij doesn't have live reload, touch config for new sessions
    touch ~/.config/zellij/config.kdl 2>/dev/null || true
  fi

  # Rofi - no daemon, but clear cache
  if [[ -d "$HOME/.cache/rofi" ]]; then
    log "Clearing Rofi cache"
    rm -rf "$HOME/.cache/rofi/"*.rasi 2>/dev/null || true
  fi

  # LazyVim/Neovim - send SIGUSR1 to reload colorscheme
  if pgrep -x nvim >/dev/null 2>&1; then
    log "Reloading Neovim instances"
    # Create a temporary file that nvim can watch
    mkdir -p ~/.cache/theme_notify
    touch ~/.cache/theme_notify/colorscheme_changed
    # Send SIGUSR1 to trigger autocmd if configured
    pkill -SIGUSR1 nvim 2>/dev/null || true
  fi
}

# --- CORE OPERATIONS ---

generate_colors() {
  local img="$1"

  log "Generating colors from: ${img##*/}"

  if matugen image "$img" -m "$THEME_MODE" 2>&1 | tee /tmp/matugen.log; then
    log "Matugen succeeded"
    update_apps
    return 0
  else
    log "ERROR: Matugen failed, check /tmp/matugen.log"
    return 1
  fi
}

apply_wallpaper() {
  local img="$1"
  [[ -f "$img" ]] || die "Wallpaper not found: $img"

  # Validate file type
  local mime=$(file --mime-type -b "$img")
  case "$mime" in
  image/jpeg | image/png | image/webp)
    log "Valid image: ${img##*/}"
    ;;
  *)
    die "Unsupported file type: $mime"
    ;;
  esac

  log "Applying wallpaper: ${img##*/}"

  # Ensure swww is ready
  ensure_swww_ready

  # Apply wallpaper synchronously
  if swww img "$img" \
    --transition-type grow \
    --transition-duration 2 \
    --transition-fps 60 2>&1 | tee -a /tmp/swww.log; then
    log "Wallpaper applied"
  else
    die "Failed to apply wallpaper"
  fi

  # Wait for transition
  sleep 2.1

  # Generate colors
  if generate_colors "$img"; then
    log "Colors generated"
  else
    log "Warning: Color generation failed"
  fi

  # NOW save state (everything completed)
  CURRENT_WALL="$img"
  save_state

  # Reload UI last
  sleep 0.5
  reload_ui
}

get_current_wallpaper() {
  local swww_output
  swww_output=$(swww query 2>&1 | head -n 1) || return 1
  [[ -n "$swww_output" ]] || return 1

  local current="${swww_output##*image: }"
  # Trim trailing whitespace
  current="${current%"${current##*[![:space:]]}"}"

  printf '%s' "$current"
}

# --- COMMANDS ---

cmd_toggle() {
  read_state

  # Debounce
  local last_toggle_file="/tmp/theme_ctl_last_toggle"
  local current_time=$(date +%s)
  if [[ -f "$last_toggle_file" ]]; then
    local last_time=$(cat "$last_toggle_file")
    local time_diff=$((current_time - last_time))
    if [[ $time_diff -lt 3 ]]; then
      log "Toggle debounced (${time_diff}s since last, 3s required)"
      notify-send "Theme" "Please wait before toggling again" 2>/dev/null || true
      exit 0
    fi
  fi
  echo "$current_time" >"$last_toggle_file"

  local new_mode="dark"
  [[ "$THEME_MODE" == "dark" ]] && new_mode="light"
  log "Toggling: $THEME_MODE -> $new_mode"

  THEME_MODE="$new_mode"
  cmd_next
  sleep 0.5
  reload_ui
}

cmd_next() {
  # Select directory
  local target_dir=""
  if [[ "$THEME_MODE" == "light" ]]; then
    target_dir="$LIGHT_DIR"
  else
    target_dir="$DARK_DIR"
  fi

  log "Looking in: $target_dir"
  [[ -d "$target_dir" ]] || die "Directory missing: $target_dir"

  # Get next wallpaper chronologically
  local next_wall
  next_wall=$(select_next_wallpaper "$target_dir") || die "No wallpapers found"

  log "Selected: ${next_wall##*/}"
  notify-send "Theme" "Switching to $THEME_MODE..." 2>/dev/null || true

  apply_wallpaper "$next_wall"
  sleep 0.5
  reload_ui

}

cmd_random() {
  read_state

  local target_dir=""
  if [[ "$THEME_MODE" == "light" ]]; then
    target_dir="$LIGHT_DIR"
  else
    target_dir="$DARK_DIR"
  fi

  [[ -d "$target_dir" ]] || die "Directory missing: $target_dir"

  # Find wallpapers
  shopt -s nullglob globstar nocaseglob
  local walls=("$target_dir"/**/*.{jpg,jpeg,png,webp})
  shopt -u nullglob globstar nocaseglob

  ((${#walls[@]} > 0)) || die "No wallpapers found"

  local rand_wall="${walls[RANDOM % ${#walls[@]}]}"
  log "Random: ${rand_wall##*/}"

  apply_wallpaper "$rand_wall"
  sleep 0.5
  reload_ui
}

cmd_refresh() {
  read_state
  ensure_swww_ready

  # Get current wallpaper from swww
  local current
  if ! current=$(get_current_wallpaper); then
    log "Could not get current wallpaper, using state"
    current="$CURRENT_WALL"
  fi

  [[ -f "$current" ]] || die "Current wallpaper not found: $current"

  log "Refreshing: ${current##*/}"

  # Reapply with fade
  swww img "$current" \
    --transition-type fade \
    --transition-duration 0.5 \
    --transition-fps 60 2>&1 | tee -a /tmp/swww.log

  sleep 0.6

  # Regenerate colors
  if generate_colors "$current"; then
    CURRENT_WALL="$current"
    save_state
  fi

  sleep 0.5
  reload_ui
}

cmd_set_image() {
  local img="$1"
  [[ -f "$img" ]] || die "File not found: $img"

  read_state
  apply_wallpaper "$(realpath "$img")"
}

cmd_reset() {
  log "Resetting theme controller state..."

  # Kill all running processes
  log "Stopping services..."
  pkill -9 swww-daemon 2>/dev/null || true
  pkill -9 swww 2>/dev/null || true
  sleep 0.5

  # Remove state files
  log "Clearing state files..."
  rm -f "$STATE_FILE" 2>/dev/null || true
  rm -f "$PUBLIC_STATE" 2>/dev/null || true
  rm -f "$TRACK_LIGHT" 2>/dev/null || true
  rm -f "$TRACK_DARK" 2>/dev/null || true
  rm -f /tmp/theme_ctl_last_toggle 2>/dev/null || true

  # Recreate default state
  log "Creating fresh state..."
  mkdir -p "$STATE_DIR"

  _TEMP_FILE=$(mktemp "${STATE_DIR}/state.conf.XXXXXX")
  cat <<EOF >"$_TEMP_FILE"
# Theme Controller State (Reset)
THEME_MODE="dark"
CURRENT_WALL=""
EOF
  mv -f "$_TEMP_FILE" "$STATE_FILE"
  _TEMP_FILE=""

  echo 0 >"$PUBLIC_STATE"

  log "State reset complete!"
  notify-send "Theme Controller" "State reset to dark mode" 2>/dev/null || true

  # Optionally apply a wallpaper
  if [[ "${1:-}" == "--apply" ]]; then
    log "Applying fresh wallpaper..."
    THEME_MODE="dark"
    cmd_random
  fi
  sleep 0.5
  reload_ui
}

# --- MAIN ---

check_deps

# Initialize state if needed
if [[ ! -f "$STATE_FILE" ]]; then
  log "Initializing state file"
  mkdir -p "$STATE_DIR"
  cat <<EOF >"$STATE_FILE"
# Theme Controller State
THEME_MODE="$THEME_MODE"
CURRENT_WALL=""
EOF
fi

read_state

# Parse global flags before command
FORCE_UNLOCK=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
  --force)
    FORCE_UNLOCK=1
    shift
    ;;
  *)
    break
    ;;
  esac
done

# Acquire lock (with force flag if needed)
if [[ $FORCE_UNLOCK -eq 1 ]]; then
  acquire_lock --force || die "Failed to acquire lock even with --force"
else
  acquire_lock || exit 0
fi

case "${1:-}" in
set | next)
  # Sequential next wallpaper
  shift
  # Parse --mode if provided
  while (($# > 0)); do
    case "$1" in
    --mode)
      [[ -n "${2:-}" ]] || die "--mode requires value"
      THEME_MODE="$2"
      shift 2
      ;;
    *)
      shift
      ;;
    esac
  done
  cmd_next
  ;;
toggle)
  cmd_toggle
  ;;
random)
  cmd_random
  ;;
refresh)
  cmd_refresh
  ;;
set-image)
  [[ -n "${2:-}" ]] || die "Usage: set-image <path>"
  cmd_set_image "$2"
  ;;
reset)
  shift
  cmd_reset "$@"
  ;;
unlock)
  log "Removing lock file..."
  rm -f "$LOCK_FILE"
  log "Lock removed. You can now run commands normally."
  notify-send "Theme Controller" "Lock file removed" 2>/dev/null || true
  exit 0
  ;;
get-mode)
  echo "$THEME_MODE"
  ;;
get-state)
  read_state
  echo "=== Theme Controller State ==="
  echo "Mode: $THEME_MODE"
  echo "Wallpaper: ${CURRENT_WALL:-none}"
  echo ""
  echo "=== Files ==="
  echo "State File: $STATE_FILE"
  echo "Public State: $(cat "$PUBLIC_STATE" 2>/dev/null || echo "N/A")"
  echo "Light Track: $(cat "$TRACK_LIGHT" 2>/dev/null || echo "none")"
  echo "Dark Track: $(cat "$TRACK_DARK" 2>/dev/null || echo "none")"
  echo ""
  echo "=== Lock Status ==="
  if [[ -f "$LOCK_FILE" ]]; then
    local lock_age=$(($(date +%s) - $(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)))
    echo "Lock File: EXISTS (${lock_age}s old)"
    local lock_pid=$(lsof -t "$LOCK_FILE" 2>/dev/null || echo "none")
    echo "Held by PID: $lock_pid"
    if [[ -n "$lock_pid" && "$lock_pid" != "none" ]]; then
      echo "Process: $(ps -p "$lock_pid" -o comm= 2>/dev/null || echo "not running")"
    fi
  else
    echo "Lock File: OK (not locked)"
  fi
  ;;
*)
  cat <<EOF
Usage: $0 [--force] <command>

Global Flags:
  --force           Force unlock and run command

Commands:
  next              Next wallpaper (chronological)
  set --mode <mode> Set mode and get next wallpaper
  toggle            Toggle light/dark
  random            Random wallpaper
  refresh           Regenerate colors from current
  set-image <path>  Apply specific image
  reset [--apply]   Reset all state (optionally apply wallpaper)
  unlock            Remove lock file
  get-mode          Print current mode
  get-state         Show detailed state information

Examples:
  $0 --force set --mode dark  # Force unlock and switch to dark
  $0 unlock                   # Just remove lock file
  $0 reset --apply            # Full reset with wallpaper
  $0 get-state                # Check if locked

Troubleshooting:
  If stuck with "Locked: another instance running":
  1. Run: $0 get-state        # Check lock status
  2. Run: $0 unlock           # Remove lock
  3. Or:  $0 --force random   # Force unlock and apply wallpaper

EOF
  exit 1
  ;;
esac

log "Done!"
