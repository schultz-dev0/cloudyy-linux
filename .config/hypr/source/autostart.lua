-- Autostart — equivalent of exec-once entries
-- Sources: source/autostart.conf

hl.on("hyprland.start", function()
local home = os.getenv("HOME")
local scripts = home .. "/cloudyy_scripts"

hl.exec_cmd("hyprlock")
hl.exec_cmd("wl-paste --type text --watch cliphist store")
hl.exec_cmd("wl-paste --type image --watch cliphist store")
hl.exec_cmd(scripts .. "/theme_controller.sh restore")
hl.exec_cmd(scripts .. "/cloudyy-other/hyprdock")
-- hl.exec_cmd("swayosd-server")

hl.exec_cmd("env QS_NO_RELOAD_POPUP=1 qs -d")
end)
