#!/usr/bin/env bash
# List installed Ollama models as JSON lines for Command Center.
set -euo pipefail

command -v ollama >/dev/null 2>&1 || exit 0

ollama list 2>/dev/null | awk 'NR > 1 && NF { print $1 }' | while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  jq -cn --arg name "$name" '{type:"ollama_model",name:$name}'
done
