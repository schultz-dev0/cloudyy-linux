-- Look and feel: general, decoration, dwindle, misc
-- Sources: source/lookandfeel.conf + user-configs/user_cloud-center.conf + user_lookandfeel.conf

local colors = require("colors")

hl.config({
	general = {
		col = {
			active_border = colors.primary,
			inactive_border = colors.inverse_on_surface,
		},
		allow_tearing = true,
		gaps_in = 8, -- cloud-center override
		gaps_out = 14, -- cloud-center override
		border_size = 2,
	},

	decoration = {
		rounding = 14, -- cloud-center override
		rounding_power = 6.0,

		active_opacity = 0.9,
		inactive_opacity = 0.8,
		fullscreen_opacity = 1.0,

		dim_inactive = true,
		dim_strength = 0.2,
		dim_special = 0.8,

		shadow = {
			enabled = true,
			range = 25,
			render_power = 1,
			color = "rgba(1a1a1aee)",
		},

		blur = {
			enabled = true,
			size = 2, -- cloud-center override
			passes = 2, -- cloud-center override
			new_optimizations = true,
			ignore_opacity = true,
			xray = false,
			vibrancy = 0.1696,
			popups = true,
		},
	},

	dwindle = {
		pseudotile = true,
		preserve_split = true,
	},
})

-- Variable framerate (was misc:vfr in older conf syntax — now debug:vfr)
hl.config({ debug = { vfr = true } })

-- Legacy windowrulev entries from lookandfeel.conf
hl.window_rule({
	name = "volume-slider-float",
	match = { class = "^(volume-slider)$" },
	float = true,
	center = true,
	stayfocused = true,
})

hl.window_rule({
	name = "game-immediate",
	match = { class = "^(game_class)$" },
	immediate = true,
})
