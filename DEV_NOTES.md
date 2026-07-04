# Dev Notes — Easy Server Switcher

> Renamed from **Easy Server Changer** on 2026-07-01 (mod id `easy_server_changer` → `easy_server_switcher`,
> folder + files + `get_mod` id + `.mod` + display name). Pre-upload rename, so no user settings to migrate.

Mod-specific source map and decisions. Reusable Darktide/DMF API facts (region service,
mission board, matchmaking, widget injection, keep-view-open) live in the shared
[`../DEV_REFERENCE.md`](../DEV_REFERENCE.md). Line numbers drift — search by symbol if stale.

A SERVER button next to PLAY that cycles matchmaking region (game's ping-sorted list); if
already queued it cancels + re-queues on the next region. Also keeps the mission board open
after PLAY so the on-board button stays reachable while queued.

Injected into **three menus** now: the **mission board** (`mission_board_view`), the **Havoc play
view** (`havoc_play_view`), and the **Party Finder / group finder** (`group_finder_view`). Everything
except the anchor scenegraph node, its width, the region-list source, and the start callback is
generic; those four differ per view and live in the `ADAPTERS` table (keyed by `view.view_name`).

## Files
```
easy_server_switcher.mod
scripts/mods/easy_server_switcher/
  easy_server_switcher.lua              -- main: region cycle, requeue, button injection, hooks
  easy_server_switcher_data.lua         -- DMF options (checkboxes, numeric offsets, keybind)
  easy_server_switcher_localization.lua -- labels + tooltips + runtime strings
```

UI is a **3-widget stepper**: `«` (prev) · current-server label · `»` (next), placed just above
PLAY (centred on the `play_button` node). The **centre label is also a button**: click it to open
a **scrollable dropdown** of every region + ping, which opens downward over PLAY and is clamped to
the frame (virtualized rows, mouse-wheel scroll, opaque backdrop, PLAY suppressed while open).

## Source map — easy_server_switcher.lua
| Area | Function | Notes |
|------|----------|-------|
| Per-view adapters | `ADAPTERS` / `adapter_for(view)` / `anchor_of(view)` / `active_supported_view()` / `play_w_of(view)` | keyed by `view.view_name`; each supplies `anchor`, `play_w`, `latencies(view)`, optional `start(view)`. `mission_board_view`→`play_button`/375/`_mission_board_logic:get_region_latencies()`/`_callback_start_selected_mission`; `havoc_play_view`→`play_button`/347/`_regions_latency`/`_cb_on_mission_start`; `group_finder_view`→`start_group_button`/300/own async fetch cached on `view._esc_regions`/**no start** |
| Region list (ping-sorted) | `ordered_regions(view)` | source is per-view via `adapter.latencies(view)`; both return a table KEYED by region id → `{min_latency,max_latency}`; sort asc by `min_latency` |
| Display name | `region_label(name,data,with_time)` | `region_localization` map + `Localize` + ` %dms`/` %d-%dms`; `with_time` appends `  HH:MM` from `region_local_time(id)` when `show_region_time` on |
| Region local time | `region_local_time(id)` / `REGION_TZ` / `dst_active` | id→representative UTC offset (+DST); `os.date("!*t")`; pcall-wrapped |
| Current region | `current_region()` | `region_latency:get_prefered_mission_region()` |
| Set region (+requeue) | `apply_region(view, entry)` | shared core: `set_prefered_mission_region` → refresh label → if `is_in_matchmaking`+`auto_requeue` → `cancel_matchmaking():next(start)` |
| Arrows | `mod.step_server(view, dir)` | `dir` -1/+1, **clamps at ends** (no wrap) → `apply_region` |
| Dropdown pick | `mod.select_server(view, name)` | jump straight to a named region → `apply_region` |
| Requeue/start | `start_on_current_selection(view)` | calls `adapter.start(view)` (board: `_callback_start_selected_mission`; Havoc: `_cb_on_mission_start`) with close suppressed |
| Stepper | `build_stepper(view)` / `make()` | 3× `terminal_button` anchored to `play_button` node, appended to `view._widgets`, laid out via `widget.offset` (prev/label/next). Centre label is clickable (`toggle_dropdown`), font shrunk via `style.text.font_size` |
| Dropdown | `build/refresh/close/scroll/toggle_dropdown` + `dropdown_metrics` / `play_button_top_y` | opaque backdrop (z78) + `max_visible` rows (z80) over PLAY; virtualized scroll; frame-clamped via `UISceneGraph.world_position`; state on `view._esc_dropdown` |
| Label sync | `refresh_label(view)` | name-only centre label (pings live in dropdown); only on change (`view._esc_region_cache`); also syncs dropdown highlight; called from `update` hook + on step |
| Reposition | `reposition(view)` | live re-offset from options |
| Hooks | bottom of file | shared bodies `on_view_enter/exit/update` registered on **both** `MissionBoardView` **and** `HavocPlayView` (`on_enter`build · `on_exit`drop refs · `update`label sync + dropdown wheel-scroll via the **passed** `input_service` + deferred close). `MissionBoardView._callback_start_selected_mission`(**suppress PLAY while dropdown open** + keep board open). `HavocPlayView._cb_on_mission_start`(**suppress PLAY while dropdown open** only — no keep-open). `UIManager.close_view`(swallow when flagged) · `next/prev_server_keybind` · `on_setting_changed`(live reposition/rebuild on whichever supported view is open) |

## Dev workflow (this mod)
- Edit here; deploy to `<game>\mods\easy_server_switcher\` (folder MUST be `easy_server_switcher`
  — the `.mod` `mod_script` paths are prefixed with it). Add `easy_server_switcher` below `dmf`
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
- **Packaged a dist** (`dist/easy_server_switcher-1.0.0.zip`): top-level `easy_server_switcher/`
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

### 2026-07-01 (cont. 4) — dropdown wheel-scroll never fired (Vector3 vs table)
- **Symptom (user screenshot):** dropdown showed 5 rows ending at "Europe … **+5**" — the `+N`
  hint proved all 10 regions were in the list and 5 more sat below, but the wheel wouldn't move it.
  So NOT a short list and NOT the frame-clamp (both correct) — the scroll read itself was dead.
- **Cause:** `input_service:get("scroll_axis")` returns a **`Vector3` (userdata)**, not a Lua table
  (`input_service.lua:15` → `Vector3(0,0,0)`; every stock view reads `scroll_axis[2]` directly).
  The wheel handler guarded with `if ok and type(axis) == "table"` — `type(Vector3)` is `"userdata"`,
  so that branch was **never** taken and every wheel delta was discarded.
- **Fix:** read `axis[2]` directly inside the pcall and drop the `type()` guard —
  `local ok, v = pcall(function() local axis = input and input:get("scroll_axis"); return (axis and axis[2]) or 0 end)`
  then act on `v ~= 0`. Kept the accumulator + `is_hover` gate. (Now a shared DEV_REFERENCE gotcha:
  axis aliases are Vector3, never `type()`-check them.) Deployed + dist rebuilt (v1.0.0, 14.3 KB).

### 2026-07-04 session — approx. region local time (user feedback: gauge who's awake)
- **Feature:** append each region's approximate local time (e.g. `Europe  21:30`) to the centre
  label and every dropdown row, so players can eyeball how populated a region likely is.
  Optional via new `show_region_time` checkbox, **default ON** (per user).
- **Impl** (top of `easy_server_switcher.lua`): `REGION_TZ` maps the game's **stable region id**
  (`region_localization.lua`: `eu, hk, mei, sa, us-east, us-west, afr-south, ap-central, ap-north,
  ap-south`) → `{off=<min east of UTC>, dst=<"eu"/"us"/"au"/nil>}`. `region_local_time(id)` reads
  `os.date("!*t")` (UTC — same idiom the game's `foundation/utilities/date.lua` uses; `os.date`/
  `os.time` both survive `scrub_dangerous_functions.lua`), adds the offset (+60 if `dst_active`),
  formats `%02d:%02d`. All os.* pcall-wrapped → bad/absent clock just hides the time, never crashes.
- **DST** is day-granularity (flips on the boundary DAY, not the 01:00/02:00 hour) — fine for an
  "are they awake" clock. Rules: EU last-Sun-Mar..last-Sun-Oct, US 2nd-Sun-Mar..1st-Sun-Nov,
  AU (southern) 1st-Sun-Oct..1st-Sun-Apr. `weekday()` via `os.time{…,hour=12}` round-trip.
- **Label clock ticks:** `refresh_label` now also refreshes when the UTC minute changes
  (`view._esc_time_min`), so the persistent label clock isn't frozen between region switches.
  Dropdown refreshes every frame while open (existing highlight-sync), so its clock is live too.
- **ASSUMPTIONS to confirm in-game** (representative city per region is a judgement call; the three
  `ap-*` + `mei` are the shaky ones): `ap-central`→India +5:30, `ap-north`→Japan/Korea +9,
  `ap-south`→Sydney +10 (DST), `mei`→Riyadh/Bahrain +3. Fix = edit the one `REGION_TZ` block.
- **Deployed** the 3 scripts to the E: install (real copy, not symlink). **NOT yet verified in-game**
  (can't drive Darktide) and **dist zip NOT rebuilt** — do both once the region times read correct.

### 2026-07-04 (cont.) — Havoc menu support (`havoc_play_view`)
User asked to add the switcher to the **Havoc** menu ("make it work first, confirm layout later").
- **Refactored to per-view `ADAPTERS`** instead of duplicating the whole stepper. The region service
  (`Managers.data_service.region_latency`) and the `play_button` scenegraph node are identical in both
  views, so only three things are view-specific and now live in the adapter keyed by `view.view_name`:
  - `latencies(view)` — board: `_mission_board_logic:get_region_latencies()`; Havoc: `_regions_latency`
    (cached by `HavocPlayView:_setup_regions`, fetched async — nil for a beat after `on_enter`, so the
    label shows the region name until it loads; dropdown populates on open). **Same shape** (id→`{min,max}`).
  - `start(view)` — board: `_callback_start_selected_mission`; Havoc: `_cb_on_mission_start`.
  - `play_w` — board 375; Havoc **347** (`play_button` = `default_button.size {347,76}`).
- **`compute_layout`/`dropdown_metrics`/`play_w_of` now take `view`** so the group centres on the right
  PLAY width. `ordered_regions`, `start_on_current_selection`, keybind lookup, `on_setting_changed` all
  go through the adapter / `active_supported_view()` (whichever supported menu is open).
- **Lifecycle hooks registered on BOTH classes** via shared `on_view_enter/exit/update` bodies. The
  update hook now reads the **passed** `input_service` (4th arg) instead of `self._stored_input_service`
  — Havoc never sets `_stored_input_service`, but every view's `update(self,dt,t,input)` gets it
  (base_view.lua:476). Mission board still works (its passed service == the one it stores).
- **Havoc PLAY-suppression:** added `mod:hook("HavocPlayView","_cb_on_mission_start", …)` that swallows
  the click while the dropdown is open — REQUIRED because hotspots don't occlude, so a dropdown-row click
  also lands on Havoc's PLAY and would instantly queue the havoc mission. Synchronous, safe.
- **DECISION — no keep-open on Havoc.** Havoc's PLAY does `activate_havoc_mission():next(… on_back_pressed
  → close_view("havoc_background_view"))` — the close is **async** (can't be caught by the synchronous
  `suppress_close_view` flag) AND closes the *parent* stack, not the play view itself. Forcing the parent
  to stay open is risky + untestable by me, and Havoc's use case is "pick a region, then queue" (not the
  board's tap-» queue-hunting). So keep-open stays mission-board-only. Revisit if the user wants it.
- **luaparser syntax-checked** all 3 files (OK). **Deployed** to the E: install. **NOT verified in-game.**
  **dist zip NOT rebuilt.** Layout on Havoc (z-order/offset vs Havoc's own widgets) is unconfirmed —
  user will confirm placement next, per the ask.

### 2026-07-04 (cont. 2) — the REAL target is Party Finder, not Havoc (Nexus feedback)
Nexus thread: GuppyWasHere asked for "Havoc menu". DiminishedAC clarified the useful bit — the Havoc
menu (talk to Dukane) **already has a native server select**, and what he actually wants is a swapper
in the **Party Finder** menu, where he hosts 40s and waits for join requests. Confirmed in source:
`HavocPlayView._callback_open_options` already builds a region dropdown → our Havoc injection is
**redundant** (kept anyway; user has Havoc unlocked and can eyeball it, harmless).
- **Party Finder = `group_finder_view`** (BaseView; `start_group_button` host node 300x40). Uses the
  SAME region service — region is the group's **category**: `start_party_finder_advertise(meta, tags,
  region)` when hosting and `party_finder_list_advertisements_stream(region, tags)` when browsing.
- **Added a `group_finder_view` adapter.** New per-view fields `anchor` (scenegraph node) + kept
  `play_w`, since PF anchors to `start_group_button`, not `play_button`. `anchor_of(view)` replaced the
  four hardcoded `"play_button"` strings (stepper make, dropdown bg + rows, `play_button_top_y`).
- **Region source:** PF's own `fetch_regions()` discards its result, and the region service has NO
  synchronous getter (all promise-based; the board's sync `get_region_latencies` is on the *logic*, not
  the service). So the adapter lazily calls `region_latency:fetch_regions_latency()` once and caches on
  `view._esc_regions` (`false` = fetched-empty sentinel so it won't refetch forever). Cleared in on_exit.
- **Start Group suppression:** hooked `GroupFinderView._cb_on_start_group_button_pressed` to swallow
  while the dropdown is open (dropdown overlaps the host button; hotspots don't occlude → a row click
  would otherwise start advertising). Registered enter/exit/update hooks for `GroupFinderView` too.
- **DEFERRED — auto re-post while advertising.** DiminishedAC's real workflow is swapping WHILE already
  advertised, which should cancel + re-advertise the live listing on the new server. Not done this cut:
  (a) PF's "advertising" is NOT `party_immaterium:is_in_matchmaking()` (it's `advertise_state()`), so the
  existing requeue branch in `apply_region` never fires in PF — switching just sets the region for your
  NEXT Start Group; (b) a correct re-post needs the game's cancel_party_finder_advertise() +
  start_party_finder_advertise() with rebuilt tags/metadata, and I can't test it. Verified the pieces
  exist and are safe to build on: `cancel_party_finder_advertise()` (gfv:1888), `_selected_tags` survive
  `_reset_search` (doesn't clear them), `advertise_state()` for detection. Next iteration once layout OK.
- **Deployed** the lua to E:. **NOT verified in-game. dist NOT rebuilt.** User will open Party Finder
  (reachable by anyone via the PF NPC) to confirm the layout, then we wire the re-post.

### 2026-07-04 (cont. 3) — in-game feedback: positions, browse-refresh bug, host-mode decision
Zan tested in-game (has Havoc unlocked). Findings + what shipped:
- **CONFIRMED not redundant in PF.** The ONLY official server control is on Dukane's Havoc menu
  (`[E] Matchmaking Server Location`); Party Finder has none. So the mod fills a real gap in PF. (Havoc
  menu also has a native `« region »` region control, so our Havoc stepper there IS redundant — kept,
  harmless.) All the `« … HH:MM »` steppers Zan sees in PF screenshots are OURS (we append the clock).
- **BUG (fixed): region change in PF did nothing** until he poked a filter. Vanilla PF only reads the
  region when it (re)opens the search stream (`_start_advertisements_stream` reads
  `get_prefered_mission_region()` fresh, gfv:2820). Fix: new per-adapter `on_region_changed(view)`,
  called from `apply_region` after the region is set. For `group_finder_view`, while BROWSING it calls
  `view:_cb_on_refresh_button_pressed()` (tears down + reopens the stream → picks up the new region).
  Gated on `not party_immaterium:is_party_advertisement_active()`. pcall-wrapped.
- **Positions (per-view base offset).** Added `base_x/base_y` to each adapter, ADDED on top of the
  user's global `nudge_x/nudge_y` in `compute_layout` (and matched in `dropdown_metrics`). So one global
  fine-tune still works but each menu starts right. Board base 0/0 (his saved nudge already dialled it);
  **Havoc base_y -40** (raise slightly); **group_finder base_y -180** (raise significantly — that button
  sits near the screen bottom). These are STARTING guesses to refine from his next screenshots.
- **HOST-MODE decision — re-list IS possible, so KEEP the button (don't remove).** Verified in source:
  `start_party_finder_advertise(config, tags, category)` attaches the ad to your existing `party_id()`,
  and `cancel_party_finder_advertise()` only pulls the public listing — party members are NOT removed
  (the party isn't bound to a server until a mission launches; the ad's `category`/region is just which
  regional board you're posted on, same value as the mission region). So cancel + re-advertise MOVES the
  listing while the party stays. Also: the PF `update` loop **self-reconciles** state from
  `is_party_advertisement_active()` (gfv:2286/2333), so driving the manager flips the view UI for free.
  **NOT yet built** (deferred, coupled + async + untestable-by-me): while advertising, the host button
  (`start_group_button`) is hidden, so the stepper must **re-anchor to `cancel_group_button`** (the REMOVE
  LISTING node, gfv_def:375) AND `on_region_changed` must cancel + re-advertise (reuse
  `_cb_on_start_group_button_pressed` which rebuilds tags from `_selected_tags` — which survive
  `_reset_search`). Next turn, after positions + browse-refresh are confirmed.
- **luaparser OK. Deployed to E:. NOT verified in-game. dist NOT rebuilt.**

### 2026-07-04 (cont. 4) — browse-refresh CONFIRMED; PF position; hide on SHIFT details
- **Browse-refresh CONFIRMED working in-game** ("changing server also refreshes the list, works perfect").
- **PF position:** `-180` overshot (landed above BACK); Zan wants it under BACK → `group_finder` base_y
  now **-80** (still a tune point). Havoc base_y -40 not yet eyeballed.
- **Hide on SHIFT "Show Details":** holding SHIFT swaps PF's left filter column for the selected party's
  player list; native filters hide, but our stepper didn't. Signal = `view._previewed_group_id ~= nil`
  (set by `_setup_group_preview`; the game also `tags_grid:disable_input(true)` then, gfv:801). New
  per-adapter `hide_when(view)` predicate + `set_stepper_hidden(view, hide)` helper toggles
  prev/label/next `.visible` on transition and closes the dropdown when hiding; `on_view_update` early-
  returns while hidden. `_esc_hidden` tracks state (cleared in on_exit / destroy_stepper). Generic — other
  views have no `hide_when` so they never hide. **NOT yet verified in-game.**
