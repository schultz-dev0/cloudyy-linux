-- Autostart — equivalent of exec-once entries
-- Sources: source/autostart.conf

hl.on("hyprland.start", function()
	local home = os.getenv("HOME")
	local scripts = home .. "/cloudyy_scripts"

	hl.exec_cmd("hyprlock")
	hl.exec_cmd("systemctl --user start hyprpolkitagent.service 2>/dev/null || /usr/lib/hyprpolkitagent/hyprpolkitagent")
	hl.exec_cmd("systemctl start geoclue.service 2>/dev/null || true")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd(scripts .. "/theme_controller.sh restore")
	hl.exec_cmd(scripts .. "/cloudyy-other/hyprdock")

	hl.exec_cmd(scripts .. "/cloudyy-other/cloudyy-system-monitor")

	-- Quickshell: single canonical command from source/quickshell.conf
	local qs_conf = home .. "/.config/hypr/source/quickshell.conf"
	local f = io.open(qs_conf, "r")
	if not f then
		error("FATAL: " .. qs_conf .. " not found — quickshell startup source missing")
	end

	local qs_cmd = nil
	for line in f:lines() do
		local cmd = line:match("^exec%-once%s*=%s*(.+)$")
		if cmd then
			qs_cmd = cmd
			break
		end
	end
	f:close()

	if not qs_cmd then
		error("FATAL: No exec-once command found in " .. qs_conf)
	end

	-- swaync owns org.freedesktop.Notifications; quickshell island never receives toasts if it runs.
	hl.exec_cmd("systemctl --user stop swaync.service 2>/dev/null || true")
	hl.exec_cmd("systemctl --user mask swaync.service 2>/dev/null || true")
	hl.exec_cmd("killall swaync 2>/dev/null || true")

	hl.exec_cmd(qs_cmd)
end)
