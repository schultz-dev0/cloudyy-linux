{ lib, pkgs, ... }:
let
  cloudyyTheme = pkgs.runCommand "cloudyy-plymouth-theme" { } ''
    themeDir="$out/share/plymouth/themes/cloudyy"
    mkdir -p "$themeDir"
    cp ${../plymouth/cloudyy}/* "$themeDir/"
    chmod u+w "$themeDir/cloudyy.plymouth"
    substituteInPlace "$themeDir/cloudyy.plymouth" \
      --replace-fail /usr/share/plymouth/themes/cloudyy "$themeDir"
  '';
in
{
  # Keep the working Arch unlock screen; NixOS supplies the initrd integration.
  boot.plymouth = {
    enable = true;
    theme = "cloudyy";
    themePackages = [ cloudyyTheme ];
    extraConfig = "UseSimpledrm=1";
  };
  boot.kernelParams = [ "quiet" "plymouth.use-simpledrm=1" ];
  boot.initrd.verbose = false;

  # Release DRM as before, but leave the last splash frame for the compositor.
  systemd.services.plymouth-quit.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${pkgs.plymouth}/bin/plymouth quit --retain-splash"
  ];

  # agetty prints an autologin banner even with --noissue. On the first tty1
  # login, use login directly so nothing writes over the retained splash.
  # Subsequent logouts return to a normal, password-protected getty.
  systemd.services."getty@tty1" = {
    overrideStrategy = "asDropin";
    serviceConfig = {
      TTYReset = false;
      TTYVTDisallocate = false;
      ExecStart = [ "" (pkgs.writeShellScript "cloudyy-tty1-login" ''
        if [ ! -e /run/agetty.autologged ]; then
          touch /run/agetty.autologged
          exec ${pkgs.shadow}/bin/login -f schultz
        fi
        exec ${lib.getExe' pkgs.util-linux "agetty"} --noclear tty1 115200 linux
      '') ];
    };
  };
  home-manager.users.schultz.home.file.".hushlogin".text = "";

  # Only tty1, once per boot. Other VTs remain available for password login.
  # Home Manager's login profile starts Hyprland; cloudyy-session-start locks it.
  services.getty.autologinUser = "schultz";
  services.getty.autologinOnce = true;
}
