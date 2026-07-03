local mod = get_mod("easy_server_switcher")

return {
	name        = mod:localize("mod_name"),
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id    = "show_button",
				type          = "checkbox",
				default_value = true,
				tooltip       = "show_button_tooltip",
			},
			{
				setting_id    = "debug_logging",
				type          = "checkbox",
				default_value = false,
				tooltip       = "debug_logging_tooltip",
			},
			{
				setting_id    = "keep_board_open",
				type          = "checkbox",
				default_value = true,
				tooltip       = "keep_board_open_tooltip",
			},
			{
				setting_id    = "auto_requeue",
				type          = "checkbox",
				default_value = true,
				tooltip       = "auto_requeue_tooltip",
			},
			-- Append each region's approximate local time (e.g. "Europe  21:30") to the
			-- label and dropdown, so you can gauge how many players are likely awake there.
			{
				setting_id    = "show_region_time",
				type          = "checkbox",
				default_value = true,
				tooltip       = "show_region_time_tooltip",
			},
			-- Where the stepper sits, measured from the centre of the PLAY button.
			-- Negative X = left, positive X = right. Negative Y = up, positive Y = down.
			-- Default puts it just above the difficulty selector.
			-- nudge_x/nudge_y move the stepper from its CENTRED-on-PLAY default
			-- (0,0 = centred). Negative X = left, positive = right; negative Y = up.
			{
				setting_id     = "nudge_x",
				type           = "numeric",
				default_value  = 0,
				range          = { -1000, 1000 },
				decimals_number = 0,
				tooltip        = "offset_x_tooltip",
			},
			{
				setting_id     = "nudge_y",
				type           = "numeric",
				default_value  = -9,
				range          = { -700, 700 },
				decimals_number = 0,
				tooltip        = "offset_y_tooltip",
			},
			-- gap between each « / » arrow box and the label box (smaller = arrows hug the label)
			{
				setting_id     = "arrow_pad",
				type           = "numeric",
				default_value  = 6,
				range          = { 0, 120 },
				decimals_number = 0,
				tooltip        = "arrow_pad_tooltip",
			},
			-- overall size of the stepper, as a percentage. Default 72 = the value Zan dialled in
			-- (small enough that the « label » sits neatly above PLAY without crowding it).
			{
				setting_id     = "button_scale",
				type           = "numeric",
				default_value  = 72,
				range          = { 40, 250 },
				decimals_number = 0,
				tooltip        = "button_scale_tooltip",
			},
			-- Optional fallbacks: hotkeys that do the same as the « / » arrows
			-- (only work while the mission board is open).
			{
				setting_id      = "next_server_key",
				type            = "keybind",
				default_value   = {},
				keybind_trigger = "pressed",
				keybind_type    = "function_call",
				function_name   = "next_server_keybind",
			},
			{
				setting_id      = "prev_server_key",
				type            = "keybind",
				default_value   = {},
				keybind_trigger = "pressed",
				keybind_type    = "function_call",
				function_name   = "prev_server_keybind",
			},
		},
	},
}
