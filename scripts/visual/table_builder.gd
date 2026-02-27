extends Node3D

class_name TableBuilder
# Kịch bản này tự động thiết lập Bàn Poker, Ghế ngồi, Camera, và Ánh Sáng mà không cần thao tác tay trong Godot Editor.

@onready var game_manager = get_node("/root/GameManager")

# Tinh chỉnh thông số bàn
var table_radius: float = 3.5
var num_players: int = 9

# Danh sách các điểm ngồi
var seat_positions: Array[Vector3] = []

func _ready() -> void:
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
	env.background_color = Color(0.05, 0.05, 0.08) # Không gian quán bar tối màu
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.2, 0.25) # Ánh sáng nền mờ mờ
	env.tonemap_mode = Environment.TONE_MAPPER_ACES # Tone màu điện ảnh
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.8
	env.glow_bloom = 0.1
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func _setup_table() -> void:
	# 1. Tạo mặt bàn (Bầu dục hoặc tròn)
	var table_static = StaticBody3D.new()
	table_static.name = "PokerTable"
	add_child(table_static)
	
	# Hình dáng va chạm
	var push_shape = CollisionShape3D.new()
	var cyl_shape = CylinderShape3D.new()
	cyl_shape.radius = table_radius
	cyl_shape.height = 0.2
	push_shape.shape = cyl_shape
	table_static.add_child(push_shape)
	
	# Hình ảnh mặt bàn (Vải nỉ xanh lá/xanh biển)
	var table_mesh_inst = MeshInstance3D.new()
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = table_radius
	cyl_mesh.bottom_radius = table_radius
	cyl_mesh.height = 0.2
	
	var table_mat = StandardMaterial3D.new()
	table_mat.albedo_color = Color(0.1, 0.4, 0.15) # Xanh nỉ
	table_mat.roughness = 0.9 # Vải nỉ rất nhám
	cyl_mesh.material = table_mat
	
	table_mesh_inst.mesh = cyl_mesh
	table_static.add_child(table_mesh_inst)
	table_static.position = Vector3(0, -0.1, 0)
	
	# 2. Tạo viền bàn bọc da
	var rim_mesh_inst = MeshInstance3D.new()
	var tor_mesh = TorusMesh.new()
	tor_mesh.inner_radius = table_radius - 0.1
	tor_mesh.outer_radius = table_radius + 0.3
	
	var rim_mat = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.2, 0.1, 0.0) # Nâu da
	rim_mat.roughness = 0.4
	tor_mesh.material = rim_mat
	
	rim_mesh_inst.mesh = tor_mesh
	rim_mesh_inst.position = Vector3(0, 0.1, 0)
	table_static.add_child(rim_mesh_inst)

func _setup_lighting() -> void:
	# Đèn DirectionalLight chiếu sáng toàn bộ không gian rõ ràng, ko gây vùng đen tụ bóng
	var main_light = DirectionalLight3D.new()
	main_light.rotation_degrees = Vector3(-60, 45, 0)
	main_light.light_color = Color(1.0, 0.95, 0.9)
	main_light.light_energy = 1.5
	main_light.shadow_enabled = true
	add_child(main_light)
	
	# Đèn bù sáng nhẹ để không bị xỉn
	var fill_light = OmniLight3D.new()
	fill_light.position = Vector3(0, 4, 0)
	fill_light.light_energy = 0.5
	fill_light.omni_range = 10.0
	add_child(fill_light)

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
	camera_base_pos = Vector3(0, 8.0, table_radius)
	camera_base_rot = Vector3(-70, 0, 0)
	
	main_camera.position = camera_base_pos
	main_camera.rotation_degrees = camera_base_rot
	main_camera.fov = 60
	camera_rig.add_child(main_camera)
	main_camera.add_to_group("Camera")
	
	target_camera_pos = camera_base_pos
	target_camera_rot = camera_base_rot
	
	# Kết nối sự kiện Focus
	if game_manager:
		game_manager.player_turn_started.connect(_on_player_turn_started)
		game_manager.state_changed.connect(_on_game_state_changed)

func _process(delta: float) -> void:
	if main_camera:
		# Làm mượt chuyển động Camera
		main_camera.position = main_camera.position.lerp(target_camera_pos, delta * 3.0)
		
		# Quay mượt
		var current_quat = Quaternion.from_euler(main_camera.rotation)
		var target_quat = Quaternion.from_euler(target_camera_rot * PI / 180.0)
		main_camera.rotation = current_quat.slerp(target_quat, delta * 3.0).get_euler()
	
	# Cập nhật chips labels
	_update_chips_labels()

func _on_player_turn_started(player_id: String) -> void:
	# Focus nhẹ (zoom) vào phía góc người chơi
	is_focusing = true
	var p = game_manager._get_player_by_id(player_id)
	if p:
		# Camera dịch một chút về hướng người chơi đó và hạ thấp tí xíu
		var dir_to_player = p.seat_position.normalized()
		target_camera_pos = camera_base_pos + (dir_to_player * 0.5)
		target_camera_pos.y = camera_base_pos.y - 0.5
		
		# Góc chúi có thể lệch nhẹ
		target_camera_rot = camera_base_rot + Vector3(0, dir_to_player.x * -5.0, 0)

func _on_game_state_changed(new_state: int, _old_state: int) -> void:
	# Reset camera khi bắt đầu phân-phát bài hoặc đang chia bài mới
	if new_state == GameManager.GameState.DEALING_FLOP \
		or new_state == GameManager.GameState.DEALING_TURN \
		or new_state == GameManager.GameState.DEALING_RIVER \
		or new_state == GameManager.GameState.SHOWDOWN \
		or new_state == GameManager.GameState.ROUND_END:
		is_focusing = false
		target_camera_pos = camera_base_pos
		target_camera_rot = camera_base_rot

var _chips_labels: Dictionary = {} # player_id -> Label3D
var _player_nodes: Array = []

func _setup_players() -> void:
	# Tính toán 9 vị trí ngồi cách đều nhau quanh bàn (theo hình tròn)
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
		var player_node: Player
		if i == 0:
			player_node = HumanPlayer.new("You", 1500)
			player_node.name = "HumanPlayer"
		else:
			player_node = AIPlayer.new("Bot_" + str(i), 1000)
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
	
	# Thêm vào tree trước rồi mới look_at
	marker_mesh.position = pos
	add_child(marker_mesh)
	
	# Đặt marker quay hướng về giữa bàn
	marker_mesh.look_at(Vector3.ZERO, Vector3.UP)
	
	# Dịch name tag lùi ra viền thêm chút
	marker_mesh.translate(Vector3(0, 0, -0.3))
	
	# Tên người chơi (billboard để luôn quay mặt vào camera)
	var name_label = Label3D.new()
	name_label.text = player.id
	name_label.pixel_size = 0.004
	name_label.font_size = 24
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 0.25, 0)
	name_label.modulate = Color(1, 1, 1) if player.is_ai else Color(0.3, 1.0, 0.5)
	name_label.outline_size = 8
	name_label.outline_modulate = Color(0, 0, 0, 0.8)
	marker_mesh.add_child(name_label)
	
	# Chips label (cập nhật liên tục)
	var chips_label = Label3D.new()
	chips_label.text = "$" + str(player.chips)
	chips_label.pixel_size = 0.003
	chips_label.font_size = 20
	chips_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	chips_label.position = Vector3(0, 0.15, 0)
	chips_label.modulate = Color(1.0, 0.85, 0.2)
	chips_label.outline_size = 6
	chips_label.outline_modulate = Color(0, 0, 0, 0.7)
	marker_mesh.add_child(chips_label)
	_chips_labels[player.id] = chips_label

func _update_chips_labels() -> void:
	for p in _player_nodes:
		if _chips_labels.has(p.id):
			_chips_labels[p.id].text = "$" + str(p.chips)
