-- Input: keyboard layout, mouse sensitivity
-- Source: source/input.conf

hl.config({
	input = {
		kb_layout = "gb,ru",
		kb_options = "grp:alt_shift_toggle",
		follow_mouse = 1,
		sensitivity = 0,
		touchpad = {
			natural_scroll = true,
			tap_to_click = true,
			disable_while_typing = false,
		},
	},
})
