# Dev Notes — Easy Server Changer

Mod-specific source map and decisions. Reusable Darktide/DMF API facts (region service,
mission board, matchmaking, widget injection, keep-view-open) live in the shared
[`../DEV_REFERENCE.md`](../DEV_REFERENCE.md). Line numbers drift — search by symbol if stale.

A SERVER button next to PLAY that cycles matchmaking region (game's ping-sorted list); if
already queued it cancels + re-queues on the next region. Also keeps the mission board open
after PLAY so the on-board button stays reachable while queued.

## Files
```
easy_server_changer.mod
scripts/mods/easy_server_changer/
  easy_server_changer.lua              -- main: region cycle, requeue, button injection, hooks
  easy_server_changer_data.lua         -- DMF options (checkboxes, numeric offsets, keybind)
  easy_server_changer_localization.lua -- labels + tooltips + runtime strings
```

UI is a **3-widget stepper**: `«` (prev) · current-server label · `»` (next), placed just above
PLAY (centred on the `play_button` node). The **centre label is also a button**: click it to open
a **scrollable dropdown** of every region + ping, which opens downward over PLAY and is clamped to
the frame (virtualized rows, mouse-wheel scroll, opaque backdrop, PLAY suppressed while open).

## Source map — easy_server_changer.lua
| Area | Function | Notes |
|------|----------|-------|
| Region list (ping-sorted) | `ordered_regions(view)` | `view._mission_board_logic:get_region_latencies()` → table KEYED by region id → `{min_latency,max_latency}`; sort asc by `min_latency` |
| Display name | `region_label(name,data)` | `region_localization` map + `Localize` + ` %dms`/` %d-%dms` |
| Current region | `current_region()` | `region_latency:get_prefered_mission_region()` |
| Set region (+requeue) | `apply_region(view, entry)` | shared core: `set_prefered_mission_region` → refresh label → if `is_in_matchmaking`+`auto_requeue` → `cancel_matchmaking():next(start)` |
| Arrows | `mod.step_server(view, dir)` | `dir` -1/+1, **clamps at ends** (no wrap) → `apply_region` |
| Dropdown pick | `mod.select_server(view, name)` | jump straight to a named region → `apply_region` |
| Requeue/start | `start_on_current_selection(view)` | calls `view:_callback_start_selected_mission()` with close suppressed |
| Stepper | `build_stepper(view)` / `make()` | 3× `terminal_button` anchored to `play_button` node, appended to `view._widgets`, laid out via `widget.offset` (prev/label/next). Centre label is clickable (`toggle_dropdown`), font shrunk via `style.text.font_size` |
| Dropdown | `build/refresh/close/scroll/toggle_dropdown` + `dropdown_metrics` / `play_button_top_y` | opaque backdrop (z78) + `max_visible` rows (z80) over PLAY; virtualized scroll; frame-clamped via `UISceneGraph.world_position`; state on `view._esc_dropdown` |
| Label sync | `refresh_label(view)` | name-only centre label (pings live in dropdown); only on change (`view._esc_region_cache`); also syncs dropdown highlight; called from `update` hook + on step |
| Reposition | `reposition(view)` | live re-offset from options |
| Hooks | bottom of file | `on_enter`(build) · `on_exit`(drop refs) · `update`(label sync + dropdown wheel-scroll + deferred close) · `_callback_start_selected_mission`(**suppress PLAY while dropdown open** + keep board open) · `UIManager.close_view`(swallow when flagged) · `next/prev_server_keybind` · `on_setting_changed`(live reposition/rebuild, closes dropdown) |

## Dev workflow (this mod)
- Edit here; deploy to `<game>\mods\easy_server_changer\` (folder MUST be `easy_server_changer`
  — the `.mod` `mod_script` paths are prefixed with it). Add `easy_server_changer` below `dmf`
  in `mod_load_order.txt`, or install a zip via Vortex. Restart game (no hot reload).

---

## Session history & decisions
### 2026-06-27 session — initial build
- **Research gate (user asked first):** confirmed no existing mod does cycle+requeue. Quickest
  Play only *respects* region; Remember Server Location only *persists* it.
- **"PLAY closes the menu" was the key constraint.** PLAY calls `close_view`, which would make
  an on-board button vanish the moment you queue. So the mod suppresses that close (option,
  default on) → board stays open while queued → button stays reachable. This is *why* an
  on-screen button (user's choice over a hotkey) needs the keep-open behaviour.
- **Region cycling reuses the game's order** (already ping-sorted) per the user's note; no custom list.
- **Requeue** = set region → `cancel_matchmaking():next(start_on_current_selection)`; start
  reuses the stock PLAY callback (mission/quickplay branch) with close suppressed, so it picks
  up the new region (logic reads `get_prefered_mission_region` internally).
- **Placement is the only un-verifiable bit** (can't see render) → exposed `offset_x/offset_y`
  numeric sliders applied live via `on_setting_changed`; default just left of PLAY. All
  game-facing calls are `pcall`-wrapped so a patch degrades to "button does nothing", never a crash.
- Memories: [[easy-server-changer-mod]], [[user-darktide-modder]].

### 2026-06-27 session — redesign to stepper (after first in-game test)
- First build was a single button defaulted to `offset {-300, 0}` → landed left of PLAY in the
  map area (next to "Special Assignment"), barely visible, and "did nothing" when not queued
  (it only switched region silently). Confirmed the offset math was right — the default was just
  a bad spot.
- User feedback: needs to **see the current server**, and wants **two arrows (prev/next)**, like
  the difficulty `« DAMNATION »` stepper. Workflow is: click PLAY first, then tap `»` when no
  queue hits.
- Rebuilt as a 3-widget stepper above the difficulty selector. Live label via the
  `MissionBoardView.update` hook (refresh only on region change). Nudgeable via the offset options.
- **Persisted-settings gotcha:** the new position default didn't apply because the user already
  had the first build's `offset_x=-300` saved → the stepper rendered at the old spot. Fix: renamed
  the option ids to `server_x` / `server_y` (defaults `0 / -160`) so they read fresh. (Now in the
  shared DEV_REFERENCE DMF gotchas.)
- **No wrap-around** (user request): `step_server` clamps at the ends instead of cycling
  first↔last; the end arrow greys out (`hotspot.disabled`) and an edge press just notifies
  "already on the closest/furthest server".

### 2026-06-28 session — the real "no text" fix + lower default
- **Root cause of persistent invisible text FOUND.** `terminal_button`'s text pass runs
  `default_button_text_change_function` every frame, which does `content.text =
  content.original_text or ""`. We were setting `content.text` → wiped to `""` next frame →
  blank buttons the whole time (the earlier "don't disable the hotspot" change was a red
  herring). Fix: set **`content.original_text`** in `make()` and in `refresh_label()`. (Now a
  flagged gotcha in the shared DEV_REFERENCE.)
- **Position default lowered.** Scenegraph: `play_button` node; the native `difficulty_stepper`
  is its child at y `-130` (the `« DAMNATION »` bar). Our stepper anchors to `play_button`;
  default was `-88` (too high per user). Changed default to `-50` (in the gap just above PLAY).
- **Forced the new default past stale saves** by renaming the option ids `pos_x/pos_y` →
  `play_x/play_y` (DMF persists by id, so a changed `default_value` alone won't move a user who
  already dragged the old slider). `arrow_gap` / `button_scale` keep their ids.
- **DMF % gotcha:** option titles run through `string.format`, so the bare `%` in
  `"Button size (%)"` threw "invalid format" at game start. Use "percent". Also: an option with
  no localization entry keyed by its `setting_id` shows as raw `<setting_id>` — added a title
  entry for every setting.

### 2026-06-28 (cont.) — proper centring, the layout was wrong all along
- **Anchor model finally pinned down** (from the first screenshot with visible text): each widget
  anchors to the `play_button` node's **TOP-LEFT** corner; offset is added there; the
  terminal_button passes then centre the text inside the widget's own box. So the old
  `px-gap / px / px+gap` put all three boxes at the node's left edge → `«` flew to the far-left
  screen edge and `»` landed in the middle of the wide label. Not a spacing bug — a centring bug.
- **Fix:** `compute_layout()` lays the three boxes out left-to-right as one group and centres the
  group on the node centre (`PLAY_W*0.5`, PLAY_W=375 from `mission_board_view_settings.lua`).
  `nudge_x/nudge_y` move the group from centred (0,0 = centred); `arrow_pad` = gap between each
  arrow box and the label box. Y is centre-based (`cy = nudge_y - h/2`) so it holds when size changes.
- **Confirmed via DMF source (`core/options.lua:536`)** that defaults are written to saved
  settings on first init (`if mod:get(id)==nil then mod:set(id, default)`), so a changed default
  never reaches an existing user → renamed `play_x/play_y → nudge_x/nudge_y` (also their Y meaning
  changed to centre-based) and `arrow_gap → arrow_pad` (meaning changed) to ship fresh defaults.

### 2026-06-28 (cont. 2) — clickable label → server dropdown, label font, defaults
User feedback on the (now centred, text-visible) stepper: label text too big; centre box "looks
like a button but isn't clickable"; wants a scrollable dropdown of all servers + pings that opens
below and stays in-frame; and "change the defaults like my setting".
- **Label font too big** — `terminal_button` text is stock 24 and wrapped "Central & Southern
  Asia" onto two lines. Fix: `widget.style.text.font_size = label_font_size()` (≈18·scale, floor
  10). Safe per-widget because `create_definition` merges pass styles into a fresh table (now a
  shared DEV_REFERENCE gotcha). Also **dropped the ping from the centre label** (name only) —
  pings now live in the dropdown, so the label stays short.
- **Centre label made clickable** — it was already a live (hoverable) hotspot with no
  `pressed_callback`, hence "looks like a button but does nothing". Wired it to `toggle_dropdown`.
- **Dropdown** opens below the label over PLAY, virtualized + scrollable + frame-clamped:
  - **Hotspots don't occlude** (verified in `ui_passes.lua`) → a row over PLAY would also press
    PLAY. Suppress PLAY in the `_callback_start_selected_mission` hook **while the dropdown is
    open**, guarded by `not suppress_close_view` so our OWN auto-requeue start still runs. Rows
    defer their close to the next frame (`close_requested`) so PLAY stays suppressed for the whole
    click frame regardless of widget processing order.
  - **`terminal_button` bg is only ~40% opaque** → added an opaque backdrop (z78) behind the rows
    (z80) so PLAY is fully hidden. Panel width = `max(group_w, PLAY_W=375)` so the backdrop covers
    PLAY's full width.
  - **Frame-clamp:** `UISceneGraph.world_position(view._ui_scenegraph,"play_button")` gives the
    design-space Y; `max_visible = floor((1080 - first_row_top - 40) / row_h)`, fallback 7. 10
    regions total (`region_localization.lua`), so scroll engages mainly at larger scales.
  - **Scroll:** mouse wheel via `_stored_input_service:get("scroll_axis")[2]`, but only while a row
    is hovered (don't hijack the mission-list scroll). Virtualized: only `max_visible` row widgets
    exist; scroll remaps which region each shows (no clipping). ASCII "+N" hints on edge rows
    (avoided ▲▼ glyphs — not guaranteed in the menu font). Current region row is `is_selected`.
- **Defaults set to Zan's dialled-in values** (`nudge_y -15→-9`, `button_scale 100→72`). NO rename
  this time — his saved values already equal the new defaults, so we WANT them preserved; the
  change only affects fresh installs. (`nudge_x`/`arrow_pad` already matched.)
- **Packaged a dist** (`dist/easy_server_changer-1.0.0.zip`): top-level `easy_server_changer/`
  folder (matches the `.mod` path prefix) with `.mod` + `scripts/` + an updated user-facing
  `README.md`; excludes `DEV_NOTES.md` and `.claude/`. Rewrote the README (was still describing
  the old single `» SERVER` cycle button + `-300/0` offsets → now stepper + dropdown + new options).

### 2026-06-28 (cont. 3) — crash fix: don't mutate view._widgets mid-draw
- **In-game crash on clicking the centre label:** `ui_widget.lua: attempt to index local 'widget'
  (a nil value)`. Cause: the label's `pressed_callback` runs **mid-draw** (hotspot passes fire
  inside `_draw_widgets`), and `toggle_dropdown` add/removed widgets in `view._widgets` while that
  loop iterated it with a cached `num_widgets` (`base_view.lua:606`) → `table.remove` on close
  left a tail slot `nil` → `UIWidget.draw(nil)`. The « » arrows never hit this (they only change
  region, no widget add/remove).
- **Fix:** the label click now only sets `view._esc_dd_toggle = true`; the **update hook**
  performs the actual `toggle_dropdown` (build/close) at a safe point (update runs before draw).
  Row-click close was already deferred (`close_requested`). All `view._widgets` add/remove now
  happens from `update`/`on_setting_changed`, never a draw-time hotspot callback. (Now a shared
  DEV_REFERENCE gotcha.)
