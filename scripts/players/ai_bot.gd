class_name AIPlayer
extends Player

enum Personality { TIGHT_AGGRESSIVE, LOOSE_AGGRESSIVE, TIGHT_PASSIVE, LOOSE_PASSIVE, MANIAC }

var personality: Personality
var is_thinking: bool = false

signal physical_action_performed(action: int, amount: int, force: float)

func _init(p_id: String, initial_chips: int = 1000):
	super(p_id, initial_chips)
	is_ai = true
	# Random tính cách cho bot khi khởi tạo
	personality = randi() % Personality.size() as Personality

# AI nhận tín hiệu tới lượt hành động từ GameManager
func request_action(current_table_bet: int, min_raise: int) -> void:
	is_thinking = true
	
	# 1. "Có hồn" - Delay suy nghĩ: 
	# AI sẽ vờ như đang suy nghĩ. Thời gian nghĩ phụ thuộc vào độ khó của quyết định.
	var base_think_time = randf_range(0.8, 1.5) # Reduced default time for better pacing
	
	# VD: Nếu số tiền cược bàn rất lớn so với tiền mình đang có, thời gian suy nghĩ lâu hơn
	var bet_ratio = float(current_table_bet) / max(1.0, float(chips + current_bet))
	if bet_ratio > 0.3:
		base_think_time += randf_range(2.0, 4.0) # Vẻ mặt căng thẳng
		
	if has_node("/root/SettingsManager"):
		if get_node("/root/SettingsManager").fast_bot_mode:
			base_think_time = 0.1
			
	# Dùng Callable có bind param để Godot quản lý rác giúp tránh lỗi capture
	get_tree().create_timer(base_think_time).timeout.connect(
		Callable(self, "_decide_action").bind(current_table_bet, min_raise)
	)

# Hàm logic quyết định chính
func _decide_action(current_table_bet: int, min_raise: int) -> void:
	is_thinking = false
	var game_manager = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if not game_manager: return
	
	# Đánh giá sức mạnh bài theo tình huống (Pre-flop hay Post-flop)
	var base_strength = _evaluate_hand_strength(game_manager.community_cards)
	var amount_to_call = current_table_bet - current_bet
	# Xác định chỉ số sẵn sàng tùy chỉnh theo Personality
	var willingness = base_strength
	var is_bluffing = false
	
	# --- DRAW AWARENESS (Task 9) ---
	if game_manager.community_cards.size() >= 3 and game_manager.community_cards.size() < 5:
		var draw_bonus = _evaluate_draw_potential(game_manager.community_cards)
		willingness += draw_bonus
	
	# --- POSITION AWARENESS (Task 10) ---
	var position_bonus = _evaluate_position(game_manager)
	willingness += position_bonus
	
	match personality:
		Personality.MANIAC:
			willingness += 0.3 # Luôn đánh lố
			is_bluffing = (randf() < 0.25)
		Personality.LOOSE_AGGRESSIVE:
			willingness += 0.15 # Dễ dãi hơn
			is_bluffing = (randf() < 0.15)
		Personality.LOOSE_PASSIVE:
			willingness += 0.1 # Dễ call nhưng ít raise
		Personality.TIGHT_PASSIVE:
			willingness -= 0.1 # Kén chọn bài
			
	willingness = clamp(willingness, 0.0, 1.0)
	
	# Tính tỷ lệ rủi ro (Pot Odds / Bet Ratio)
	var total_pot = game_manager.pot_manager.get_total_pot()
	# pot_odds là "Tỷ lệ tiền phải bỏ ra so với tổng tiền sẽ lấy được nếu thắng"
	var pot_odds = float(amount_to_call) / max(1.0, float(total_pot + amount_to_call))
	
	# ----- AI MEMORY MODULE -----
	# Nếu người đang Raise/Bet tạo ra áp lực (last_aggressor) là Human,
	# Bot sẽ dùng trí nhớ của mình để đánh giá thái độ.
	if amount_to_call > 0 and game_manager.active_players.size() > game_manager.last_aggressor_index:
		var aggressor_id = game_manager.active_players[game_manager.last_aggressor_index]
		if aggressor_id == "You":
			# Nếu đối phương là Human, check bluff factor (0.5 là trung bình)
			# Factor càng cao (tức người chơi hay Tố láo), Bot càng dễ chịu Call
			var bluff_factor = game_manager.human_bluff_factor
			
			if bluff_factor > 0.8:
				# Biết người chơi hay Bluff -> tăng phần trăm chấp nhận call/raise
				willingness += (bluff_factor - 0.5) * 0.2
			elif bluff_factor < 0.3:
				# Người chơi đánh quá cẩn thận (chỉ show hand bài khủng)
				# Bot sẽ phải nể sợ và giảm willingness
				willingness -= 0.15
				
	willingness = clamp(willingness, 0.0, 1.0)
	
	var chosen_action = GameManager.PlayerAction.FOLD
	var chosen_amount = 0
	
	if amount_to_call == 0:
		# Miễn phí để xem bài tiếp (Check)
		# Nếu bài ngon, và không phải thể loại thụ động quá, đâm thêm tiền
		if (willingness > 0.7 or is_bluffing) and chips > min_raise and personality != Personality.LOOSE_PASSIVE and personality != Personality.TIGHT_PASSIVE:
			chosen_action = GameManager.PlayerAction.RAISE
			chosen_amount = _calculate_raise_amount(game_manager, current_table_bet, min_raise, willingness)
		else:
			chosen_action = GameManager.PlayerAction.CHECK
	else:
		# Phải bỏ thêm tiền
		if willingness > 0.85 and chips > amount_to_call + min_raise:
			# Bài cực mạnh, RAISE
			chosen_action = GameManager.PlayerAction.RAISE
			chosen_amount = _calculate_raise_amount(game_manager, current_table_bet, min_raise, willingness)
		elif willingness > (pot_odds + 0.1): 
			# Đủ mạnh để theo cược (so với rủi ro)
			chosen_action = GameManager.PlayerAction.CALL
		elif is_bluffing and chips > amount_to_call + min_raise:
			# Lá gan lớn, tung Bluff
			chosen_action = GameManager.PlayerAction.RAISE
			chosen_amount = _calculate_raise_amount(game_manager, current_table_bet, min_raise, willingness + 0.3)
		else:
			# Bài yếu hoặc pot quá đắt -> FOLD
			if amount_to_call < chips * 0.05 and willingness > 0.15: # Mồi cỏ con con thì Cứ Call xem lật
				chosen_action = GameManager.PlayerAction.CALL
			else:
				chosen_action = GameManager.PlayerAction.FOLD
	
	# Quyết định lực ném vật lý (ném mạnh nếu Aggressive/bực tức, ném nhẹ nếu chần chừ)
	var throw_force = randf_range(0.8, 1.2)
	match personality:
		Personality.MANIAC, Personality.TIGHT_AGGRESSIVE, Personality.LOOSE_AGGRESSIVE:
			throw_force = randf_range(1.2, 1.8) # Ném mạnh hơn một chút
		Personality.TIGHT_PASSIVE, Personality.LOOSE_PASSIVE:
			throw_force = randf_range(0.4, 0.8) # Đặt nhẹ
			
	# Gửi tín hiệu hành động vật lý (Ném chip, vất bài) => Tích hợp animation
	physical_action_performed.emit(chosen_action, chosen_amount, throw_force)
	
	# --- BANTER CHATTER LOGIC ---
	_emit_chatter(game_manager, chosen_action, amount_to_call, chosen_amount)
	
	# Trả về kết quả cho Logic Core
	if game_manager:
		game_manager.process_player_action(id, chosen_action, chosen_amount)

func _emit_chatter(game_manager: Node, action: int, amount_to_call: int, _raise_amount: int) -> void:
	# Only chat 15% of the time to avoid spam
	if randf() > 0.15: return
	
	var msg = ""
	match action:
		GameManager.PlayerAction.FOLD:
			if amount_to_call > game_manager.big_blind * 3:
				var lines = ["Too rich for my blood...", "You got lucky this time.", "I fold. Show me your bluff!", "I'm out.", "Folding..."]
				msg = lines[randi() % lines.size()]
		GameManager.PlayerAction.RAISE:
			var lines = ["Read 'em and weep!", "Let's make this interesting.", "Raise! Can you handle it?", "I've got a monster."]
			msg = lines[randi() % lines.size()]
		GameManager.PlayerAction.ALL_IN:
			var lines = ["ALL-IN BABY!", "Time to go home, folks.", "Pushing all my chips in!", "Go big or go home!"]
			msg = lines[randi() % lines.size()]
			
	if msg != "":
		game_manager.emit_signal("game_message", "[color=yellow][b]" + self.id + ":[/b][/color] " + msg)

# Thuật toán đánh giá Hand cho Bot dựa trên luật Texas Hold'em cơ bản
func _evaluate_hand_strength(community_cards: Array[Card]) -> float:
	if hole_cards.size() < 2: return 0.0
	
	var c1 = hole_cards[0].get_value()
	var c2 = hole_cards[1].get_value()
	
	if community_cards.size() == 0:
		# PRE-FLOP LOGIC (Chưa lật bài chung)
		var is_pair = (c1 == c2)
		var is_suited = (hole_cards[0].suit == hole_cards[1].suit)
		var high_card = max(c1, c2)
		var low_card = min(c1, c2)
		
		var strength = 0.0
		
		# Tính điểm gốc
		if is_pair:
			strength = 0.5 + float(c1) / 30.0 # Đôi 2: 0.56, Đôi A: 0.96
		else:
			# Hai lá to
			strength = (float(high_card) + float(low_card) / 2.0) / 25.0 
			
		# Suited adds value (Đồng chất dễ ra flush)
		if is_suited: strength += 0.05
		# Connectors add value (Liền nhau dễ ra sảnh, ví dụ: 8,9 hoặc 10,J)
		if (high_card - low_card) == 1 or (high_card == Card.Rank.ACE and low_card == 2):
			strength += 0.05
		elif (high_card - low_card) == 2:
			strength += 0.02
				
		return clamp(strength, 0.0, 1.0)
		
	else:
		# POST-FLOP LOGIC (Đã lật 3-5 bài chung)
		# Tích hợp HandEvaluator xịn từ core
		var result = HandEvaluator.evaluate(hole_cards, community_cards)
		
		match result.rank:
			HandEvaluator.HandRank.ROYAL_FLUSH: return 1.0
			HandEvaluator.HandRank.STRAIGHT_FLUSH: return 1.0
			HandEvaluator.HandRank.FOUR_OF_A_KIND: return 0.98
			HandEvaluator.HandRank.FULL_HOUSE: return 0.95
			HandEvaluator.HandRank.FLUSH: return 0.88
			HandEvaluator.HandRank.STRAIGHT: return 0.82
			HandEvaluator.HandRank.THREE_OF_A_KIND: return 0.70
			HandEvaluator.HandRank.TWO_PAIR: return 0.55
			HandEvaluator.HandRank.PAIR: 
				# Phân loại Pair: Overpair > Top Pair > Middle/Bottom Pair
				var pair_rank = result.kickers[0] # Trong HandEvaluator, kickers[0] của PAIR là giá trị đôi
				
				# Tìm lá lớn nhất trên bàn
				var max_board_rank = 0
				for c in community_cards:
					if c.get_value() > max_board_rank:
						max_board_rank = c.get_value()
				
				if pair_rank > max_board_rank:
					return 0.65 # Overpair (VD: Cầm KK trên bàn 2-5-9) -> Rất mạnh
				elif pair_rank == max_board_rank:
					return 0.50 # Top Pair -> Khá
				else:
					return 0.30 # Middle/Bottom pair -> Yếu
					
			HandEvaluator.HandRank.HIGH_CARD: 
				# Nếu chưa ra hết bài (Flop/Turn), cân nhắc Draw (mua bán)
				if community_cards.size() < 5:
					# Đơn giản hóa: Có 2 lá to (J+) thì vẫn nuôi hy vọng
					if c1 >= 11 and c2 >= 11:
						return 0.35
					return 0.20 
				else:
					# River: High Card thường là thua, trừ khi Ace High heads-up
					if max(c1, c2) == 14: # Ace High
						return 0.15
					return 0.05
				
	return 0.0

# --- DRAW AWARENESS (Task 9) ---
func _evaluate_draw_potential(community_cards: Array[Card]) -> float:
	if hole_cards.size() < 2: return 0.0
	
	var all_cards: Array[Card] = []
	all_cards.append_array(hole_cards)
	all_cards.append_array(community_cards)
	
	var draw_bonus = 0.0
	
	# Flush draw: 4 of the same suit
	var suit_counts = {}
	for card in all_cards:
		if not suit_counts.has(card.suit):
			suit_counts[card.suit] = 0
		suit_counts[card.suit] += 1
	
	for suit in suit_counts:
		if suit_counts[suit] == 4:
			# Check if at least one hole card is in this suit
			var has_hole_suit = false
			for hc in hole_cards:
				if hc.suit == suit: has_hole_suit = true
			if has_hole_suit:
				draw_bonus += 0.15  # Flush draw (~35% to hit)
	
	# Open-ended straight draw (OESD): check for 4 consecutive values
	var values = []
	for card in all_cards:
		var v = card.get_value()
		if not values.has(v):
			values.append(v)
	values.sort()
	
	# Check for 4-card sequences
	for i in range(values.size() - 3):
		if values[i+3] - values[i] == 3:
			# 4 consecutive — check if hole cards contribute
			var seq = [values[i], values[i+1], values[i+2], values[i+3]]
			var hole_in_seq = false
			for hc in hole_cards:
				if seq.has(hc.get_value()): hole_in_seq = true
			if hole_in_seq:
				# Check if open-ended (not gutshot)
				if values[i] > 2 and values[i+3] < 14:  # Not bottom or top blocked
					draw_bonus += 0.12  # OESD (~31% to hit)
				else:
					draw_bonus += 0.06  # Gutshot-ish (~17%)
	
	# Reduce bonus on turn (fewer outs)
	if community_cards.size() == 4:
		draw_bonus *= 0.55
	
	return draw_bonus

# --- POSITION AWARENESS (Task 10) ---
func _evaluate_position(game_manager: Node) -> float:
	var my_index = game_manager.active_players.find(id)
	if my_index < 0: return 0.0
	
	var total = game_manager.active_players.size()
	if total <= 2: return 0.0  # Heads-up, position less relevant
	
	# Position relative to dealer (last is best)
	var relative_pos = float(my_index) / float(total - 1)  # 0.0 = earliest, 1.0 = latest
	
	# Late position bonus, early position penalty
	if relative_pos >= 0.7:
		return 0.08  # Late position advantage
	elif relative_pos <= 0.3:
		return -0.06  # Early position — tighter play
	return 0.0

# --- IMPROVED RAISE SIZING (Task 11) ---
func _calculate_raise_amount(game_manager: Node, current_table_bet: int, min_raise: int, strength: float) -> int:
	var total_pot = game_manager.pot_manager.get_total_pot()
	var bb = game_manager.big_blind
	var is_preflop = (game_manager.community_cards.size() == 0)
	
	var raise_amount: int
	
	if is_preflop:
		# Pre-flop: 2.5x-3.5x BB base, personality affects multiplier
		var mult = randf_range(2.5, 3.5)
		match personality:
			Personality.MANIAC: mult = randf_range(3.5, 6.0)
			Personality.LOOSE_AGGRESSIVE: mult = randf_range(3.0, 4.5)
			Personality.TIGHT_AGGRESSIVE: mult = randf_range(2.5, 3.5)
		raise_amount = int(bb * mult)
	else:
		# Post-flop: percentage of pot, scaled by strength
		var pot_pct = 0.0
		if strength > 0.9:
			pot_pct = randf_range(0.75, 1.0)  # Strong hand: 75-100% pot
		elif strength > 0.7:
			pot_pct = randf_range(0.5, 0.75)  # Medium-strong: 50-75% pot
		else:
			pot_pct = randf_range(0.33, 0.5)  # Value/bluff: 33-50% pot
		
		match personality:
			Personality.MANIAC: pot_pct += randf_range(0.2, 0.5)
			Personality.LOOSE_AGGRESSIVE: pot_pct += randf_range(0.1, 0.2)
			Personality.TIGHT_PASSIVE: pot_pct *= 0.7
		
		raise_amount = max(int(total_pot * pot_pct), min_raise)
	
	# Ensure raise is at least min_raise above current bet
	raise_amount = max(raise_amount, current_table_bet + min_raise)
	
	# Round to BB for cleaner numbers
	if bb > 0:
		raise_amount = int(round(float(raise_amount) / float(bb)) * bb)
	
	# Cap at our chip stack
	raise_amount = min(raise_amount, chips + current_bet)
	
	return raise_amount
