#!/usr/bin/env bash
# Package manager helpers for Command Center (replaces rofi/packages.sh menus).
set -euo pipefail

PROTECTED=(
    base base-devel linux linux-headers linux-firmware
    systemd bash glibc pacman sudo
    hyprland rofi kitty networkmanager
    grub efibootmgr mesa xorg-server wayland
)

# NixOS: packages are declarations in the repo, never imperative installs/removals.
NIX_CFG=/etc/cloudyy/nixos.json

detect_pm() {
    if [[ -f "$NIX_CFG" ]]; then echo "nix"
    elif command -v yay &>/dev/null; then echo "yay"
    elif command -v paru &>/dev/null; then echo "paru"
    elif command -v pacman &>/dev/null; then echo "pacman"
    else echo ""; fi
}

is_protected() {
    local pkg="$1" p
    for p in "${PROTECTED[@]}"; do
        [[ "$pkg" == "$p" ]] && return 0
    done
    return 1
}

# explicit = only names the repo's nixos/ declarations actually mention (not NixOS base closure).
nix_list() {
    local filter="$1" repo cfg tokens=
    repo="$(jq -r .repo "$NIX_CFG")" cfg="$(jq -r .configuration "$NIX_CFG")"
    nix eval --json "path:$repo#nixosConfigurations.$cfg.config.environment.systemPackages" \
        --apply 'ps: map (p: { name = p.pname or p.name; version = p.version or ""; }) ps' |
        jq -c --arg explicit "$filter" --rawfile tokens <(
            [[ "$filter" == explicit ]] && grep -rhoE '[A-Za-z0-9_.+-]+' "$repo/nixos" | sort -u
        ) '($tokens | split("\n")) as $t
           | unique_by(.name)[]
           | select($explicit != "explicit" or (.name as $n | $t | index($n)))
           | {name, version, pm:"nix"}'
}

list_packages() {
    local filter="$1"
    local pm
    pm="$(detect_pm)"
    [[ -n "$pm" ]] || exit 0
    [[ "$pm" == "nix" ]] && { nix_list "$filter"; return; }

    local raw
    if [[ "$filter" == "explicit" ]]; then
        raw="$(pacman -Qe 2>/dev/null | awk '{print $1}')"
    else
        raw="$(pacman -Q 2>/dev/null | awk '{print $1}')"
    fi
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] || [[ "$pkg" == *" "* ]] && continue
        if [[ "$filter" == "explicit" ]]; then
            is_protected "$pkg" && continue
        fi
        jq -cn --arg name "$pkg" --arg pm "$pm" '{name:$name,pm:$pm}'
    done <<<"$raw"
}

# info: show version + where it is declared. edit: open that declaration, then offer a rebuild.
nix_terminal() {
    local mode="$1" pkg="$2" repo cfg
    repo="$(jq -r .repo "$NIX_CFG")" cfg="$(jq -r .configuration "$NIX_CFG")"
    kitty -e bash -c '
        mode=$1 pkg=$2 repo=$3 cfg=$4
        hit=$(grep -rnwF -m1 -- "$pkg" "$repo/nixos" | head -1)
        file=${hit%%:*} rest=${hit#*:} line=${rest%%:*}
        if [[ $mode == info ]]; then
            "$0" list all | jq -r --arg n "$pkg" "select(.name==\$n) | \"\(.name) \(.version)\""
            echo "declared: ${hit:-not in $repo/nixos}"
        elif [[ -n $hit ]]; then
            ${EDITOR:-nvim} "+$line" "$file"
            read -rp "Rebuild now? [y/N] " a
            [[ $a == [yY] ]] && sudo nixos-rebuild switch --flake "path:$repo#$cfg"
        else
            echo "no declaration of $pkg in $repo/nixos"
        fi
        echo; read -rp "Press Enter to close "
    ' "$0" "$mode" "$pkg" "$repo" "$cfg"
}

run_remove() {
    local pkg="$1"
    local pm qpkg
    pm="$(detect_pm)"
    [[ -n "$pm" && -n "$pkg" ]] || exit 1
    if [[ "$pm" == "nix" ]]; then
        nix_terminal edit "$pkg" &
        return
    fi
    is_protected "$pkg" && exit 1
    qpkg=$(printf '%q' "$pkg")
    if [[ "$pm" == "pacman" ]]; then
        kitty -e sh -c "sudo pacman -Rns ${qpkg}; echo; read -rp 'Press Enter to close '" &
    else
        kitty -e sh -c "${pm} -Rns ${qpkg}; echo; read -rp 'Press Enter to close '" &
    fi
}

run_info() {
    local pkg="$1"
    local pm qpkg
    pm="$(detect_pm)"
    [[ -n "$pm" && -n "$pkg" ]] || exit 1
    if [[ "$pm" == "nix" ]]; then
        nix_terminal info "$pkg" &
        return
    fi
    qpkg=$(printf '%q' "$pkg")
    if [[ "$pm" == "pacman" ]]; then
        kitty -e sh -c "pacman -Qi ${qpkg}; echo; read -rp 'Press Enter to close '" &
    else
        kitty -e sh -c "${pm} -Qi ${qpkg}; echo; read -rp 'Press Enter to close '" &
    fi
}

cmd="${1:-}"
case "$cmd" in
    pm) detect_pm ;;
    list) list_packages "${2:-all}" ;;
    remove) run_remove "${2:-}" ;;
    info) run_info "${2:-}" ;;
    *)
        echo "usage: packages-ctl.sh {pm|list explicit|all|remove PKG|info PKG}" >&2
        exit 1
        ;;
esac
