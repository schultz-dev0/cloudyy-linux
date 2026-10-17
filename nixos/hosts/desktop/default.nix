# The main PC (Gigabyte board, Core Ultra 7 270K Plus, RTX 5070 Ti, LUKS + Btrfs).
# Installed side-by-side with Arch: new Btrfs subvolumes on the same LUKS disk, shared
# /home (@home) and ESP. Do not use this module on other hardware.
{ config, lib, pkgs, ... }:
let
  # pcup sends the passphrase on stdin (no tty); hand it to whichever prompt is waiting.
  unlock = pkgs.writeScript "cloudyy-initrd-unlock" ''
    #!/bin/bash
    IFS= read -r -d "" key || true
    key=''${key%$'\n'}
    for _ in $(seq 120); do
      for ask in /run/systemd/ask-password/ask.*; do
        [[ -e $ask ]] || continue
        sock=$(while IFS== read -r k v; do [[ $k == Socket ]] && echo "$v"; done < "$ask")
        [[ -n $sock ]] && printf '%s' "$key" |
          ${config.boot.initrd.systemd.package}/lib/systemd/systemd-reply-password 1 "$sock" && exit 0
      done
      sleep 1
    done
    echo "no LUKS password prompt appeared" >&2
    exit 1
  '';
in
{
  imports = [ ./hardware.nix ../../modules/limine-shared-esp.nix ../../modules/boot-session.nix ];

  config = {
    networking.hostName = "SchultzPC";
    networking.networkmanager.enable = true;
    time.timeZone = "Europe/London";
    i18n.defaultLocale = "en_GB.UTF-8";
    console = { font = "Lat2-Terminus16"; keyMap = "uk"; };

    # Same stack as the Arch install: newest kernel + NVIDIA 615.78.08. nixpkgs' own 595.71.05
    # does not build on Linux 7.2, so the driver is pinned below. To bump it: change the
    # version and refresh the four hashes (nix store prefetch-file [--unpack] on the .run
    # and the NVIDIA/{open-gpu-kernel-modules,nvidia-settings,nvidia-persistenced} tags).
    boot.kernelPackages = pkgs.linuxPackages_latest;
    # Same GPU parameters Arch boots with; AQ_NO_MODIFIERS is deliberately NOT set (hung the session).
    boot.kernelParams = [ "nvidia_drm.modeset=1" "nvidia_drm.fbdev=1" ];

    hardware.graphics.enable = true;
    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      open = true; # Blackwell requires the open kernel modules
      modesetting.enable = true;
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "615.78.08";
        sha256_64bit = "sha256-Pj9t3cLudnoIGFMAr3vjyyhuznZpjS3eNSRZl4LQf/4=";
        openSha256 = "sha256-HBINiOjL0ZJLIAJeNIBYHBnwgUXtNwPPtnFpAI1YwF4=";
        settingsSha256 = "sha256-inDRpG02sdDgHmlqgu/DsgK8OFdOt1fZIYyXdhlGC/c=";
        persistencedSha256 = "sha256-RzeR6Ldct6MUxjnXRyThdh5Y3jjMehTVg85MtwuWNX4=";
      };
    };
    hardware.cpu.intel.updateMicrocode = true;
    hardware.bluetooth.enable = true;
    # Magic-packet wake; the packet itself is sent by ~/pcup on the homelab. Same .link as Arch:
    # networking.interfaces.<if>.wakeOnLan matches OriginalName, which is still eth0 at link
    # setup, so it never applies. A matching .link replaces 99-default, hence the name policies.
    systemd.network.links."50-wol" = {
      matchConfig.MACAddress = "10:ff:e0:8b:6b:16";
      linkConfig = {
        NamePolicy = "keep kernel database onboard slot path";
        AlternativeNamesPolicy = "database onboard slot path";
        MACAddressPolicy = "persistent";
        WakeOnLan = "magic";
      };
    };

    users.users.schultz = {
      isNormalUser = true;
      uid = 1000; # matches ownership of the shared /home
      # The switch script copies Arch's hash here (root-only), so the password is unchanged.
      hashedPasswordFile = "/etc/secrets/schultz.passwd";
      extraGroups = [ "wheel" "networkmanager" ];
    };
    services.openssh.enable = true;
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    environment.etc."cloudyy/nixos.json".text = builtins.toJSON {
      repo = "/home/schultz/cloudyy-linux";
      configuration = "cloudyy-desktop";
    };

    # Remote LUKS unlock for ~/pcup on the homelab: it wakes the PC, expects boot SSH on
    # 192.168.0.13 with the pinned ECDSA key (Arch's dropbear key, converted by the switch
    # script), pipes the passphrase into `ssh -T root@`, then waits for .103 to show the
    # normal ed25519 host key (also copied from Arch). The host key is an initrd secret,
    # appended on the ESP by the Limine hook, never put in the store.
    boot.initrd.network.enable = true;
    boot.initrd.systemd.network.networks."10-unlock" = {
      matchConfig.MACAddress = "10:ff:e0:8b:6b:16";
      address = [ "192.168.0.13/24" ];
    };
    boot.initrd.network.ssh = {
      enable = true;
      port = 22;
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ecdsa_key" ];
      # Only pcup's key, and it can only answer the password prompt.
      authorizedKeys = [
        ''command="${unlock}",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILWGJRT8+J+MQH4LsrH8DaFBsCHVKud3pCbjvbOSQR0/ box-unlock''
      ];
    };
    boot.initrd.systemd.storePaths = [ unlock "${config.boot.initrd.systemd.package}/lib/systemd/systemd-reply-password" ];

    system.stateVersion = "26.05";
  };
}
