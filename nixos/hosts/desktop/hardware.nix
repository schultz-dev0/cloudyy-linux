# Hand-written from the running Arch system (lsblk/fstab). Subvolumes marked "new" are
# created by lib/cloudyy-nixos/switch-from-arch.sh. /home is a snapshot of Arch's @home
# taken at switch time, so Home Manager never writes into the Arch fallback's files.
{ lib, ... }:
let
  btrfs = "/dev/disk/by-uuid/9d56f5e5-582c-4aa1-ae57-6055020cc18f";
  opts = sub: [ "subvol=${sub}" "compress=zstd:3" "noatime" ];
in
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" "r8169" ];
  boot.kernelModules = [ "kvm-intel" ];

  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-uuid/5bab80da-5655-4cda-91a2-64281a17af0f";
    allowDiscards = true;
  };

  fileSystems."/"        = { device = btrfs; fsType = "btrfs"; options = opts "@nixos"; };        # new
  fileSystems."/nix"     = { device = btrfs; fsType = "btrfs"; options = opts "@nixos-nix"; };    # new
  fileSystems."/var/log" = { device = btrfs; fsType = "btrfs"; options = opts "@nixos-log"; };    # new
  fileSystems."/home"    = { device = btrfs; fsType = "btrfs"; options = opts "@nixos-home"; };   # new (snapshot of @home)
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/4266-8834";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };
  fileSystems."/mnt/games2" = {
    device = "/dev/disk/by-uuid/7abcd2ee-c41a-40a2-ba2b-caffcdb8bde3";
    fsType = "ext4";
    options = [ "nofail" "noatime" ];
  };
  fileSystems."/mnt/DCS_FAST" = {
    device = "/dev/disk/by-uuid/484E8F4A4E8F302C";
    fsType = "ntfs3";
    options = [ "nofail" "noatime" "uid=1000" "gid=1000" ];
  };

  swapDevices = [ ];
  zramSwap.enable = true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
