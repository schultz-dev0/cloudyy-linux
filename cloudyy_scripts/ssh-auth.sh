#!/usr/bin/env bash
# ssh-auth.sh — manual SSH-agent helper.
#
# The vendor ssh-agent (ssh-agent.socket) and ~/.ssh/config's IdentityAgent
# already handle agent lifecycle and socket discovery for git/ssh. The key
# itself is auto-loaded at boot by
# ~/.local/lib/cloudyy/cloudyy-ssh-key-unlock.sh (local, not tracked here —
# see 07 - Projects/Cloudyy/Documentation/Cloudyy Misc Dotfiles & Services.md).
#
# This script is just a manual fallback/status check:
#   source ~/cloudyy_scripts/ssh-auth.sh   — sets SSH_AUTH_SOCK, reports status
#   ~/cloudyy_scripts/ssh-auth.sh          — same, plus prompts to load the key if missing

export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"

if ssh-add -l &>/dev/null; then
  echo "ssh-auth: key already loaded"
elif (return 0 2>/dev/null); then
  echo "ssh-auth: no keys loaded — run: ssh-add ~/.ssh/id_ed25519"
else
  echo "ssh-auth: no keys loaded"
  ssh-add ~/.ssh/id_ed25519
fi
