class_name HumanPlayer
extends Player

signal human_turn_started(current_bet: int, min_raise: int)
signal physical_action_performed(action: int, amount: int, force: float)

# Human Player sẽ chờ input từ UI để đưa ra quyết định
func _init(p_id: String, initial_chips: int = 1000):
	super(p_id, initial_chips)
	is_ai = false

# Khi tới lượt, báo cho UI hiển thị các nút bấm (Fold, Call, Raise)
func request_action(current_table_bet: int, min_raise: int) -> void:
	# Gửi tín hiệu để UI CanvasLayer bắt được và hiện Nút tương tác
	human_turn_started.emit(current_table_bet, min_raise)

# Hàm này sẽ được gọị bởi các Nút bấm UI sau khi người chơi thao tác
func receive_ui_input(action: int, amount: int = 0) -> void:
	var throw_force = 1.0 # Lực ném chip cơ bản cho người, nhẹ để không văng khỏi bàn
	physical_action_performed.emit(action, amount, throw_force)
	
	# Gửi vào game loop
	var game_manager = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if game_manager:
		if game_manager.multiplayer_mode:
			game_manager.request_action_rpc.rpc_id(1, action, amount)
		else:
			game_manager.process_player_action(id, action, amount)
