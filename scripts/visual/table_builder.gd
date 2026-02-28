extends Node3D

class_name TableBuilder
# Kịch bản này tự động thiết lập Bàn Poker, Ghế ngồi, Camera, và Ánh Sáng mà không cần thao tác tay trong Godot Editor.

@onready var game_manager = get_node("/root/GameManager")

# Tinh chỉnh thông số bàn
var table_radius: float = 5.0
var num_players: int = 5 # Default is 5 (You + 4 bots)

# Danh sách các điểm ngồi
var seat_positions: Array[Vector3] = []

func _ready() -> void:
	# Đọc tùy chỉnh số lượng Bot từ Settings
	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	if sm:
		# num_players = human(1) + num_bots
		num_players = 1 + sm.num_bots
	num_players = clamp(num_players, 2, 9)

	_setup_environment()
	_setup_table()
	_setup_lighting()
	_setup_camera()
	_setup_players()
	
	# Bắt đầu game sau khi khởi tạo xong scene 1 giây
	get_tree().create_timer(1.0).timeout.connect(func():
		if game_manager:
			game_manager.start_game()
	)

func _setup_environment() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03) # Phòng tối đen
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.10, 0.10, 0.11) # Phòng tối nhưng thấy được hình dáng
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_strength = 0.4
	env.glow_bloom = 0.15  # Bloom nhẹ tạo cảm giác ấm cúng
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	
	get_viewport().msaa_3d = Viewport.MSAA_4X

func _setup_table() -> void:
	var table_static = StaticBody3D.new()
	table_static.name = "PokerTable"
	add_child(table_static)
	
	var push_shape = CollisionShape3D.new()
	var cyl_shape = CylinderShape3D.new()
	cyl_shape.radius = table_radius
	cyl_shape.height = 0.2
	push_shape.shape = cyl_shape
	table_static.add_child(push_shape)
	
	# Mặt bàn — vải nỉ xanh đậm như casino thật
	var table_mesh_inst = MeshInstance3D.new()
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = table_radius
	cyl_mesh.bottom_radius = table_radius
	cyl_mesh.height = 0.2
	cyl_mesh.radial_segments = 64
	cyl_mesh.rings = 2
	
	var table_mat = StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.04, 0.22, 0.08) # Xanh đậm như nỉ casino thật
	table_mat.roughness = 0.95  # Vải nỉ rất nhám, không bóng
	table_mat.metallic = 0.0
	cyl_mesh.material = table_mat
	
	table_mesh_inst.mesh = cyl_mesh
	table_static.add_child(table_mesh_inst)
	table_static.position = Vector3(0, -0.1, 0)
	
	# Viền bàn gỗ mahogany đậm
	var rim_mesh_inst = MeshInstance3D.new()
	var tor_mesh = TorusMesh.new()
	tor_mesh.inner_radius = table_radius - 0.15
	tor_mesh.outer_radius = table_radius + 0.4
	tor_mesh.rings = 48
	tor_mesh.ring_segments = 24
	
	var rim_mat = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.12, 0.05, 0.02) # Mahogany đậm
	rim_mat.roughness = 0.55  # Gỗ đánh bóng nhẹ
	rim_mat.metallic = 0.08  # Phản chiếu rất nhẹ như gỗ Veneer
	tor_mesh.material = rim_mat
	
	rim_mesh_inst.mesh = tor_mesh
	rim_mesh_inst.position = Vector3(0, 0.1, 0)
	table_static.add_child(rim_mesh_inst)

func _setup_lighting() -> void:
	# Không dùng DirectionalLight mạnh — phòng tối chỉ có đèn trên bàn
	var main_light = DirectionalLight3D.new()
	main_light.rotation_degrees = Vector3(-55, 30, 0)
	main_light.light_color = Color(0.95, 0.85, 0.7) # Vàng ấm
	main_light.light_energy = 0.5  # Nhẹ — để thấy hình dáng
	main_light.shadow_enabled = true
	add_child(main_light)
	
	# Đèn trên bàn — nguồn sáng chính, ấm vàng
	var table_lamp = SpotLight3D.new()
	table_lamp.position = Vector3(0, 4, 0)
	table_lamp.rotation_degrees = Vector3(-90, 0, 0)
	table_lamp.light_energy = 3.5
	table_lamp.light_color = Color(1.0, 0.88, 0.65)
	table_lamp.spot_range = 10.0
	table_lamp.spot_angle = 45.0
	table_lamp.spot_attenuation = 1.0  # Mềm đều hơn
	table_lamp.shadow_enabled = false  # Tắt shadow — tránh chấm đen giữa bàn
	add_child(table_lamp)
	
	# Fill light nhẹ phía dưới để không bị đen hoàn toàn
	var fill = OmniLight3D.new()
	fill.position = Vector3(0, 2, 0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.9, 0.8, 0.6)
	fill.omni_range = 8.0
	add_child(fill)

var camera_rig: Node3D
var main_camera: Camera3D
var camera_base_pos: Vector3
var camera_base_rot: Vector3
var target_camera_pos: Vector3
var target_camera_rot: Vector3
var is_focusing: bool = false

func _setup_camera() -> void:
	camera_rig = Node3D.new()
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	
	main_camera = Camera3D.new()
	main_camera.name = "MainCamera"
	
	# Góc nhìn ngồi ghế: cao hơn (~3.8m) và lùi xa viền bàn (~2.0m)
	var sit_z = table_radius + 2.0
	camera_base_pos = Vector3(0, 3.8, sit_z)
	# Chúi xuống ~40° để nhìn rõ community cards ở giữa bàn
	camera_base_rot = Vector3(-40, 0, 0)
	
	main_camera.position = camera_base_pos
	main_camera.rotation_degrees = camera_base_rot
	main_camera.fov = 65  # Rộng hơn để thấy toàn bàn
	camera_rig.add_child(main_camera)
	main_camera.add_to_group("Camera")
	
	target_camera_pos = camera_base_pos
	target_camera_rot = camera_base_rot
	
	# Kết nối sự kiện Focus
	if game_manager:
		game_manager.player_turn_started.connect(_on_player_turn_started)
		game_manager.state_changed.connect(_on_game_state_changed)
		game_manager.action_received.connect(_on_player_action)
		game_manager.winners_declared.connect(_on_winners_declared)
		
func _on_player_action(player_id: String, action: int, amount: int) -> void:
	_update_chips_labels()
	match action:
		GameManager.PlayerAction.FOLD: show_reaction(player_id, "FOLD")
		GameManager.PlayerAction.RAISE: show_reaction(player_id, "RAISE")
		GameManager.PlayerAction.ALL_IN: show_reaction(player_id, "ALLIN")
		
func _on_winners_declared(payouts: Dictionary, _best_cards: Dictionary) -> void:
	_update_chips_labels()
	for pid in payouts:
		if payouts[pid] > 0:
			show_reaction(pid, "WIN")
		else:
			# Chỉ những người không Fold và vẫn còn trong Showdown mới buồn
			var p = game_manager._get_player_by_id(pid)
			if p and not p.is_folded and game_manager.active_players.has(pid):
				show_reaction(pid, "LOSE")

func _process(delta: float) -> void:
	if main_camera:
		# Làm mượt chuyển động Camera
		main_camera.position = main_camera.position.lerp(target_camera_pos, delta * 3.0)
		
		# Quay mượt
		var current_quat = Quaternion.from_euler(main_camera.rotation)
		var target_quat = Quaternion.from_euler(target_camera_rot * PI / 180.0)
		main_camera.rotation = current_quat.slerp(target_quat, delta * 3.0).get_euler()

func _on_player_turn_started(player_id: String) -> void:
	# Focus nhẹ (dịch tầm nhìn) về phía người chơi đang hành động
	is_focusing = true
	var p = game_manager._get_player_by_id(player_id)
	if p:
		# Từ góc nhìn ngồi: chỉ dịch nhẹ trái/phải và liếc mắt theo
		var dir_to_player = p.seat_position.normalized()
		target_camera_pos = camera_base_pos + Vector3(dir_to_player.x * 0.3, 0, 0)
		# Liếc nhẹ sang trái/phải
		target_camera_rot = camera_base_rot + Vector3(0, dir_to_player.x * -8.0, 0)
		
		# Occasionally show thinking bubble for AI
		if p.is_ai and randf() < 0.35:
			get_tree().create_timer(randf_range(0.5, 1.2)).timeout.connect(func():
				# Only show if still their turn
				if game_manager.current_player_index == game_manager.active_players.find(player_id):
					show_reaction(player_id, "THINK")
			)

func _on_game_state_changed(new_state: int, _old_state: int) -> void:
	# Reset camera khi bắt đầu phân-phát bài hoặc đang chia bài mới
	if new_state == GameManager.GameState.DEALING_FLOP \
		or new_state == GameManager.GameState.DEALING_TURN \
		or new_state == GameManager.GameState.DEALING_RIVER \
		or new_state == GameManager.GameState.ROUND_END:
		is_focusing = false
		target_camera_pos = camera_base_pos
		target_camera_rot = camera_base_rot
		
	elif new_state == GameManager.GameState.SHOWDOWN:
		# ZOOM IN DRAMATICALLY
		is_focusing = true
		target_camera_pos = camera_base_pos + Vector3(0, -1.0, -1.5) # Lower and Closer
		target_camera_rot = Vector3(-55, 0, 0) # Look straight down at the carnage

var _chips_labels: Dictionary = {} # player_id -> Label3D
var _player_nodes: Array = []

func _setup_players() -> void:
	# Check multiplayer mode
	var nm = get_node("/root/NetworkManager")
	var is_multiplayer = multiplayer.has_multiplayer_peer()
	
	if is_multiplayer:
		# --- MULTIPLAYER SETUP ---
		var peer_ids = nm.players.keys()
		peer_ids.sort() # Ensure consistent order on all clients
		num_players = peer_ids.size()
		
		var angle_step = PI * 2.0 / num_players
		var my_id = multiplayer.get_unique_id()
		var my_index = peer_ids.find(my_id)
		
		for i in range(num_players):
			var peer_id = peer_ids[i]
			var p_id_str = str(peer_id)
			
			# Rotate table so Local Player is always at the bottom (PI/2)
			var relative_i = (i - my_index + num_players) % num_players
			var angle = (PI / 2.0) + (relative_i * angle_step)
			
			var sit_radius = table_radius - 0.5 
			var pos = Vector3(cos(angle) * sit_radius, 0.1, sin(angle) * sit_radius)
			seat_positions.append(pos)
			
			# All players are HumanPlayer in multiplayer (remote or local)
			var chips = 5000 # Default tournament stack for Multiplayer
			var player_node = HumanPlayer.new(p_id_str, chips)
			player_node.name = p_id_str
			player_node.set_multiplayer_authority(peer_id)
			player_node.seat_position = pos
			
			add_child(player_node)
			_player_nodes.append(player_node)
			
			if game_manager:
				game_manager.register_player(player_node)
			
			_create_seat_marker(pos, player_node)
			
			# Set display name
			var p_name = nm.players[peer_id].get("name", "Player")
			# Update marker name tag
			if _chips_labels.has(p_id_str):
				var lbl_chip = _chips_labels[p_id_str]
				var lbl_name = lbl_chip.get_parent().get_child(0) as Label3D
				if lbl_name: lbl_name.text = p_name

	else:
		# --- SINGLEPLAYER SETUP ---
		var angle_step = PI * 2.0 / num_players
		
		for i in range(num_players):
			# Human player sẽ ngồi ở góc 90 độ (PI/2) để quay mặt thẳng vào view camera
			var angle = (PI / 2.0) + (i * angle_step)
			
			# Bán kính ngồi lùi ra viền bàn một chút
			var sit_radius = table_radius - 0.5 
			
			var pos = Vector3(
				cos(angle) * sit_radius,
				0.1, # Ngay trên mặt bàn một chút để ném bài
				sin(angle) * sit_radius
			)
			seat_positions.append(pos)
			
			# Khởi tạo Player Node
			var human_chips = 5000
			var sm = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
			if sm:
				human_chips = sm.get_chips()
			
			var player_node: Player
			if i == 0:
				player_node = HumanPlayer.new("You", human_chips)
				player_node.name = "HumanPlayer"
			else:
				player_node = AIPlayer.new("Bot_" + str(i), human_chips)
				player_node.name = "Bot_" + str(i)
				
			player_node.seat_position = pos
			add_child(player_node)
			_player_nodes.append(player_node)
			
			if game_manager:
				game_manager.register_player(player_node)
				
			# Tạo marker cho mỗi seat
			_create_seat_marker(pos, player_node)

func _create_seat_marker(pos: Vector3, player: Player) -> void:
	var marker_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.4, 0.05, 0.2)
	marker_mesh.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.2)
	box.material = mat
	
	# Ẩn TẤT CẢ marker mesh — không hiện cục đen nào
	marker_mesh.visible = false
	
	# Thêm vào tree trước rồi mới look_at
	marker_mesh.position = pos
	add_child(marker_mesh)
	
	# Đặt marker quay hướng về giữa bàn
	marker_mesh.look_at(Vector3.ZERO, Vector3.UP)
	
	# Dịch name tag lùi ra ngoài viền bàn
	marker_mesh.translate(Vector3(0, 0, -1.2))
	
	# Tên người chơi — to hơn, màu dịu hơn
	var name_label = Label3D.new()
	name_label.text = player.id
	name_label.pixel_size = 0.006
	name_label.font_size = 36
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 0.35, 0)
	name_label.modulate = Color(0.9, 0.85, 0.75) if player.is_ai else Color(0.5, 0.9, 0.6)
	name_label.outline_size = 10
	name_label.outline_modulate = Color(0, 0, 0, 0.6)
	marker_mesh.add_child(name_label)
	
	# Chips label — to hơn, vàng dịu
	var chips_label = Label3D.new()
	chips_label.text = "$" + str(player.chips)
	chips_label.pixel_size = 0.005
	chips_label.font_size = 28
	chips_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	chips_label.position = Vector3(0, 0.15, 0)
	chips_label.modulate = Color(0.85, 0.75, 0.3)
	chips_label.outline_size = 8
	chips_label.outline_modulate = Color(0, 0, 0, 0.5)
	marker_mesh.add_child(chips_label)
	_chips_labels[player.id] = chips_label

func _update_chips_labels() -> void:
	for p in _player_nodes:
		if _chips_labels.has(p.id):
			_chips_labels[p.id].text = "$" + str(p.chips)

# ---- REACTION SYSTEM ----
func show_reaction(player_id: String, reaction_type: String) -> void:
	var marker = null
	# Tìm marker của player (đang là parent của chips_label)
	if _chips_labels.has(player_id):
		marker = _chips_labels[player_id].get_parent()
		
	if not marker: return
	
	var emoji = ""
	match reaction_type:
		"WIN": emoji = ["🤑", "😎", "🥳", "💰"].pick_random()
		"LOSE": emoji = ["😭", "🤬", "💀", "🏳️"].pick_random()
		"THINK": emoji = ["🤔", "🤨", "💭", "👀"].pick_random()
		"RAISE": emoji = ["🚀", "🔥", "😤", "💪"].pick_random()
		"ALLIN": emoji = ["🚨", "💣", "🍀", "🙏"].pick_random()
		"FOLD": emoji = ["👋", "🙈", "🤐", "😴"].pick_random()
		_: emoji = reaction_type
		
	var lbl = Label3D.new()
	lbl.text = emoji
	lbl.font_size = 96
	lbl.pixel_size = 0.01
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true # Luôn hiện trên cùng
	lbl.render_priority = 10
	lbl.modulate = Color(1, 1, 1, 0) # Start transparent
	lbl.outline_render_priority = 9
	lbl.position = Vector3(0, 1.5, 0) # Xuất hiện trên đầu
	marker.add_child(lbl)
	
	# Animate
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", 2.5, 1.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.3)
	tw.chain().tween_property(lbl, "modulate:a", 0.0, 0.5).set_delay(1.0)
	tw.tween_callback(lbl.queue_free)
