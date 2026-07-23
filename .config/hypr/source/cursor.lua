-- @description = Cursor appearance, movement, visibility, and output behavior
-- Hyprland 0.55 defaults. Cloud Center copies this module through HCM when
-- the user first applies Cursor-page changes.

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
