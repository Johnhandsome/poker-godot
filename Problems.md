1. Critical Logic Bugs (High Priority)
These issues affect the correctness of the poker rules and AI behavior.

Flawed AI Post-Flop Evaluation (ai_bot.gd):

High Card Logic: The bot returns a strength of 0.0 for HIGH_CARD on the River (when community_cards.size() == 5). This means the bot will always fold unless it has at least a Pair, even if it holds Ace-High in a heads-up pot.
Pair Logic: The logic if c1 == top_table or c2 == top_table only detects if the bot pairs the highest card on the board. It fails to detect:
Pocket Pairs (e.g., holding K, K on a 2, 5, 9 board).
Bottom/Middle Pairs (e.g., holding 5, A on a 2, 5, 9 board).
Recommendation: Use a proper hand strength calculator (e.g., Monte Carlo simulation or a simpler "Effective Hand Strength" metric) that considers all pair types and potential kickers.
I
ncorrect "Check" Implementation (game_manager.gd):
Inside process_player_action, PlayerAction.CHECK calculates amount_to_check = min(current_bet - p.current_bet, p.chips).
Problem: In poker, you can only CHECK if current_bet == p.current_bet. If there is a bet to match, the action must be CALL. By calculating an amount for CHECK, the code effectively treats a Check as a Call, which confuses the game state and UI logic.
Fix: PlayerAction.CHECK should assert that current_bet == p.current_bet (amount is 0). If not, the move is illegal or should be rejected.

Potential Infinite Loop in Turn Logic (game_manager.gd):
The while loop in _next_player_turn relies on current_player_index == last_aggressor_index to break.
Risk: If last_aggressor_index becomes desynchronized (e.g., player elimination, side pots, or complex splits), the loop might run indefinitely or skip turns incorrectly.
Fix: Add a safety counter (e.g., loops_count) to break the loop if it exceeds active_players.size().
2. Architecture & Design (Medium Priority)
"God Object" GameManager:
GameManager handles game flow, rules, networking/signals, and player management. It is nearly 500 lines and growing.
Improvement: Extract logic into dedicated classes:
TurnManager: Handles current_player_index, last_aggressor, and turn order.
BettingManager: Handles pots, raises, and verify legal actions.

Visuals Creating Logic (table_builder.gd):
The TableBuilder script (a visual helper) is responsible for HumanPlayer.new and AIPlayer.new.
Problem: This couples the 3D representation with the core game logic. If you wanted to run a simulation without graphics, you couldn't easily do so.
Fix: The GameScene or a SessionManager should instantiate players, and TableBuilder should only be responsible for visualizing them (e.g., assigning a 3D avatar to an existing player node).

UI Constructed in Code (main.gd):
The entire Game UI is built procedurally in _setup_ui (hundreds of lines of Label.new(), HBoxContainer.new()).
Problem: This ignores Godot's powerful visual editor, making the UI hard to design, style, and maintain.
Fix: Move the UI to a separate scene (GameUI.tscn) and instantiate it.
3. Code Quality & Best Practices (Low Priority)
Manual Node Lifecycle Management:
GameManager uses is_instance_valid checks and manual array clearing (players.remove_at) to handle player deletion.
Improvement: Use Godot's signal system. Connect to the tree_exiting signal of a player to automatically unregister them from the GameManager.
Hardcoded Values:
Blind progression (10 * pow(2, ...)), timer delays (0.15, 4.0), and AI personality constants are hardcoded.
Fix: Move these to SettingsManager or a dedicated GameConfig resource.
randi() usage:
The code uses randi() % N.
Fix: Use randi_range(min, max) or pick_random() for arrays in Godot 4 for cleaner code.
Await on Timers:
await get_tree().create_timer(...).timeout is used frequently. If the scene changes while waiting, the code after await might try to access freed nodes.
Fix: Ensure critical logic checks is_instance_valid(self) or use a Timer node that is stopped when the scene exits.