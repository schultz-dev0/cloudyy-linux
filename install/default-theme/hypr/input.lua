-- @cloud-center-state = {"input:accel_profile": "adaptive", "input:follow_mouse": "1", "input:kb_layout": "gb,ru", "input:kb_options": "grp:alt_shift_toggle", "input:sensitivity": "0.61"}

hl.config({
	input = {
		kb_layout = "gb,ru",
		kb_options = "grp:alt_shift_toggle",
		follow_mouse = 1,
		mouse_refocus = false,
		float_switch_override_focus = 0,
		sensitivity = 0,
		touchpad = {
			natural_scroll = true,
			disable_while_typing = false,
		},
	},
})

-- --- Cloud Center managed input settings ---
hl.config({
    input = {
        kb_layout = "gb,ru",
        kb_options = "grp:alt_shift_toggle",
        follow_mouse = 1,
        sensitivity = 0.61,
        accel_profile = "adaptive",
    },
})
-- --- End Cloud Center managed input settings ---
