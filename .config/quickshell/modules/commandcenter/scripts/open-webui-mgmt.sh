#!/usr/bin/env bash
# Open WebUI container control for Command Center.
set -euo pipefail

readonly CONTAINER_CANDIDATES=(open-webui openwebui)

docker_socks() {
  local -a socks=()
  [[ -n "${DOCKER_HOST:-}" ]] && socks+=("${DOCKER_HOST#unix://}")
  socks+=("/var/run/docker.sock" "${HOME}/.docker/desktop/docker.sock")
  printf '%s\n' "${socks[@]}"
}

docker_on_sock() {
  local sock="$1"
  shift
  DOCKER_HOST="unix://${sock}" docker "$@" 2>/dev/null
}

resolve_webui_container() {
  local sock name id
  WEBUI_DOCKER_SOCK=""
  WEBUI_CONTAINER_ID=""

  while IFS= read -r sock; do
    [[ -z "$sock" || ! -S "$sock" ]] && continue
    for name in "${CONTAINER_CANDIDATES[@]}"; do
      id=$(docker_on_sock "$sock" ps -q -f "name=^/${name}$" | head -1)
      if [[ -n "$id" ]]; then
        WEBUI_DOCKER_SOCK="$sock"
        WEBUI_CONTAINER_ID="$id"
        return 0
      fi
    done
    id=$(docker_on_sock "$sock" ps -q --filter publish=8080 | head -1)
    if [[ -n "$id" ]]; then
      WEBUI_DOCKER_SOCK="$sock"
      WEBUI_CONTAINER_ID="$id"
      return 0
    fi
  done < <(docker_socks)
  return 1
}

resolve_stopped_webui_container() {
  local sock name id
  WEBUI_DOCKER_SOCK=""
  WEBUI_CONTAINER_ID=""

  while IFS= read -r sock; do
    [[ -z "$sock" || ! -S "$sock" ]] && continue
    for name in "${CONTAINER_CANDIDATES[@]}"; do
      id=$(docker_on_sock "$sock" ps -aq -f "name=^/${name}$" -f status=exited | head -1)
      if [[ -n "$id" ]]; then
        WEBUI_DOCKER_SOCK="$sock"
        WEBUI_CONTAINER_ID="$id"
        return 0
      fi
    done
  done < <(docker_socks)
  return 1
}

webui_process_running() {
  pgrep -f 'uvicorn open_webui\.main:app' >/dev/null 2>&1
}

webui_is_running() {
  resolve_webui_container || webui_process_running
}

run_status() {
  if webui_is_running; then
    echo "running"
  else
    echo "stopped"
  fi
}

run_stop() {
  if resolve_webui_container; then
    if docker_on_sock "$WEBUI_DOCKER_SOCK" stop "$WEBUI_CONTAINER_ID" >/dev/null; then
      notify-send "Open WebUI" "Stopped — RAM freed." -t 2000 2>/dev/null || true
      return 0
    fi
    notify-send "Open WebUI" "Failed to stop container." -u critical 2>/dev/null || true
    return 1
  fi
  if webui_process_running; then
    pkill -f 'uvicorn open_webui\.main:app' 2>/dev/null || true
    notify-send "Open WebUI" "Stopped process." -t 2000 2>/dev/null || true
    return 0
  fi
  notify-send "Open WebUI" "Not running." -t 2000 2>/dev/null || true
}

run_start() {
  if webui_is_running; then
    notify-send "Open WebUI" "Already running." -t 2000 2>/dev/null || true
    return 0
  fi
  if resolve_stopped_webui_container; then
    if docker_on_sock "$WEBUI_DOCKER_SOCK" start "$WEBUI_CONTAINER_ID" >/dev/null; then
      notify-send "Open WebUI" "Started." -t 2000 2>/dev/null || true
      return 0
    fi
    notify-send "Open WebUI" "Failed to start container." -u critical 2>/dev/null || true
    return 1
  fi
  notify-send "Open WebUI" "No container found — install or create one first." -u critical 2>/dev/null || true
  return 1
}

cmd="${1:-}"
case "$cmd" in
  status) run_status ;;
  stop) run_stop ;;
  start) run_start ;;
  *)
    echo "usage: open-webui-mgmt.sh {status|stop|start}" >&2
    exit 1
    ;;
esac
