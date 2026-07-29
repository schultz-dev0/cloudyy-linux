-- Autostart — equivalent of exec-once entries

hl.on("hyprland.start", function()
	-- TTY autologin starts only the compositor. This gate waits for the
	-- Quickshell lock before starting any normal desktop services.
	hl.exec_cmd("cloudyy-session-start")
end)

-- @cloud-center-rules-startup-state = {"autostart": []}

-- --- Cloud Center managed additions ---
-- --- End Cloud Center managed additions ---
