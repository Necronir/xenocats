# Epic: Code Review & Gameplay Audit Fixes (T-08 — T-13)

> **Source Audit:** Project Code & Gameplay Review (`v0.16.3`)  
> **Engine:** Godot 4.7.2 (Stable) | Strict Typed GDScript  
> **Workflow:** Isolated feature/fix branches off `main` (zero file overlap across branches)

---

## Ticket Overview Matrix

| ID | Branch | Ticket Title | Priority | Files / Modules |
|---|---|---|---|---|
| **T-08** | `fix/t08-ui-settings-video-concert` | `fix(ui): fix fullscreen toggle, concert spotlights rendering, and video player cutoff/bus` | P0 / P1 | `game_settings.gd`, `epilogue_scene.gd`, `video_player_scene.gd` |
| **T-09** | `fix/t09-input-qte-dodge-arena` | `fix(input): prevent QTE from blocking Pause/Menu and fix analog stick sensitivity in DodgeArena` | P1 | `qte_controller.gd`, `dodge_arena.gd` |
| **T-10** | `fix/t10-hub-ng-plus-and-gamepad` | `fix(hub): add New Game+ cycle selector, align shuttle module tooltips, and add gamepad focus navigation` | P0 / P1 | `hub_scene.gd` |
| **T-11** | `fix/t11-data-catalog-tres-and-enemy-ai` | `fix(data): sync boss .tres skills with DataCatalog, filter enemy parts from loot pool, and fix modular AI skill weighting` | P1 | `enemy_instance.gd`, `data_catalog.gd`, `cat_mech_instance.gd`, `export_resources.gd`, `data/resources/**` |
| **T-12** | `fix/t12-combat-bleed-fusions-final-boss` | `fix(combat): fix player bleed turn skip, multi-turn fusions, AOE/bleed phase gates, and ensemble finisher QTE` | P0 | `combat_arena.gd`, `map_scene.gd`, `dev_menu_bar.gd` |
| **T-13** | `chore/t13-test-isolation-export-and-parser` | `chore(infra): isolate user:// saves in verify suite, exclude unused dialogic from exports, deduplicate assets, and extract DtlTimelineParser` | P2 | `save_manager.gd`, `verify_all_systems.gd`, `export_presets.cfg`, `project.godot`, `dtl_timeline_parser.gd`, `event_scene.gd`, `mid_battle_dialogue_overlay.gd`, `assets/photos/` |

---

### Ticket T-08: Fullscreen Toggle, Concert Spotlights & Video Player Lifecycle
* **Branch:** `fix/t08-ui-settings-video-concert`
* **Problems:**
  1. `GameSettings.set_fullscreen()` had `set_dev_menu_enabled()` spliced into its body, never calling `apply_display()` or `changed.emit()`.
  2. `EpilogueScene` Act 2 drew spotlight polygons in `EpilogueScene._draw()` behind the opaque `_concert_bg` `TextureRect` and called `spot.queue_redraw()` on empty child `Node2D` nodes instead of a foreground drawing canvas item.
  3. `VideoPlayerScene` forcibly aborted active videos at `_estimated_duration = 14.0` seconds instead of waiting for `_video_player.finished`, routed audio to `Master` instead of `Music`, and unconditionally wrote `current_run.json` even when `SaveManager.has_active_run == false`.

---

### Ticket T-09: QTE Pause Interception & DodgeArena Stick / Touch Controls
* **Branch:** `fix/t09-input-qte-dodge-arena`
* **Problems:**
  1. `QTEController._input()` treated `JOY_BUTTON_START` and clicks/taps on top-bar UI buttons (`|| МЕНЮ`, `DevMenuBar`) as QTE strikes, blocking Pause during QTE.
  2. `DodgeArena._process()` summed `Input.get_vector("dodge_*")` with raw `Input.get_joy_axis()`, doubling analog stick sensitivity at partial tilt.

---

### Ticket T-10: Hub New Game+ Cycle Selector, Tooltip Alignment & Gamepad Focus
* **Branch:** `fix/t10-hub-ng-plus-and-gamepad`
* **Problems:**
  1. `New Game+` unlocked in Epilogue (`highest_ng_cycle`) had no UI selector or entry point in `HubScene` (`start_new_run()` reset `ng_cycle = 0`).
  2. `HubScene.SHUTTLE_MODULES` advertised `+25%` starting Sync for `harmonic_battery` while `SaveManager` grants `+12%` per level.
  3. Upgrade, perk, and tape buttons in `HubScene` lacked high-contrast `focus` StyleBoxes and cross-column `focus_neighbor_*` links for gamepads.

---

### Ticket T-11: `.tres` Resource Sync, Loot Pool Filtering & Modular Enemy AI Weighting
* **Branch:** `fix/t11-data-catalog-tres-and-enemy-ai`
* **Problems:**
  1. `boss_satellite.tres` lacked its signature `enemy_satellite_strike` skill, embedded `SubResource` skills lacked `dodge_pattern_id` / `dodge_patterns`, and `boss_censor` was missing from `DataCatalog` fallback initialization.
  2. `DataCatalog.get_loot_parts()` returned internal `boss_*` and `elite_*` parts alongside player-equippable parts.
  3. `EnemyInstance.choose_next_skill()` appended `data.skills` on top of intact modular part skills, giving `body_part` skills 2x probability weight.

---

### Ticket T-12: Combat Bleed Turn-Skip, Multi-Turn Fusions, Final Boss Gates & Finisher QTE
* **Branch:** `fix/t12-combat-bleed-fusions-final-boss`
* **Problems:**
  1. Indentation bug on `continue` in `CombatArena._advance_turn()` caused any living cat with `bleed_stacks > 0` to skip its turn completely.
  2. Tiered fusions (`_activate_fusion_tier`) immediately deactivated after 1 action instead of lasting their 2/3-round duration with unified HP pool and enemy DodgeBox routing.
  3. `ALL_ENEMIES` skills and enemy `BLEED` ticks bypassed `FinalBossController` color affinity & `party_members` gates, allowing Phase 1 AoE/bleed kills to one-shot the entire 4-phase final boss.
  4. `_start_ensemble_finisher()` ignored QTE timing failure (`true` hardcoded), `TRIUMPH_AURA` (`tape_bremen_triumph`) did not apply its advertised `+25%` damage bonus, `FinalBossController` HUD showed raw modular HP instead of active colored phase/shield, and Quartet runs could not reach `boss_censor` / Boss 4 in `DevMenuBar` & campaign climax.

---

### Ticket T-13: Test Suite Save Isolation, Export Bloat Cleanup & Shared `.dtl` Parser
* **Branch:** `chore/t13-test-isolation-export-and-parser`
* **Problems:**
  1. Running `verify_scene.tscn` wiped the developer's/player's real `user://meta_save.json`, `user://current_run.json`, and `user://settings.cfg`, and dirtied `res://data/resources/parts/*.tres`.
  2. `export_presets.cfg` packed 962 unused files (`7.26 MB`) from `addons/dialogic/`, and `assets/photos/` contained 10 unreferenced byte-for-byte duplicate `.jpg` files.
  3. `project.godot` kept `gdscript/warnings/*` at `1` (`WARN`) instead of `2` (`ERROR`), `SaveManager._exit_tree()` invoked nonexistent `clear_static_cache()` / `clear_cache()`, and `.dtl` parsing logic was duplicated across `EventScene` and `MidBattleDialogueOverlay`.
