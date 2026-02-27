extends Node

# This script is attached to an Autoload singleton named GameManager

enum GameState {
	WAITING_FOR_PLAYERS,
	DEALING_HOLE_CARDS,
	PREFLOP_BETTING,
	DEALING_FLOP,
	FLOP_BETTING,
	DEALING_TURN,
	TURN_BETTING,
	DEALING_RIVER,
	RIVER_BETTING,
	SHOWDOWN,
	DISTRIBUTING_POTS,
	ROUND_END
}

enum PlayerAction {
	FOLD,
	CHECK,
	CALL,
	RAISE,
	ALL_IN
}

signal state_changed(new_state: GameState, old_state: GameState)
# Removed unused player_action_requested signal
signal action_received(player_id: String, action: PlayerAction, amount: int)
signal community_cards_changed(cards: Array)
signal player_turn_started(player_id: String)
signal hand_evaluated(results: Dictionary)
signal game_message(message: String)
signal winners_declared(payouts: Dictionary, best_cards: Dictionary)

var current_state: GameState = GameState.WAITING_FOR_PLAYERS
var players: Array = [] # Array of player objects (nodes)
var active_players: Array = [] # IDs of players still in the hand
var dealer_index: int = 0
var current_player_index: int = 0
var last_aggressor_index: int = 0

var deck: Deck
var pot_manager: PotManager
var community_cards: Array[Card] = []

var small_blind: int = 10
var big_blind: int = 20
var current_bet: int = 0
var min_raise: int = 20

func _ready():
	deck = Deck.new()
	pot_manager = PotManager.new()

func register_player(player_node):
	players.append(player_node)
	
func start_game():
	if players.size() < 2:
		emit_signal("game_message", "Need at least 2 players to start.")
		return
		
	dealer_index = randi() % players.size()
	_start_new_round()

func _start_new_round():
	_change_state(GameState.WAITING_FOR_PLAYERS)
	
	deck.reset()
	deck.shuffle()
	pot_manager.reset()
	community_cards.clear()
	emit_signal("community_cards_changed", community_cards)
	
	active_players.clear()
	for player in players:
		if player.chips > 0:
			player.reset_for_new_round()
			active_players.append(player.id)
			
	if active_players.size() < 2:
		emit_signal("game_message", "Game Over - Not enough players with chips.")
		return
		
	dealer_index = (dealer_index + 1) % active_players.size()
	
	_post_blinds()
	_change_state(GameState.DEALING_HOLE_CARDS)
	# Visual dealing will happen here; we will await an animation finish signal later.
	await _deal_hole_cards_async()
	
	_change_state(GameState.PREFLOP_BETTING)
	_start_betting_round()

func _post_blinds():
	# Helper to find next active player index
	var sb_idx = (dealer_index + 1) % active_players.size()
	var bb_idx = (dealer_index + 2) % active_players.size()
	
	# In heads-up (2 players), dealer is SB
	if active_players.size() == 2:
		sb_idx = dealer_index
		bb_idx = (dealer_index + 1) % active_players.size()
		
	var sb_player = _get_player_by_id(active_players[sb_idx])
	var bb_player = _get_player_by_id(active_players[bb_idx])
	
	_process_bet(sb_player, min(small_blind, sb_player.chips))
	_process_bet(bb_player, min(big_blind, bb_player.chips))
	
	current_bet = big_blind
	min_raise = big_blind
	
	# Action starts UTG (Under the Gun), which is after BB
	current_player_index = (bb_idx + 1) % active_players.size()
	last_aggressor_index = bb_idx # Action closes on BB if no raises

func _deal_hole_cards_async():
	for _i in range(2):
		for p_id in active_players:
			var p = _get_player_by_id(p_id)
			p.draw_card(deck.deal())
			await get_tree().create_timer(0.08).timeout # Delay vật lý nhanh hơn
	await get_tree().create_timer(0.2).timeout # Đợi tất cả bài ổn định trên bàn

func _start_betting_round():
	# Find next active player who is not all-in
	_next_player_turn()

func _next_player_turn():
	# Check if betting round is over
	var _all_in_count = 0
	var active_non_allin_count = 0
	
	for p_id_itr in active_players:
		var player_itr = _get_player_by_id(p_id_itr)
		if player_itr.is_all_in:
			_all_in_count += 1
		else:
			active_non_allin_count += 1
			
	if active_non_allin_count <= 1 and active_players.size() > 1:
		# Everyone is all-in or only one player can still act, jump to showdown 
		# (need a check here if they owe money still)
		var all_matched = true
		for p_id_itr in active_players:
			var player_itr = _get_player_by_id(p_id_itr)
			if not player_itr.is_all_in and player_itr.current_bet < current_bet:
				all_matched = false
				break
		
		if all_matched:
			_end_betting_round()
			return

	# Normal turn logic
	var starting_idx = current_player_index
	var current_p_id = active_players[current_player_index]
	var current_p = _get_player_by_id(current_p_id)
	
	while current_p.is_all_in or current_p.is_folded or current_p.chips == 0:
		current_player_index = (current_player_index + 1) % active_players.size()
		if current_player_index == last_aggressor_index:
			# Round is over!
			_end_betting_round()
			return
			
		current_p_id = active_players[current_player_index]
		current_p = _get_player_by_id(current_p_id)
		
		# Infinite loop protection just in case
		if current_player_index == starting_idx:
			_end_betting_round()
			return
			
	emit_signal("player_turn_started", current_p_id)
	# Tell the player to make a decision
	current_p.request_action(current_bet, min_raise)

func _end_betting_round():
	pot_manager.gather_bets(active_players)
	current_bet = 0
	min_raise = big_blind
	
	for p_id in active_players:
		_get_player_by_id(p_id).current_bet = 0
		
	if active_players.size() == 1:
		# Everyone else folded
		_change_state(GameState.SHOWDOWN)
		_handle_showdown()
		return
		
	# Advance state
	match current_state:
		GameState.PREFLOP_BETTING:
			_change_state(GameState.DEALING_FLOP)
			await _deal_community_cards_async(3)
			_change_state(GameState.FLOP_BETTING)
			_reset_turn_order()
			_start_betting_round()
		GameState.FLOP_BETTING:
			_change_state(GameState.DEALING_TURN)
			await _deal_community_cards_async(1)
			_change_state(GameState.TURN_BETTING)
			_reset_turn_order()
			_start_betting_round()
		GameState.TURN_BETTING:
			_change_state(GameState.DEALING_RIVER)
			await _deal_community_cards_async(1)
			_change_state(GameState.RIVER_BETTING)
			_reset_turn_order()
			_start_betting_round()
		GameState.RIVER_BETTING:
			_change_state(GameState.SHOWDOWN)
			_handle_showdown()

func _reset_turn_order():
	current_player_index = (dealer_index + 1) % active_players.size()
	last_aggressor_index = current_player_index # Close action on the button

func _deal_community_cards_async(count: int):
	# Burn a card
	deck.deal() 
	for _i in range(count):
		community_cards.append(deck.deal())
		emit_signal("community_cards_changed", community_cards)
		await get_tree().create_timer(0.15).timeout # Delay từng lá community nhanh hơn
	await get_tree().create_timer(0.2).timeout

func _handle_showdown():
	var player_results = {}
	
	if active_players.size() > 1:
		for p_id in active_players:
			var p = _get_player_by_id(p_id)
			var result = HandEvaluator.evaluate(p.hole_cards, community_cards)
			player_results[p_id] = result
			p.hand_result = result
			
		emit_signal("hand_evaluated", player_results)
		
	_change_state(GameState.DISTRIBUTING_POTS)
	
	var payouts = pot_manager.distribute_pots(player_results)
	var win_best_cards = {}
	for p_id in payouts:
		if payouts[p_id] > 0 and player_results.has(p_id):
			win_best_cards[p_id] = player_results[p_id].best_cards
	emit_signal("winners_declared", payouts, win_best_cards)
	
	for p_id in payouts:
		var p = _get_player_by_id(p_id)
		p.chips += payouts[p_id]
		emit_signal("game_message", p.id + " thắng $" + str(payouts[p_id]) + "!")
		
	_change_state(GameState.ROUND_END)
	
	# Auto-start round mới sau 4 giây bằng Callable (tránh lỗi Lambda capture freed)
	get_tree().create_timer(4.0).timeout.connect(Callable(self, "_start_new_round"))

# --- Callbacks from player logic ---

func process_player_action(player_id: String, action: PlayerAction, amount: int = 0):
	var p = _get_player_by_id(player_id)
	
	match action:
		PlayerAction.FOLD:
			p.is_folded = true
			active_players.erase(player_id)
			if active_players.size() == 1:
				# Everyone folded, end round immediately
				_end_betting_round()
				return
				
		PlayerAction.CHECK:
			# Player checks, meaning they match the current bet (which is 0 for them)
			# or they are already matched. No chips are added.
			# The original logic `min(current_bet - p.current_bet, p.chips)` would result in 0 if matched.
			var amount_to_check = min(current_bet - p.current_bet, p.chips)
			_process_bet(p, amount_to_check) # This will process 0 if already matched
			
		PlayerAction.CALL:
			var amount_to_call = current_bet - p.current_bet
			if amount_to_call >= p.chips:
				amount_to_call = p.chips
				p.is_all_in = true
			_process_bet(p, amount_to_call)
			amount = amount_to_call # Cập nhật amount thật để UI hiện thị đúng số tiền call thay vì 0
			
		PlayerAction.RAISE:
			# amount here is the total new bet they want to make
			var added_amount = amount - p.current_bet
			if added_amount >= p.chips:
				added_amount = p.chips
				p.is_all_in = true
				
			_process_bet(p, added_amount)
			var raise_amount = amount - current_bet
			if raise_amount >= min_raise:
				min_raise = raise_amount
			current_bet = p.current_bet
			last_aggressor_index = current_player_index
			
		PlayerAction.ALL_IN:
			var all_in_amount = p.chips
			_process_bet(p, all_in_amount)
			p.is_all_in = true
			amount = all_in_amount # Cập nhật cho UI
			if p.current_bet > current_bet:
				var raise_amount = p.current_bet - current_bet
				if raise_amount > min_raise:
					min_raise = raise_amount
				current_bet = p.current_bet
				last_aggressor_index = current_player_index
				
	emit_signal("action_received", player_id, action, amount)
	
	current_player_index = (current_player_index + 1) % active_players.size()
	if current_player_index == last_aggressor_index:
		_end_betting_round()
	else:
		_next_player_turn()

func _process_bet(player, amount: int):
	if amount <= 0: return
	player.chips -= amount
	player.current_bet += amount
	pot_manager.add_bet(player.id, amount)
	if player.chips == 0:
		player.is_all_in = true

# --- Helpers ---

func _change_state(new_state: GameState):
	var old_state = current_state
	current_state = new_state
	emit_signal("state_changed", new_state, old_state)

func _get_player_by_id(id: String):
	for p in players:
		if p.id == id:
			return p
	return null
