-- Autostart — equivalent of exec-once entries
-- Sources: source/autostart.conf

hl.on("hyprland.start", function()
	local home = os.getenv("HOME")

	hl.exec_cmd("hyprlock")
	hl.exec_cmd(
		"systemctl --user start hyprpolkitagent.service 2>/dev/null || /usr/lib/hyprpolkitagent/hyprpolkitagent"
	)
	hl.exec_cmd("systemctl start geoclue.service 2>/dev/null || true")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("cloudyy-theme restore")

	hl.exec_cmd("cloudyy-system-monitor")

	-- Quickshell: launch env (QS_NO_RELOAD_POPUP, CLOUDYY_LIGHTWEIGHT) comes from
	-- Cloud Center via qs_start.sh. Swaync is stopped by the autostart handler above.
	hl.exec_cmd("cloudyy-quickshell-start")

	-- First-run welcome popup — skips itself once ~/.config/OOBE/.dont_show exists.
	hl.exec_cmd("test -f " .. home .. "/.config/OOBE/.dont_show || qs -n -d -p " .. home .. "/.config/OOBE")
end)
