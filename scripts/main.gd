extends Node3D

class_name MainScene

# Script này là gốc (Root) của game.

var pot_label: Label
var chips_label: Label
var state_label: Label
var turn_label: Label
var btn_fold: Button
var btn_call_check: Button
var btn_raise: Button
var btn_all_in: Button
var raise_spinbox: SpinBox
var card_display: HBoxContainer  # 2D card display for human

func _ready() -> void:
	print("Poker Godot 3D - Bắt đầu khởi tạo...")
	
	# 1. Khởi tạo và thêm TableBuilder (Xây dựng môi trường 3D)
	var table_builder = TableBuilder.new()
	table_builder.name = "TableBuilder"
	add_child(table_builder)
	
	# 2. Khởi tạo và thêm PhysicalManager (Quản lý các mảnh ghép Bài, Chip)
	var physical_manager = PhysicalManager.new()
	physical_manager.name = "PhysicalManager"
	add_child(physical_manager)
	
	# 3. Tạo UI đơn giản để Human tương tác
	_setup_ui()
	
	# 4. Kết nối signal để cập nhật UI
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		gm.state_changed.connect(_on_state_changed)
		gm.action_received.connect(_on_action_received)
		gm.player_turn_started.connect(_on_player_turn)
		gm.community_cards_changed.connect(_on_community_changed)
	
	# 5. Kết nối signal card_drawn của human player (chờ 1 frame)
	await get_tree().process_frame
	if gm:
		for p in gm.players:
			if !p.is_ai:
				p.card_drawn.connect(_on_human_card_drawn)
				break

func _setup_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "GameUI"
	add_child(canvas)
	
	# ---- TOP BAR: Pot + State info ----
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.custom_minimum_size = Vector2(0, 60)
	
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = Color(0, 0, 0, 0.6)
	top_style.content_margin_left = 20
	top_style.content_margin_right = 20
	top_style.content_margin_top = 8
	top_style.content_margin_bottom = 8
	top_panel.add_theme_stylebox_override("panel", top_style)
	canvas.add_child(top_panel)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_theme_constant_override("separation", 40)
	top_panel.add_child(top_hbox)
	
	# Pot label
	pot_label = Label.new()
	pot_label.text = "POT: $0"
	pot_label.add_theme_font_size_override("font_size", 22)
	pot_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	top_hbox.add_child(pot_label)
	
	# State label
	state_label = Label.new()
	state_label.text = "Chờ người chơi..."
	state_label.add_theme_font_size_override("font_size", 18)
	state_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	top_hbox.add_child(state_label)
	
	# Turn label
	turn_label = Label.new()
	turn_label.text = ""
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	top_hbox.add_child(turn_label)
	
	# ---- BOTTOM BAR: Chips + Action buttons ----
	var bottom_panel = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.custom_minimum_size = Vector2(0, 70)
	# Đặt position.y để nằm sát đáy
	bottom_panel.position.y = -70
	
	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = Color(0, 0, 0, 0.7)
	bottom_style.content_margin_left = 20
	bottom_style.content_margin_right = 20
	bottom_style.content_margin_top = 10
	bottom_style.content_margin_bottom = 10
	bottom_panel.add_theme_stylebox_override("panel", bottom_style)
	canvas.add_child(bottom_panel)
	
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 15)
	bottom_panel.add_child(bottom_hbox)
	
	# Chips label bên trái
	chips_label = Label.new()
	chips_label.text = "CHIPS: $1500"
	chips_label.add_theme_font_size_override("font_size", 20)
	chips_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	chips_label.custom_minimum_size = Vector2(150, 0)
	bottom_hbox.add_child(chips_label)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(30, 0)
	bottom_hbox.add_child(spacer)
	
	# Action buttons
	btn_fold = _create_action_button("FOLD", Color(0.8, 0.2, 0.2), "Fold")
	bottom_hbox.add_child(btn_fold)
	
	btn_call_check = _create_action_button("CHECK", Color(0.2, 0.6, 0.8), "Call")
	bottom_hbox.add_child(btn_call_check)
	
	btn_raise = _create_action_button("RAISE", Color(0.8, 0.7, 0.1), "Raise")
	bottom_hbox.add_child(btn_raise)
	
	raise_spinbox = SpinBox.new()
	raise_spinbox.custom_minimum_size = Vector2(100, 45)
	raise_spinbox.step = 10
	raise_spinbox.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb_theme = Theme.new()
	sb_theme.set_font_size("font_size", "LineEdit", 18)
	raise_spinbox.theme = sb_theme
	bottom_hbox.add_child(raise_spinbox)
	
	btn_all_in = _create_action_button("ALL-IN", Color(0.7, 0.2, 0.9), "AllIn")
	bottom_hbox.add_child(btn_all_in)
	
	# ---- CARD DISPLAY: Hiển thị bài của human 2D (góc trái-dưới) ----
	var card_panel = PanelContainer.new()
	card_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card_panel.position = Vector2(15, -200)
	card_panel.custom_minimum_size = Vector2(220, 160)
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.05, 0.08, 0.15, 0.85)
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_left = 10
	card_style.corner_radius_bottom_right = 10
	card_style.content_margin_left = 12
	card_style.content_margin_right = 12
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card_style.border_width_top = 2
	card_style.border_width_bottom = 2
	card_style.border_width_left = 2
	card_style.border_width_right = 2
	card_style.border_color = Color(0.4, 0.6, 0.9, 0.5)
	card_panel.add_theme_stylebox_override("panel", card_style)
	canvas.add_child(card_panel)
	
	var card_vbox = VBoxContainer.new()
	card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_panel.add_child(card_vbox)
	
	var card_title = Label.new()
	card_title.text = "YOUR CARDS"
	card_title.add_theme_font_size_override("font_size", 14)
	card_title.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_vbox.add_child(card_title)
	
	card_display = HBoxContainer.new()
	card_display.alignment = BoxContainer.ALIGNMENT_CENTER
	card_display.add_theme_constant_override("separation", 8)
	card_vbox.add_child(card_display)

func _add_action_button(parent: HBoxContainer, text: String, color: Color, action: String) -> void:
	var btn = _create_action_button(text, color, action)
	parent.add_child(btn)

func _create_action_button(text: String, color: Color, action: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(120, 45)
	
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = color
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style_normal)
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = color.lightened(0.2)
	style_hover.corner_radius_top_left = 6
	style_hover.corner_radius_top_right = 6
	style_hover.corner_radius_bottom_left = 6
	style_hover.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("hover", style_hover)
	
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = color.darkened(0.2)
	style_pressed.corner_radius_top_left = 6
	style_pressed.corner_radius_top_right = 6
	style_pressed.corner_radius_bottom_left = 6
	style_pressed.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", Color.WHITE)
	
	btn.pressed.connect(func(): _on_ui_action_pressed(action))
	return btn

func _on_ui_action_pressed(action_type: String) -> void:
	# Lấy node Human
	var game_manager = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if !game_manager: return
	
	var human = null
	for p in game_manager.players:
		if !p.is_ai:
			human = p
			break
			
	if !human: return
	
	print("Human chọn: ", action_type)
	
	match action_type:
		"Fold": human.receive_ui_input(GameManager.PlayerAction.FOLD, 0)
		"Call": human.receive_ui_input(GameManager.PlayerAction.CALL, 0)
		"Raise": human.receive_ui_input(GameManager.PlayerAction.RAISE, int(raise_spinbox.value))
		"AllIn": human.receive_ui_input(GameManager.PlayerAction.ALL_IN, human.chips)
		
	# Bấm xong là disable luôn tới turn tiếp theo
	_set_action_buttons_disabled(true)

func _set_action_buttons_disabled(disabled: bool) -> void:
	if btn_fold: btn_fold.disabled = disabled
	if btn_call_check: btn_call_check.disabled = disabled
	if btn_raise: btn_raise.disabled = disabled
	if btn_all_in: btn_all_in.disabled = disabled
	if raise_spinbox: raise_spinbox.editable = !disabled

# ---- UI UPDATE CALLBACKS ----

func _on_state_changed(new_state: int, _old_state: int) -> void:
	if not state_label:
		return
	
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	
	match new_state:
		GameManager.GameState.WAITING_FOR_PLAYERS:
			state_label.text = "Đang chuẩn bị..."
		GameManager.GameState.DEALING_HOLE_CARDS:
			state_label.text = "Chia bài..."
			_clear_card_display()
		GameManager.GameState.PREFLOP_BETTING:
			state_label.text = "Pre-Flop"
		GameManager.GameState.DEALING_FLOP:
			state_label.text = "Lật Flop..."
		GameManager.GameState.FLOP_BETTING:
			state_label.text = "Flop"
		GameManager.GameState.DEALING_TURN:
			state_label.text = "Lật Turn..."
		GameManager.GameState.TURN_BETTING:
			state_label.text = "Turn"
		GameManager.GameState.DEALING_RIVER:
			state_label.text = "Lật River..."
		GameManager.GameState.RIVER_BETTING:
			state_label.text = "River"
		GameManager.GameState.SHOWDOWN:
			state_label.text = "Showdown!"
		GameManager.GameState.DISTRIBUTING_POTS:
			state_label.text = "Chia tiền..."
		GameManager.GameState.ROUND_END:
			state_label.text = "Kết thúc ván"
			
	# Update trạng thái disable của nút khi chuyển state mới mà không phải lượt đánh	
	_set_action_buttons_disabled(true)
	
	# Cập nhật pot
	if gm and pot_label:
		pot_label.text = "POT: $" + str(gm.pot_manager.get_total_pot())
	
	# Cập nhật chips human
	_update_chips_label()

func _on_action_received(_player_id: String, _action: int, _amount: int) -> void:
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm and pot_label:
		pot_label.text = "POT: $" + str(gm.pot_manager.get_total_pot())
	_update_chips_label()

func _on_player_turn(player_id: String) -> void:
	if not turn_label:
		return
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		var p = gm._get_player_by_id(player_id)
		if p:
			if p.is_ai:
				turn_label.text = "Lượt: " + p.id + " (đang nghĩ...)"
				turn_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			else:
				turn_label.text = ">>> LƯỢT CỦA BẠN <<<"
				turn_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
				
				# Mở khóa các nút
				_set_action_buttons_disabled(false)
				
				# Cập nhật nút Call/Check
				var amount_to_call = gm.current_bet - p.current_bet
				if btn_call_check:
					if amount_to_call > 0:
						btn_call_check.text = "CALL $" + str(amount_to_call)
					else:
						btn_call_check.text = "CHECK"
				
				# Cập nhật nút Raise và SpinBox
				if btn_raise and raise_spinbox:
					var min_r = gm.current_bet + gm.min_raise
					# Nếu tiền mình có không đủ min_raise thì cap lại ở max
					raise_spinbox.max_value = p.chips + p.current_bet
					raise_spinbox.min_value = min(min_r, raise_spinbox.max_value)
					raise_spinbox.value = raise_spinbox.min_value
					btn_raise.text = "RAISE"

func _on_community_changed(_cards: Array) -> void:
	_update_chips_label()

func _update_chips_label() -> void:
	if not chips_label:
		return
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		for p in gm.players:
			if !p.is_ai:
				chips_label.text = "CHIPS: $" + str(p.chips)
				break

func _on_human_card_drawn(card: Card) -> void:
	if not card_display:
		return
	
	# Tạo TextureRect hiển thị lá bài
	var tex_rect = TextureRect.new()
	tex_rect.texture = CardTextureGenerator.get_card_texture(card)
	tex_rect.custom_minimum_size = Vector2(90, 130)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	card_display.add_child(tex_rect)

func _clear_card_display() -> void:
	if not card_display:
		return
	for child in card_display.get_children():
		child.queue_free()
