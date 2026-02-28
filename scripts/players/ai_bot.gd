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
	var base_think_time = randf_range(1.5, 3.5)
	
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
			chosen_amount = current_table_bet + min_raise * (randi() % 3 + 1)
		else:
			chosen_action = GameManager.PlayerAction.CHECK
	else:
		# Phải bỏ thêm tiền
		if willingness > 0.85 and chips > amount_to_call + min_raise:
			# Bài cực mạnh, RAISE
			chosen_action = GameManager.PlayerAction.RAISE
			chosen_amount = current_table_bet + min_raise * (randi() % 4 + 1)
		elif willingness > (pot_odds + 0.1): 
			# Đủ mạnh để theo cược (so với rủi ro)
			chosen_action = GameManager.PlayerAction.CALL
		elif is_bluffing and chips > amount_to_call + min_raise:
			# Lá gan lớn, tung Bluff
			chosen_action = GameManager.PlayerAction.RAISE
			chosen_amount = current_table_bet + min_raise * (randi() % 5 + 2)
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

func _emit_chatter(game_manager: Node, action: int, amount_to_call: int, raise_amount: int) -> void:
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
				# Nút Top Pair mạnh hơn Bottom Pair
				var top_table = 0
				for c in community_cards:
					if c.get_value() > top_table: top_table = c.get_value()
				if c1 == top_table or c2 == top_table:
					return 0.45 # Top Pair
				return 0.30 # Bottom/Middle pair
			HandEvaluator.HandRank.HIGH_CARD: 
				# Draw potential (Sảnh chờ / Thùng chờ) cho Flop/Turn
				if community_cards.size() < 5:
					# Tăng winrate ảo lên 35% để Bot chịu Call các bet nhỏ đuổi sảnh/thùng thay vì luôn Fold
					return 0.35 
				return 0.0
				
	return 0.0
