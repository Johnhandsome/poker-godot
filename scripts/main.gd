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
var raise_slider: HSlider
var raise_value_label: Label
var card_display: HBoxContainer  # 2D card display for human

func _ready() -> void:
	print("Poker Godot 3D - Bắt đầu khởi tạo...")
	
	# Khởi tạo âm thanh nền (Ambience)
	var ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = preload("res://assets/audio/freesound_community-poker-room-33521.mp3")
	ambient_player.volume_db = -8.0
	ambient_player.finished.connect(func(): ambient_player.play())
	add_child(ambient_player)
	ambient_player.play()
	
	# Đặt lại hệ thống nếu đây là lần chơi mới từ Main Menu
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		gm.players.clear()
		gm.active_players.clear()
		gm.community_cards.clear()
	
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
	gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		gm.state_changed.connect(_on_state_changed)
		gm.action_received.connect(_on_action_received)
		gm.player_turn_started.connect(_on_player_turn)
		gm.community_cards_changed.connect(_on_community_changed)
		gm.winners_declared.connect(func(_p, _b): _update_chips_label())
		gm.game_over.connect(_on_game_over)
	
	# 5. Kết nối signal card_drawn của human player (chờ 1 frame)
	await get_tree().process_frame
	if gm:
		for p in gm.players:
			if !p.is_ai:
				p.card_drawn.connect(_on_human_card_drawn)
				break

var dealer_btn: MeshInstance3D

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
	# Khởi tạo UI
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
	
	# Spacer để đẩy Menu sang phải
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer)
	
	# Menu/Pause button
	var btn_pause = Button.new()
	btn_pause.text = " MENU ⚙️ "
	btn_pause.custom_minimum_size = Vector2(100, 36)
	btn_pause.add_theme_font_size_override("font_size", 16)
	var pause_style = StyleBoxFlat.new()
	pause_style.bg_color = THEME_BG_DARK
	pause_style.border_width_all = 1
	pause_style.border_color = THEME_TEXT
	pause_style.corner_radius_top_left = 6
	pause_style.corner_radius_top_right = 6
	pause_style.corner_radius_bottom_left = 6
	pause_style.corner_radius_bottom_right = 6
	btn_pause.add_theme_stylebox_override("normal", pause_style)
	btn_pause.pressed.connect(_show_pause_menu)
	top_hbox.add_child(btn_pause)
	
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
	
	# Raise slider + giá trị hiển thị
	var raise_container = VBoxContainer.new()
	raise_container.custom_minimum_size = Vector2(180, 50)
	raise_container.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_child(raise_container)
	
	raise_value_label = Label.new()
	raise_value_label.text = "$40"
	raise_value_label.add_theme_font_size_override("font_size", 14)
	raise_value_label.add_theme_color_override("font_color", THEME_GOLD)
	raise_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raise_container.add_child(raise_value_label)
	
	raise_slider = HSlider.new()
	raise_slider.custom_minimum_size = Vector2(180, 20)
	raise_slider.step = 10
	raise_slider.min_value = 40
	raise_slider.max_value = 1500
	raise_slider.value = 40
	raise_slider.value_changed.connect(_on_raise_slider_changed)
	raise_slider.value_changed.connect(func(_val): _play_ui_sound())
	raise_container.add_child(raise_slider)
	
	btn_all_in = _create_action_button("ALL-IN", THEME_BTN_BORDER_ALLIN, "AllIn")
	bottom_hbox.add_child(btn_all_in)

func _add_action_button(parent: HBoxContainer, text: String, color: Color, action: String) -> void:
	var btn = _create_action_button(text, color, action)
	parent.add_child(btn)

func _create_action_button(text: String, accent_color: Color, action: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(115, 46)
	
	# Normal: nền tối sang trọng, viền dưới accent nổi bật
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.10, 0.09, 0.95)
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 3  # Viền dưới dày — điểm nhấn
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_color = accent_color.darkened(0.2)
	style_normal.shadow_color = Color(0, 0, 0, 0.3)
	style_normal.shadow_size = 2
	style_normal.shadow_offset = Vector2(0, 1)
	btn.add_theme_stylebox_override("normal", style_normal)
	
	# Hover: sáng lên thanh lịch
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = Color(0.12, 0.16, 0.13, 0.98)
	style_hover.corner_radius_top_left = 8
	style_hover.corner_radius_top_right = 8
	style_hover.corner_radius_bottom_left = 8
	style_hover.corner_radius_bottom_right = 8
	style_hover.border_width_top = 1
	style_hover.border_width_bottom = 3
	style_hover.border_width_left = 1
	style_hover.border_width_right = 1
	style_hover.border_color = accent_color
	style_hover.shadow_color = Color(0, 0, 0, 0.4)
	style_hover.shadow_size = 3
	style_hover.shadow_offset = Vector2(0, 2)
	btn.add_theme_stylebox_override("hover", style_hover)
	
	# Pressed: chìm xuống
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = accent_color.darkened(0.6)
	style_pressed.corner_radius_top_left = 8
	style_pressed.corner_radius_top_right = 8
	style_pressed.corner_radius_bottom_left = 8
	style_pressed.corner_radius_bottom_right = 8
	style_pressed.border_width_top = 2
	style_pressed.border_width_bottom = 1  # Ngược lại — tạo hiệu ứng nhấn
	style_pressed.border_width_left = 1
	style_pressed.border_width_right = 1
	style_pressed.border_color = accent_color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_font_size_override("font_size", 16)
	# Text màu kem sang trọng, không chói
	btn.add_theme_color_override("font_color", Color(0.92, 0.88, 0.80))
	
	btn.pressed.connect(func():
		_play_ui_sound()
		_on_ui_action_pressed(action)
	)
	return btn

func _play_ui_sound() -> void:
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth:
		synth.play_ui_click()

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
		"Call":
			# Phân biệt CHECK vs CALL dựa trên amount_to_call
			var amount_to_call = game_manager.current_bet - human.current_bet
			if amount_to_call > 0:
				human.receive_ui_input(GameManager.PlayerAction.CALL, 0)
			else:
				human.receive_ui_input(GameManager.PlayerAction.CHECK, 0)
		"Raise": human.receive_ui_input(GameManager.PlayerAction.RAISE, int(raise_slider.value))
		"AllIn": human.receive_ui_input(GameManager.PlayerAction.ALL_IN, human.chips)
		
	# Bấm xong là disable luôn tới turn tiếp theo
	_set_action_buttons_disabled(true)

func _set_action_buttons_disabled(disabled: bool) -> void:
	if btn_fold: btn_fold.disabled = disabled
	if btn_call_check: btn_call_check.disabled = disabled
	if btn_raise: btn_raise.disabled = disabled
	if btn_all_in: btn_all_in.disabled = disabled
	if raise_slider: raise_slider.editable = !disabled

func _on_raise_slider_changed(value: float) -> void:
	if raise_value_label:
		raise_value_label.text = "$" + str(int(value))

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
				
				# Cập nhật Raise slider
				if btn_raise and raise_slider:
					var min_r = gm.current_bet + gm.min_raise
					raise_slider.max_value = p.chips + p.current_bet
					raise_slider.min_value = min(min_r, raise_slider.max_value)
					raise_slider.step = gm.big_blind # Stepping theo BB cho tròn số
					raise_slider.value = raise_slider.min_value
					btn_raise.text = "RAISE"
					if raise_value_label:
						raise_value_label.text = "$" + str(int(raise_slider.value))

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

func _on_game_over(human_won: bool) -> void:
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if human_won and synth:
		synth.play_win()

	var popup_bg = ColorRect.new()
	popup_bg.color = Color(0, 0, 0, 0.85)
	popup_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(popup_bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	popup_bg.add_child(vbox)
	
	var lbl = Label.new()
	lbl.text = "YOU WIN!\nCHAMPION" if human_won else "BANKRUPT\nGAME OVER"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 64)
	lbl.add_theme_color_override("font_color", THEME_GOLD if human_won else Color(1.0, 0.3, 0.3))
	vbox.add_child(lbl)
	
	var btn = Button.new()
	btn.text = "Main Menu"
	btn.custom_minimum_size = Vector2(250, 60)
	btn.add_theme_font_size_override("font_size", 24)
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG_DARK
	style.border_width_bottom = 4
	style.border_color = THEME_GOLD
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", style)
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	vbox.add_child(btn)

# ---- PAUSE MENU & SETTINGS ----
func _show_pause_menu() -> void:
	_play_ui_sound()
	if has_node("PauseOverlay"): return
	
	var overlay = ColorRect.new()
	overlay.name = "PauseOverlay"
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	overlay.add_child(vbox)
	
	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", THEME_GOLD)
	vbox.add_child(title)
	
	var btn_resume = _create_menu_button("RESUME")
	btn_resume.pressed.connect(func():
		_play_ui_sound()
		overlay.queue_free()
	)
	vbox.add_child(btn_resume)
	
	var btn_settings = _create_menu_button("SETTINGS")
	btn_settings.pressed.connect(func():
		_play_ui_sound()
		_show_settings_panel()
	)
	vbox.add_child(btn_settings)
	
	var btn_quit = _create_menu_button("QUIT TO MENU")
	btn_quit.pressed.connect(func():
		_play_ui_sound()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	vbox.add_child(btn_quit)
	
	add_child(overlay)

func _create_menu_button(text_str: String) -> Button:
	var btn = Button.new()
	btn.text = text_str
	btn.custom_minimum_size = Vector2(250, 50)
	btn.add_theme_font_size_override("font_size", 20)
	var style = StyleBoxFlat.new()
	style.bg_color = THEME_BG_DARK
	style.border_width_bottom = 3
	style.border_color = THEME_GOLD
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal", style)
	return btn

# Tái sử dụng code SettingsPanel từ MainMenu
func _show_settings_panel() -> void:
	if has_node("SettingsPanel"): return
	
	var panel = PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(500, 400)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_all = 2
	style.border_color = Color(0.4, 0.6, 1.0, 0.5)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	
	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	
	var master_box = HBoxContainer.new()
	master_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var master_lbl = Label.new()
	master_lbl.text = "Master Vol:"
	master_lbl.custom_minimum_size = Vector2(120, 0)
	var master_slider = HSlider.new()
	master_slider.custom_minimum_size = Vector2(200, 30)
	master_slider.max_value = 1.0
	master_slider.step = 0.05
	if sm: master_slider.value = sm.master_volume
	master_box.add_child(master_lbl)
	master_box.add_child(master_slider)
	vbox.add_child(master_box)
	
	var sfx_box = HBoxContainer.new()
	sfx_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var sfx_lbl = Label.new()
	sfx_lbl.text = "SFX Vol:"
	sfx_lbl.custom_minimum_size = Vector2(120, 0)
	var sfx_slider = HSlider.new()
	sfx_slider.custom_minimum_size = Vector2(200, 30)
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	if sm: sfx_slider.value = sm.sfx_volume
	sfx_box.add_child(sfx_lbl)
	sfx_box.add_child(sfx_slider)
	vbox.add_child(sfx_box)
	
	var bgm_box = HBoxContainer.new()
	bgm_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var bgm_lbl = Label.new()
	bgm_lbl.text = "Music Vol:"
	bgm_lbl.custom_minimum_size = Vector2(120, 0)
	var bgm_slider = HSlider.new()
	bgm_slider.custom_minimum_size = Vector2(200, 30)
	bgm_slider.max_value = 1.0
	bgm_slider.step = 0.05
	if sm: bgm_slider.value = sm.bgm_volume
	bgm_box.add_child(bgm_lbl)
	bgm_box.add_child(bgm_slider)
	vbox.add_child(bgm_box)
	
	var fast_box = HBoxContainer.new()
	fast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var fast_lbl = Label.new()
	fast_lbl.text = "Fast Bot Mode:"
	fast_lbl.custom_minimum_size = Vector2(120, 0)
	var fast_check = CheckBox.new()
	fast_check.text = "Skip Thinking Delays"
	if sm: fast_check.button_pressed = sm.fast_bot_mode
	fast_box.add_child(fast_lbl)
	fast_box.add_child(fast_check)
	vbox.add_child(fast_box)
	
	if sm:
		var update_audio = func():
			sm.master_volume = master_slider.value
			sm.sfx_volume = sfx_slider.value
			sm.bgm_volume = bgm_slider.value
			sm.apply_and_save()
			
			var target_linear = sm.master_volume * sm.bgm_volume
			if target_linear <= 0.01:
				for child in get_children():
					if child is AudioStreamPlayer:
						child.volume_db = -80.0
			else:
				var db = linear_to_db(target_linear)
				for child in get_children():
					if child is AudioStreamPlayer:
						child.volume_db = db
				
		master_slider.value_changed.connect(func(_val): update_audio.call())
		sfx_slider.value_changed.connect(func(_val): update_audio.call())
		bgm_slider.value_changed.connect(func(_val): update_audio.call())
		
		fast_check.toggled.connect(func(pressed):
			sm.fast_bot_mode = pressed
			sm.apply_and_save()
		)
	
	var btn_close = Button.new()
	btn_close.text = "CLOSE"
	btn_close.custom_minimum_size = Vector2(200, 50)
	var btn_box = CenterContainer.new()
	btn_box.add_child(btn_close)
	vbox.add_child(btn_box)
	
	btn_close.pressed.connect(func():
		_play_ui_sound()
		panel.queue_free()
	)
	
	add_child(panel)
