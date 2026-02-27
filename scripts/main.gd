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

# ---- THEME COLORS (Dark Emerald + Gold) ----
const THEME_BG_DARK = Color(0.06, 0.09, 0.07, 0.88)       # Nền tối xanh rêu đậm
const THEME_BG_MEDIUM = Color(0.08, 0.14, 0.10, 0.92)      # Nền panel trung
const THEME_BORDER = Color(0.55, 0.75, 0.35, 0.6)          # Viền xanh lá nhạt
const THEME_GOLD = Color(1.0, 0.85, 0.25)                  # Vàng chính (pot, tiền)
const THEME_GOLD_DIM = Color(0.85, 0.70, 0.20)             # Vàng phụ
const THEME_TEXT = Color(0.88, 0.92, 0.85)                  # Chữ chính sáng
const THEME_TEXT_DIM = Color(0.55, 0.65, 0.50)              # Chữ phụ
const THEME_ACCENT = Color(0.30, 0.75, 0.40)                # Xanh lá accent
const THEME_BTN_BG = Color(0.10, 0.18, 0.12, 0.95)         # Nền nút
const THEME_BTN_BORDER_FOLD = Color(0.85, 0.30, 0.25)      # Viền nút Fold
const THEME_BTN_BORDER_CHECK = Color(0.35, 0.70, 0.85)     # Viền nút Check
const THEME_BTN_BORDER_RAISE = Color(0.90, 0.78, 0.20)     # Viền nút Raise
const THEME_BTN_BORDER_ALLIN = Color(0.80, 0.40, 0.90)     # Viền nút All-in

func _setup_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "GameUI"
	add_child(canvas)
	
	# ---- TOP BAR: Pot + State info ----
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.custom_minimum_size = Vector2(0, 50)
	
	var top_style = StyleBoxFlat.new()
	top_style.bg_color = THEME_BG_DARK
	top_style.content_margin_left = 20
	top_style.content_margin_right = 20
	top_style.content_margin_top = 6
	top_style.content_margin_bottom = 6
	top_style.border_width_bottom = 1
	top_style.border_color = THEME_BORDER
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
	pot_label.add_theme_color_override("font_color", THEME_GOLD)
	top_hbox.add_child(pot_label)
	
	# State label
	state_label = Label.new()
	state_label.text = "Chờ người chơi..."
	state_label.add_theme_font_size_override("font_size", 18)
	state_label.add_theme_color_override("font_color", THEME_TEXT)
	top_hbox.add_child(state_label)
	
	# Turn label
	turn_label = Label.new()
	turn_label.text = ""
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.add_theme_color_override("font_color", THEME_ACCENT)
	top_hbox.add_child(turn_label)
	
	# ---- BOTTOM BAR: Cards + Chips + Action buttons (tất cả trong 1 thanh) ----
	var bottom_panel = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.custom_minimum_size = Vector2(0, 80)
	bottom_panel.position.y = -80
	
	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = THEME_BG_DARK
	bottom_style.content_margin_left = 15
	bottom_style.content_margin_right = 15
	bottom_style.content_margin_top = 8
	bottom_style.content_margin_bottom = 8
	bottom_style.border_width_top = 1
	bottom_style.border_color = THEME_BORDER
	bottom_panel.add_theme_stylebox_override("panel", bottom_style)
	canvas.add_child(bottom_panel)
	
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 12)
	bottom_panel.add_child(bottom_hbox)
	
	# -- Bài 2D inline (bên trái thanh dưới) --
	var card_wrapper = PanelContainer.new()
	var card_wrapper_style = StyleBoxFlat.new()
	card_wrapper_style.bg_color = THEME_BG_MEDIUM
	card_wrapper_style.corner_radius_top_left = 6
	card_wrapper_style.corner_radius_top_right = 6
	card_wrapper_style.corner_radius_bottom_left = 6
	card_wrapper_style.corner_radius_bottom_right = 6
	card_wrapper_style.content_margin_left = 8
	card_wrapper_style.content_margin_right = 8
	card_wrapper_style.content_margin_top = 4
	card_wrapper_style.content_margin_bottom = 4
	card_wrapper_style.border_width_top = 1
	card_wrapper_style.border_width_bottom = 1
	card_wrapper_style.border_width_left = 1
	card_wrapper_style.border_width_right = 1
	card_wrapper_style.border_color = THEME_BORDER
	card_wrapper.add_theme_stylebox_override("panel", card_wrapper_style)
	card_wrapper.custom_minimum_size = Vector2(140, 60)
	bottom_hbox.add_child(card_wrapper)
	
	card_display = HBoxContainer.new()
	card_display.alignment = BoxContainer.ALIGNMENT_CENTER
	card_display.add_theme_constant_override("separation", 6)
	card_wrapper.add_child(card_display)
	
	# -- Separator --
	var sep1 = VSeparator.new()
	sep1.custom_minimum_size = Vector2(2, 40)
	sep1.modulate = THEME_BORDER
	bottom_hbox.add_child(sep1)
	
	# -- Chips label --
	chips_label = Label.new()
	chips_label.text = "CHIPS: $1500"
	chips_label.add_theme_font_size_override("font_size", 18)
	chips_label.add_theme_color_override("font_color", THEME_GOLD)
	chips_label.custom_minimum_size = Vector2(130, 0)
	bottom_hbox.add_child(chips_label)
	
	# -- Separator --
	var sep2 = VSeparator.new()
	sep2.custom_minimum_size = Vector2(2, 40)
	sep2.modulate = THEME_BORDER
	bottom_hbox.add_child(sep2)
	
	# Action buttons (cùng theme)
	btn_fold = _create_action_button("FOLD", THEME_BTN_BORDER_FOLD, "Fold")
	bottom_hbox.add_child(btn_fold)
	
	btn_call_check = _create_action_button("CHECK", THEME_BTN_BORDER_CHECK, "Call")
	bottom_hbox.add_child(btn_call_check)
	
	btn_raise = _create_action_button("RAISE", THEME_BTN_BORDER_RAISE, "Raise")
	bottom_hbox.add_child(btn_raise)
	
	raise_spinbox = SpinBox.new()
	raise_spinbox.custom_minimum_size = Vector2(90, 40)
	raise_spinbox.step = 10
	raise_spinbox.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb_theme = Theme.new()
	sb_theme.set_font_size("font_size", "LineEdit", 16)
	raise_spinbox.theme = sb_theme
	bottom_hbox.add_child(raise_spinbox)
	
	btn_all_in = _create_action_button("ALL-IN", THEME_BTN_BORDER_ALLIN, "AllIn")
	bottom_hbox.add_child(btn_all_in)

func _add_action_button(parent: HBoxContainer, text: String, color: Color, action: String) -> void:
	var btn = _create_action_button(text, color, action)
	parent.add_child(btn)

func _create_action_button(text: String, accent_color: Color, action: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 40)
	
	# Normal: nền tối + viền accent
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = THEME_BTN_BG
	style_normal.corner_radius_top_left = 5
	style_normal.corner_radius_top_right = 5
	style_normal.corner_radius_bottom_left = 5
	style_normal.corner_radius_bottom_right = 5
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_color = accent_color
	btn.add_theme_stylebox_override("normal", style_normal)
	
	# Hover: nền sáng hơn một tí
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = THEME_BTN_BG.lightened(0.15)
	style_hover.corner_radius_top_left = 5
	style_hover.corner_radius_top_right = 5
	style_hover.corner_radius_bottom_left = 5
	style_hover.corner_radius_bottom_right = 5
	style_hover.border_width_top = 2
	style_hover.border_width_bottom = 2
	style_hover.border_width_left = 2
	style_hover.border_width_right = 2
	style_hover.border_color = accent_color.lightened(0.2)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	# Pressed: nền accent đậm
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = accent_color.darkened(0.5)
	style_pressed.corner_radius_top_left = 5
	style_pressed.corner_radius_top_right = 5
	style_pressed.corner_radius_bottom_left = 5
	style_pressed.corner_radius_bottom_right = 5
	style_pressed.border_width_top = 2
	style_pressed.border_width_bottom = 2
	style_pressed.border_width_left = 2
	style_pressed.border_width_right = 2
	style_pressed.border_color = accent_color
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", accent_color.lightened(0.3))
	
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
	
	# Tạo TextureRect hiển thị lá bài (nhỏ gọn vừa thanh dưới)
	var tex_rect = TextureRect.new()
	tex_rect.texture = CardTextureGenerator.get_card_texture(card)
	tex_rect.custom_minimum_size = Vector2(42, 58)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	card_display.add_child(tex_rect)

func _clear_card_display() -> void:
	if not card_display:
		return
	for child in card_display.get_children():
		child.queue_free()
