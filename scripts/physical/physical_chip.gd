class_name PhysicalChip
extends RigidBody3D

@export var denom_value: int = 10 
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null

var is_settled: bool = false
var time_settled: float = 0.0

func _ready() -> void:
	# Bật theo dõi điểm va chạm để phát ra âm thanh lạch cạch
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(_on_body_entered)
	
	mass = 0.02 # Chip khá nhẹ
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.6
	physics_material_override.bounce = 0.3 # Vẫn nảy một chút khi đập xuống bàn

func _physics_process(delta: float) -> void:
	if is_settled:
		return
		
	if linear_velocity.length() < 0.1 and angular_velocity.length() < 0.1:
		time_settled += delta
		if time_settled > 1.0:
			# Ngủ để tiết kiệm bộ nhớ khi chip nằm im lìm trên bàn
			sleeping = true
			is_settled = true
	else:
		time_settled = 0.0

func _on_body_entered(_body: Node) -> void:
	if linear_velocity.length() > 0.5:
		_play_clink_sound()

func _play_clink_sound() -> void:
	if audio_player and audio_player.stream:
		# Thay đổi độ cao pitch một chút để các tiếng không giống y hệt nhau
		audio_player.pitch_scale = randf_range(0.9, 1.1)
		audio_player.play()

func throw_towards(target_position: Vector3, throw_force: float = 3.0) -> void:
	# Ném chip hướng về phía tâm bàn (pot) với một quỹ đạo vòng cung nhỏ
	var direction := (target_position - global_position).normalized()
	var arc_offset := Vector3(0, randf_range(0.5, 1.5), 0)
	apply_central_impulse((direction + arc_offset) * throw_force)
	
	# Kèm xoay dọc trục y
	apply_torque_impulse(Vector3(0, randf_range(-1, 1), 0))

func set_value(val: int) -> void:
	denom_value = val
	var color = Color(0.8, 0.2, 0.2) # Default red ($10)
	if val >= 500:
		color = Color(0.6, 0.2, 0.6) # Purple
	elif val >= 100:
		color = Color(0.1, 0.1, 0.1) # Black
	elif val >= 50:
		color = Color(0.1, 0.6, 0.2) # Green
	elif val >= 25:
		color = Color(0.1, 0.3, 0.8) # Blue
	
	for child in get_children():
		if child is MeshInstance3D:
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			child.material_override = mat
			break

func fly_to_winner(target_pos: Vector3, delay: float = 0.0) -> void:
	# Bỏ qua vật lý, để bay thẳng tới người thắng
	freeze = true
	var tween = create_tween()
	
	var mid_pos = (global_position + target_pos) / 2.0
	mid_pos.y += randf_range(0.3, 0.8)
	
	tween.tween_interval(delay)
	tween.tween_property(self, "global_position", mid_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(self.queue_free)
