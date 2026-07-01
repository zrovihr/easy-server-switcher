--[[
	Easy Server Switcher
	--------------------
	Adds a server stepper to the mission board:  «  Hong Kong 56ms  »
	sitting just above the difficulty selector, next to PLAY.

	- «  / »  step to the previous / next region (the game's own ping-sorted list).
	- The middle shows the region you're currently queueing into.
	- If you press an arrow while you're ALREADY in a queue, it cancels matchmaking and
	  instantly re-queues on the new region (so: click PLAY once, then just tap » whenever
	  no queue hits).
	- PLAY no longer closes the board, so the stepper stays reachable while you wait.

	All game-facing calls are pcall-wrapped: a future patch can at worst make the stepper
	do nothing, never crash the mission board.
]]

local mod = get_mod("easy_server_switcher")

local VIEW_NAME = "mission_board_view"

-- gated debug logging (Mod Settings -> Debug logging); shows up in console_logs/*.log
local function dbg(fmt, ...)
	if mod:get("debug_logging") then
		mod:info(fmt, ...)
	end
end

-- view name whose close we swallow during a PLAY / requeue call
local suppress_close_view = nil

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function region_loc_mappings()
	local ok, mappings = pcall(require, "scripts/settings/backend/region_localization")
	if ok and type(mappings) == "table" then
		return mappings
	end
	return {}
end

local function region_latency_service()
	local ds = Managers.data_service
	return ds and ds.region_latency
end

-- ordered (by ping) list of regions: { {name, data={min_latency,max_latency}}, ... } or nil
local function ordered_regions(view)
	local logic = view and view._mission_board_logic
	local latencies = logic and logic.get_region_latencies and logic:get_region_latencies()

	if type(latencies) ~= "table" then
		return nil
	end

	local list = {}
	for name, data in pairs(latencies) do
		list[#list + 1] = {
			name  = name,
			data  = data,
			order = (type(data) == "table" and data.min_latency) or 99999,
		}
	end

	if #list == 0 then
		return nil
	end

	table.sort(list, function(a, b)
		return a.order < b.order
	end)

	return list
end

-- "Hong Kong 56ms"
local function region_label(name, data)
	if not name or name == "" then
		return "—"
	end

	local loc_key = region_loc_mappings()[name]
	local display = name

	if loc_key and rawget(_G, "Localize") then
		local ok, localized = pcall(Localize, loc_key)
		if ok and localized and localized ~= "" then
			display = localized
		end
	end

	if type(data) == "table" and data.min_latency then
		if data.max_latency and math.abs(data.max_latency - data.min_latency) >= 5 then
			display = string.format("%s %d-%dms", display, data.min_latency, data.max_latency)
		else
			display = string.format("%s %dms", display, data.min_latency)
		end
	end

	return display
end

local function find_entry(list, name)
	if not list then
		return nil
	end
	for i = 1, #list do
		if list[i].name == name then
			return list[i], i
		end
	end
	return nil
end

local function current_region()
	local rls = region_latency_service()
	return rls and rls.get_prefered_mission_region and rls:get_prefered_mission_region()
end

local function notify(message)
	if not message or message == "" then
		return
	end
	pcall(function()
		Managers.event:trigger("event_add_notification_message", "default", { text = message })
	end)
end

-- Dropdown lives further down, but refresh_label and the hooks call into it. Forward-declare
-- so those upvalues resolve to the real functions once they're assigned below.
local refresh_dropdown, build_dropdown, close_dropdown, toggle_dropdown, scroll_dropdown

-- Update the centre label to the region we're currently set to (only when it changes).
-- The label shows the region NAME ONLY (pings live in the dropdown) so it stays short enough
-- to fit on one line at small button scales.
local function refresh_label(view)
	if not view or not view._esc_widgets then
		return
	end

	local cur = current_region()
	if cur ~= view._esc_region_cache then
		view._esc_region_cache = cur

		local list = ordered_regions(view)
		local _, idx = find_entry(list, cur)
		local label = region_label(cur, nil)   -- name only; pings are shown in the dropdown

		local widgets = view._esc_widgets
		if widgets.label then
			-- terminal_button reads original_text (it overwrites content.text each frame)
			widgets.label.content.original_text = label
			widgets.label.content.text = label
			widgets.label.dirty = true
		end

		-- grey out the arrow at each end (no wrap-around)
		if list and idx then
			if widgets.prev then
				widgets.prev.content.hotspot.disabled = (idx <= 1)
				widgets.prev.dirty = true
			end
			if widgets.next then
				widgets.next.content.hotspot.disabled = (idx >= #list)
				widgets.next.dirty = true
			end
		end
	end

	-- keep the open dropdown's current-region highlight in sync
	if view._esc_dropdown and view._esc_dropdown.open and refresh_dropdown then
		refresh_dropdown(view)
	end
end

-- ---------------------------------------------------------------------------
-- core action
-- ---------------------------------------------------------------------------

-- Start (or restart) matchmaking on the current selection without closing the board.
local function start_on_current_selection(view)
	if not view or not view._callback_start_selected_mission then
		return
	end

	suppress_close_view = view.view_name or VIEW_NAME
	local ok, err = pcall(view._callback_start_selected_mission, view)
	suppress_close_view = nil

	if not ok then
		mod:error("Failed to (re)start matchmaking: %s", tostring(err))
	end
end

-- Set the region to `entry`, refresh the label, and (if already queued + auto_requeue) requeue.
-- Shared by the « / » arrows (step_server) and the dropdown rows (select_server).
local function apply_region(view, entry)
	local rls = region_latency_service()
	if not rls or not rls.set_prefered_mission_region or not entry then
		dbg("apply_region: region service unavailable or no entry")
		notify(mod:localize("regions_not_loaded"))
		return
	end

	rls:set_prefered_mission_region(entry.name)
	refresh_label(view)
	dbg("apply_region: region set -> '%s'", tostring(entry.name))

	local label = region_label(entry.name, entry.data)

	local party = Managers.party_immaterium
	local in_matchmaking = mod:get("auto_requeue")
		and party and party.is_in_matchmaking and party:is_in_matchmaking()
	dbg("apply_region: in_matchmaking=%s", tostring(in_matchmaking))

	if in_matchmaking then
		notify(string.format("%s %s", mod:localize("requeueing"), label))

		local cancelled = nil
		pcall(function()
			cancelled = party:cancel_matchmaking()
		end)

		if cancelled and cancelled.next then
			cancelled:next(function()
				start_on_current_selection(view)
			end):catch(function()
				start_on_current_selection(view)
			end)
		else
			start_on_current_selection(view)
		end
	else
		notify(string.format("%s %s", mod:localize("server_switched"), label))
	end
end

-- Step to the previous (-1) / next (+1) region in the ping-sorted list. Clamps at the ends.
function mod.step_server(view, direction)
	dbg("step_server: direction=%s", tostring(direction))

	local list = ordered_regions(view)
	if not list then
		dbg("step_server: region list NOT loaded yet")
		notify(mod:localize("regions_not_loaded"))
		return
	end

	local _, idx = find_entry(list, current_region())
	idx = idx or 1

	-- clamp at the ends — do NOT wrap around
	local next_idx = idx + direction
	if next_idx < 1 or next_idx > #list then
		notify(mod:localize(direction < 0 and "already_first" or "already_last"))
		return
	end

	apply_region(view, list[next_idx])
end

-- Jump straight to a named region (used by the dropdown rows).
function mod.select_server(view, region_name)
	local list = ordered_regions(view)
	local entry = find_entry(list, region_name)
	if entry then
		apply_region(view, entry)
	else
		notify(mod:localize("regions_not_loaded"))
	end
end

-- ---------------------------------------------------------------------------
-- the on-screen stepper  ( «  region  » )
-- ---------------------------------------------------------------------------

-- base (100%) sizes; scaled by button_scale
local ARROW_W, LABEL_W, H = 48, 240, 52
-- dropdown row height (base 100%), scaled by button_scale
local ROW_H = 44
-- play_button scenegraph node size (mission_board_view_settings.lua). Our three widgets all
-- anchor to that node's TOP-LEFT corner and each terminal_button centres its own text inside
-- its box — so to get a real «  label  » we centre the whole group on the node centre (PLAY_W/2)
-- ourselves and lay the boxes out left-to-right. (The old px±gap math anchored every box at the
-- node's left edge, which flung « to the far left and dropped » into the middle of the label.)
local PLAY_W = 375

local function metrics()
	local scale = math.max(0.25, (mod:get("button_scale") or 100) / 100)
	return math.floor(ARROW_W * scale), math.floor(LABEL_W * scale), math.floor(H * scale)
end

-- The centre label + dropdown rows use a smaller font than the « » arrows so long region names
-- ("Central & Southern Asia") fit on one line. Scales with button_scale, floored so it stays
-- legible at small scales. (terminal_button's stock font is 24, which wrapped the label.)
local function label_font_size()
	local scale = math.max(0.25, (mod:get("button_scale") or 100) / 100)
	return math.max(10, math.floor(18 * scale + 0.5))
end

-- Returns offsets { prev={x,y,z}, label=…, next=… } and the box sizes aw,lw,h.
-- nudge_x/nudge_y move the (otherwise centred) group; arrow_pad is the gap between each
-- arrow box and the label box (smaller = arrows hug the label).
local function compute_layout()
	local aw, lw, h = metrics()
	local pad     = mod:get("arrow_pad") or 6
	local nudge_x = mod:get("nudge_x") or 0
	-- centre Y on (node_top + nudge_y): subtract h/2 so it stays put when the size changes
	local cy      = (mod:get("nudge_y") or -15) - h * 0.5
	local z       = 30

	local group_w    = aw + pad + lw + pad + aw
	local group_left = PLAY_W * 0.5 + nudge_x - group_w * 0.5
	local label_left = group_left + aw + pad

	return {
		prev  = { group_left,            cy, z },
		label = { label_left,            cy, z },
		next  = { label_left + lw + pad, cy, z },
	}, aw, lw, h
end

-- ---------------------------------------------------------------------------
-- the server dropdown ( opens below the centre label, scrollable, frame-clamped )
--
-- Hotspots in Darktide DON'T occlude each other (see ui_passes.lua: each computes is_hover from
-- the cursor independently), so a dropdown row drawn over PLAY would ALSO fire PLAY on click.
-- Two things stop that: (1) the `_callback_start_selected_mission` hook swallows PLAY while the
-- dropdown is open, and (2) an opaque backdrop hides PLAY (terminal_button's own bg is only
-- ~40% opaque — Color.terminal_background alpha 100/255).
-- Scrolling is virtualised: we create only `max_visible` row widgets and remap which region each
-- one shows, so nothing ever renders outside the panel (no clipping needed).
-- ---------------------------------------------------------------------------

-- Darktide's UI is laid out in a FIXED 1920x1080 "fragment" canvas (UIResolution: NUM_SCREEN_
-- FRAGMENTS_H = 1080) that the engine scales to fit any monitor. world_position + widget.offset +
-- font_size all live in this space, so the whole stepper/dropdown is resolution-independent and
-- the screen bottom is always design-y 1080. We derive it from the engine (not a magic number) so
-- it tracks any future change; the clamp only affects HOW MANY rows show, never their placement,
-- so on unusual aspect ratios it errs toward fewer rows / earlier scroll — never off-screen.
local DESIGN_H = 1080
pcall(function()
	local UIResolution = require("scripts/managers/ui/ui_resolution")
	if UIResolution and UIResolution.height_fragments then
		DESIGN_H = UIResolution.height_fragments()
	end
end)

-- design-space Y of the play_button node's top-left, or nil if it can't be resolved
local function play_button_top_y(view)
	local ok, y = pcall(function()
		local UIScenegraph = require("scripts/managers/ui/ui_scenegraph")
		local wp = UIScenegraph.world_position(view._ui_scenegraph, "play_button")
		return wp and wp[2]
	end)
	if ok and type(y) == "number" then
		return y
	end
	return nil
end

-- Panel geometry for `total` rows: panel_left, panel_w, first-row top-offset (rel. play_button
-- top-left), row_h, and how many rows fit on-screen (the rest scroll).
local function dropdown_metrics(view, total)
	local pos, aw, lw, h = compute_layout()
	local scale   = math.max(0.25, (mod:get("button_scale") or 100) / 100)
	local pad     = mod:get("arrow_pad") or 6
	local nudge_x = mod:get("nudge_x") or 0
	local row_h   = math.max(18, math.floor(ROW_H * scale))
	local group_w = aw + pad + lw + pad + aw

	-- panel is at least PLAY's width (375) so its opaque backdrop fully covers PLAY underneath;
	-- rows are this wide too so they're an easy click target.
	local panel_w    = math.max(group_w, PLAY_W)
	local panel_left = PLAY_W * 0.5 + nudge_x - panel_w * 0.5
	local top_off    = pos.label[2] + h + 4   -- just below the label box

	-- clamp visible rows so the panel never runs off the bottom of the frame
	local max_visible
	local play_y = play_button_top_y(view)
	if play_y then
		local available = DESIGN_H - (play_y + top_off) - 40   -- 40px bottom margin
		max_visible = math.floor(available / row_h)
	else
		max_visible = math.min(total, 7)                       -- safe fallback if no scenegraph
	end
	max_visible = math.clamp(max_visible, 1, total)

	return panel_left, panel_w, top_off, row_h, max_visible
end

-- opaque backdrop so the semi-transparent terminal_button rows fully hide PLAY behind them
local DROPDOWN_BACKDROP = {
	{
		pass_type = "texture",
		style_id  = "bg",
		value     = "content/ui/materials/backgrounds/default_square",
		style     = { color = { 255, 8, 10, 12 } },   -- ARGB: opaque near-black
	},
	{
		pass_type = "texture",
		style_id  = "frame",
		value     = "content/ui/materials/frames/frame_tile_2px",
		style     = {
			horizontal_alignment = "center",
			vertical_alignment   = "center",
			color  = { 255, 90, 110, 120 },
			offset = { 0, 0, 1 },
		},
	},
}

function build_dropdown(view)
	if not view or view._esc_dropdown then
		return
	end
	if type(view._widgets) ~= "table" or not view._create_widget then
		return
	end

	local list = ordered_regions(view)
	if not list then
		notify(mod:localize("regions_not_loaded"))
		return
	end

	local ok, err = pcall(function()
		local UIWidget = require("scripts/managers/ui/ui_widget")
		local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")

		local total = #list
		local panel_left, panel_w, top_off, row_h, max_visible = dropdown_metrics(view, total)
		local font = label_font_size()

		-- opaque backdrop (z=78, under the rows)
		local bg_def = UIWidget.create_definition(DROPDOWN_BACKDROP, "play_button", nil, { panel_w, max_visible * row_h })
		local backdrop = view:_create_widget("esc_dd_bg", bg_def)
		backdrop.offset = { panel_left, top_off, 78 }
		view._widgets[#view._widgets + 1] = backdrop

		-- rows (z=80, on top of the backdrop and PLAY)
		local rows = {}
		for i = 1, max_visible do
			local def = UIWidget.create_definition(ButtonPassTemplates.terminal_button, "play_button", nil, { panel_w, row_h })
			local widget = view:_create_widget("esc_dd_row_" .. i, def)
			widget.style.text.font_size = font
			widget.offset = { panel_left, top_off + (i - 1) * row_h, 80 }
			-- which region row `i` maps to is resolved at click time from the live scroll offset
			widget.content.hotspot.pressed_callback = function()
				local dd = view._esc_dropdown
				local entry = dd and dd.list and dd.list[(dd.scroll or 0) + i]
				if entry then
					dbg("dropdown row %d clicked -> %s", i, tostring(entry.name))
					mod.select_server(view, entry.name)
					-- close NEXT frame, not now: keeps the dropdown "open" for the rest of this
					-- input frame so the PLAY hotspot underneath stays suppressed.
					dd.close_requested = true
				end
			end
			view._widgets[#view._widgets + 1] = widget
			rows[i] = widget
		end

		view._esc_dropdown = {
			open = true, backdrop = backdrop, rows = rows, list = list, total = total,
			scroll = 0, max_visible = max_visible, row_h = row_h, scroll_accum = 0,
		}
		refresh_dropdown(view)
		dbg("dropdown built: %d regions, %d visible rows, row_h=%d", total, max_visible, row_h)
	end)

	if not ok then
		mod:error("Could not build server dropdown: %s", tostring(err))
		view._esc_dropdown = nil
	end
end

function refresh_dropdown(view)
	local dd = view and view._esc_dropdown
	if not dd or not dd.open then
		return
	end

	dd.scroll = math.clamp(dd.scroll or 0, 0, math.max(0, dd.total - dd.max_visible))
	local cur = current_region()

	for i = 1, dd.max_visible do
		local widget = dd.rows[i]
		local entry = dd.list[dd.scroll + i]
		if widget and entry then
			local text = region_label(entry.name, entry.data)
			-- ASCII "+N" scroll hints on the edge rows (no triangle glyphs — not guaranteed in
			-- the menu font) so the user knows more regions exist above / below.
			if i == 1 and dd.scroll > 0 then
				text = "+" .. dd.scroll .. "   " .. text
			elseif i == dd.max_visible then
				local below = dd.total - (dd.scroll + dd.max_visible)
				if below > 0 then
					text = text .. "   +" .. below
				end
			end
			widget.content.original_text = text
			widget.content.text = text
			widget.content.hotspot.is_selected = (entry.name == cur)   -- highlight current region
			widget.visible = true
			widget.dirty = true
		elseif widget then
			widget.visible = false
			widget.dirty = true
		end
	end
end

function close_dropdown(view)
	local dd = view and view._esc_dropdown
	if not dd then
		return
	end
	local arr = view._widgets
	if type(arr) == "table" then
		local ours = {}
		if dd.backdrop then ours[dd.backdrop] = true end
		if dd.rows then
			for i = 1, #dd.rows do ours[dd.rows[i]] = true end
		end
		for i = #arr, 1, -1 do
			if ours[arr[i]] then
				table.remove(arr, i)
			end
		end
	end
	view._esc_dropdown = nil
end

function scroll_dropdown(view, delta)
	local dd = view and view._esc_dropdown
	if not dd or not dd.open then
		return
	end
	dd.scroll = math.clamp((dd.scroll or 0) + delta, 0, math.max(0, dd.total - dd.max_visible))
	refresh_dropdown(view)
end

function toggle_dropdown(view)
	if view._esc_dropdown and view._esc_dropdown.open then
		close_dropdown(view)
	else
		build_dropdown(view)
	end
end

local function build_stepper(view)
	if not mod:get("show_button") then
		return
	end
	if not view or view._esc_widgets then
		return
	end
	if type(view._widgets) ~= "table" or not view._create_widget then
		return
	end

	local ok, err = pcall(function()
		local UIWidget = require("scripts/managers/ui/ui_widget")
		local ButtonPassTemplates = require("scripts/ui/pass_templates/button_pass_templates")

		local pos, aw, lw, h = compute_layout()

		-- terminal_button's text pass (default_button_text_change_function) copies
		-- content.original_text -> content.text EVERY frame. Setting content.text
		-- alone gets wiped to "" instantly -> invisible text. The text MUST live in
		-- content.original_text. (This is how the game itself feeds every terminal_button.)
		local function make(name, w, text, on_press)
			local def = UIWidget.create_definition(ButtonPassTemplates.terminal_button, "play_button", nil, { w, h })
			local widget = view:_create_widget(name, def)
			widget.content.original_text = text
			widget.content.text = text
			if on_press then
				widget.content.hotspot.pressed_callback = on_press
			end
			view._widgets[#view._widgets + 1] = widget
			return widget
		end

		local widgets = {}
		widgets.prev  = make("esc_server_prev",  aw, "«", function() dbg("« clicked"); mod.step_server(view, -1) end)
		widgets.label = make("esc_server_label", lw, mod:localize("regions_not_loaded"),
			-- DEFER the toggle. This callback fires mid-draw (inside the view's widget-draw loop);
			-- building/closing the dropdown adds/removes entries in view._widgets, and structurally
			-- mutating that array while `_draw_widgets` iterates it with a cached length corrupts the
			-- loop → `UIWidget.draw(nil)` crash. The update hook performs it at a safe point instead.
			function() dbg("label clicked -> request dropdown toggle"); view._esc_dd_toggle = true end)
		widgets.next  = make("esc_server_next",  aw, "»", function() dbg("» clicked"); mod.step_server(view,  1) end)

		-- smaller font on the centre label so long region names fit on one line (arrows keep 24)
		widgets.label.style.text.font_size = label_font_size()

		widgets.prev.offset  = pos.prev
		widgets.label.offset = pos.label
		widgets.next.offset  = pos.next

		view._esc_widgets = widgets
		view._esc_region_cache = nil
		refresh_label(view)
		dbg("stepper built: prev_x=%d label_x=%d next_x=%d y=%d", pos.prev[1], pos.label[1], pos.next[1], pos.prev[2])
	end)

	if not ok then
		mod:error("Could not create server stepper: %s", tostring(err))
	end
end

-- Reposition existing widgets from current option values (live).
local function reposition(view)
	local widgets = view and view._esc_widgets
	if not widgets then
		return
	end
	local pos = compute_layout()
	if widgets.prev  then widgets.prev.offset  = pos.prev;  widgets.prev.dirty = true end
	if widgets.label then widgets.label.offset = pos.label; widgets.label.dirty = true end
	if widgets.next  then widgets.next.offset  = pos.next;  widgets.next.dirty = true end
end

-- Remove our widgets from the view (needed before a size rebuild).
local function destroy_stepper(view)
	close_dropdown(view)   -- drop any open dropdown first (its rows live in the same _widgets array)
	local widgets = view and view._esc_widgets
	if not widgets then
		return
	end
	local ours = { [widgets.prev] = true, [widgets.label] = true, [widgets.next] = true }
	local arr = view._widgets
	if type(arr) == "table" then
		for i = #arr, 1, -1 do
			if ours[arr[i]] then
				table.remove(arr, i)
			end
		end
	end
	view._esc_widgets = nil
	view._esc_region_cache = nil
end

-- ---------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------

mod:hook_safe("MissionBoardView", "on_enter", function(self)
	build_stepper(self)
end)

mod:hook_safe("MissionBoardView", "on_exit", function(self)
	self._esc_widgets = nil
	self._esc_region_cache = nil
	self._esc_dropdown = nil   -- widgets die with the view; just drop our ref
	self._esc_dd_toggle = nil
end)

-- keep the label in sync, and drive the dropdown (deferred close + mouse-wheel scroll)
mod:hook_safe("MissionBoardView", "update", function(self)
	if self._esc_widgets then
		refresh_label(self)
	end

	-- process the deferred dropdown toggle from the label click (build/close mutate view._widgets,
	-- which must NOT happen mid-draw — see the label callback in build_stepper). update() runs
	-- before draw(), so doing it here is safe.
	if self._esc_dd_toggle then
		self._esc_dd_toggle = nil
		toggle_dropdown(self)
	end

	local dd = self._esc_dropdown
	if dd and dd.open then
		-- a row was clicked last frame: close now (PLAY stayed suppressed for that whole frame)
		if dd.close_requested then
			close_dropdown(self)
			return
		end

		-- mouse-wheel scroll, but ONLY while hovering the dropdown, so we don't hijack the
		-- mission-list scroll. scroll_axis[2] > 0 = wheel up = scroll toward the top of the list.
		if dd.total > dd.max_visible then
			local hovering = false
			for i = 1, #dd.rows do
				if dd.rows[i].content.hotspot.is_hover then
					hovering = true
					break
				end
			end
			if hovering then
				local input = self._stored_input_service   -- set by the view every draw
				-- scroll_axis comes back as a Vector3 (USERDATA), not a Lua table — every game
				-- view reads scroll_axis[2] directly. A `type(axis) == "table"` guard here is
				-- ALWAYS false and silently eats every scroll. Index [2] inside the pcall instead.
				local ok, v = pcall(function()
					local axis = input and input:get("scroll_axis")
					return (axis and axis[2]) or 0
				end)
				if ok and v ~= 0 then
					dd.scroll_accum = (dd.scroll_accum or 0) + v
					while dd.scroll_accum >= 1 do
						dd.scroll_accum = dd.scroll_accum - 1
						scroll_dropdown(self, -1)
					end
					while dd.scroll_accum <= -1 do
						dd.scroll_accum = dd.scroll_accum + 1
						scroll_dropdown(self, 1)
					end
				end
			end
		end
	end
end)

-- keep the board open after PLAY so the stepper stays reachable while queued
mod:hook("MissionBoardView", "_callback_start_selected_mission", function(func, self, ...)
	-- The dropdown overlaps PLAY and hotspots don't occlude, so a click on a row also lands on
	-- PLAY underneath. Swallow PLAY while the dropdown is open — but NOT when it's our own requeue
	-- starting the mission (start_on_current_selection sets suppress_close_view first), otherwise
	-- auto-requeue from the dropdown would never actually start.
	if self._esc_dropdown and self._esc_dropdown.open and not suppress_close_view then
		dbg("PLAY suppressed: server dropdown open")
		return
	end

	if not mod:get("keep_board_open") then
		return func(self, ...)
	end

	suppress_close_view = self.view_name or VIEW_NAME
	local ok, err = pcall(func, self, ...)
	suppress_close_view = nil

	if not ok then
		mod:error("PLAY callback error: %s", tostring(err))
	end
end)

-- swallow the close that PLAY / requeue would trigger on the mission board
mod:hook("UIManager", "close_view", function(func, self, view_name, ...)
	if suppress_close_view and view_name == suppress_close_view then
		return
	end
	return func(self, view_name, ...)
end)

-- optional hotkeys (only act while the board is open)
local function view_or_warn()
	local ui = Managers.ui
	local view = ui and ui.view_instance and ui:view_instance(VIEW_NAME)
	if not view then
		notify(mod:localize("open_board_first"))
	end
	return view
end

function mod.next_server_keybind()
	local view = view_or_warn()
	if view then mod.step_server(view, 1) end
end

function mod.prev_server_keybind()
	local view = view_or_warn()
	if view then mod.step_server(view, -1) end
end

-- live-apply position / size / visibility changes from the options menu
mod.on_setting_changed = function(setting_id)
	local watched = {
		nudge_x = "move", nudge_y = "move", arrow_pad = "move",
		button_scale = "rebuild", show_button = "rebuild",
	}
	local action = watched[setting_id]
	if not action then
		return
	end

	local ui = Managers.ui
	local view = ui and ui.view_instance and ui:view_instance(VIEW_NAME)
	if not view then
		return
	end

	-- any geometry/size change invalidates an open dropdown's layout — drop it; the user reopens
	close_dropdown(view)

	if not mod:get("show_button") then
		destroy_stepper(view)
		return
	end

	if action == "rebuild" then
		-- size change: recreate the widgets at the new size
		destroy_stepper(view)
		build_stepper(view)
	elseif view._esc_widgets then
		reposition(view)
	else
		build_stepper(view)
	end
end
