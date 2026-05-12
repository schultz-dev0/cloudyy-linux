-- Window rules and layer rules
-- Sources: user-configs/user_windowrules.conf (active) + source/windowrules.conf

-- ── Application-specific rules ───────────────────────────────────────────────

hl.window_rule({
	name = "firefox",
	match = { class = "^(firefox)$" },
	size = "1080 1080",
	float = true,
})

hl.window_rule({
	name = "opaque-youtube",
	match = { class = "^(firefox)$", title = ".*Youtube.*" },
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
	--size = "1080 900",
	--float = true,
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

hl.window_rule({
	name = "rustykeys",
	match = { class = "^(org.cloudyy.rustykeys)$" },
	float = true,
	size = "550 420",
	center = true,
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
	name = "thunar-rename",
	match = { class = "^(thunar)$", title = ".*Rename*." },
	float = true,
	size = "530 400",
	center = true,
})

hl.window_rule({
	name = "thunar",
	match = { class = "^(thunar)$" },
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
	size = "1000 960",
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

hl.layer_rule({
	name = "quickshell_panel",
	match = { namespace = "^(quickshell)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "rofi",
	match = { namespace = "rofi" },
	animation = "slide down",
})

hl.layer_rule({
	name = "hyprdock",
	match = { namespace = "^(hyprdock)$" },
	blur = true,
	ignore_alpha = 0.2,
})

hl.layer_rule({
	name = "hyprdock-spotlight",
	match = { namespace = "^(hyprdock%-spotlight.*)$" },
	blur = true,
	ignore_alpha = 0.1,
})

hl.layer_rule({
	name = "hyprdock-trigger",
	match = { namespace = "^(hyprdock%-trigger)$" },
	blur = false,
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
