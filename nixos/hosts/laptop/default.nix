{ lib, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ../../modules/boot.nix ../../modules/boot-session.nix ./power.nix ];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  # Keep Plymouth and Hyprland on the same GPU driver. Loading xe only after
  # LUKS unlock replaces simpledrm's framebuffer and blanks the retained splash.
  boot.initrd.kernelModules = [ "xe" ];
  boot.initrd.systemd.services.plymouth-start.after = [ "systemd-modules-load.service" ];
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;
  hardware.uinput.enable = true; # touchpad edge-volume service re-emits input
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "uk";
  };

  users.users.schultz = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "input" "uinput" ];
    packages = [ pkgs.tree ];
  };
  services.openssh.enable = true;
  # Background synchronization should not heat the laptop during login.
  home-manager.users.schultz.systemd.user.services.syncthing = {
    Install.WantedBy = lib.mkForce [ "cloudyy-unlocked.target" ];
    Service = {
      CPUQuota = "100%"; # one CPU core total, not all CPUs at 100%
      Nice = 10;
      IOSchedulingClass = "idle";
      Environment = [ "GOMAXPROCS=2" ];
    };
  };
  # This updater requires syncthing.service, so it must share the unlock gate.
  home-manager.users.schultz.systemd.user.services.syncthing-init.Install.WantedBy =
    lib.mkForce [ "cloudyy-unlocked.target" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.etc."cloudyy/nixos.json".text = builtins.toJSON {
    repo = "/home/schultz/cloudyy-linux";
    configuration = "cloudyy-laptop";
  };
  system.stateVersion = "26.05";
}
