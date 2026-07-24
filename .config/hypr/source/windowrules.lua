-- Window rules and layer rules
-- Source: active Lua windowrules

-- ── Application-specific rules ───────────────────────────────────────────────

hl.window_rule({
	name = "zen-browser",
	match = { class = "^(zen)$" },
	size = "1920 1080",
	float = true,
	opaque = true,
})

hl.window_rule({
	name = "image-viewer",
	match = { class = "^(org.gnome.Loupe)$" },
	size = "1280 720",
	float = true,
})

hl.window_rule({
	name = "terminal",
	match = { class = "^(.*kitty)$" },
	size = "1080 900",
	float = false,
})

hl.window_rule({
	name = "Steam",
	match = { class = "^(.*steam)$" },
	size = "1280 720",
	float = true,
})

hl.window_rule({
	name = "mpv",
	match = { class = "^(.*mpv)$" },
	size = "1280 720",
	float = true,
})

hl.window_rule({
	name = "Keypunch",
	match = { class = "^(.*Keypunch)$" },
	size = "1280 720",
	float = true,
})

-- ── Utilities ─────────────────────────────────────────────────────────────────

hl.window_rule({
	name = "float-blueman",
	match = { class = "^(blueman-manager)$" },
	float = true,
	size = "530 313",
	center = true,
})

hl.window_rule({
	name = "file-manager",
	match = { class = "^(nautilus)$" },
	float = true,
	size = "1080 920",
	center = true,
})

hl.window_rule({
	name = "bluetui",
	match = { class = "^(bluetui)$" },
	float = true,
	size = "551 362",
	center = true,
})

hl.window_rule({
	name = "spotify",
	match = { class = "^(spotify)$" },
	float = true,
	size = "900 900",
	center = true,
})

hl.window_rule({
	name = "pavu",
	match = { class = "^(org.pulseaudio.pavucontrol)$" },
	float = true,
	size = "551 362",
	center = true,
})

hl.window_rule({
	name = "cloudcenter",
	match = { class = "^(dev.cloudyy.CloudCenter)$" },
	float = true,
	size = "1080 1080",
	center = true,
})

hl.window_rule({
	name = "cloudcenter-qml",
	match = { class = "^(org.quickshell)$", title = "^(Cloud Center)$" },
	float = true,
	size = "1100 760",
	center = true,
	opacity = "1.0 override 1.0 override",
})

hl.window_rule({
	name = "oobe-welcome",
	match = { class = "^(org.quickshell)$", title = "^(Welcome to Cloudyy)$" },
	float = true,
	size = "560 460",
	center = true,
})

hl.window_rule({
	name = "openrgb",
	match = { class = "org.openrgb.OpenRGB" },
	float = true,
	size = "1000 960",
})

hl.window_rule({
	name = "MatLab",
	match = { class = "^(.*MATLAB.*)$" },
	float = true,
	size = "1920 1080",
	center = true,
})

-- ── Yad sliders ───────────────────────────────────────────────────────────────

hl.window_rule({
	name = "yad_sliders",
	match = { class = "^(yad)$" },
	size = "350 100",
	float = true,
	center = true,
})

-- ── General / XWayland fixes ──────────────────────────────────────────────────

hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move = "20 monitor_h-120",
	float = true,
})

-- ── Layer rules ───────────────────────────────────────────────────────────────

-- Quickshell layer blur standard (match Control Center):
--   blur = true, ignore_alpha = 0.2
-- Panel shells should use Theme.glassShell / Theme.glassSection in QML.

hl.layer_rule({
	name = "quickshell_bar_vignette",
	match = { namespace = "^(quickshell:bar-vignette)$" },
	blur = false,
})

hl.layer_rule({
	name = "quickshell_panel",
	match = { namespace = "^(quickshell)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_command",
	match = { namespace = "^(quickshell:command)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_control",
	match = { namespace = "^(quickshell:control)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_system",
	match = { namespace = "^(quickshell:system)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_overview",
	match = { namespace = "^(quickshell:overview)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_dock",
	match = { namespace = "^(quickshell:dock)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_notifications",
	match = { namespace = "^(quickshell:notifications)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_island",
	match = { namespace = "^(quickshell:island)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_calculator",
	match = { namespace = "^(quickshell:calculator)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_timer",
	match = { namespace = "^(quickshell:timer)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_calendar",
	match = { namespace = "^(quickshell:calendar)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "quickshell_sliders",
	match = { namespace = "^(quickshell:sliders)$" },
	blur = true,
	ignore_alpha = 0.2,
})

--------------

hl.layer_rule({
	name = "rofi",
	match = { namespace = "rofi" },
	animation = "slide down",
	blur = true,
	ignore_alpha = 0.5,
})

hl.layer_rule({
	name = "slurp",
	match = { namespace = "^(slurp)$" },
	blur = false,
})

hl.layer_rule({
	name = "hyprpicker",
	match = { namespace = "^(hyprpicker)$" },
	blur = false,
})
