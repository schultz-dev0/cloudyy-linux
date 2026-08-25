-- @cloud-center-state = {"decoration:blur:enabled": "true", "decoration:blur:passes": "3", "decoration:blur:size": "3", "decoration:rounding": "0", "decoration:shadow:enabled": "true", "decoration:shadow:range": "1", "general:border_size": "1", "general:gaps_in": "8", "general:gaps_out": "14", "general:layout": "dwindle"}

local colors = require("colors")

hl.config({
	general = {
		col = {
			active_border = colors.accent,
			inactive_border = colors.border,
		},
		allow_tearing = true,
	},

	decoration = {
		rounding_power = 6.0,
		active_opacity = 0.9,
		inactive_opacity = 0.8,
		fullscreen_opacity = 1.0,
		dim_inactive = true,
		dim_strength = 0.2,
		dim_special = 0.8,

		shadow = {
			render_power = 1,
			color = "rgba(1a1a1aee)",
		},

		blur = {
			new_optimizations = true,
			ignore_opacity = true,
			xray = false,
			vibrancy = 0.1696,
			popups = true,
		},
	},

	dwindle = {
		preserve_split = true,
	},
})

hl.config({ debug = { vfr = true } })

hl.window_rule({
	name = "game-immediate",
	match = { class = "^(game_class)$" },
	immediate = true,
})

-- --- Cloud Center managed lookandfeel settings ---
hl.config({
    general = {
        border_size = 1,
        gaps_out = 14,
        gaps_in = 8,
        layout = "dwindle",
    },
    decoration = {
        rounding = 0,
        shadow = {
            enabled = true,
            range = 1,
        },
        blur = {
            enabled = true,
            passes = 3,
            size = 3,
        },
    },
})
-- --- End Cloud Center managed lookandfeel settings ---
