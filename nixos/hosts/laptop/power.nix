# Battery, thermals and ASUS hardware for the Vivobook S 14 (Core Ultra 7 258V).
{ pkgs, ... }:
{
  # power-profiles-daemon (enabled in modules/desktop.nix) stays: Cloud Center drives it,
  # and asusd syncs its firmware profile with it. TLP would conflict, so it is not used.
  services.thermald.enable = true;
  services.asusd.enable = true; # asusctl, keyboard backlight, charge limit
  zramSwap.enable = true;
  services.fstrim.enable = true;

  # ponytail: no hibernate, the disk layout has no swap/resume target. Add a Btrfs swapfile + resume_offset if wanted.
  # asusd's unit sandboxes /etc/asusd and refuses to start if it is missing.
  systemd.tmpfiles.rules = [ "d /etc/asusd 0755 root root -" ];

  systemd.services.cloudyy-charge-limit = {
    description = "Cap battery charge at 80%";
    after = [ "asusd.service" ];
    wants = [ "asusd.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.asusctl}/bin/asusctl battery limit 80";
      # asusctl exits 0 even when asusd is down, so verify the limit actually applied.
      ExecStartPost = "${pkgs.runtimeShell} -c 'grep -qx 80 /sys/class/power_supply/BAT0/charge_control_end_threshold'";
    };
  };

  environment.systemPackages = [ pkgs.v4l-utils ];
}
