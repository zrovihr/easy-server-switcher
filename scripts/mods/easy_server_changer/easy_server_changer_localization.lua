return {
	mod_name = {
		en = "Easy Server Changer",
	},
	mod_description = {
		en = "Adds a one-press SERVER button next to PLAY on the mission board that cycles your matchmaking region (sorted by ping). If you are already in a queue, it cancels and instantly re-queues on the next region so you never have to stop / play / change / play again.",
	},

	-- Option titles (DMF shows the raw <setting_id> when a setting has no matching
	-- localization entry, so each setting_id below MUST be a key here). The position
	-- labels state the origin so the centre point is obvious: PLAY = 0.
	show_button = {
		en = "Show server stepper",
	},
	debug_logging = {
		en = "Debug logging",
	},
	keep_board_open = {
		en = "Keep board open after PLAY",
	},
	auto_requeue = {
		en = "Auto re-queue when changing server",
	},
	nudge_x = {
		en = "Position X   (0 = centred on PLAY,  - left / + right)",
	},
	nudge_y = {
		en = "Position Y   (0 = on PLAY,  - up / + down)",
	},
	arrow_pad = {
		en = "Arrow spacing",
	},
	-- NOTE: no bare "%" here — DMF runs titles through string.format, so a lone
	-- "%" is read as a format specifier and throws "invalid format". Use the word.
	button_scale = {
		en = "Button size (percent)",
	},
	next_server_key = {
		en = "Hotkey: next server",
	},
	prev_server_key = {
		en = "Hotkey: previous server",
	},

	show_button_tooltip = {
		en = "Show the server stepper ( « region » ) on the mission board.",
	},
	debug_logging_tooltip = {
		en = "Write diagnostic lines to the console log (for troubleshooting).",
	},
	keep_board_open_tooltip = {
		en = "Keep the mission board open after pressing PLAY, so the SERVER button stays reachable while you wait in queue. Press ESC to leave. Turn this off to restore the stock behaviour (board closes on PLAY).",
	},
	auto_requeue_tooltip = {
		en = "When you are already in a queue and press SERVER, cancel matchmaking and immediately re-queue on the newly selected region. Turn off to only switch the region without re-queueing.",
	},
	offset_x_tooltip = {
		en = "Nudge the stepper left/right from its centred-on-PLAY position. 0 = centred. Negative = left, positive = right.",
	},
	offset_y_tooltip = {
		en = "Nudge the stepper up/down. 0 = level with PLAY. Negative = up (toward the difficulty selector), positive = down.",
	},
	arrow_pad_tooltip = {
		en = "Gap between each « / » arrow and the centre label. Smaller = arrows hug the label tighter.",
	},
	button_scale_tooltip = {
		en = "Overall size of the stepper (percent). 100 = default; larger = bigger buttons and a wider label (fits longer server names).",
	},

	-- runtime strings
	server_switched = {
		en = "Server:",
	},
	button_prefix = {
		en = "» SERVER",
	},
	regions_not_loaded = {
		en = "Server list not loaded yet — open the mission board and try again.",
	},
	open_board_first = {
		en = "Open the mission board first to change server.",
	},
	requeueing = {
		en = "Re-queueing on",
	},
	already_first = {
		en = "Already on the closest server (lowest ping).",
	},
	already_last = {
		en = "Already on the furthest server (highest ping).",
	},
}
