{ config, lib, pkgs, ... }:
let
  repo = "${config.home.homeDirectory}/cloudyy-linux";
  link = config.lib.file.mkOutOfStoreSymlink;
  typelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.gtk4 pkgs.libadwaita pkgs.glib.out pkgs.pango.out pkgs.gdk-pixbuf
    pkgs.harfbuzz pkgs.graphene pkgs.gobject-introspection
  ];
  qmlPath = "${pkgs.qt6.qt5compat}/${pkgs.qt6.qtbase.qtQmlPrefix}";
  schemaPath = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas";
  commands = builtins.filter (lib.hasPrefix "cloudyy")
    (builtins.attrNames (builtins.readDir ../../bin));
in
{
  home.sessionPath = [ "${repo}/bin" ];
  home.sessionVariables.GI_TYPELIB_PATH = typelibPath;
  home.sessionVariables.QML_IMPORT_PATH = qmlPath;
  home.sessionVariables.GSETTINGS_SCHEMA_DIR = schemaPath;
  # Compositor-managed launches need real profile commands, not only shell PATH edits.
  home.packages = map (name: pkgs.writeShellScriptBin name ''
    export PATH="${repo}/bin:$PATH"
    export GI_TYPELIB_PATH="${typelibPath}"
    export QML_IMPORT_PATH="${qmlPath}"
    export GSETTINGS_SCHEMA_DIR="${schemaPath}"
    exec "${repo}/bin/${name}" "$@"
  '') commands;
  home.file."cloudyy_scripts".source = link "${repo}/cloudyy_scripts";
  xdg.configFile."quickshell".source = link "${repo}/.config/quickshell";
  xdg.configFile."kitty".source = link "${repo}/.config/kitty";
  xdg.configFile."matugen".source = link "${repo}/.config/matugen";
  xdg.configFile."tmux".source = link "${repo}/.config/tmux";

  home.activation.cloudyyDesktop = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.bash pkgs.python3 pkgs.jq pkgs.util-linux pkgs.imagemagick pkgs.findutils pkgs.gnused pkgs.gnugrep ]}:$PATH"
    test -d "${repo}/install/assets/defaults/hypr"
    mkdir -p "$HOME/.config/hypr"
    # A symlinked hypr dir is an existing Cloudyy deploy (the desktop's, carried over from Arch): keep it.
    if [ ! -e "$HOME/.config/hypr/.cloudyy-seeded" ] && [ ! -L "$HOME/.config/hypr" ]; then
      if [ -e "$HOME/.config/hypr/hyprland.lua" ]; then
        mv --backup=numbered "$HOME/.config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua.pre-cloudyy"
      fi
      if [ -e "$HOME/.config/hypr/hyprland.conf" ]; then
        mv --backup=numbered "$HOME/.config/hypr/hyprland.conf" "$HOME/.config/hypr/hyprland.conf.pre-cloudyy"
      fi
      cp --no-clobber "${repo}/install/assets/defaults/hypr/"* "$HOME/.config/hypr/"
      chmod u+w "$HOME/.config/hypr/"*
      touch "$HOME/.config/hypr/.cloudyy-seeded"
    fi
    # Migrate only the old island shortcut; preserve other personal bindings.
    python3 - <<'PYBIND'
from pathlib import Path
import re

path = Path.home() / ".config/hypr/bindings.lua"
text = path.read_text()
pattern = r'(hl\.bind\(\s*mainMod \.\. " \+ apostrophe",\s*hl\.dsp\.exec_cmd\(")qs ipc call island toggle("\),\s*\{ desc = ")Toggle utility island \(pull out and focus\)(" \}\s*\))'
updated = re.sub(pattern, r'\1cloudyy-screenshot-capture --edit\2Edit latest screenshot\3', text)
if ' + apostrophe"' not in updated:
    updated += '\nhl.bind(mainMod .. " + apostrophe", hl.dsp.exec_cmd("cloudyy-screenshot-capture --edit"), { desc = "Edit latest screenshot" })\n'
if updated != text:
    path.write_text(updated)
# Existing installs retain writable rules; add the shipped Satty rule once.
rules_path = Path.home() / ".config/hypr/windowrules.lua"
rules = rules_path.read_text() if rules_path.exists() else ""
if not re.search(r'name\s*=\s*"satty"', rules):
    defaults = Path("${repo}/install/assets/defaults/hypr/windowrules.lua").read_text()
    satty_rule = re.search(r'hl\.window_rule\(\{\s*name = "satty",.*?\n\}\)', defaults, re.S)
    with rules_path.open("a") as handle:
        handle.write("\n" + satty_rule.group(0) + "\n")
PYBIND
    if [ ! -e "$HOME/.local/state/cloudyy/current" ]; then
      "${repo}/bin/cloudyy-theme" bootstrap mono
    fi
  '';

  systemd.user.services.quickshell = {
    Unit = {
      Description = "Cloudyy desktop shell";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/qs -n";
      Environment = [ "QS_NO_RELOAD_POPUP=1" "GI_TYPELIB_PATH=${typelibPath}" "QML_IMPORT_PATH=${qmlPath}" "GSETTINGS_SCHEMA_DIR=${schemaPath}" ];
      EnvironmentFile = "-%h/.config/quickshell/qs.env";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStopSec = 5;
    };
  };
  systemd.user.services.hypridle = {
    Unit = { Description = "Cloudyy idle manager"; PartOf = [ "graphical-session.target" ]; };
    Service = {
      ExecStart = "${pkgs.hypridle}/bin/hypridle -c %h/.config/hypr/hypridle.conf";
      # cloudyy-lock launches Quickshell, which needs the same QML/GI paths as the shell service.
      Environment = [ "GI_TYPELIB_PATH=${typelibPath}" "QML_IMPORT_PATH=${qmlPath}" "GSETTINGS_SCHEMA_DIR=${schemaPath}" ];
      Restart = "on-failure";
    };
  };
  # Right-edge touchpad slide = volume. Needs the input + uinput groups (laptop host).
  systemd.user.services.cloudyy-touchpad-edge = {
    Unit = {
      Description = "Cloudyy touchpad edge volume";
      PartOf = [ "graphical-session.target" ];
      ConditionPathExists = "/dev/uinput";
    };
    Service = {
      ExecStart = "${pkgs.python3.withPackages (ps: [ ps.evdev ])}/bin/python3 ${repo}/bin/cloudyy-touchpad-edge";
      Environment = [ "CLOUDYY_PAMIXER=${pkgs.pamixer}/bin/pamixer" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  systemd.user.services.hyprpolkitagent = {
    Unit = { Description = "Hyprland authentication agent"; PartOf = [ "graphical-session.target" ]; };
    Service = { ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent"; Restart = "on-failure"; };
  };
  systemd.user.targets.cloudyy-unlocked.Unit = {
    Description = "Cloudyy unlocked desktop";
    PartOf = [ "graphical-session.target" ];
  };
}
