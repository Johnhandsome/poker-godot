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

# Removed unused player_action_requested signal
signal action_received(player_id: String, action: PlayerAction, amount: int)
signal community_cards_changed(cards: Array)
signal player_turn_started(player_id: String)
signal hand_evaluated(results: Dictionary)
signal state_changed(new_state: int, old_state: int)
signal betting_round_ended() # Phát ra khi kết thúc một vòng cược để gom chip
signal game_message(message: String)
signal winners_declared(payouts: Dictionary, best_cards: Dictionary)
signal player_eliminated(player_id: String)
signal game_over(human_won: bool)
signal blinds_level_changed(level: int, sb: int, bb: int)

var current_state: GameState = GameState.WAITING_FOR_PLAYERS
var players: Array = [] # Array of player objects (nodes)
var active_players: Array = [] # IDs of players still in the hand
var dealer_player_id: String = "" # Track dealer by ID to handle eliminations
var dealer_index: int = 0
var current_player_index: int = 0
var last_aggressor_index: int = 0

# Track memory for AI
var human_bluff_factor: float = 0.5 # Range 0.0 to 2.0. Base 0.5. Higher means Human bluffs more often.

var deck: Deck
var pot_manager: PotManager
var community_cards: Array[Card] = []

var small_blind: int = 10
var big_blind: int = 20
var current_bet: int = 0
var min_raise: int = 20

# Tính năng Blinds Progression (Giải đấu)
var hands_played: int = 0
var current_blind_level: int = 1

var multiplayer_mode: bool = false

func _ready():
	deck = Deck.new()
	pot_manager = PotManager.new()
	
	if multiplayer.has_multiplayer_peer():
		multiplayer_mode = true

func register_player(player_node):
	players.append(player_node)
	
func start_game():
	if multiplayer.has_multiplayer_peer():
		multiplayer_mode = true
		
	# Xoá các player rác từ lần chơi trước nếu chúng đã bị giải phóng (freed)
	for i in range(players.size() - 1, -1, -1):
		if not is_instance_valid(players[i]):
			players.remove_at(i)
			
	if multiplayer_mode and not multiplayer.is_server():
		return # Clients wait for sync
			
	if players.size() < 2:
		emit_signal("game_message", _tc("Need at least 2 players to start.", "Cần ít nhất 2 người chơi để bắt đầu."))
		return
		
	# Khởi tạo dealer ngẫu nhiên lần đầu tiên
	dealer_player_id = players[randi() % players.size()].id
	_start_new_round()

# --- MULTIPLAYER RPCs ---

@rpc("authority", "call_local", "reliable")
func sync_state(new_state_int: int):
	var new_state = new_state_int as GameState
	var old_state = current_state
	current_state = new_state
	emit_signal("state_changed", new_state, old_state)

@rpc("authority", "call_local", "reliable")
func sync_community_cards(card_data_array: Array):
	community_cards.clear()
	for data in card_data_array:
		community_cards.append(Card.new(data["suit"], data["rank"]))
	emit_signal("community_cards_changed", community_cards)

var client_pot: int = 0

@rpc("authority", "call_local", "reliable")
func sync_pot(total: int):
	client_pot = total

@rpc("authority", "call_local", "reliable")
func sync_turn(p_id: String):
	emit_signal("player_turn_started", p_id)

@rpc("authority", "call_local", "reliable")
func sync_action(p_id: String, action: int, amount: int):
	emit_signal("action_received", p_id, action, amount)

@rpc("authority", "call_local", "reliable")
func sync_chips(p_id: String, chips: int, current_bet: int):
	var p = _get_player_by_id(p_id)
	if p:
		p.chips = chips
		p.current_bet = current_bet
	emit_signal("action_received", p_id, -1, 0) # Trigger UI update

@rpc("any_peer", "call_local", "reliable")
func request_action_rpc(action: int, amount: int):
	var sender_id = multiplayer.get_remote_sender_id()
	# Validate turn
	if active_players.size() <= current_player_index: return
	
	var current_p_id = active_players[current_player_index]
	# Map sender_id to player ID
	if str(sender_id) == current_p_id:
		process_player_action(current_p_id, action, amount)

@rpc("authority", "call_local", "reliable")
func sync_game_over(winner_id: String):
	var my_id = str(multiplayer.get_unique_id())
	if winner_id == my_id:
		emit_signal("game_over", true)
	else:
		emit_signal("game_over", false)

# ------------------------

func _start_new_round():
	_change_state(GameState.WAITING_FOR_PLAYERS)
	
	deck.reset()
	deck.shuffle()
	pot_manager.reset()
	community_cards.clear()
	emit_signal("community_cards_changed", community_cards)
	
	# Tính năng Tournament Blinds: Cứ 5 ván thì tiền cược tự động nhân đôi
	hands_played += 1
	var new_level = 1 + int((hands_played - 1) / 5)
	if new_level > current_blind_level:
		current_blind_level = new_level
		small_blind = 10 * int(pow(2, current_blind_level - 1))
		big_blind = 20 * int(pow(2, current_blind_level - 1))
		var msg = _tc("[color=red][b]BLINDS LEVEL UP ", "[color=red][b]BLINDS LÊN CẤP ")
		emit_signal("game_message", msg + str(current_blind_level) + ": $" + str(small_blind) + "/$" + str(big_blind) + "[/b][/color]")
	emit_signal("blinds_level_changed", current_blind_level, small_blind, big_blind)
	
	# Phục hồi min_raise mặc định của level mới
	min_raise = big_blind
	
	# Tìm vị trí Dealer hiện tại trong danh sách vật lý
	var phys_dealer_idx = 0
	for i in range(players.size()):
		if players[i].id == dealer_player_id:
			phys_dealer_idx = i
			break
			
	# Di chuyển Dealer sang người ngồi cạnh còn tiền
	while true:
		phys_dealer_idx = (phys_dealer_idx + 1) % players.size()
		if players[phys_dealer_idx].chips > 0:
			break
	dealer_player_id = players[phys_dealer_idx].id
	
	active_players.clear()
	# Tạo danh sách active players bắt đầu từ Small Blind (người bên trái dealer) 
	# để index dễ tính toán (SB=0, BB=1, UTG=2)
	var start_idx = (phys_dealer_idx + 1) % players.size()
	for i in range(players.size()):
		var p_idx = (start_idx + i) % players.size()
		var p = players[p_idx]
		if p.chips > 0:
			p.reset_for_new_round()
			active_players.append(p.id)
		elif not p.is_eliminated:
			p.is_eliminated = true
			emit_signal("player_eliminated", p.id)
			
	# Kiểm tra Win / Loss Game Over
	var alive_count = 0
	var human_alive = false
	
	for p in players:
		if not p.is_eliminated:
			alive_count += 1
			if not p.is_ai: human_alive = true
	
	if multiplayer_mode:
		# Multiplayer Win Condition: Last Man Standing
		# Ensure we actually started with > 1 player
		if alive_count <= 1 and players.size() > 1:
			var winner_id = ""
			for p in players:
				if not p.is_eliminated:
					winner_id = p.id
					break
			if winner_id != "":
				sync_game_over.rpc(winner_id)
				return
	else:
		# Single Player Logic
		if not human_alive:
			emit_signal("game_over", false) # Busted
			return
		elif alive_count == 1 and human_alive:
			emit_signal("game_over", true) # Won
			return
			
	if active_players.size() < 2:
		emit_signal("game_message", _tc("Game Over - Not enough players with chips.", "Trò chơi kết thúc - Không đủ người chơi còn tiền."))
		return
		
	# Vì danh sách active_players đã xoay bắt đầu từ SB, dealer luôn là người cuối cùng trong active_players
	dealer_index = active_players.size() - 1
	
	_post_blinds()
	_change_state(GameState.DEALING_HOLE_CARDS)
	# Visual dealing will happen here; we will await an animation finish signal later.
	await _deal_hole_cards_async()
	
	_change_state(GameState.PREFLOP_BETTING)
	_start_betting_round()

func _post_blinds():
	# Vì list array active_players đã được căn chỉnh bắt đầu từ SB
	# (Index 0 = SB, Index 1 = BB). Ngoại trừ Heads-up (2 người).
	var sb_idx = 0
	var bb_idx = 1
	
	# In heads-up (2 players), dealer (index 1) is SB, player 0 is BB
	if active_players.size() == 2:
		sb_idx = 1 # Dealer
		bb_idx = 0
		
	var sb_player = _get_player_by_id(active_players[sb_idx])
	var bb_player = _get_player_by_id(active_players[bb_idx])
	
	_process_bet(sb_player, min(small_blind, sb_player.chips))
	_process_bet(bb_player, min(big_blind, bb_player.chips))
	
	current_bet = big_blind
	min_raise = big_blind
	
	# Action starts UTG (Under the Gun), which is after BB
	if active_players.size() == 2:
		current_player_index = sb_idx # Heads up: SB acts first pre-flop
	else:
		current_player_index = 2 % active_players.size() # Index sau BB
	
	# Action closes on BB if no raises
	last_aggressor_index = current_player_index

func _deal_hole_cards_async():
	for _i in range(2):
		for p_id in active_players:
			var p = _get_player_by_id(p_id)
			var card = deck.deal()
			p.draw_card(card)
			
			if multiplayer_mode and multiplayer.is_server():
				# Notify everyone (including self for consistency if needed, but self already drew)
				# Actually, self drew. Remote clients need to know.
				notify_card_dealt.rpc(p_id)
				
				# Send private data to the owner if it's a remote human
				# In multiplayer mode, player ID IS the peer ID (string)
				if not p.is_ai and p.id != "1":
					var peer_id = int(p.id)
					if peer_id > 0:
						sync_hole_card.rpc_id(peer_id, card.suit, card.rank)
			
			await get_tree().create_timer(0.08).timeout # Delay vật lý nhanh hơn
	await get_tree().create_timer(0.2).timeout # Đợi tất cả bài ổn định trên bàn

@rpc("authority", "call_remote", "reliable")
func notify_card_dealt(p_id: String):
	# Remote clients receive this to visualize dealing
	var p = _get_player_by_id(p_id)
	if p:
		# Draw a dummy card (Back facing)
		# We use a placeholder that won't reveal info
		var dummy = Card.new(Card.Suit.SPADES, Card.Rank.TWO)
		p.draw_card(dummy)

@rpc("authority", "call_local", "reliable")
func sync_hole_card(suit: int, rank: int):
	# Receive private hole card data
	var my_id = str(multiplayer.get_unique_id())
	# If this RPC is for me, update my last card
	# But wait, the RPC is targeted to peer_id.
	# So whoever receives this IS the owner.
	
	# Find my player object
	var p = _get_player_by_id(my_id)
	if p and p.hole_cards.size() > 0:
		var last_card = p.hole_cards.back()
		last_card.suit = suit
		last_card.rank = rank
		p.emit_signal("card_updated", last_card)

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
	
	var loop_safety = 0
	while current_p.is_all_in or current_p.is_folded or current_p.chips == 0:
		loop_safety += 1
		if loop_safety > active_players.size() + 2:
			print("Safety break triggered in turn loop")
			_end_betting_round()
			return

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
	
	if multiplayer_mode and multiplayer.is_server():
		sync_turn.rpc(current_p_id)
		
	# Tell the player to make a decision
	current_p.request_action(current_bet, min_raise)

func _end_betting_round():
	var unfolded_players = []
	var all_in_players = []
	
	for p_id in active_players:
		var p = _get_player_by_id(p_id)
		if not p.is_folded:
			unfolded_players.append(p_id)
		if p.is_all_in:
			all_in_players.append(p_id)
			
	pot_manager.gather_bets(unfolded_players, all_in_players)
	emit_signal("betting_round_ended")
	current_bet = 0
	min_raise = big_blind
	
	for p_id in active_players:
		_get_player_by_id(p_id).current_bet = 0
		
	if active_players.size() == 1:
		# Everyone else folded
		if active_players[0] == "You":
			# Human forced everyone else to fold. Might be a bluff.
			human_bluff_factor += 0.1
			human_bluff_factor = min(human_bluff_factor, 2.0)
		else:
			# Bot won by forcing Human to fold, slightly reduces bluff expectation
			human_bluff_factor -= 0.05
			human_bluff_factor = max(human_bluff_factor, 0.0)
			
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
	# Sau Flop, người đầu tiên bên trái Dealer (người đầu danh sách nếu chưa Fold)
	# Tuy nhiên do index đã thay đổi nếu có người Fold/All-in, cần reset đơn giản:
	# Bắt đầu vòng sau round là đi từ Index 0 (vì Index 0 luôn là SB hoặc người tiếp theo)
	current_player_index = 0
	last_aggressor_index = current_player_index # Nếu ai cũng Check thì end round khi tới người đóng

func _deal_community_cards_async(count: int):
	# Burn a card
	deck.deal() 
	for _i in range(count):
		community_cards.append(deck.deal())
		emit_signal("community_cards_changed", community_cards)
		
		if multiplayer_mode and multiplayer.is_server():
			var card_data = []
			for c in community_cards:
				card_data.append({"suit": c.suit, "rank": c.rank})
			sync_community_cards.rpc(card_data)
			
		await get_tree().create_timer(0.08).timeout # Faster dealing
	await get_tree().create_timer(0.15).timeout

func _handle_showdown():
	var player_results = {}
	
	if active_players.size() > 1:
		for p_id in active_players:
			var p = _get_player_by_id(p_id)
			if p.is_folded:
				continue
				
			var result = HandEvaluator.evaluate(p.hole_cards, community_cards)
			player_results[p_id] = result
			p.hand_result = result
			
		emit_signal("hand_evaluated", player_results)
		
		# Update Human bluff factor based on showdown
		if player_results.has("You"):
			var human_res = player_results["You"]
			# If human went to showdown with a weak hand (High Card or weak Pair), they are bluffing/loose
			if human_res.rank <= HandEvaluator.HandRank.PAIR:
				human_bluff_factor += 0.2
			# If human went to showdown with a strong hand (Three of a Kind+), they are playing solid
			elif human_res.rank >= HandEvaluator.HandRank.THREE_OF_A_KIND:
				human_bluff_factor -= 0.15
			human_bluff_factor = clamp(human_bluff_factor, 0.0, 2.0)
		
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
		var id_str = _tc("You", "Bạn") if p.id == "You" else p.id
		var won_str = _tc(" won $", " thắng $")
		emit_signal("game_message", id_str + won_str + str(payouts[p_id]) + "!")
		
	# Lưu tiến trình bankroll vào ổ cứng
	_save_human_progress()
		
	_change_state(GameState.ROUND_END)
	
	# Auto-start round mới sau 2.5 giây bằng Callable (tránh lỗi Lambda capture freed)
	get_tree().create_timer(2.5).timeout.connect(Callable(self, "_start_new_round"))

# Lưu dữ liệu người chơi thật vào cuối ván
func _save_human_progress() -> void:
	var human = _get_player_by_id("You")
	var sm = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
	if human and sm:
		sm.update_chips(human.chips)
		sm.add_game_played()

# --- Callbacks from player logic ---

func process_player_action(player_id: String, action: PlayerAction, amount: int = 0):
	var p = _get_player_by_id(player_id)
	var p_index = active_players.find(player_id)
	
	match action:
		PlayerAction.FOLD:
			p.is_folded = true
			# KHÔNG XÓA KHỎI active_players Ở ĐÂY để tránh lật index của người tiếp theo.
			# Thay vào đó chỉ đánh dấu is_folded = true.
			
			# Kiểm tra xem chỉ còn 1 người chưa fold không
			var active_unfolded = 0
			for pid in active_players:
				if not _get_player_by_id(pid).is_folded:
					active_unfolded += 1
			
			if active_unfolded == 1:
				_end_betting_round()
				return
				
		PlayerAction.CHECK:
			var amount_to_call = current_bet - p.current_bet
			if amount_to_call > 0:
				# Cannot check if there is a bet to call. Force Fold or handle as error.
				# For robustness, we'll treat it as a fold if logic fails, but UI should prevent this.
				p.is_folded = true
			else:
				_process_bet(p, 0)
			
		PlayerAction.CALL:
			var amount_to_call = current_bet - p.current_bet
			if amount_to_call >= p.chips:
				amount_to_call = p.chips
				p.is_all_in = true
			_process_bet(p, amount_to_call)
			amount = amount_to_call
			
		PlayerAction.RAISE:
			var added_amount = amount - p.current_bet
			if added_amount >= p.chips:
				added_amount = p.chips
				p.is_all_in = true
				
			_process_bet(p, added_amount)
			var raise_amount = p.current_bet - current_bet
			if raise_amount >= min_raise:
				min_raise = raise_amount
				last_aggressor_index = p_index # Cập nhật người đóng action
			current_bet = p.current_bet
			
		PlayerAction.ALL_IN:
			var all_in_amount = p.chips
			_process_bet(p, all_in_amount)
			p.is_all_in = true
			amount = all_in_amount 
			
			if p.current_bet > current_bet:
				var raise_amount = p.current_bet - current_bet
				# Luật Hold'em: All-in phải lớn hơn hoặc bằng min_raise mới được tính là "full raise" 
				# để mở lại vòng cược (reopen betting) cho những người đã hành động.
				if raise_amount >= min_raise:
					min_raise = raise_amount
					last_aggressor_index = p_index # Cập nhật người đóng vì đây là full raise
				current_bet = p.current_bet
				
	emit_signal("action_received", player_id, action, amount)
	
	if multiplayer_mode and multiplayer.is_server():
		sync_action.rpc(player_id, action, amount)
		# Sync chips
		var p_obj = _get_player_by_id(player_id)
		if p_obj:
			sync_chips.rpc(player_id, p_obj.chips, p_obj.current_bet)
		# Sync pot
		sync_pot.rpc(pot_manager.get_total_pot())
	
	# Xử lý lưu ngay lập tức ngay thời điểm Human ra quyết định (chống thoát game)
	var sm = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
	if player_id == "You" and sm:
		var p_human = _get_player_by_id("You")
		sm.update_chips(p_human.chips)
	
	if active_players.is_empty():
		return

	current_player_index = (p_index + 1) % active_players.size()
	
	if current_player_index == last_aggressor_index:
		# Kiểm tra xe còn ai chưa call đủ tiền không (vì all-in short stack không đổi last_aggressor_index nhưng vẫn thay đổi current_bet)
		var all_matched = true
		for pid in active_players:
			var px = _get_player_by_id(pid)
			if not px.is_folded and not px.is_all_in and px.current_bet < current_bet:
				all_matched = false
				break
		
		if all_matched:
			_end_betting_round()
		else:
			_next_player_turn()
	else:
		_next_player_turn()

func _process_bet(player, amount: int):
	if amount <= 0: return
	player.chips -= amount
	player.current_bet += amount
	pot_manager.add_bet(player.id, amount)
	if player.chips == 0:
		player.is_all_in = true
	
	# Xử lý lưu ngay lập tức nếu là rớt tiền để chống người chơi thoát ra (cheat)
	var sm = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
	if player.id == "You" and sm:
		sm.update_chips(player.chips)

# --- Helpers ---

func _change_state(new_state: GameState):
	var old_state = current_state
	current_state = new_state
	emit_signal("state_changed", new_state, old_state)
	
	if multiplayer_mode and multiplayer.is_server():
		sync_state.rpc(new_state)

func _get_player_by_id(id: String):
	for p in players:
		if p.id == id:
			return p
	return null

func _tc(en: String, vi: String) -> String:
	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	if sm and sm.has_method("tc"):
		return sm.tc(en, vi)
	return en
