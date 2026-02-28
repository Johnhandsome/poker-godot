# Poker Godot — Bug Report

**Date:** 2026-02-28  
**Scope:** Full codebase audit of all `.gd` scripts and `.tscn` scenes

---

## P0 — Critical Bugs (Game-breaking)

### BUG-01: Card constructor arguments swapped in MainMenu floating cards
- **File:** `scripts/ui/main_menu.gd` line 468
- **Description:** `Card.new(randi_range(2, 14), randi() % 4)` passes `rank` as the first arg and `suit` as the second, but `Card._init(s: Suit, r: Rank)` expects `(suit, rank)`. This creates cards with invalid or swapped suit/rank values, potentially causing texture lookup failures.
- **Impact:** Floating background cards on the main menu render incorrectly or crash.
- **Fix:** Swap the arguments: `Card.new(randi() % 4, randi_range(2, 14))`

### BUG-02: Quick-raise buttons look up non-existent PotManager autoload
- **File:** `scripts/main.gd` line 498
- **Description:** `get_node("/root/PotManager")` is used but `PotManager` is NOT an autoload singleton — it's an instance created inside `GameManager`. The node is never found, so all pot-fraction quick-raise buttons (1/4, 1/3, 1/2, etc.) silently do nothing.
- **Impact:** Quick-raise shortcut buttons are completely non-functional.
- **Fix:** Access `gm.pot_manager` directly instead of looking for a node path.

### BUG-03: Folded players stay in `active_players`, breaking single-remaining-player detection
- **File:** `scripts/core/game_manager.gd` line 378
- **Description:** When a player folds, they are only marked `is_folded = true` but never removed from `active_players`. The `_end_betting_round()` function checks `active_players.size() == 1` to detect "everyone else folded", but this can never be true since folded players remain in the list. The actual unfolded-count check in `process_player_action` works, but the duplicate check in `_end_betting_round` is dead code, and the bluff-factor update logic keyed on `active_players[0]` may reference a folded player.
- **Impact:** AI bluff-tracking logic may misfire. Redundant size check is misleading.
- **Fix:** Use an unfolded-player count check instead of `active_players.size()`.

---

## P1 — Significant Bugs (Functional issues)

### BUG-04: Hardcoded `"You"` ID breaks multiplayer mode
- **File:** `scripts/core/game_manager.gd` lines 381, 389, 489, 505, 547, 601, 607
- **Description:** Multiple places compare player IDs against the literal string `"You"`, which is only valid in single-player mode. In multiplayer, the human player's ID is their peer ID (e.g., `"1"`). This causes the AI memory system (`human_bluff_factor`), save-on-action, and showdown bluff analysis to silently skip.
- **Impact:** AI bluff tracking and auto-save are non-functional in multiplayer.
- **Fix:** Add a `_get_human_id()` helper that returns `"You"` in singleplayer or the local peer ID in multiplayer.

### BUG-05: BGM volume slider not connected in main menu settings
- **File:** `scripts/ui/main_menu.gd` ~line 358
- **Description:** The `update_audio` lambda only updates `master_volume` and `sfx_volume` but never reads or applies `bgm_slider.value` to `sm.bgm_volume`. Additionally, `bgm_slider.value_changed` is not connected to any callback.
- **Impact:** Changing BGM volume in the main menu has no effect.
- **Fix:** Add `sm.bgm_volume = bgm_slider.value` inside the update lambda and connect `bgm_slider.value_changed`.

### BUG-06: Bot starting chips heavily imbalanced vs human
- **File:** `scripts/visual/table_builder.gd` line 311
- **Description:** Bots are always created with 1000 chips while the human player starts with their saved bankroll (default 5000). This gives the human a 5:1 chip advantage.
- **Impact:** Game difficulty is trivially easy; bots are eliminated quickly.
- **Fix:** Give bots a reasonable starting stack relative to the human (e.g., same as human or a configurable tournament stack).

### BUG-07: Deprecated `Callable(ClassName, "method")` syntax for static methods
- **File:** `scripts/core/hand_evaluator.gd` lines 41, 96, 193, 201
- **Description:** `Callable(HandEvaluator, "_sort_card_descending")` is the Godot 3.x style. In Godot 4.x, this should be a direct method reference. Depending on the engine build, this may produce warnings or fail silently.
- **Impact:** Potential sorting failures leading to wrong hand evaluation.
- **Fix:** Replace with lambda wrappers or direct static method references.

---

## P2 — Minor Issues (Quality / Performance)

### BUG-08: Multiplayer lobby signal connections leak on panel close
- **File:** `scripts/ui/main_menu.gd` lines 583–603
- **Description:** When the multiplayer panel is opened, signals from `NetworkManager` are connected to lambdas that reference UI nodes. When the panel is closed and freed, these connections remain on the autoload, pointing at freed objects. Reopening creates duplicate connections.
- **Impact:** Potential errors or duplicate UI updates after reopening the lobby.
- **Fix:** Disconnect signals when the panel is freed.

### BUG-09: `_update_chips_labels()` runs every `_process` frame
- **File:** `scripts/visual/table_builder.gd` line 186
- **Description:** Chip label text is updated every frame via `_process(delta)`. This is wasteful since chips only change on specific events.
- **Impact:** Unnecessary CPU/GPU overhead.
- **Fix:** Move the update to event-driven calls (on `action_received`, `state_changed`).

### BUG-10: No signal cleanup on scene exit in main.gd
- **File:** `scripts/main.gd`
- **Description:** When navigating from the game back to the main menu, the `GameManager` autoload retains stale signal connections from the freed main scene. Re-entering the game scene creates duplicate connections.
- **Impact:** Potential double-firing of callbacks, memory leaks.
- **Fix:** Disconnect signals in `_exit_tree()`.

---

## Summary Table

| ID | Priority | File | Short Description |
|----|----------|------|-------------------|
| BUG-01 | P0 | main_menu.gd | Card.new() args swapped |
| BUG-02 | P0 | main.gd | PotManager node not found |
| BUG-03 | P0 | game_manager.gd | Folded players in active list |
| BUG-04 | P1 | game_manager.gd | Hardcoded "You" in multiplayer |
| BUG-05 | P1 | main_menu.gd | BGM slider disconnected |
| BUG-06 | P1 | table_builder.gd | Bot chips imbalance |
| BUG-07 | P1 | hand_evaluator.gd | Deprecated Callable syntax |
| BUG-08 | P2 | main_menu.gd | Signal leak in lobby |
| BUG-09 | P2 | table_builder.gd | Per-frame label updates |
| BUG-10 | P2 | main.gd | No exit_tree cleanup |
