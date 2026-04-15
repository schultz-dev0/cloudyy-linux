#!/usr/bin/env bash
# ==============================================================================
# SYSTEM UPDATER
# Handles: pacman system update, AUR updates, and local GitHub repo pulls
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION ---
# Edit these to match your setup
readonly AUR_HELPER="${AUR_HELPER:-yay}" # yay | paru | trizen
readonly REPO_DIRS=( # Add all your local GitHub repos here
  "${HOME}/cloudyy-linux"
  #"${HOME}/dots" #for my main rig
)
readonly PRESERVED_REPO_PATHS=(
  ".config/hypr/hyprland.conf"
)
readonly LOG_DIR="${HOME}/.local/share/system-update"
readonly LOG_FILE="${LOG_DIR}/update_$(date +%Y%m%d_%H%M%S).log"
readonly LATEST_LOG="${LOG_DIR}/latest.log"
readonly NOTIFY_ON_COMPLETE="${NOTIFY_ON_COMPLETE:-1}"

# --- COLORS ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- COUNTERS ---
STEPS_DONE=0
STEPS_TOTAL=0
ERRORS=()
WARNINGS=()

# --- LOGGING ---
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log() { printf "${BLUE}[UPDATE]${RESET} %s\n" "$*"; }
success() { printf "${GREEN}[  OK  ]${RESET} %s\n" "$*"; }
warn() {
  printf "${YELLOW}[ WARN ]${RESET} %s\n" "$*"
  WARNINGS+=("$*")
}
err() {
  printf "${RED}[FAILED]${RESET} %s\n" "$*"
  ERRORS+=("$*")
}
step() {
  STEPS_DONE=$((STEPS_DONE + 1))
  printf "\n${BOLD}${CYAN}━━━ Step ${STEPS_DONE}/${STEPS_TOTAL}: %s ${RESET}\n" "$*"
}
divider() { printf "${CYAN}%s${RESET}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }

notify_desktop() {
  [[ "$NOTIFY_ON_COMPLETE" == "1" ]] || return 0
  notify-send "System Updater" "$1" -u "${2:-normal}" -t 5000 2>/dev/null || true
}

# --- CHECKS ---

check_network() {
  log "Checking network connectivity..."
  if ! ping -c 1 -W 3 archlinux.org &>/dev/null; then
    warn "Network check failed — updates may fail if offline"
  else
    success "Network OK"
  fi
}

check_aur_helper() {
  if ! command -v "$AUR_HELPER" &>/dev/null; then
    warn "AUR helper '$AUR_HELPER' not found. Skipping AUR update."
    return 1
  fi
  return 0
}

is_preserved_repo_path() {
  local path="$1"
  local preserved_path
  for preserved_path in "${PRESERVED_REPO_PATHS[@]}"; do
    [[ "$path" == "$preserved_path" ]] && return 0
  done
  return 1
}

repo_has_blocking_changes() {
  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if ! is_preserved_repo_path "$path"; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(
    {
      git diff --name-only HEAD --
      git diff --cached --name-only --
    } | sort -u
  )
  return 1
}

preserve_repo_files() {
  local backup_dir="$1"
  local preserved_path
  local preserved_any=1

  mkdir -p "$backup_dir"

  for preserved_path in "${PRESERVED_REPO_PATHS[@]}"; do
    if ! git ls-files --error-unmatch -- "$preserved_path" >/dev/null 2>&1; then
      continue
    fi

    if [[ ! -f "$preserved_path" ]]; then
      continue
    fi

    mkdir -p "${backup_dir}/$(dirname "$preserved_path")"
    cp -- "$preserved_path" "${backup_dir}/${preserved_path}"
    git checkout HEAD -- "$preserved_path" >/dev/null 2>&1
    log "  Preserving local file during pull: $preserved_path"
    preserved_any=0
  done

  return "$preserved_any"
}

restore_repo_files() {
  local backup_dir="$1"
  local preserved_path
  local restored_any=1

  for preserved_path in "${PRESERVED_REPO_PATHS[@]}"; do
    if [[ ! -f "${backup_dir}/${preserved_path}" ]]; then
      continue
    fi

    mkdir -p "$(dirname "$preserved_path")"
    cp -- "${backup_dir}/${preserved_path}" "$preserved_path"
    log "  Restored local file after pull: $preserved_path"
    restored_any=0
  done

  return "$restored_any"
}

# --- UPDATE STEPS ---

update_pacman() {
  step "System update (pacman -Syu)"
  log "Running: sudo pacman -Syu --noconfirm"

  if sudo pacman -Syu --noconfirm; then
    success "Pacman system update complete"
  else
    err "Pacman update failed (exit code $?)"
    return 1
  fi
}

update_aur() {
  step "AUR update ($AUR_HELPER)"

  if ! check_aur_helper; then
    warn "Skipping AUR step — '$AUR_HELPER' not available"
    return 0
  fi

  log "Running: $AUR_HELPER -Syu --aur --noconfirm"

  if "$AUR_HELPER" -Syu --aur --noconfirm; then
    success "AUR update complete"
  else
    err "AUR update failed (exit code $?)"
    return 1
  fi
}

update_repos() {
  step "GitHub repo pulls"

  if ((${#REPO_DIRS[@]} == 0)); then
    warn "No repos configured in REPO_DIRS. Edit the script to add yours."
    return 0
  fi

  local pulled=0
  local skipped=0
  local failed=0

  for repo in "${REPO_DIRS[@]}"; do
    local blocking_path=""
    local preserve_dir=""
    local preserved_files=0

    # Expand tilde
    repo="${repo/#\~/$HOME}"

    if [[ ! -d "$repo" ]]; then
      warn "Repo not found, skipping: $repo"
      skipped=$((skipped + 1))
      continue
    fi

    if [[ ! -d "${repo}/.git" ]]; then
      warn "Not a git repo, skipping: $repo"
      skipped=$((skipped + 1))
      continue
    fi

    log "Pulling: $repo"
    pushd "$repo" >/dev/null

    # Check for uncommitted changes, but allow preserved files like hyprland.conf.
    if blocking_path="$(repo_has_blocking_changes)"; then
      warn "$repo has uncommitted changes in $blocking_path — skipping pull to avoid conflicts"
      skipped=$((skipped + 1))
      popd >/dev/null
      continue
    fi

    # Get current branch
    local branch
    branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo 'HEAD')"
    log "  Branch: $branch"

    preserve_dir="$(mktemp -d "${TMPDIR:-/tmp}/cloudyy-updater.XXXXXX")"
    if preserve_repo_files "$preserve_dir"; then
      preserved_files=1
    fi

    # Fetch and pull
    if git fetch --all --prune 2>&1 && git pull --ff-only 2>&1; then
      local commits
      commits="$(git log ORIG_HEAD..HEAD --oneline 2>/dev/null | wc -l || echo '?')"
      if [[ "$commits" == "0" || "$commits" == "?" ]]; then
        success "$repo — already up to date"
      else
        success "$repo — pulled $commits new commit(s)"
      fi
      pulled=$((pulled + 1))
    else
      err "Pull failed: $repo (may need manual merge)"
      failed=$((failed + 1))
    fi

    if [[ "$preserved_files" == "1" ]]; then
      restore_repo_files "$preserve_dir"
    fi
    rm -rf "$preserve_dir"

    popd >/dev/null
  done

  log "Repos: ${pulled} pulled, ${skipped} skipped, ${failed} failed"
  [[ "$failed" -gt 0 ]] && return 1
  return 0
}

# --- OPTIONAL STEPS ---

clean_cache() {
  step "Cache cleanup"
  log "Removing old pacman package cache (keeping last 2 versions)..."

  if command -v paccache &>/dev/null; then
    sudo paccache -rk2
    success "Pacman cache cleaned"
  else
    warn "paccache not found (install pacman-contrib). Skipping."
  fi

  if check_aur_helper 2>/dev/null; then
    log "Cleaning $AUR_HELPER cache..."
    "$AUR_HELPER" -Sc --noconfirm 2>/dev/null || warn "AUR cache clean failed"
  fi
}

check_orphans() {
  step "Orphan packages check"
  local orphans
  orphans="$(pacman -Qdtq 2>/dev/null || true)"

  if [[ -z "$orphans" ]]; then
    success "No orphaned packages found"
  else
    local count
    count="$(echo "$orphans" | wc -l)"
    warn "$count orphaned package(s) found. Remove with: sudo pacman -Rns \$(pacman -Qdtq)"
    echo "$orphans" | while read -r pkg; do
      log "  Orphan: $pkg"
    done
  fi
}

# --- SUMMARY ---

print_summary() {
  divider
  printf "\n${BOLD}UPDATE SUMMARY${RESET}\n\n"

  if ((${#ERRORS[@]} == 0)); then
    printf "${GREEN}${BOLD}✓ All steps completed successfully${RESET}\n"
    notify_desktop "✓ System update complete — no errors" normal
  else
    printf "${RED}${BOLD}✗ Completed with ${#ERRORS[@]} error(s):${RESET}\n"
    for e in "${ERRORS[@]}"; do
      printf "  ${RED}• %s${RESET}\n" "$e"
    done
    notify_desktop "⚠ Update finished with ${#ERRORS[@]} error(s)" critical
  fi

  if ((${#WARNINGS[@]} > 0)); then
    printf "\n${YELLOW}Warnings (${#WARNINGS[@]}):${RESET}\n"
    for w in "${WARNINGS[@]}"; do
      printf "  ${YELLOW}• %s${RESET}\n" "$w"
    done
  fi

  printf "\n${CYAN}Log saved:${RESET} %s\n" "$LOG_FILE"

  # Symlink latest log
  ln -sf "$LOG_FILE" "$LATEST_LOG"

  divider
}

# --- ARGUMENT PARSING ---

usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --aur-helper HELPER   Override AUR helper (default: yay)
  --no-aur              Skip AUR update
  --no-repos            Skip GitHub repo pulls
  --clean               Also clean package cache after update
  --orphans             Also check for orphaned packages
  --dry-run             Show what would run without executing
  --help                Show this help

Environment:
  AUR_HELPER=paru $0    Override AUR helper via env var
  NOTIFY_ON_COMPLETE=0  Disable desktop notifications

Examples:
  $0                    # Standard update (pacman + AUR + repos)
  $0 --clean --orphans  # Full cleanup run
  AUR_HELPER=paru $0    # Use paru instead of yay
EOF
}

# Parse flags
DO_AUR=1
DO_REPOS=1
DO_CLEAN=0
DO_ORPHANS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  --aur-helper)
    AUR_HELPER="$2"
    shift 2
    ;;
  --no-aur)
    DO_AUR=0
    shift
    ;;
  --no-repos)
    DO_REPOS=0
    shift
    ;;
  --clean)
    DO_CLEAN=1
    shift
    ;;
  --orphans)
    DO_ORPHANS=1
    shift
    ;;
  --dry-run)
    DRY_RUN=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    usage
    exit 1
    ;;
  esac
done

# Count steps
STEPS_TOTAL=1 # pacman always runs
[[ "$DO_AUR" == "1" ]] && STEPS_TOTAL=$((STEPS_TOTAL + 1))
[[ "$DO_REPOS" == "1" ]] && STEPS_TOTAL=$((STEPS_TOTAL + 1))
[[ "$DO_CLEAN" == "1" ]] && STEPS_TOTAL=$((STEPS_TOTAL + 1))
[[ "$DO_ORPHANS" == "1" ]] && STEPS_TOTAL=$((STEPS_TOTAL + 1))

# --- MAIN ---

divider
printf "${BOLD}${CYAN}  SYSTEM UPDATER  —  $(date '+%A %d %B %Y, %H:%M')${RESET}\n"
divider

if [[ "$DRY_RUN" == "1" ]]; then
  printf "${YELLOW}DRY RUN — no changes will be made${RESET}\n"
  log "Steps that would run:"
  log "  1. pacman -Syu"
  [[ "$DO_AUR" == "1" ]] && log "  2. $AUR_HELPER -Syu --aur"
  [[ "$DO_REPOS" == "1" ]] && log "  3. git pull on: ${REPO_DIRS[*]:-none configured}"
  [[ "$DO_CLEAN" == "1" ]] && log "  +. Cache cleanup"
  [[ "$DO_ORPHANS" == "1" ]] && log "  +. Orphan check"
  exit 0
fi

check_network

# Run steps — use || true to capture errors in ERRORS array without killing script
update_pacman || true
[[ "$DO_AUR" == "1" ]] && { update_aur || true; }
[[ "$DO_REPOS" == "1" ]] && { update_repos || true; }
[[ "$DO_CLEAN" == "1" ]] && { clean_cache || true; }
[[ "$DO_ORPHANS" == "1" ]] && { check_orphans || true; }

print_summary
