#!/usr/bin/env bash
# Ollama model management helpers for Command Center (ported from rofi/ai.sh).
set -euo pipefail

ollama_is_running() {
  systemctl --user is-active --quiet ollama.service 2>/dev/null ||
    systemctl is-active --quiet ollama.service 2>/dev/null ||
    pgrep -x ollama &>/dev/null
}

ollama_wait_until_ready() {
  local _
  for _ in {1..10}; do
    ollama_is_running && return 0
    sleep 0.3
  done
  return 1
}

start_ollama_direct() {
  nohup ollama serve >/dev/null 2>&1 &
  disown
  ollama_wait_until_ready
}

ensure_daemon() {
  ollama_is_running && return 0
  start_ollama_direct
}

list_installed() {
  command -v ollama >/dev/null 2>&1 || exit 0
  ollama list 2>/dev/null | awk 'NR > 1 && NF { print $1 }' | while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    jq -cn --arg name "$name" '{name:$name}'
  done
}

list_running() {
  command -v ollama >/dev/null 2>&1 || exit 0
  ollama ps 2>/dev/null | awk 'NR > 1 && NF { if (!seen[$1]++) print $1 }' | while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    jq -cn --arg name "$name" '{name:$name}'
  done
}

run_pull() {
  local model="$1"
  [[ -n "$model" ]] || exit 1
  ensure_daemon || {
    notify-send "Ollama" "Failed to start daemon." -u critical 2>/dev/null || true
    exit 1
  }
  notify-send "Ollama" "Pulling ${model}..." -t 3000 2>/dev/null || true
  qmodel=$(printf '%q' "$model")
  kitty --hold --class "ollama_pull" --title "Pulling ${model}" \
    -e sh -c "ollama pull ${qmodel}; echo; echo 'Done — press Enter to close'; read -r" &
}

run_pull_custom() {
  local model_name
  model_name=$(rofi -dmenu -p "Model name (e.g. llama3.2:8b)" \
    -theme-str 'window { width: 40%; }' \
    -theme-str 'listview { lines: 0; }' 2>/dev/null) || true
  [[ -z "$model_name" ]] && exit 0
  run_pull "$model_name"
}

run_info() {
  local model="$1"
  [[ -n "$model" ]] || exit 1
  qmodel=$(printf '%q' "$model")
  kitty --hold --class "ollama_info" --title "Info — ${model}" \
    -e sh -c "ollama show ${qmodel}; echo; read -rp 'Press Enter to close'" &
}

run_stop() {
  local model="$1"
  [[ -n "$model" ]] || exit 1
  if ollama stop "$model" >/dev/null 2>&1; then
    notify-send "Ollama" "Stopped: ${model}" -t 2000 2>/dev/null || true
  else
    notify-send "Ollama" "Failed to stop: ${model}" -u critical 2>/dev/null || true
    exit 1
  fi
}

run_remove() {
  local model="$1"
  [[ -n "$model" ]] || exit 1
  qmodel=$(printf '%q' "$model")
  if ollama rm "$model" 2>/dev/null; then
    notify-send "Ollama" "Deleted: ${model}" -t 2000 2>/dev/null || true
  else
    notify-send "Ollama" "Failed to delete: ${model}" -u critical 2>/dev/null || true
    exit 1
  fi
}

cmd="${1:-}"
case "$cmd" in
  list-installed) list_installed ;;
  list-running) list_running ;;
  pull) run_pull "${2:-}" ;;
  pull-custom) run_pull_custom ;;
  info) run_info "${2:-}" ;;
  stop) run_stop "${2:-}" ;;
  remove) run_remove "${2:-}" ;;
  *)
    echo "usage: ollama-mgmt.sh {list-installed|list-running|pull MODEL|pull-custom|info MODEL|stop MODEL|remove MODEL}" >&2
    exit 1
    ;;
esac
