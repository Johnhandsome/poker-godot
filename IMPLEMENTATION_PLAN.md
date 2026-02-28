# Poker Godot — Implementation Plan

**Date:** 2026-02-28  
**Based on:** BUGS_REPORT.md

---

## Execution Order

Fixes are grouped by file to minimize context-switching. Within each file, changes are applied from bottom-to-top (highest line number first) to avoid line-number drift.

---

## Phase 1: P0 Critical Fixes

### Step 1 — BUG-01: Fix `Card.new()` argument order
- **File:** `scripts/ui/main_menu.gd` line 468
- **Change:** `Card.new(randi_range(2, 14), randi() % 4)` → `Card.new(randi() % 4 as Card.Suit, randi_range(2, 14) as Card.Rank)`
- **Risk:** None — cosmetic floating cards only.

### Step 2 — BUG-02: Fix quick-raise PotManager lookup
- **File:** `scripts/main.gd` line 498–510
- **Change:** Remove the `get_node("/root/PotManager")` lookup. Use `gm.pot_manager.get_total_pot()` directly via the existing `gm` variable.
- **Risk:** Low — only affects raise shortcut buttons.

### Step 3 — BUG-03: Fix folded-player detection in `_end_betting_round`
- **File:** `scripts/core/game_manager.gd` line 378
- **Change:** Replace `active_players.size() == 1` with a count of unfolded players. Also fix the `active_players[0]` bluff-factor reference to find the actual last unfolded player.
- **Risk:** Medium — core game loop change; need to preserve behavior for the working path in `process_player_action`.

---

## Phase 2: P1 Significant Fixes

### Step 4 — BUG-04: Replace hardcoded `"You"` with helper
- **File:** `scripts/core/game_manager.gd`
- **Change:** Add `_get_human_id() -> String` helper. Replace all `== "You"` checks with `_get_human_id()`. Guard with `multiplayer_mode` flag.
- **Locations:** Lines 381, 389, 489, 505, 547, 601, 607.
- **Risk:** Medium — touches multiple code paths.

### Step 5 — BUG-05: Connect BGM slider in main menu settings
- **File:** `scripts/ui/main_menu.gd` ~line 355
- **Change:** Add `sm.bgm_volume = bgm_slider.value` inside the `update_audio` lambda. Connect `bgm_slider.value_changed` to the same callback.
- **Risk:** None.

### Step 6 — BUG-06: Balance bot starting chips
- **File:** `scripts/visual/table_builder.gd` line 311
- **Change:** Set bot chips to match human chips (or a fair tournament stack like 1500). Read from a configurable value.
- **Risk:** Low — gameplay balance change; no code-path risk.

### Step 7 — BUG-07: Replace deprecated Callable syntax
- **File:** `scripts/core/hand_evaluator.gd` lines 41, 96
- **Change:** Replace `Callable(HandEvaluator, "_sort_card_descending")` with `func(a, b): return a.get_value() > b.get_value()` (or similar lambda).
- **Risk:** Low — pure refactor of comparison functions.

---

## Phase 3: P2 Quality Fixes

### Step 8 — BUG-08: Disconnect multiplayer lobby signals
- **File:** `scripts/ui/main_menu.gd` ~line 583
- **Change:** Store signal connections and disconnect them in the `btn_close` callback before freeing the panel. Use `overlay.tree_exiting` signal for guaranteed cleanup.
- **Risk:** Low.

### Step 9 — BUG-09: Make chip label updates event-driven
- **File:** `scripts/visual/table_builder.gd`
- **Change:** Remove `_update_chips_labels()` from `_process()`. Call it from `_on_player_action`, `_on_game_state_changed`, and `_on_winners_declared` instead.
- **Risk:** Low — purely a performance optimization.

### Step 10 — BUG-10: Add `_exit_tree` cleanup to main.gd
- **File:** `scripts/main.gd`
- **Change:** Add `_exit_tree()` function that disconnects all signals connected to `GameManager` in `_ready()`.
- **Risk:** Low.

---

## Verification

After all fixes:
1. Launch the main menu — floating cards should render correctly (BUG-01).
2. Start a single-player game — quick-raise buttons should work (BUG-02).
3. Play until a player folds — game should continue normally (BUG-03).
4. Check that bot chips match human chips (BUG-06).
5. Verify hand evaluation with edge cases (BUG-07).
6. Open/close settings panel — BGM slider should affect music (BUG-05).
7. Open/close multiplayer lobby multiple times — no errors (BUG-08).
