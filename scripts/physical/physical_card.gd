class_name PhysicalCard
extends RigidBody3D

var card_data: Card
var mesh_instance: MeshInstance3D = null

var is_face_up: bool = false
var _front_material: StandardMaterial3D
var _back_material: StandardMaterial3D

func _ready() -> void:
	mass = 0.05
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.4
	physics_material_override.bounce = 0.1
	
	# Tìm MeshInstance3D con
	for child in get_children():
		if child is MeshInstance3D:
			mesh_instance = child
	
	# Tạo material mặt sau
	_back_material = StandardMaterial3D.new()
	_back_material.albedo_color = Color(0.82, 0.82, 0.82)
	_back_material.albedo_texture = CardTextureGenerator.get_back_texture()
	_back_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_back_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_back_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	if mesh_instance:
		mesh_instance.material_override = _back_material

func set_card_data(data: Card) -> void:
	card_data = data
	# Tạo material mặt trước
	_front_material = StandardMaterial3D.new()
	_front_material.albedo_color = Color(0.82, 0.82, 0.82)
	_front_material.albedo_texture = CardTextureGenerator.get_card_texture(card_data)
	_front_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_front_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_front_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_update_visuals()

func _update_visuals() -> void:
	if not mesh_instance:
		# Thử tìm lại
		for child in get_children():
			if child is MeshInstance3D:
				mesh_instance = child
				break
	
	if not mesh_instance:
		return
	
	if is_face_up and card_data and _front_material:
		mesh_instance.material_override = _front_material
	elif _back_material:
		mesh_instance.material_override = _back_material

func throw_to(target_pos: Vector3, duration: float = 0.25, _spin_force: float = 1.0) -> void:
	# Đóng băng vật lý để dùng Tween
	freeze = true
	
	var tween = create_tween()
	
	# Tạo đường cong bay lên giữa chừng rồi rớt xuống bàn
	var mid_pos = (global_position + target_pos) / 2.0
	mid_pos.y += 0.8
	
	# Phát âm thanh chia bài trượt trên bàn
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth: synth.play_card_slide()
	
	tween.tween_property(self, "global_position", mid_pos, duration / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", target_pos, duration / 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func flip() -> void:
	is_face_up = !is_face_up
	_update_visuals()
	
	# Phát âm thanh lật bài
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth: synth.play_ui_click()

func dim() -> void:
	if _front_material:
		_front_material.albedo_color = Color(0.3, 0.3, 0.3)
	if _back_material:
		_back_material.albedo_color = Color(0.3, 0.3, 0.3)

func highlight() -> void:
	if _front_material:
		_front_material.albedo_color = Color(1.0, 1.0, 1.0) # Normal bright
	
	var tween = create_tween()
	tween.tween_property(self, "global_position:y", global_position.y + 0.08, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
