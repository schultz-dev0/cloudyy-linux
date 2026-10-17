#!/usr/bin/env bash
# cloudyy:summary=Install NixOS side-by-side with Arch on this PC (dry-run unless --apply)
#
# Layout: new Btrfs subvolumes (@nixos, @nixos-nix, @nixos-log) on the existing LUKS disk,
# @nixos-home as a snapshot of Arch's @home, shared ESP. Arch is never modified, except
# limine.conf gains a marked NixOS block (backed up first). Default run: preflight, stage a clean source copy, build the system.
# Nothing touches disks until --apply AND you type the confirmation word.
set -euo pipefail -E

readonly TARGET_CONFIG="${CLOUDYY_NIXOS_CONFIG:-cloudyy-desktop}"
readonly REPO="${CLOUDYY_REPO:-$HOME/cloudyy-linux}"
readonly STAGE="${XDG_CACHE_HOME:-$HOME/.cache}/cloudyy-nixos/stage"
readonly OUT="${XDG_CACHE_HOME:-$HOME/.cache}/cloudyy-nixos/${TARGET_CONFIG}-system"
readonly BTRFS_UUID=9d56f5e5-582c-4aa1-ae57-6055020cc18f
readonly LUKS_UUID=5bab80da-5655-4cda-91a2-64281a17af0f
readonly ESP_UUID=4266-8834
readonly MAPPER=/dev/mapper/root
readonly SUBVOLS=(@nixos @nixos-nix @nixos-log)
readonly HOME_SV=@nixos-home
# What ~/pcup on the homelab has pinned: the initrd (dropbear) key and the normal sshd key.
readonly PCUP_INITRD_KEY='ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBDAif81hlTyR4bkbCyV2kazuOoARE2n/+K86mFyje2CeJgaykDmPRg5ot8u/4WngDHLd0AxNHihTO5vlYPvER9I='
readonly PCUP_HOST_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIABWXlvQR3+UDtIr8GM5Uh8RKJmfEnvrQzGO/8wHhT3K'
readonly NIX=(nix --extra-experimental-features 'nix-command flakes')

if [[ -t 1 ]]; then B=$'\e[1m' G=$'\e[32m' R=$'\e[31m' Y=$'\e[33m' Z=$'\e[0m'; else B='' G='' R='' Y='' Z=''; fi
say()  { printf '%s[*]%s %s\n' "$B" "$Z" "$*"; }
ok()   { printf '%s[ok]%s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$Z" "$*"; }
die()  { printf '%s[x]%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }

apply=false
for a in "$@"; do
  case "$a" in
    --apply) apply=true ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) die "unknown argument: $a" ;;
  esac
done

[[ $EUID -ne 0 ]] || die "run as your normal user; sudo is requested only for --apply steps"

# ---- 1. preflight (read-only) ------------------------------------------------------
say "preflight"
[[ -f /etc/arch-release ]] || die "this script switches an Arch system; /etc/arch-release is missing"
command -v nix >/dev/null || die "nix is not installed"
command -v rsync >/dev/null || die "rsync is not installed"
command -v dropbearconvert >/dev/null || die "dropbearconvert is not installed (needed to carry over the initrd SSH key)"
[[ "$(cut -d' ' -f1-2 /etc/ssh/ssh_host_ed25519_key.pub)" == "$PCUP_HOST_KEY" ]] ||
  die "/etc/ssh/ssh_host_ed25519_key is not the key ~/pcup has pinned"
[[ -b "$MAPPER" ]] || die "$MAPPER is not open (LUKS root not mapped?)"
[[ "$(findmnt -no UUID /)" == "$BTRFS_UUID" ]] || die "root filesystem UUID is not $BTRFS_UUID; this module is hand-written for this disk"
grep -q "cryptdevice=UUID=$LUKS_UUID:" /proc/cmdline ||
  die "Arch did not boot from LUKS UUID $LUKS_UUID; check nixos/hosts/desktop/hardware.nix"
mountpoint -q /boot || die "/boot is not mounted"
[[ "$(findmnt -no UUID /boot)" == "$ESP_UUID" ]] || die "/boot UUID is not $ESP_UUID"
[[ -f /boot/limine/limine.conf ]] || die "/boot/limine/limine.conf not found"
free_g=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
esp_m=$(df -BM --output=avail /boot | tail -1 | tr -dc 0-9)
[[ "$free_g" -ge 60 ]] || die "only ${free_g}G free on the Btrfs filesystem (need 60G)"
[[ "$esp_m" -ge 300 ]] || die "only ${esp_m}M free on /boot (need 300M for 3 generations)"
ok "disk ${free_g}G free, ESP ${esp_m}M free"
[[ -f "$REPO/flake.nix" ]] || die "no flake.nix in $REPO"
grep -q '^# >>> cloudyy-nixos' /boot/limine/limine.conf && warn "limine.conf already has a NixOS block (re-run is fine)"

# ---- 2. stage a clean source copy (live repo has sockets/ignored files that break path: flakes) ----
say "staging clean source to $STAGE"
mkdir -p "$STAGE"
rsync -a --delete --delete-excluded \
  --include='/flake.nix' --include='/flake.lock' \
  --include='/nixos/***' --include='/bin/***' \
  --include='/install/' --include='/install/assets/' --include='/install/assets/zen/***' \
  --exclude='*' "$REPO/" "$STAGE/"

# ---- 3. build ---------------------------------------------------------------------
say "building $TARGET_CONFIG (this downloads a lot the first time)"
mkdir -p "$(dirname "$OUT")"
"${NIX[@]}" build "path:$STAGE#nixosConfigurations.$TARGET_CONFIG.config.system.build.toplevel" --out-link "$OUT"
system="$(readlink -f "$OUT")"
ok "built $system"

# ---- 4. plan ----------------------------------------------------------------------
cat <<PLAN

${B}Plan (nothing below has run yet)${Z}
  1. mount Btrfs top level; create subvolumes: ${SUBVOLS[*]}
  2. snapshot @home as $HOME_SV (NOW: anything you change in Arch afterwards stays in Arch)
  3. in the snapshot only: move Arch shell rc files to *.arch, unlink the config symlinks
     Home Manager owns, turn ~/.config/{zsh,systemd} into real dirs (keeps zsh history)
  4. mount target tree under /mnt/cloudyy-target (@nixos, /nix, /var/log, $HOME_SV, /boot)
  5. nix copy the system closure into the target; nixos-install --no-bootloader
  6. carry over SSH host keys (pcup-pinned), initrd key (dropbear -> OpenSSH), Tailscale
     and Bluetooth state, and your Arch password hash (root-only, never printed)
  7. back up /boot/limine/limine.conf, then add the NixOS block (kernel/initrd go to /boot/nixos)
  8. set limine timeout to 5s so the menu is reachable (Arch stays the first/default entry)
  9. unmount; reboot into the NixOS entry right away

  Arch root (@), Arch @home, games disks: untouched.
  Rollback: delete the marked block from limine.conf (or restore the backup), then
  'btrfs subvolume delete' the four new subvolumes. Arch boots exactly as before.

PLAN

if ! $apply; then
  say "dry run complete. Re-run with --apply to perform the steps above."
  exit 0
fi

# Every kernel/initrd the NixOS block references must exist on the ESP and be byte-identical
# to the one in the system closure. A truncated copy on a FAT ESP would otherwise only show
# up at boot. Args: limine.conf, ESP dir, root the closure lives under ("" or the target).
verify_esp() {
  local conf="$1" esp="$2" root="$3" n=0 bad=0
  local line init sys kpath ipath
  init='' kpath='' ipath=''
  while IFS= read -r line; do
    case "$line" in
      "# >>> cloudyy-nixos"*) n=1 ;;
      "# <<< cloudyy-nixos"*) n=0 ;;
    esac
    [[ $n -eq 1 ]] || continue
    case "$line" in
      *module_path:*/nixos/*-initrd) ipath="${line#*:/}" ;;  # first ":/" is the one in "boot():/"
      *path:*/nixos/*-kernel) kpath="${line#*:/}" ;;
      *cmdline:*init=*) init="${line#*init=}"; init="${init%% *}"; sys="${init%/init}" ;;
    esac
    if [[ -n "$kpath" && -n "$ipath" && -n "${sys:-}" ]]; then
      cmp -s -- "$root$sys/kernel" "$esp/$kpath" || { warn "ESP kernel mismatch: $kpath"; bad=1; }
      # The ESP initrd is the closure's initrd plus appended secrets, so compare the prefix.
      local ci; ci="$(readlink -f -- "$root$sys/initrd")"
      cmp -s -n "$(stat -c%s -- "$ci")" -- "$ci" "$esp/$ipath" || { warn "ESP initrd mismatch: $ipath"; bad=1; }
      kpath='' ipath='' sys=''
    fi
  done <"$conf"
  return "$bad"
}

# ---- 5. apply ---------------------------------------------------------------------
read -rp "Type SWITCH to modify disks and the bootloader: " word
[[ "$word" == SWITCH ]] || die "aborted"

top=/mnt/cloudyy-top
tgt=/mnt/cloudyy-target
cleanup() {
  for m in "$tgt/boot" "$tgt/home" "$tgt/var/log" "$tgt/nix" "$tgt" "$top"; do
    mountpoint -q "$m" && sudo umount "$m" || true
  done
}
trap cleanup EXIT

sudo mkdir -p "$top" "$tgt"
sudo mount -o subvolid=5 "$MAPPER" "$top"
for sv in "${SUBVOLS[@]}"; do
  if [[ -e "$top/$sv" ]]; then warn "$sv already exists, reusing"; else sudo btrfs subvolume create "$top/$sv"; fi
done
if [[ -e "$top/$HOME_SV" ]]; then
  warn "$HOME_SV already exists, reusing (it is NOT refreshed from @home)"
else
  say "snapshotting @home as $HOME_SV"
  sudo btrfs subvolume snapshot "$top/@home" "$top/$HOME_SV"
  # Home Manager links these itself; Arch's copies would collide or point into Arch's /nix.
  h="$top/$HOME_SV/schultz"
  for f in .zshenv .bashrc .profile .bash_profile .hushlogin; do
    if [[ -e "$h/$f" || -L "$h/$f" ]]; then sudo mv -T "$h/$f" "$h/$f.arch"; fi
  done
  for l in .config/kitty .config/quickshell .config/matugen .config/tmux cloudyy_scripts; do
    if [[ -L "$h/$l" ]]; then sudo rm "$h/$l"; fi
  done
  # Arch links these dirs into the repo; HM would write its zshrc and user units there.
  for d in zsh systemd; do
    if [[ -L "$h/.config/$d" ]]; then
      sudo mv -T "$h/.config/$d" "$h/.config/$d.arch"
      sudo install -d -o 1000 -g 1000 "$h/.config/$d"
    fi
  done
  hist="$h/cloudyy-linux/.config/zsh/.zsh_history"
  if [[ -f "$hist" ]]; then sudo cp -a "$hist" "$h/.config/zsh/"; fi
fi
sudo umount "$top"

bo="compress=zstd:3,noatime"
sudo mount -o "subvol=@nixos,$bo" "$MAPPER" "$tgt"
sudo mkdir -p "$tgt"/{nix,home,boot,var/log,etc/secrets}
sudo mount -o "subvol=@nixos-nix,$bo" "$MAPPER" "$tgt/nix"
sudo mount -o "subvol=@nixos-log,$bo" "$MAPPER" "$tgt/var/log"
sudo mount -o "subvol=$HOME_SV,$bo" "$MAPPER" "$tgt/home"
sudo mount --bind /boot "$tgt/boot"

say "copying the system closure"
sudo "${NIX[@]}" copy --no-check-sigs --to "$tgt" "$system"
say "installing (no bootloader step)"
sudo "${NIX[@]}" shell nixpkgs#nixos-install-tools -c \
  nixos-install --root "$tgt" --system "$system" --no-root-passwd --no-bootloader

say "password hash (copied from Arch, not displayed)"
sudo awk -F: '$1=="schultz"{print $2}' /etc/shadow | sudo install -m 600 -o root -g root /dev/stdin "$tgt/etc/secrets/schultz.passwd"
[[ -s "$tgt/etc/secrets/schultz.passwd" ]] || die "could not read the schultz hash from /etc/shadow"

say "SSH host keys (pcup-pinned), Tailscale and Bluetooth state"
sudo install -d -m 755 "$tgt/etc/ssh"
sudo cp -a /etc/ssh/ssh_host_* "$tgt/etc/ssh/"
sudo install -d -m 700 "$tgt/etc/secrets/initrd"
ik="$tgt/etc/secrets/initrd/ssh_host_ecdsa_key"
sudo dropbearconvert dropbear openssh /etc/dropbear/dropbear_ecdsa_host_key "$ik" >/dev/null
sudo chmod 600 "$ik"
[[ "$(sudo ssh-keygen -y -f "$ik" | cut -d' ' -f1-2)" == "$PCUP_INITRD_KEY" ]] ||
  die "converted initrd key does not match the key ~/pcup has pinned"
for d in /var/lib/tailscale /var/lib/bluetooth; do
  if sudo test -d "$d"; then sudo install -d "$tgt$(dirname "$d")"; sudo cp -a "$d" "$tgt$(dirname "$d")/"; fi
done

say "bootloader entries"
sudo cp -a /boot/limine/limine.conf "/boot/limine/limine.conf.pre-nixos-$(date +%Y%m%d-%H%M%S)"
sudo "${NIX[@]}" shell nixpkgs#nixos-install-tools -c \
  nixos-enter --root "$tgt" -c '/nix/var/nix/profiles/system/bin/switch-to-configuration boot'
sudo sed -i 's/^timeout:.*/timeout: 5/' /boot/limine/limine.conf
grep -q '^# >>> cloudyy-nixos' /boot/limine/limine.conf || die "NixOS block missing from limine.conf; Arch entries untouched, do not reboot into NixOS"
verify_esp /boot/limine/limine.conf /boot "$tgt" ||
  die "ESP files do not match the closure; do not reboot into NixOS (Arch entries are untouched, backup: /boot/limine/limine.conf.pre-nixos-*)"
ok "ESP kernels/initrds verified against the closure"

ok "done. Reboot and pick the NixOS entry; Arch remains the default entry."
