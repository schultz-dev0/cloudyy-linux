-- @cloud-center-state = {"cursor:default_monitor": "", "cursor:enable_hyprcursor": "true", "cursor:hide_on_key_press": "false", "cursor:hide_on_tablet": "false", "cursor:hide_on_touch": "false", "cursor:hotspot_padding": "1", "cursor:inactive_timeout": "3", "cursor:invisible": "false", "cursor:min_refresh_rate": "24", "cursor:no_break_fs_vrr": "2", "cursor:no_hardware_cursors": "2", "cursor:no_warps": "false", "cursor:persistent_warps": "true", "cursor:sync_gsettings_theme": "true", "cursor:use_cpu_buffer": "2", "cursor:warp_back_after_non_mouse_input": "false", "cursor:warp_on_change_workspace": "1", "cursor:warp_on_toggle_special": "0", "cursor:zoom_detached_camera": "true", "cursor:zoom_disable_aa": "false", "cursor:zoom_factor": "1", "cursor:zoom_rigid": "true"}

-- @description = Cursor appearance, movement, visibility, and output behavior
-- Hyprland 0.55 defaults. Seeded once as ~/.config/hypr/cursor.lua; Cloud
-- Center (ccd/cursor.py) edits this single file in place from then on.

hl.config({
	cursor = {
		invisible = false,
		sync_gsettings_theme = true,
		no_hardware_cursors = 2,
		no_break_fs_vrr = 2,
		min_refresh_rate = 24,
		hotspot_padding = 0,
		inactive_timeout = 0.0,
		no_warps = false,
		persistent_warps = false,
		warp_on_change_workspace = 0,
		warp_on_toggle_special = 0,
		default_monitor = "",
		zoom_factor = 1.0,
		zoom_rigid = false,
		zoom_disable_aa = false,
		zoom_detached_camera = true,
		enable_hyprcursor = true,
		hide_on_key_press = false,
		hide_on_touch = true,
		hide_on_tablet = false,
		use_cpu_buffer = 2,
		warp_back_after_non_mouse_input = false,
	},
})

-- --- Cloud Center managed cursor settings ---
hl.config({
    cursor = {
        enable_hyprcursor = true,
        no_warps = false,
        persistent_warps = true,
        warp_on_change_workspace = 1,
        warp_on_toggle_special = 0,
        default_monitor = "",
        warp_back_after_non_mouse_input = false,
        inactive_timeout = 3,
        hide_on_key_press = false,
        hide_on_touch = false,
        hide_on_tablet = false,
        invisible = false,
        zoom_factor = 1,
        zoom_rigid = true,
        zoom_detached_camera = true,
        zoom_disable_aa = false,
        sync_gsettings_theme = true,
        no_hardware_cursors = 2,
        use_cpu_buffer = 2,
        no_break_fs_vrr = 2,
        min_refresh_rate = 24,
        hotspot_padding = 1,
    },
})
-- --- End Cloud Center managed cursor settings ---
