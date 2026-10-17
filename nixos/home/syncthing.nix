{ config, lib, ... }:
{
  options.cloudyy.syncthing.enable = lib.mkEnableOption "the migrated personal Syncthing service";
  options.cloudyy.syncthing.fresh = lib.mkEnableOption "a new Syncthing identity that peers with the desktop and syncs only ~/projects";

  config = lib.mkMerge [ (lib.mkIf config.cloudyy.syncthing.enable {
    services.syncthing = {
      enable = true;
      # Preserve restored config.xml and UI-managed folder/device settings.
      overrideDevices = false;
      overrideFolders = false;
    };
    systemd.user.services.syncthing = {
      Unit.ConditionPathExists = [
        "%h/.local/state/syncthing/config.xml"
        "%h/.local/state/syncthing/cert.pem"
        "%h/.local/state/syncthing/key.pem"
      ];
      Service.WorkingDirectory = "%h";
    };
  }) # migrated desktop identity
  # The laptop is its own peer (new identity, generated on first start), not a clone of the desktop.
  (lib.mkIf config.cloudyy.syncthing.fresh { services.syncthing = {
    enable = true;
    overrideDevices = true;
    overrideFolders = true;
    settings = {
      devices.desktop.id = "JX5CBCW-HHL6ADA-TO6FEE5-E3MYM7W-HHJBUQN-CA6WNAN-GBDLRP7-Y4ZBVAF";
      folders.projects = {
        id = "sqsv4-hwn5u"; # same folder ID as the desktop's "Projects"
        label = "Projects";
        path = "~/projects";
        devices = [ "desktop" ];
      };
    };
  }; })
  ];
}
