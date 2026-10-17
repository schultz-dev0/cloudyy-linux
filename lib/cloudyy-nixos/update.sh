#!/usr/bin/env bash

set -euo pipefail -E

bold='' dim='' accent='' green='' red='' reset=''
interactive=false
if [[ -t 1 && "${TERM:-dumb}" != dumb && ! -v NO_COLOR ]]; then
  interactive=true
  bold=$'\e[1m' dim=$'\e[2m' accent=$'\e[36m'
  green=$'\e[32m' red=$'\e[31m' reset=$'\e[0m'
fi
spinner_pid=''

stop_spinner() {
  if [[ -n "$spinner_pid" ]]; then
    kill "$spinner_pid" 2>/dev/null || true
    wait "$spinner_pid" 2>/dev/null || true
    spinner_pid=''
  fi
}

run_step() {
  local number="$1" label="$2" started="$SECONDS" result
  shift 2
  printf '\n[%s/3] %s\n' "$number" "$label" >> "$run_dir/update.log"
  if "$interactive" && [[ "$number" -lt 3 ]]; then
    (
      frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
      frame=0
      while true; do
        printf '\r\033[2K  %s[%s/3]%s  %-14s %s%s%s %ss' \
          "$dim" "$number" "$reset" "$label" "$accent" \
          "${frames[frame % ${#frames[@]}]}" "$reset" "$((SECONDS - started))"
        frame=$((frame + 1))
        sleep 0.12
      done
    ) &
    spinner_pid=$!
  else
    printf '  %s[%s/3]%s  %s\n' "$dim" "$number" "$reset" "$label"
  fi

  # Keep sudo in the foreground so authentication stays usable; its prompt uses /dev/tty.
  if "$@" >> "$run_dir/update.log" 2>&1; then result=0; else result=$?; fi
  stop_spinner
  "$interactive" && printf '\r\033[2K'
  if [[ "$result" -eq 0 ]]; then
    printf '  %s[%s/3]%s  %-14s %sdone%s  %s%ss%s\n' \
      "$dim" "$number" "$reset" "$label" "$green" "$reset" "$dim" "$((SECONDS - started))" "$reset"
  else
    printf '  %s[%s/3]%s  %-14s %sfailed%s\n\n' \
      "$dim" "$number" "$reset" "$label" "$red" "$reset"
    tail -n 18 "$run_dir/update.log"
    printf '\n  %sUpdate stopped.%s\n  Log: %s\n  Previous lock: %s\n' \
      "$red" "$reset" "$run_dir/update.log" "$run_dir/flake.lock.before"
  fi
  return "$result"
}

dry_run=false
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=true ;;
  -h|--help)
    printf 'Usage: cloudyy-update [--dry-run]\n'
    exit 0
    ;;
  *) printf 'Usage: cloudyy-update [--dry-run]\n' >&2; exit 64 ;;
esac
[[ "$#" -le 1 ]] || exit 64

config_file="${CLOUDYY_NIXOS_CONFIG:-/etc/cloudyy/nixos.json}"
repo="$(jq -er '.repo | select(type == "string" and startswith("/"))' "$config_file")"
configuration="$(jq -er '.configuration | select(type == "string" and test("^[A-Za-z0-9_-]+$"))' "$config_file")"
[[ -f "$repo/flake.nix" && -f "$repo/flake.lock" ]] || {
  printf 'Cloudyy flake or lock file missing in %s\n' "$repo" >&2
  exit 1
}

update=(nix flake update --flake "$repo")
build=(nix build --no-link "path:$repo#nixosConfigurations.$configuration.config.system.build.toplevel")
activate=(sudo nixos-rebuild switch --flake "path:$repo#$configuration")

printf '\n  %scloudyy update%s\n  %s%s%s\n\n' "$bold" "$reset" "$dim" "$configuration" "$reset"
if "$dry_run"; then
  printf '  %sPreview — no changes%s\n\n' "$accent" "$reset"
  for step in update build activate; do
    declare -n command="$step"
    printf '  '
    printf '%q ' "${command[@]}"
    printf '\n'
  done
  printf '\n'
  exit 0
fi

[[ "$EUID" -ne 0 ]] || { printf 'Run cloudyy-update without sudo.\n' >&2; exit 1; }
printf '  Update locked inputs, build, and activate? %s[y/N]%s ' "$dim" "$reset"
read -r answer
[[ "$answer" =~ ^[Yy]$ ]] || { printf '\n  %sCancelled.%s\n\n' "$dim" "$reset"; exit 0; }
printf '\n'

state="${XDG_STATE_HOME:-$HOME/.local/state}/cloudyy/updates"
mkdir -p -- "$state"
run_dir="$(mktemp -d "$state/update.XXXXXXXX")"
cp -- "$repo/flake.lock" "$run_dir/flake.lock.before"
trap stop_spinner EXIT
trap 'stop_spinner; printf "\n  Interrupted. Log: %s\n" "$run_dir/update.log"; exit 130' INT
trap 'stop_spinner; exit 143' TERM

run_step 1 inputs "${update[@]}"
run_step 2 build "${build[@]}"
run_step 3 activate "${activate[@]}"
printf '\n  %sSystem updated.%s\n  %sLog: %s%s\n\n' "$green" "$reset" "$dim" "$run_dir/update.log" "$reset"
