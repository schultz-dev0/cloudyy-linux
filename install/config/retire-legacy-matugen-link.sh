#!/usr/bin/env bash
# Detach only the old Cloudyy-owned ~/.config/matugen repository symlink.

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  printf 'Usage: %s <repository> <backup-directory>\n' "${0##*/}" >&2
  exit 64
fi

readonly REPOSITORY="$(readlink -m -- "$1")"
readonly BACKUP_DIRECTORY="$2"
readonly TARGET="${HOME}/.config/matugen"
readonly OWNED_SOURCE="${REPOSITORY}/.config/matugen"

[[ -L "$TARGET" ]] || exit 0

link_value="$(readlink -- "$TARGET")"
if [[ "$link_value" == /* ]]; then
  resolved_target="$(readlink -m -- "$link_value")"
else
  resolved_target="$(readlink -m -- "$(dirname -- "$TARGET")/$link_value")"
fi
[[ "$resolved_target" == "$OWNED_SOURCE" ]] || exit 0

if [[ -d "$TARGET" ]]; then
  destination="${BACKUP_DIRECTORY}/.config/matugen"
  if [[ -e "$destination" || -L "$destination" ]]; then
    printf 'cloudyy: legacy Matugen backup path is occupied: %s\n' "$destination" >&2
    exit 1
  fi
  mkdir -p -- "$(dirname -- "$destination")"
  mkdir -- "$destination"
  cp -a -- "$TARGET/." "$destination/"
  printf 'cloudyy: backed up legacy repository-owned Matugen data to %s\n' "$destination"
fi

rm -f -- "$TARGET"
printf 'cloudyy: detached legacy repository-owned Matugen link\n'
