{ pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ../../modules/boot.nix ];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "uk";
  };

  users.users.schultz = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    packages = [ pkgs.tree ];
  };
  services.qemuGuest.enable = true;
  services.openssh.enable = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.etc."cloudyy/nixos.json".text = builtins.toJSON {
    repo = "/home/schultz/cloudyy-linux";
    configuration = "nixos-btw";
  };
  system.stateVersion = "26.05";
}
