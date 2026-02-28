class_name PhysicalChip
extends RigidBody3D

@export var denom_value: int = 10 

var is_settled: bool = false
var time_settled: float = 0.0

func _ready() -> void:
	max_contacts_reported = 0
	contact_monitor = false
	
	mass = 0.05
	linear_damp = 1.5     # Giảm tốc vừa phải — tự nhiên hơn
	angular_damp = 2.0    # Cho phép lắc nhẹ khi chạm bàn
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.7
	physics_material_override.bounce = 0.2  # Nảy nhẹ khi chạm bàn — tự nhiên

func _physics_process(delta: float) -> void:
	if is_settled:
		return
	
	# Chờ chip nằm yên rồi mới freeze
	if linear_velocity.length() < 0.08 and angular_velocity.length() < 0.08:
		time_settled += delta
		if time_settled > 0.8:  # Chờ lâu hơn để animation landing hoàn tất
			freeze = true
			is_settled = true
	else:
		time_settled = 0.0

func throw_towards(target_position: Vector3, throw_force: float = 3.0) -> void:
	# Ném chip hướng về phía tâm bàn (pot) với một quỹ đạo vòng cung nhỏ
	var direction := (target_position - global_position).normalized()
	var arc_offset := Vector3(0, randf_range(0.5, 1.5), 0)
	apply_central_impulse((direction + arc_offset) * throw_force)
	
	# Kèm xoay dọc trục y
	apply_torque_impulse(Vector3(0, randf_range(-1, 1), 0))
	
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth: synth.play_chip_clink()

func set_value(val: int) -> void:
	denom_value = val
	# Màu đậm hơn, giống chip casino thật
	var color = Color(0.7, 0.08, 0.08) # Default red ($10)
	if val >= 500:
		color = Color(0.35, 0.05, 0.35) # Purple đậm
	elif val >= 100:
		color = Color(0.08, 0.08, 0.08) # Black
	elif val >= 50:
		color = Color(0.05, 0.40, 0.12) # Green đậm
	elif val >= 25:
		color = Color(0.08, 0.18, 0.55) # Blue đậm
	
	for child in get_children():
		if child is MeshInstance3D and child.name == "MeshInstance3D":
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mat.metallic = 0.15
			mat.roughness = 0.45
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
