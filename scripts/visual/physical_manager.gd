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
# Dealer Button 3D
var _dealer_button_label: Label3D = null
# Player HUDs
var _player_huds: Dictionary = {} # player_id -> Label3D

func _ready() -> void:
	# Tự động tạo PackedScene cho Card và Chip bằng code thay vì tạo file .tscn trong Editor
	card_scene = _build_card_prefab()
	chip_scene = _build_chip_prefab()

	# Thêm sàn để bài/chip không rơi vô tận
	_setup_floor()
	
	# Khởi tạo Label3D cho Dealer Button
	_dealer_button_label = Label3D.new()
	_dealer_button_label.text = " D "
	_dealer_button_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_dealer_button_label.modulate = Color(1.0, 0.9, 0.2) # Màu vàng
	_dealer_button_label.outline_modulate = Color(0.1, 0.1, 0.1, 1.0)
	_dealer_button_label.font_size = 48
	_dealer_button_label.pixel_size = 0.006
	_dealer_button_label.outline_size = 12
	add_child(_dealer_button_label)
	_dealer_button_label.hide()

	if game_manager:
		game_manager.state_changed.connect(_on_game_state_changed)
		game_manager.community_cards_changed.connect(_on_community_cards_dealt)
		game_manager.action_received.connect(_on_player_action)
		game_manager.winners_declared.connect(_on_winners_declared)
		game_manager.betting_round_ended.connect(_gather_chips_to_pot)
		game_manager.player_eliminated.connect(_on_player_eliminated)

	# Chờ 1 frame để TableBuilder kịp register players
	await get_tree().process_frame
	
	_setup_player_huds()

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
	mat.albedo_color = Color(0.82, 0.82, 0.82) # Không trắng chói — dịu hơn dưới đèn
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	
	var col = CollisionShape3D.new()
	var cyl = CylinderShape3D.new()
	cyl.radius = 0.12
	cyl.height = 0.03
	col.shape = cyl
	root.add_child(col)
	col.owner = root
	
	# Body chính — sắc nét, chip dày hơn
	var mesh_inst = MeshInstance3D.new()
	var mesh = CylinderMesh.new()
	mesh.top_radius = cyl.radius
	mesh.bottom_radius = cyl.radius
	mesh.height = cyl.height
	mesh.radial_segments = 48
	mesh.rings = 2
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.08, 0.08)
	mat.metallic = 0.15
	mat.roughness = 0.45
	mesh.material = mat
	mesh_inst.mesh = mesh
	mesh_inst.name = "MeshInstance3D"
	root.add_child(mesh_inst)
	mesh_inst.owner = root
	
	# Vân viền ngoài (edge stripe) — trắng
	var edge = MeshInstance3D.new()
	var edge_mesh = TorusMesh.new()
	edge_mesh.inner_radius = cyl.radius - 0.006
	edge_mesh.outer_radius = cyl.radius + 0.003
	edge_mesh.rings = 32
	edge_mesh.ring_segments = 8
	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.92, 0.90, 0.85)
	edge_mat.metallic = 0.1
	edge_mat.roughness = 0.5
	edge_mesh.material = edge_mat
	edge.mesh = edge_mesh
	edge.name = "EdgeStripe"
	root.add_child(edge)
	edge.owner = root
	
	# Vân trang trí bên trong (inner ring)
	var inner = MeshInstance3D.new()
	var inner_mesh = TorusMesh.new()
	inner_mesh.inner_radius = cyl.radius * 0.55
	inner_mesh.outer_radius = cyl.radius * 0.62
	inner_mesh.rings = 32
	inner_mesh.ring_segments = 6
	var inner_mat = StandardMaterial3D.new()
	inner_mat.albedo_color = Color(0.88, 0.85, 0.78)
	inner_mat.metallic = 0.08
	inner_mat.roughness = 0.55
	inner_mesh.material = inner_mat
	inner.mesh = inner_mesh
	inner.name = "InnerRing"
	root.add_child(inner)
	inner.owner = root
	
	var ap = AudioStreamPlayer3D.new()
	ap.name = "AudioStreamPlayer3D"
	ap.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
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
	
	# Determine if this player is "Me" (Local User)
	var is_me = (player.id == "You") 
	if multiplayer.has_multiplayer_peer():
		is_me = (player.id == str(multiplayer.get_unique_id()))
	
	if is_me:
		# MY CARDS: Đặt bài tĩnh, ngửa, ngay trước camera
		p_card.is_face_up = true
		p_card._update_visuals()
		
		# Human cards nằm sát mép bàn
		var card_pos = player.seat_position + Vector3(offset_x, offset_y, -0.3)
		p_card.global_position = card_pos
		p_card.rotation_degrees = Vector3(-90, 0, 0) # Nằm ngang phẳng xuống bàn
		p_card.freeze = true
	else:
		# OTHERS (Bots or Remote Humans): Face Down
		p_card.is_face_up = false # Always face down for others
		p_card._update_visuals()
		
		p_card.global_position = dealer_pos
		
		# Tính hướng từ tâm bàn đến người chơi
		var dir_to_center = (Vector3.ZERO - player.seat_position).normalized()
		if dir_to_center.length_squared() < 0.01:
			dir_to_center = Vector3.FORWARD
			
		var angle_y = atan2(dir_to_center.x, dir_to_center.z)
		p_card.rotation = Vector3(deg_to_rad(-90), angle_y, 0)
		
		# Vị trí đích ngay ngắn trước mặt họ
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

func _on_physical_action(action: int, amount: int, _force: float, player: Player) -> void:
	# Đẩy chip mượt mà ra giữa bàn
	if action == GameManager.PlayerAction.CALL or action == GameManager.PlayerAction.RAISE or action == GameManager.PlayerAction.ALL_IN:
		# Tính số tiền thực cho CALL (bot gửi amount=0)
		var actual_amount = amount
		if action == GameManager.PlayerAction.CALL and actual_amount <= 0:
			if game_manager:
				actual_amount = game_manager.current_bet - player.current_bet
		if actual_amount <= 0: return
		
		# Chia amount thành các chip mệnh giá khác nhau
		var remaining = actual_amount
		var chip_values = []
		var denoms = [500, 100, 50, 25, 10]
		
		for denom in denoms:
			while remaining >= denom and chip_values.size() < 15: # Max 15 chips
				chip_values.append(denom)
				remaining -= denom
				
		if remaining > 0:
			chip_values.append(remaining)
		
		var delay_accum = 0.0
		for idx in range(chip_values.size()):
			var val = chip_values[idx]
			var chip = chip_scene.instantiate() as PhysicalChip
			add_child(chip)
			chip.set_value(val)
			chip.freeze = true  # Bắt đầu đông cứng — tween điều khiển
			
			# Spawn gần player
			var spawn_pos = player.seat_position
			spawn_pos.y = 0.15
			var dir_to_center = -player.seat_position.normalized()
			spawn_pos += dir_to_center * 0.3
			chip.global_position = spawn_pos
			
			# Vị trí đích: vòng quanh khu vực giữa (tránh che bài)
			var dist_from_center = randf_range(1.2, 2.0)
			var target_pos = dir_to_center * -dist_from_center
			target_pos.x += randf_range(-0.3, 0.3)
			target_pos.z += randf_range(-0.3, 0.3)
			
			# Vị trí thả chip: ngay phía trên target để rơi xuống tự nhiên
			var drop_pos = Vector3(target_pos.x, 0.4 + idx * 0.05, target_pos.z)
			
			# Tween arc → drop position, sau đó unfreeze cho vật lý xử lý landing
			var tween = create_tween()
			if delay_accum > 0:
				tween.tween_interval(delay_accum)
			
			# Bay cung nhẹ lên
			var mid = (spawn_pos + drop_pos) / 2.0
			mid.y = 0.6 + idx * 0.03
			tween.tween_property(chip, "global_position", mid, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			# Bay tới vị trí thả
			tween.tween_property(chip, "global_position", drop_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			var chip_id = chip.get_instance_id()
			tween.tween_callback(func(): 
				var c = instance_from_id(chip_id) as PhysicalChip
				if is_instance_valid(c):
					c.freeze = false
					c.is_settled = false
					c.time_settled = 0.0
					
					var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
					if synth: synth.play_chip_clink()
						
					c.apply_torque_impulse(Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3)))
			)
			
			_spawned_chips.append(chip)
			delay_accum += 0.06

# ---- PLAYER HUDS ----
func _setup_player_huds() -> void:
	if not game_manager: return
	
	for p in game_manager.players:
		var hud = Label3D.new()
		hud.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		hud.pixel_size = 0.006
		hud.outline_size = 10
		hud.font_size = 32
		hud.text = p.id + "\n$" + str(p.chips)
		
		if p.is_ai:
			hud.modulate = Color(0.8, 0.9, 1.0)
		else:
			hud.modulate = Color(1.0, 0.9, 0.5) # Human nổi bật hơn
			
		hud.position = p.seat_position + Vector3(0, 0.35, 0) # Nằm ngay trên đầu chip/bài
		add_child(hud)
		_player_huds[p.id] = hud

func _update_player_huds() -> void:
	if not game_manager: return
	
	for p in game_manager.players:
		if _player_huds.has(p.id):
			var hud = _player_huds[p.id]
			if is_instance_valid(hud):
				hud.text = p.id + "\n$" + str(p.chips)
				if p.is_folded or p.chips == 0 and not game_manager.active_players.has(p.id):
					hud.modulate.a = 0.4 # Làm mờ người đã fold hoặc hết tiền
				else:
					hud.modulate.a = 1.0

func _on_player_eliminated(player_id: String) -> void:
	if _player_huds.has(player_id):
		var hud = _player_huds[player_id]
		if is_instance_valid(hud):
			hud.queue_free()
		_player_huds.erase(player_id)

# ---- POT ANIMATIONS ----
func _gather_chips_to_pot() -> void:
	if _spawned_chips.size() == 0: return
	
	var gather_tween = create_tween()
	gather_tween.set_parallel(true)
	var delay = 0.0
	
	# Phát âm thanh lùa tiền (lấy 1 tiếng chip rớt ngẫu nhiên đóng vai trò lùa)
	# Phát âm thanh lùa tiền (dùng tiếng slide thay thế)
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth: synth.play_card_slide()
	
	for chip in _spawned_chips:
		if is_instance_valid(chip):
			# Làm cho chip mất tính phản hồi vật lý để bay thẳng không bị kẹt
			chip.freeze = true 
			chip.collision_layer = 0
			chip.collision_mask = 0
			
			# Gom về giữa bàn, hơi rải rác một chút cho tự nhiên
			var target_pos = dealer_pos + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.1), randf_range(-0.2, 0.2))
			
			gather_tween.tween_property(chip, "global_position", target_pos, 0.4 + delay)\
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			
			delay += 0.02 # Các chip lùa vào lần lượt như chổi quyét
			
	gather_tween.chain()

# ---- EVENT HANDLERS ----
func _on_game_state_changed(new_state: int, _old_state: int) -> void:
	_update_player_huds()
	# Cleanup khi bắt đầu round mới
	if new_state == GameManager.GameState.WAITING_FOR_PLAYERS:
		_cleanup_round()
	elif new_state == GameManager.GameState.DEALING_HOLE_CARDS:
		if game_manager and _dealer_button_label:
			_dealer_button_label.show()
			var dlr_id = game_manager.dealer_player_id
			var dlr = game_manager._get_player_by_id(dlr_id)
			if dlr:
				# Đặt Dealer button ngay cạnh ghế người chơi
				var offset_dir = dlr.seat_position.normalized()
				var right_dir = Vector3.UP.cross(offset_dir).normalized()
				_dealer_button_label.position = dlr.seat_position + right_dir * 0.4 + Vector3(0, 0.05, 0)
	elif new_state == GameManager.GameState.SHOWDOWN:
		# Ẩn các label action (CALL/RAISE) cũ để lấy chỗ hiện thông báo người thắng
		for pid in _action_labels:
			var lbl = _action_labels[pid]
			if is_instance_valid(lbl):
				lbl.queue_free()
		_action_labels.clear()

func _on_player_action(player_id: String, action: int, amount: int) -> void:
	_update_player_huds()
	
	# Hiển thị action label nổi trên đầu player
	if not game_manager:
		return
	
	var player = game_manager._get_player_by_id(player_id)
	if not player:
		return
	
	# === FOLD ANIMATION: Bài bay vào giữa bàn và biến mất ===
	if action == GameManager.PlayerAction.FOLD:
		_animate_fold_cards(player_id)
	
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
	var lbl_id = label.get_instance_id()
	tween.tween_callback(func():
		var l = instance_from_id(lbl_id) as Label3D
		if is_instance_valid(l):
			l.queue_free()
		if _action_labels.has(player_id) and is_instance_valid(l) and _action_labels[player_id] == l:
			_action_labels.erase(player_id)
	)

func _cleanup_round() -> void:
	# Clear community cards
	for c in _spawned_community_cards:
		if is_instance_valid(c):
			c.queue_free()
	_spawned_community_cards.clear()
	
	# Clear player cards
	for pid in _player_cards:
		var cards = _player_cards[pid]
		for c in cards:
			if is_instance_valid(c):
				c.queue_free()
	_player_cards.clear()
	
	# Clear action labels
	for pid in _action_labels:
		var lbl = _action_labels[pid]
		if is_instance_valid(lbl):
			lbl.queue_free()
	_action_labels.clear()
	
	# Clear chips if any left
	for c in _spawned_chips:
		if is_instance_valid(c):
			c.queue_free()
	_spawned_chips.clear()

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
			
			if is_winner:
				_spawn_confetti(p.seat_position)
				_spawn_floating_text("+$" + str(payouts[p_id]), p.seat_position, Color(0.2, 1.0, 0.4))
			
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
				chip.freeze = true
				chip.collision_layer = 0
				chip.collision_mask = 0
				
				var flight_tween = create_tween()
				flight_tween.tween_interval(delay)
				
				# Quỹ đạo bay vòng cung
				var mid_pos = (chip.global_position + center_winner_pos) / 2.0
				mid_pos.y += 1.0
				
				flight_tween.tween_property(chip, "global_position", mid_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				flight_tween.tween_property(chip, "global_position", center_winner_pos, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				
				# Bay tới nơi thì xóa chip để đỡ nặng máy, tiền đã cộng vào hud
				flight_tween.tween_callback(chip.queue_free)
				delay += 0.02
				
		_spawned_chips.clear()

func _is_card_in_array(card: Card, card_array: Array) -> bool:
	if card == null: return false
	for c in card_array:
		if c.suit == card.suit and c.rank == card.rank:
			return true
	return false

func _animate_fold_cards(player_id: String) -> void:
	if not _player_cards.has(player_id):
		return
	
	var cards = _player_cards[player_id]
	var delay = 0.0
	
	for p_card in cards:
		if not is_instance_valid(p_card):
			continue
		
		# Lật úp bài nếu đang ngửa
		if p_card.is_face_up:
			p_card.is_face_up = false
			p_card._update_visuals()
		
		# Animation: bay vào giữa bàn → thu nhỏ → biến mất
		var tween = create_tween()
		tween.set_parallel(false)
		
		# Đợi delay nhẹ giữa các lá
		if delay > 0:
			tween.tween_interval(delay)
		
		# Bay lên một chút và phát âm thanh trượt
		var mid_pos = p_card.global_position
		mid_pos.y += 0.5
		
		var c_id = p_card.get_instance_id()
		tween.tween_callback(func():
			var c = instance_from_id(c_id) as PhysicalCard
			if is_instance_valid(c):
				var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
				if synth: synth.play_card_slide()
		)
		
		tween.tween_property(p_card, "global_position", mid_pos, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		
		# Bay vào giữa bàn (dealer_pos)
		var center = Vector3(0, 0.3, 0)
		tween.tween_property(p_card, "global_position", center, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		# Thu nhỏ và biến mất
		tween.tween_property(p_card, "scale", Vector3(0.01, 0.01, 0.01), 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
		# Xóa card
		tween.tween_callback(p_card.queue_free)
		
		delay += 0.1
	
	# Xóa khỏi tracking sau khi animation chạy
	_player_cards.erase(player_id)

# -------- PREMIUM AESTHETICS (CONFETTI & TEXT) --------

func _spawn_floating_text(text_str: String, pos: Vector3, color: Color) -> void:
	var label = Label3D.new()
	label.text = text_str
	label.pixel_size = 0.008
	label.font_size = 64
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.position = pos + Vector3(0, 0.5, 0)
	label.no_depth_test = true
	add_child(label)
	
	var tw = create_tween().set_parallel(true)
	label.scale = Vector3.ZERO
	tw.tween_property(label, "scale", Vector3.ONE, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(label, "position:y", label.position.y + 1.2, 2.5).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 2.5).set_ease(Tween.EASE_IN)
	
	tw.chain().tween_callback(label.queue_free)

func _spawn_confetti(pos: Vector3) -> void:
	var particles = GPUParticles3D.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.2) # Vàng chóe
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.1)
	mat.emission_energy_multiplier = 2.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.08, 0.08)
	mesh.material = mat
	particles.draw_pass_1 = mesh
	
	var pmat = ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = 0.4
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 60.0
	pmat.initial_velocity_min = 4.0
	pmat.initial_velocity_max = 7.0
	pmat.gravity = Vector3(0, -9.8, 0)
	pmat.scale_min = 0.5
	pmat.scale_max = 1.5
	pmat.angle_min = -180.0
	pmat.angle_max = 180.0
	
	particles.process_material = pmat
	particles.amount = 100
	particles.lifetime = 3.0
	particles.one_shot = true
	particles.explosiveness = 0.95
	
	particles.position = pos + Vector3(0, 1.0, 0)
	add_child(particles)
	particles.emitting = true
	
	get_tree().create_timer(4.0).timeout.connect(particles.queue_free)
