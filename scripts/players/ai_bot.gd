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
		
	# Dùng Callable có bind param để Godot quản lý rác giúp tránh lỗi capture
	get_tree().create_timer(base_think_time).timeout.connect(
		Callable(self, "_decide_action").bind(current_table_bet, min_raise)
	)

# Hàm logic quyết định chính
func _decide_action(current_table_bet: int, min_raise: int) -> void:
	is_thinking = false
	
	# Xác định mức độ sẵn sàng cược (0.0 đến 1.0) dựa trên tính cách & sức mạnh bài 
	# (Tạm thời là Random cho nhanh ở bản Demo, sẽ nối HandEvaluator sau)
	var willingness = randf()
	var amount_to_call = current_table_bet - current_bet
	
	var chosen_action = GameManager.PlayerAction.FOLD
	var chosen_amount = 0
	
	if amount_to_call == 0:
		# Miễn phí để xem bài tiếp (Check)
		if willingness > 0.8 and chips > min_raise:
			chosen_action = GameManager.PlayerAction.RAISE
			chosen_amount = current_table_bet + min_raise
		else:
			chosen_action = GameManager.PlayerAction.CHECK
	else:
		# Phải trả tiền để xem bài
		if willingness > 0.85 and chips > amount_to_call + min_raise:
			# RAISE
			chosen_action = GameManager.PlayerAction.RAISE
			chosen_amount = current_table_bet + min_raise * (randi() % 3 + 1)
		elif willingness > 0.4:
			# CALL
			chosen_action = GameManager.PlayerAction.CALL
		else:
			if amount_to_call > chips * 0.1:
				# FOLD nếu phải trả quá nhiều cho bài yếu
				chosen_action = GameManager.PlayerAction.FOLD
			else:
				chosen_action = GameManager.PlayerAction.CALL
	
	# Quyết định lực ném vật lý (ném mạnh nếu Aggressive/bực tức, ném nhẹ nếu chần chừ)
	var throw_force = randf_range(0.8, 1.2)
	match personality:
		Personality.MANIAC, Personality.TIGHT_AGGRESSIVE, Personality.LOOSE_AGGRESSIVE:
			throw_force = randf_range(1.2, 1.8) # Ném mạnh hơn một chút
		Personality.TIGHT_PASSIVE, Personality.LOOSE_PASSIVE:
			throw_force = randf_range(0.4, 0.8) # Đặt nhẹ
			
	# Gửi tín hiệu hành động vật lý (Ném chip, vất bài) => Tích hợp animation
	physical_action_performed.emit(chosen_action, chosen_amount, throw_force)
	
	# Trả về kết quả cho Logic Core
	var game_manager = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if game_manager:
		game_manager.process_player_action(id, chosen_action, chosen_amount)
