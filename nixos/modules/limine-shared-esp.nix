# Boot NixOS from an ESP and Limine that Arch also uses.
# NixOS never rewrites limine.conf: after each switch this hook copies the newest
# generations' kernel/initrd to /boot/nixos and rewrites only the block between the
# markers below. Arch's own entries and the rest of the file stay exactly as they are.
{ pkgs, ... }:
let
  hook = pkgs.writeShellScript "cloudyy-limine-hook" ''
    set -euo pipefail
    export PATH=${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.findutils ]}
    esp=/boot
    conf=$esp/limine/limine.conf
    dir=$esp/nixos
    keep=3
    [[ -f "$conf" ]] || { echo "cloudyy-limine-hook: $conf not found" >&2; exit 1; }
    mkdir -p "$dir"

    block=$(mktemp)
    used=$(mktemp)
    n=0
    for link in $(ls -1d /nix/var/nix/profiles/system-*-link | sort -t- -k2 -n -r | head -n "$keep"); do
      sys=$(readlink -f "$link")
      gen=$(basename "$link" | cut -d- -f2)
      id=$(basename "$sys" | cut -c1-32)
      [[ -f "$dir/$id-kernel" ]] || cp "$sys/kernel" "$dir/$id-kernel"
      if [[ ! -f "$dir/$id-initrd" ]]; then
        # Secrets (initrd SSH host key) are appended to the ESP copy only, never the store.
        cp "$(readlink -f "$sys/initrd")" "$dir/.$id-initrd.tmp"
        [[ ! -e "$sys/append-initrd-secrets" ]] || "$sys/append-initrd-secrets" "$dir/.$id-initrd.tmp"
        mv -f "$dir/.$id-initrd.tmp" "$dir/$id-initrd"
      fi
      echo "$id-kernel" >> "$used"; echo "$id-initrd" >> "$used"
      label="NixOS (generation $gen)"
      [[ $n -eq 0 ]] && label="NixOS"
      {
        echo "/$label"
        echo "    protocol: linux"
        echo "    path: boot():/nixos/$id-kernel"
        echo "    cmdline: init=$sys/init $(cat "$sys/kernel-params")"
        echo "    module_path: boot():/nixos/$id-initrd"
        echo
      } >> "$block"
      n=$((n + 1))
    done

    [[ $n -gt 0 ]] || { echo "cloudyy-limine-hook: no system generations found" >&2; exit 1; }

    tmp=$(mktemp "$esp/limine/.limine.conf.XXXXXX")
    awk '/^# >>> cloudyy-nixos/{skip=1} !skip{print} /^# <<< cloudyy-nixos/{skip=0}' "$conf" > "$tmp"
    { echo "# >>> cloudyy-nixos (generated, do not edit)"; cat "$block"; echo "# <<< cloudyy-nixos"; } >> "$tmp"
    mv -f "$tmp" "$conf"

    # Only after the new config is in place: drop kernels/initrds no entry references.
    for f in "$dir"/*; do
      [[ -e "$f" ]] || continue
      grep -qxF "$(basename "$f")" "$used" || rm -f "$f"
    done
    rm -f "$block" "$used"
  '';
in
{
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = false;
  boot.loader.limine.enable = false;
  boot.loader.supportsInitrdSecrets = true;
  boot.loader.external = {
    enable = true;
    installHook = "${hook}";
  };
}
