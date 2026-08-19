#!/usr/bin/env bash
# Configure login shell, keyring integration, and opt-in boot behaviour.
set -euo pipefail -E

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_DIR="$(cd "${INSTALL_DIR}/.." && pwd)"

usage() {
  printf 'Usage: %s [--help]\n\nConfigure zsh, oh-my-zsh, keyring password sync, and boot optimisation.\n' "$(basename "$0")"
}

case "${1:-}" in
--help | -h) usage; exit 0 ;;
esac

zsh_path="$(command -v zsh 2>/dev/null || true)"
if [[ -n "$zsh_path" && "${SHELL:-}" != "$zsh_path" ]]; then
  sudo chsh -s "$zsh_path" "$USER" >/dev/null 2>&1 ||
    printf '[!] Could not set zsh as the default shell.\n' >&2
fi

omz_dir="${HOME}/.config/zsh/oh-my-zsh"
if [[ -n "$zsh_path" && ! -d "$omz_dir" ]]; then
  installer="$(mktemp)"
  if curl -fsSL --connect-timeout 10 --max-time 30 \
    https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$installer"; then
    # --keep-zshrc: the installer resolves its target as ${ZDOTDIR:-$HOME}/.zshrc,
    # not $ZSH, so without this it moves a live config to .zshrc.pre-oh-my-zsh and
    # drops in its stock template — even when $omz_dir points somewhere else.
    ZSH="$omz_dir" RUNZSH=no CHSH=no sh "$installer" '' --unattended --keep-zshrc 2>/dev/null ||
      printf '[!] oh-my-zsh install failed (non-fatal).\n' >&2
  fi
  rm -f "$installer"
fi

if [[ -n "$zsh_path" ]]; then
  mkdir -p "${omz_dir}/custom/plugins"
  for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    sys_path="/usr/share/zsh/plugins/${plugin}"
    [[ -d "$sys_path" && ! -e "${omz_dir}/custom/plugins/${plugin}" ]] &&
      ln -snf "$sys_path" "${omz_dir}/custom/plugins/${plugin}"
  done
fi

xdg-user-dirs-update 2>/dev/null || true
bash "${SCRIPT_DIR}/keyring.sh"

boot_opt="${REPO_DIR}/bin/cloudyy-boot-opt"
if [[ -x "$boot_opt" ]]; then
  sudo "$boot_opt" "$USER"
fi
