extends Node3D

class_name PhysicalManager
# Singleton hoặc Node chính để spawn chip và bài (Vật lý) vào môi trường 3D

@onready var game_manager = get_node("/root/GameManager") if has_node("/root/GameManager") else null

var card_scene: PackedScene
var chip_scene: PackedScene

# Vị trí spawn bài (Dealer đứng giữa bàn)
var dealer_pos: Vector3 = Vector3(0, 0.5, 0)

# Track community cards đã spawn
var _spawned_community_cards: Array = []
# Track action labels
var _action_labels: Dictionary = {} # player_id -> Label3D
# Track player physical cards
var _player_cards: Dictionary = {} # player_id -> Array[PhysicalCard]
# Track physical chips currently on table
var _spawned_chips: Array[PhysicalChip] = []

func _ready() -> void:
	# Tự động tạo PackedScene cho Card và Chip bằng code thay vì tạo file .tscn trong Editor
	card_scene = _build_card_prefab()
	chip_scene = _build_chip_prefab()

	# Thêm sàn để bài/chip không rơi vô tận
	_setup_floor()

	if game_manager:
		game_manager.state_changed.connect(_on_game_state_changed)
		game_manager.community_cards_changed.connect(_on_community_cards_dealt)
		game_manager.action_received.connect(_on_player_action)
		game_manager.winners_declared.connect(_on_winners_declared)

	# Chờ 1 frame để TableBuilder kịp register players
	await get_tree().process_frame

	if game_manager:
		# Lắng nghe sự kiện Player bốc bài
		for p in game_manager.players:
			p.card_drawn.connect(_on_player_drew_card.bind(p))
			
			# Nếu là AI hoặc Human, lắng nghe hành động quăng chip vật lý
			if p.has_signal("physical_action_performed"):
				p.physical_action_performed.connect(_on_physical_action.bind(p))

func _setup_floor() -> void:
	var floor_body = StaticBody3D.new()
	floor_body.name = "Floor"
	
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(20, 0.1, 20)
	col.shape = shape
	floor_body.add_child(col)
	
	# Mặt phẳng sàn nằm dưới bàn để bắt bài/chip rơi
	floor_body.position = Vector3(0, -2.0, 0)
	add_child(floor_body)

# ---- TẠO PREFAB BẰNG CODE ----
func _build_card_prefab() -> PackedScene:
	var root = RigidBody3D.new()
	root.name = "PhysicalCard"
	root.set_script(load("res://scripts/physical/physical_card.gd"))
	
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	
	# Tính theo đúng tỷ lệ 226x314 của asset PNG thật
	var card_w = 226.0
	var card_h = 314.0
	var h = 0.95
	var w = h * (card_w / card_h)
	box.size = Vector3(w, h, 0.01) 
	col.shape = box
	root.add_child(col)
	col.owner = root # Quan trọng: để pack() lưu node này
	
	var mesh_inst = MeshInstance3D.new()
	# Dùng QuadMesh thay vì BoxMesh — hiển thị đúng toàn bộ texture lên mặt phẳng
	var mesh = QuadMesh.new()
	mesh.size = Vector2(w, h)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # Đảm bảo bài luôn sáng rực
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED # Hiện cả 2 mặt (trước/sau)
	mesh.material = mat
	
	mesh_inst.mesh = mesh
	mesh_inst.name = "MeshInstance3D"
	root.add_child(mesh_inst)
	mesh_inst.owner = root # Quan trọng
	
	var ds = PackedScene.new()
	ds.pack(root)
	return ds

func _build_chip_prefab() -> PackedScene:
	var root = RigidBody3D.new()
	root.name = "PhysicalChip"
	root.set_script(load("res://scripts/physical/physical_chip.gd"))
	
	# Collision — chip lớn hơn, dày hơn
	var col = CollisionShape3D.new()
	var cyl = CylinderShape3D.new()
	cyl.radius = 0.12
	cyl.height = 0.025
	col.shape = cyl
	root.add_child(col)
	col.owner = root
	
	# Mesh chính — chip poker tròn, mịn
	var mesh_inst = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = cyl.radius
	mesh.bottom_radius = cyl.radius
	mesh.height = cyl.height
	mesh.radial_segments = 32  # Mịn tròn, không răng cưa
	mesh.rings = 1
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.15, 0.15) # Chip đỏ mặc định
	mat.metallic = 0.3
	mat.metallic_specular = 0.6
	mat.roughness = 0.35
	mesh.material = mat
	mesh_inst.mesh = mesh
	mesh_inst.name = "MeshInstance3D"
	root.add_child(mesh_inst)
	mesh_inst.owner = root
	
	# Viền trắng (edge stripe) — vành mỏng quanh chip
	var edge_mesh_inst = MeshInstance3D.new()
	var edge_mesh = TorusMesh.new()
	edge_mesh.inner_radius = cyl.radius - 0.008
	edge_mesh.outer_radius = cyl.radius + 0.002
	edge_mesh.rings = 24
	edge_mesh.ring_segments = 12
	
	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.9, 0.9, 0.85)
	edge_mat.metallic = 0.2
	edge_mat.roughness = 0.4
	edge_mesh.material = edge_mat
	edge_mesh_inst.mesh = edge_mesh
	edge_mesh_inst.name = "EdgeStripe"
	root.add_child(edge_mesh_inst)
	edge_mesh_inst.owner = root
	
	var ap = AudioStreamPlayer3D.new()
	ap.name = "AudioStreamPlayer3D"
	root.add_child(ap)
	ap.owner = root
	
	var ds = PackedScene.new()
	ds.pack(root)
	return ds

# ---- EVENT HANDLERS ----

func _on_player_drew_card(card: Card, player: Player) -> void:
	var p_card = card_scene.instantiate() as PhysicalCard
	add_child(p_card)
	p_card.set_card_data(card)
	
	if not _player_cards.has(player.id):
		_player_cards[player.id] = []
	_player_cards[player.id].append(p_card)
	
	var card_index = player.hole_cards.size() - 1
	var offset_x = (card_index - 0.5) * 0.7 # Khoảng cách rộng hơn cho bài to
	var offset_y = 0.02 + card_index * 0.003 # Sát mặt bàn
	
	if !player.is_ai:
		# HUMAN: Đặt bài tĩnh, ngửa, trước mặt (BoxMesh đã nằm ngang sẵn)
		p_card.is_face_up = true
		p_card._update_visuals()
		
		# Human cards nằm sát mép bàn
		var card_pos = player.seat_position + Vector3(offset_x, offset_y, -0.3)
		p_card.global_position = card_pos
		p_card.rotation_degrees = Vector3(-90, 0, 0) # Nằm ngang phẳng xuống bàn
		p_card.freeze = true
	else:
		# AI: Xếp bài ngay ngắn thay vì vứt lung tung
		p_card.global_position = dealer_pos
		
		# Tính hướng từ tâm bàn đến người chơi
		var dir_to_center = (Vector3.ZERO - player.seat_position).normalized()
		if dir_to_center.length_squared() < 0.01:
			dir_to_center = Vector3.FORWARD
			
		var angle_y = atan2(dir_to_center.x, dir_to_center.z)
		p_card.rotation = Vector3(deg_to_rad(-90), angle_y, 0)
		
		# Vị trí đích ngay ngắn trước mặt bot
		var right_dir = Vector3(dir_to_center.z, 0, -dir_to_center.x)
		var target_pos = player.seat_position + dir_to_center * 0.2 + right_dir * offset_x
		target_pos.y = offset_y
		
		p_card.throw_to(target_pos, randf_range(0.3, 0.45), randf_range(1.0, 3.0))

func _on_community_cards_dealt(cards: Array) -> void:
	# Chỉ spawn các lá bài mới (không spawn lại cái đã có)
	var new_start = _spawned_community_cards.size()
	if new_start >= cards.size():
		return
	
	for i in range(new_start, cards.size()):
		var card = cards[i]
		var p_card = card_scene.instantiate() as PhysicalCard
		add_child(p_card)
		
		# Vị trí giữa bàn, xếp hàng ngang cách nhau vừa vặn (bàn lớn hơn)
		var total_width = 0.85 * 4  # 5 cards max
		var start_x = -total_width / 2.0
		var card_x = start_x + i * 0.85
		
		# Đặt sát mặt bàn (y = 0.02 để vừa chìm vào nỉ)
		p_card.global_position = Vector3(card_x, 0.02 + i * 0.002, 0)
		p_card.rotation_degrees = Vector3(-90, 0, 0) # Xoay nằm phẳng xuống bàn
		p_card.set_card_data(card)
		p_card.is_face_up = true
		p_card._update_visuals()
		p_card.freeze = true
		
		_spawned_community_cards.append(p_card)

func _on_physical_action(action: int, amount: int, force: float, player: Player) -> void:
	# Ném chip theo số lượng amount
	if action == GameManager.PlayerAction.CALL or action == GameManager.PlayerAction.RAISE or action == GameManager.PlayerAction.ALL_IN:
		if amount <= 0: return
		
		# Chia amount thành các chip mệnh giá khác nhau
		var remaining = amount
		var chip_values = []
		var denoms = [500, 100, 50, 25, 10]
		
		for denom in denoms:
			while remaining >= denom and chip_values.size() < 25: # Max 25 chips để khỏi lag
				chip_values.append(denom)
				remaining -= denom
				
		# Thuộc phần dư nếu có (nếu quá giới hạn 25 chip) thành 1 chip to
		if remaining > 0:
			chip_values.append(remaining)
		
		for val in chip_values:
			var chip = chip_scene.instantiate() as PhysicalChip
			add_child(chip)
			chip.set_value(val)
			
			var spawn_pos = player.seat_position + Vector3(0, 0.2, 0)
			# Thêm chút sai số vị trí để các chip rơi không đè trùng 1 điểm
			spawn_pos.x += randf_range(-0.1, 0.1)
			spawn_pos.z += randf_range(-0.1, 0.1)
			
			spawn_pos = spawn_pos.move_toward(Vector3.ZERO, 0.3) 
			chip.global_position = spawn_pos
			
			var pot_target = spawn_pos.move_toward(Vector3.ZERO, randf_range(1.0, 1.4))
			chip.throw_towards(pot_target, force)
			
			_spawned_chips.append(chip)

func _on_game_state_changed(new_state: int, _old_state: int) -> void:
	# Cleanup khi bắt đầu round mới
	if new_state == GameManager.GameState.WAITING_FOR_PLAYERS:
		_cleanup_round()
	elif new_state == GameManager.GameState.SHOWDOWN:
		# Ẩn các label action (CALL/RAISE) cũ để lấy chỗ hiện thông báo người thắng
		for pid in _action_labels:
			var lbl = _action_labels[pid]
			if is_instance_valid(lbl):
				lbl.queue_free()
		_action_labels.clear()

func _on_player_action(player_id: String, action: int, amount: int) -> void:
	# Hiển thị action label nổi trên đầu player
	if not game_manager:
		return
	
	var player = game_manager._get_player_by_id(player_id)
	if not player:
		return
	
	# Xóa label cũ nếu có
	if _action_labels.has(player_id):
		var old_label = _action_labels[player_id]
		if is_instance_valid(old_label):
			old_label.queue_free()
		_action_labels.erase(player_id)
	
	# Tạo label mới
	var label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.008
	label.outline_size = 12
	label.font_size = 32
	
	# Text và màu dựa trên action
	var action_text = ""
	var action_color = Color.WHITE
	
	match action:
		GameManager.PlayerAction.FOLD:
			action_text = "FOLD"
			action_color = Color(1.0, 0.3, 0.3) # Đỏ
		GameManager.PlayerAction.CHECK:
			action_text = "CHECK"
			action_color = Color(0.5, 0.8, 1.0) # Xanh nhạt
		GameManager.PlayerAction.CALL:
			action_text = "CALL $" + str(amount)
			action_color = Color(0.3, 1.0, 0.5) # Xanh lá
		GameManager.PlayerAction.RAISE:
			action_text = "RAISE $" + str(amount)
			action_color = Color(1.0, 0.85, 0.2) # Vàng
		GameManager.PlayerAction.ALL_IN:
			action_text = "ALL-IN $" + str(amount)
			action_color = Color(0.9, 0.3, 1.0) # Tím
	
	label.text = action_text
	label.modulate = action_color
	label.outline_modulate = Color(0, 0, 0, 0.8)
	
	# Đặt phía trên đầu player
	label.position = player.seat_position + Vector3(0, 0.8, 0)
	add_child(label)
	_action_labels[player_id] = label
	
	# Fade out sau 2.5 giây
	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
		if _action_labels.has(player_id) and _action_labels[player_id] == label:
			_action_labels.erase(player_id)
	)

func _cleanup_round() -> void:
	# Xóa community cards cũ
	for card_node in _spawned_community_cards:
		if is_instance_valid(card_node):
			card_node.queue_free()
	_spawned_community_cards.clear()
	
	# Xóa hole cards
	for p_id in _player_cards:
		for p_card in _player_cards[p_id]:
			if is_instance_valid(p_card):
				p_card.queue_free()
	_player_cards.clear()
	
	# Đề phòng còn sót chip chưa dọn
	for chip in _spawned_chips:
		if is_instance_valid(chip):
			chip.queue_free()
	_spawned_chips.clear()
	
	# Xóa action labels
	for pid in _action_labels:
		var lbl = _action_labels[pid]
		if is_instance_valid(lbl):
			lbl.queue_free()
	_action_labels.clear()

func _on_winners_declared(payouts: Dictionary, best_cards: Dictionary) -> void:
	# Lật bài bot lên
	for p_id in game_manager.active_players:
		var p = game_manager._get_player_by_id(p_id)
		if p and p.is_ai and _player_cards.has(p_id):
			for p_card in _player_cards[p_id]:
				if not p_card.is_face_up:
					p_card.is_face_up = true
					p_card._update_visuals()
					# Nhảy lên một chút để tạo hiệu ứng lật bài
					var tween = create_tween()
					tween.tween_property(p_card, "global_position:y", p_card.global_position.y + 0.1, 0.15)
					tween.tween_property(p_card, "global_position:y", p_card.global_position.y, 0.15)
	
	# Làm tối các lá bài không phải bài thắng, highlight bài thắng
	var all_winning_cards = []
	var winner_positions = []
	
	for p_id in game_manager.active_players:
		var p = game_manager._get_player_by_id(p_id)
		if p and p.hand_result:
			var is_winner = (payouts.has(p_id) and payouts[p_id] > 0)
			
			# Hiển thị text kết quả cho từng người chơi
			var hand_name = HandEvaluator.format_hand_name(p.hand_result.rank)
			var label = Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.font_size = 40 if is_winner else 24
			label.pixel_size = 0.008
			label.outline_size = 12
			
			if is_winner:
				label.text = "WINNER!\n" + hand_name + "\n+$" + str(payouts[p_id])
				label.modulate = Color(1.0, 0.85, 0.2) # Vàng chóe
				all_winning_cards.append_array(best_cards[p_id])
				winner_positions.append(p.seat_position)
			else:
				label.text = hand_name
				label.modulate = Color(0.6, 0.6, 0.6)
				
			label.position = p.seat_position + Vector3(0, 1.0, 0)
			
			# Tăng z-index logic của label bằng cách tắt depth testing (không bị chữ khác hoặc chip che mất)
			label.no_depth_test = true
			
			add_child(label)
			_action_labels[p_id] = label
			
			# Highlight/Dim hole cards
			if _player_cards.has(p_id):
				for p_card in _player_cards[p_id]:
					if is_winner and _is_card_in_array(p_card.card_data, best_cards.get(p_id, [])):
						p_card.highlight()
					else:
						p_card.dim()

	# Process community cards
	for p_card in _spawned_community_cards:
		if _is_card_in_array(p_card.card_data, all_winning_cards):
			p_card.highlight()
		else:
			p_card.dim()
			
	# Animate chips bay về người chiến thắng
	if winner_positions.size() > 0:
		# Lấy trung bình vị trí người thắng (nếu có chia gà)
		var center_winner_pos = Vector3.ZERO
		for pos in winner_positions:
			center_winner_pos += pos
		center_winner_pos /= float(winner_positions.size())
		
		var delay = 1.0 # Đợi lật bài hiển thị kết quả 1 giây trước khi kéo tiền
		for chip in _spawned_chips:
			if is_instance_valid(chip):
				chip.fly_to_winner(center_winner_pos, delay)
				delay += 0.02
				
		# Mảng được giải phóng dần trong fly_to_winner
		_spawned_chips.clear()

func _is_card_in_array(card: Card, card_array: Array) -> bool:
	if card == null: return false
	for c in card_array:
		if c.suit == card.suit and c.rank == card.rank:
			return true
	return false
