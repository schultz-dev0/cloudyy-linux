#!/usr/bin/env bash
# =============================================================================
# ai.sh — Local AI & Ollama Menu
# =============================================================================
# Placeholders are marked with: ### PLACEHOLDER ###
# Search for that string to find every spot that needs your personal config.
# =============================================================================

set -uo pipefail

readonly ROFI_DIR="${HOME}/cloudyy_scripts/rofi"
source "${ROFI_DIR}/lib/common.sh"

# config
readonly AI_CHAT_APP="${HOME}/.local/share/applications/aichat.desktop"
readonly BROWSER="${BROWSER:-xdg-open}"
readonly OPEN_WEBUI_URL="http://localhost:8080/"

# e.g. OLLAMA_RUN_FLAGS="--verbose"  Leave empty if none.
readonly OLLAMA_RUN_FLAGS=""

# =============================================================================
# OLLAMA HELPERS
# =============================================================================

ollama_is_running() {
  systemctl --user is-active --quiet ollama.service 2>/dev/null ||
    pgrep -x ollama &>/dev/null
}

ollama_status_label() {
  if ollama_is_running; then
    echo "running"
  else
    echo "stopped"
  fi
}

# Returns a newline-separated list of locally installed model names
list_models() {
  if ! command -v ollama &>/dev/null; then
    echo ""
    return
  fi
  # Strip the header line and the size/modified columns — keep just the name
  ollama list 2>/dev/null | tail -n +2 | awk '{print $1}'
}

# Pretty size info for the model detail view
model_info() {
  local model="$1"
  ollama show "$model" 2>/dev/null || echo "Could not retrieve info for: $model"
}

# =============================================================================
# SERVICE CONTROL
# =============================================================================

show_service_menu() {
  local status
  status=$(ollama_status_label)

  local choice
  choice=$(menu "Ollama Service (${status})" \
    "▶ Start Service\n■ Stop Service\n Restart Service\n󰋼 Service Status")

  case "${choice}" in
  "▶ Start Service")
    if systemctl --user start ollama.service 2>/dev/null; then
      notify-send "Ollama" "Service started." -t 2000
    else
      # Fallback: launch daemon directly
      nohup ollama serve >/dev/null 2>&1 &
      disown
      notify-send "Ollama" "Daemon launched (fallback)." -t 2000
    fi
    show_service_menu
    ;;
  "■ Stop Service")
    systemctl --user stop ollama.service 2>/dev/null ||
      pkill -x ollama 2>/dev/null || true
    notify-send "Ollama" "Service stopped." -t 2000
    show_service_menu
    ;;
  " Restart Service")
    systemctl --user restart ollama.service 2>/dev/null || {
      pkill -x ollama 2>/dev/null || true
      sleep 1
      nohup ollama serve >/dev/null 2>&1 &
      disown
    }
    notify-send "Ollama" "Service restarted." -t 2000
    show_service_menu
    ;;
  "󰋼 Service Status")
    kitty --hold -e sh -c \
      "systemctl --user status ollama.service 2>/dev/null || \
                 pgrep -a ollama || echo 'Ollama not found in process list'" &
    disown
    ;;
  *) show_ai_menu ;;
  esac
}

# =============================================================================
# MODEL RUNNER  — pick a model, it opens in kitty
# =============================================================================

show_run_model_menu() {
  local models
  models=$(list_models)

  if [[ -z "$models" ]]; then
    notify-send "Ollama" "No models installed. Pull one first." -u normal
    show_model_management_menu
    return
  fi

  local choice
  choice=$(printf "%s\n" "$models" |
    rofi -dmenu -i -p "Run Model" \
      -theme-str 'window { width: 35%; }' \
      -theme-str 'listview { lines: 12; }' \
      -mesg "Select a model to start an interactive session") || true

  [[ -z "$choice" ]] && {
    show_ai_menu
    return
  }

  if ! ollama_is_running; then
    notify-send "Ollama" "Starting daemon first..." -t 1500
    nohup ollama serve >/dev/null 2>&1 &
    disown
    sleep 1
  fi

  # Launch model in a kitty terminal
  # shellcheck disable=SC2086
  kitty --class "ollama_chat" --title "ollama — ${choice}" \
    -e ollama run $OLLAMA_RUN_FLAGS "$choice" &
  disown
  exit 0
}

# =============================================================================
# MODEL MANAGEMENT — pull, delete, inspect
# =============================================================================

show_model_management_menu() {
  local choice
  choice=$(menu "Model Management" \
    "󰇚 Pull / Download Model\n󰋼 Mode Info\n󰆴 Delete Model")

  case "$choice" in
  *"Pull"*) pull_model ;;
  *"Info"*) inspect_model ;;
  *"Delete"*) delete_model ;;
  *) show_ai_menu ;;
  esac
}

pull_model() {
  # Show a curated list of popular models + free-type option
  local popular=(
    "llama3.2:3b        — Meta, fast & lightweight"
    "llama3.2:8b        — Meta, well-rounded"
    "llama3.1:70b       — Meta, large / needs VRAM"
    "mistral:7b         — Mistral AI, great instruction following"
    "mistral-nemo:12b   — Mistral + Nvidia, long context"
    "gemma3:4b          — Google, efficient"
    "gemma3:12b         — Google, stronger"
    "phi4:14b           — Microsoft, reasoning focused"
    "qwen2.5:7b         — Alibaba, multilingual"
    "qwen2.5-coder:7b   — Alibaba, code specialist"
    "deepseek-r1:7b     — DeepSeek, reasoning chain"
    "deepseek-r1:14b    — DeepSeek, stronger reasoning"
    "nomic-embed-text   — Embedding model"
    ### PLACEHOLDER — add your own favourites above this line
    "✏ Type custom model name..."
  )

  local choice
  choice=$(printf "%s\n" "${popular[@]}" |
    rofi -dmenu -i -p "Pull Model" \
      -theme-str 'window { width: 50%; }' \
      -theme-str 'listview { lines: 14; }' \
      -mesg "Choose a model or type a name from ollama.com/library") || true

  [[ -z "$choice" ]] && {
    show_model_management_menu
    return
  }

  local model_name
  if [[ "$choice" == *"Type custom"* ]]; then
    model_name=$(rofi -dmenu -p "Model name (e.g. llama3.2:8b)" \
      -theme-str 'window { width: 40%; }' \
      -theme-str 'listview { lines: 0; }') || true
  else
    # Extract just the model tag before the dash description
    model_name=$(echo "$choice" | awk '{print $1}')
  fi

  [[ -z "$model_name" ]] && {
    show_model_management_menu
    return
  }

  notify-send "Ollama" "Pulling ${model_name}..." -t 3000

  if ! ollama_is_running; then
    nohup ollama serve >/dev/null 2>&1 &
    disown
    sleep 1
  fi

  kitty --hold --class "ollama_pull" --title "Pulling ${model_name}" \
    -e sh -c "ollama pull '${model_name}'; echo; echo 'Done — press Enter to close'; read -r" &
  disown
  exit 0
}

inspect_model() {
  local models
  models=$(list_models)
  [[ -z "$models" ]] && {
    notify-send "Ollama" "No models installed." -u normal
    show_model_management_menu
    return
  }

  local choice
  choice=$(printf "%s\n" "$models" |
    rofi -dmenu -i -p "Inspect Model" \
      -theme-str 'window { width: 35%; }' \
      -theme-str 'listview { lines: 12; }') || true

  [[ -z "$choice" ]] && {
    show_model_management_menu
    return
  }

  kitty --hold --class "ollama_info" --title "Info — ${choice}" \
    -e sh -c "ollama show '${choice}'; echo; read -rp 'Press Enter to close'" &
  disown
}

delete_model() {
  local models
  models=$(list_models)
  [[ -z "$models" ]] && {
    notify-send "Ollama" "No models installed." -u normal
    show_model_management_menu
    return
  }

  local choice
  choice=$(printf "%s\n" "$models" |
    rofi -dmenu -i -p "Delete Model" \
      -theme-str 'window { width: 35%; }' \
      -theme-str 'listview { lines: 12; }' \
      -mesg "⚠ This will permanently remove the model") || true

  [[ -z "$choice" ]] && {
    show_model_management_menu
    return
  }

  # Confirmation
  local confirm
  confirm=$(centered_menu "Delete ${choice}?" \
    "󰆴 Yes, delete it\n󰘍 Cancel") || true

  case "$confirm" in
  *"Yes"*)
    ollama rm "$choice" &&
      notify-send "Ollama" "Deleted: ${choice}" -t 2000 ||
      notify-send "Ollama" "Failed to delete: ${choice}" -u critical
    ;;
  *) show_model_management_menu ;;
  esac
}

# =============================================================================
# CHAT FRONTENDS
# =============================================================================

show_chat_menu() {
  local choice
  choice=$(menu "Chat Frontends" \
    "󰭹 AI Chat App\n󰏋 Open WebUI (Browser)")

  case "$choice" in
  *"AI Chat App"*)
    ### PLACEHOLDER — swap the block below for however your chat app launches
    if [[ "$AI_CHAT_APP" == "__YOUR_CHAT_APP_HERE__" ]]; then
      notify-send "AI Menu" "Chat app not configured — edit ai.sh and set AI_CHAT_APP." -u normal
    else
      run_app "$AI_CHAT_APP"
    fi
    ;;
  *"Open WebUI"*)
    ### PLACEHOLDER — if Open WebUI isn't running, optionally start it here
    run_app "$BROWSER" "$OPEN_WEBUI_URL"
    ;;
  *) show_ai_menu ;;
  esac
}

# =============================================================================
# LEARN — documentation & resources
# =============================================================================

show_ai_learn_menu() {
  local choice
  choice=$(menu "Learn — Local AI" \
    "󰖟 Ollama Docs\n󰖟 Ollama Model Library\n󰖟 Ollama GitHub\n󰖟 r/LocalLLaMA\n󰖟 HuggingFace Hub\n󰖟 Open WebUI Docs\n󰖟 LM Studio (alt runtime)\n󰖟 llm.ggml.ai (GGUF info)")

  local url=""
  case "$choice" in
  *"Ollama Docs"*) url="https://ollama.com/docs" ;;
  *"Model Library"*) url="https://ollama.com/library" ;;
  *"Ollama GitHub"*) url="https://github.com/ollama/ollama" ;;
  *"LocalLLaMA"*) url="https://www.reddit.com/r/LocalLLaMA/" ;;
  *"HuggingFace"*) url="https://huggingface.co/models?library=gguf" ;;
  *"Open WebUI"*) url="https://docs.openwebui.com/" ;;
  *"LM Studio"*) url="https://lmstudio.ai/" ;;
  *"ggml"*) url="https://llm.ggml.ai/" ;;
  *)
    show_ai_menu
    return
    ;;
  esac

  [[ -n "$url" ]] && run_app "$BROWSER" "$url"
}

# =============================================================================
# QUICK STATS  (shown as rofi -mesg in the main AI menu)
# =============================================================================

get_ai_status_line() {
  local status model_count gpu_info
  status=$(ollama_status_label)
  model_count=$(list_models | grep -c . 2>/dev/null || echo 0)

  # Try to grab GPU name — works on NVIDIA; gracefully skips otherwise
  gpu_info=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 ||
    glxinfo 2>/dev/null | grep "OpenGL renderer" | cut -d: -f2 | xargs ||
    echo "GPU unknown")

  echo "Ollama: ${status} | Models: ${model_count} | ${gpu_info}"
}

# =============================================================================
# AI MAIN MENU
# =============================================================================

show_ai_menu() {
  local status_line
  status_line=$(get_ai_status_line)

  local choice
  choice=$(menu "AI" \
    "󰚩 Run a Model\n󰭹 Chat\n󰇚 Model Management\n󱐋 Ollama Service\n󰖟 Learn & Resources" \
    -mesg "$status_line")

  case "$choice" in
  *"Run a Model"*) show_run_model_menu ;;
  *"Chat"*) show_chat_menu ;;
  *"Model Management"*) show_model_management_menu ;;
  *"Service"*) show_service_menu ;;
  *"Learn"*) show_ai_learn_menu ;;
  *) back_to_main ;;
  esac
}

# =============================================================================
# ENTRY POINT
# =============================================================================

show_ai_menu
