# Easy Server Switcher

A Warhammer 40,000: Darktide mod (Darktide Mod Framework) that adds a small
**server switcher** next to **PLAY** on the mission board, so you can chase a populated
region without the stop / play / switch / play grind.

## What it does

A compact control sits just above PLAY:

```
        «   Asia & Pacific   »
        ┌─────────────────────┐
        │        PLAY         │
        └─────────────────────┘
```

- **`«` / `»` step** to the previous / next region through the game's own list
  (already sorted by ping). The arrow greys out at each end — **no wrap-around**.
- **The centre label shows the region you're on. Click it** to drop a **scrollable list
  of every region with its ping** — click any one to jump straight to it. The list opens
  below, stays inside the screen, and scrolls (mouse wheel) if it's tall.
- **Change region while you're sitting in a queue** → it cancels matchmaking and
  **instantly re-queues** on the new region. So when no queue hits, you just tap `»`
  (or pick from the list) and you're searching the next one.
- **Change region before queuing** → it just switches the region; press PLAY to start.
- **PLAY no longer closes the mission board.** The board stays open while you wait so the
  stepper stays reachable. Press **ESC** to leave. (Toggle off in options for stock behaviour.)

No existing mod did this — [Quickest Play](https://www.nexusmods.com/warhammer40kdarktide/mods/105)
only *respects* your region, and [Remember Server Location](https://www.nexusmods.com/warhammer40kdarktide/mods/308)
only persists it. Neither cycles + re-queues.

## Install

1. You need the **Darktide Mod Framework** + **Darktide Mod Loader** (already set up
   if you run other mods).
2. **Vortex:** install this zip through Vortex (it owns `mod_load_order.txt`).
   **Manual:** extract so you end up with:

   ```
   <game>/mods/easy_server_switcher/easy_server_switcher.mod
   <game>/mods/easy_server_switcher/scripts/mods/easy_server_switcher/...
   ```

   (the folder in `mods/` must be named `easy_server_switcher`), then add
   `easy_server_switcher` to `<game>/mods/mod_load_order.txt`, **below** `dmf`.
3. Launch with mods enabled.

## Options (Mod Settings menu)

| Setting | Default | Notes |
|---|---|---|
| Show server stepper | On | Show / hide the whole control. |
| Keep board open after PLAY | On | Keeps the board open so the stepper stays reachable in queue. |
| Auto re-queue when changing server | On | When queued, cancel + re-queue on the new region. Off = switch region only. |
| Position X | 0 | Nudge left (−) / right (+). **0 = centred on PLAY.** Applies live. |
| Position Y | −9 | Nudge up (−) / down (+). Applies live. |
| Arrow spacing | 6 | Gap between each `«` / `»` arrow and the centre label. |
| Button size (percent) | 72 | Overall scale of the control. |
| Hotkey: next / previous server | unbound | Optional fallbacks for `»` / `«` (only while the board is open). |

All position / size sliders update **in real time** while the board is open, so you can
dial it in exactly where you want it.

## Notes / limitations

- This injects widgets into `MissionBoardView` and hooks its PLAY callback. That UI is
  owned by Fatshark, so a future patch *could* move/rename it and stop the control from
  appearing. Everything is wrapped in `pcall`, so the worst case is the stepper does
  nothing — it won't crash the mission board. The region logic itself (list, set region,
  cancel/re-queue) is patch-stable; only the placement would need updating.
- The list opens over PLAY; clicking a region there never also starts a mission (PLAY is
  suppressed while the list is open).
- Re-queue uses the game's own cancel → start path. If a region has zero players you'll
  simply pick another.

## Dev reference

Built against the decompiled scripts (`Aussiemon/Darktide-Source-Code`). Key APIs used:

- Region list / get / set: `Managers.data_service.region_latency`
  (`get_region_latencies`, `get_prefered_mission_region`, `set_prefered_mission_region`),
  display names from `scripts/settings/backend/region_localization`.
- Start matchmaking: `MissionBoardView._callback_start_selected_mission` →
  `MissionBoardViewLogic:start_mission_matchmaking` (reads preferred region internally).
- Cancel queue: `Managers.party_immaterium:cancel_matchmaking()`; state via `:is_in_matchmaking()`.
- Keep-open: suppress `UIManager:close_view("mission_board_view")` during PLAY.
