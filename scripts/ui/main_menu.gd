extends Control

# =================================================================
# MAIN MENU — Polished production UI with PokerTheme
# =================================================================

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Casino ambient sound
	var ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = preload("res://assets/audio/freesound_community-poker-room-33521.mp3")
	ambient_player.volume_db = -5.0
	ambient_player.finished.connect(func(): ambient_player.play())
	add_child(ambient_player)
	ambient_player.play()

	# Dark background
	var bg = ColorRect.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.02, 0.02, 0.04, 1.0)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Center glow
	var glow = ColorRect.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	void fragment() {
		vec2 uv = UV - vec2(0.5);
		float dist = length(uv);
		float alpha = smoothstep(0.6, 0.1, dist);
		COLOR = vec4(0.05, 0.10, 0.18, alpha * 0.8);
	}
	"""
	mat.shader = shader
	glow.material = mat

	_spawn_floating_cards()

	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	center.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "TEXAS HOLD'EM\nGODOT POKER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", PokerTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", PokerTheme.GOLD)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 4)
	vbox.add_child(title)
	# Title entrance animation
	title.modulate.a = 0.0; title.scale = Vector2(0.85, 0.85)
	title.pivot_offset = Vector2(300, 50)
	var tw_title = create_tween().set_parallel(true)
	tw_title.tween_property(title, "modulate:a", 1.0, 0.4).set_delay(0.1)
	tw_title.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.1)

	# Bankroll display
	var current_chips = 5000
	var save_mgr = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
	if save_mgr:
		current_chips = save_mgr.get_chips()
	var bankroll_lbl = Label.new()
	bankroll_lbl.text = "BANKROLL: $" + str(current_chips)
	bankroll_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bankroll_lbl.add_theme_font_size_override("font_size", PokerTheme.FONT_SUBTITLE)
	bankroll_lbl.add_theme_color_override("font_color", PokerTheme.ACCENT_GREEN if current_chips > 0 else PokerTheme.ACCENT_RED)
	vbox.add_child(bankroll_lbl)

	# PLAY button
	var play_text = _tc("PLAY GAME", "CHƠI TIẾP") if current_chips > 0 else _tc("RESTART ($5000)", "CHƠI LẠI ($5000)")
	var btn_play = PokerTheme.make_menu_button(play_text, PokerTheme.GOLD, Vector2(320, 70))
	btn_play.add_theme_font_size_override("font_size", 30)
	btn_play.pressed.connect(func():
		_play_ui_sound()
		var sm = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
		if sm and sm.get_chips() <= 0:
			sm.reset_save()
		_fade_to_scene("res://scenes/main.tscn")
	)
	PokerTheme.attach_hover_anim(btn_play, self)
	vbox.add_child(btn_play)

	# MULTIPLAYER button
	var btn_multi = PokerTheme.make_menu_button(_tc("MULTIPLAYER", "CHƠI ONLINE"), PokerTheme.ACCENT_BLUE)
	btn_multi.pressed.connect(func(): _play_ui_sound(); _show_multiplayer_panel())
	PokerTheme.attach_hover_anim(btn_multi, self)
	vbox.add_child(btn_multi)

	# SETTINGS button
	var btn_settings = PokerTheme.make_menu_button(_tc("SETTINGS", "CÀI ĐẶT"), PokerTheme.TEXT_SECONDARY)
	btn_settings.pressed.connect(func(): _play_ui_sound(); _show_settings_panel())
	PokerTheme.attach_hover_anim(btn_settings, self)
	vbox.add_child(btn_settings)

	# QUIT button
	if not OS.has_feature("web"):
		var btn_quit = PokerTheme.make_menu_button(_tc("QUIT", "THOÁT"), PokerTheme.ACCENT_RED)
		btn_quit.pressed.connect(func(): _play_ui_sound(); get_tree().quit())
		PokerTheme.attach_hover_anim(btn_quit, self)
		vbox.add_child(btn_quit)

	# Stagger button entrance
	var delay = 0.15
	for i in range(vbox.get_child_count()):
		var child = vbox.get_child(i)
		if child is Button:
			child.modulate.a = 0.0
			child.position.x += 40
			var tw_btn = create_tween().set_parallel(true)
			tw_btn.tween_property(child, "modulate:a", 1.0, 0.25).set_delay(delay)
			tw_btn.tween_property(child, "position:x", child.position.x - 40, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(delay)
			delay += 0.08

	# Version tag
	var ver = Label.new()
	ver.text = "v1.0"
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", PokerTheme.TEXT_MUTED)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.offset_right = -10; ver.offset_bottom = -6
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(ver)

# ============================================================
# SCENE TRANSITIONS
# ============================================================
func _fade_to_scene(scene_path: String) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var tw = create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 0.3)
	tw.tween_callback(func(): get_tree().change_scene_to_file(scene_path))

# ============================================================
# SETTINGS PANEL
# ============================================================
func _show_settings_panel() -> void:
	if has_node("SettingsPanel"): return

	var overlay = CenterContainer.new()
	overlay.name = "SettingsPanel"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dim background
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var tw_dim = create_tween()
	tw_dim.tween_property(dim, "color:a", 0.5, 0.15)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 480)
	var style = PokerTheme.make_panel_style(Color(0.08, 0.08, 0.12, 0.97), PokerTheme.ACCENT_BLUE.darkened(0.4), PokerTheme.CORNER_LG, 2, 22)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = _tc("SETTINGS", "CÀI ĐẶT")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", PokerTheme.TEXT_PRIMARY)
	vbox.add_child(title)

	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	var master_slider = _add_slider_row(vbox, _tc("Master Vol:", "Tổng:"), 0.0, 1.0, 0.05, sm.master_volume if sm else 1.0)
	var sfx_slider = _add_slider_row(vbox, _tc("SFX Vol:", "Hiệu ứng:"), 0.0, 1.0, 0.05, sm.sfx_volume if sm else 1.0)
	var bgm_slider = _add_slider_row(vbox, _tc("Music Vol:", "Nhạc:"), 0.0, 1.0, 0.05, sm.bgm_volume if sm else 0.5)

	# Fast Bot
	var fast_box = HBoxContainer.new()
	fast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var fast_lbl = Label.new()
	fast_lbl.text = _tc("Bot Speed:", "Tốc độ Bot:")
	fast_lbl.custom_minimum_size = Vector2(140, 0)
	fast_lbl.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var check_fast = CheckButton.new()
	check_fast.text = _tc("Skip Delays", "Bỏ Chờ")
	check_fast.focus_mode = Control.FOCUS_NONE
	if sm: check_fast.button_pressed = sm.fast_bot_mode
	fast_box.add_child(fast_lbl); fast_box.add_child(check_fast)
	vbox.add_child(fast_box)

	# Bot Count
	var bot_lbl_ref: Label
	var bot_box = HBoxContainer.new()
	bot_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_lbl_ref = Label.new()
	bot_lbl_ref.text = _tc("Opponents: ", "Đối thủ: ") + str(sm.num_bots if sm else 4)
	bot_lbl_ref.custom_minimum_size = Vector2(140, 0)
	bot_lbl_ref.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var bot_slider = HSlider.new()
	bot_slider.custom_minimum_size = Vector2(200, 28)
	bot_slider.min_value = 1; bot_slider.max_value = 8; bot_slider.step = 1
	bot_slider.focus_mode = Control.FOCUS_NONE
	if sm: bot_slider.value = sm.num_bots
	bot_box.add_child(bot_lbl_ref); bot_box.add_child(bot_slider)
	vbox.add_child(bot_box)

	# Language
	var lang_box = HBoxContainer.new()
	lang_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var lang_lbl = Label.new()
	lang_lbl.text = _tc("Language:", "Ngôn ngữ:")
	lang_lbl.custom_minimum_size = Vector2(140, 0)
	lang_lbl.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var lang_btn = OptionButton.new()
	lang_btn.add_item("English"); lang_btn.add_item("Tiếng Việt")
	lang_btn.focus_mode = Control.FOCUS_NONE
	if sm:
		lang_btn.selected = 1 if sm.language == "vi" else 0
		lang_btn.item_selected.connect(func(idx):
			var new_lang = "vi" if idx == 1 else "en"
			if sm.language != new_lang:
				sm.language = new_lang; sm.save_settings()
				get_tree().reload_current_scene()
		)
	lang_box.add_child(lang_lbl); lang_box.add_child(lang_btn)
	vbox.add_child(lang_box)

	# Wiring
	if sm:
		var update_audio = func():
			sm.master_volume = master_slider.value
			sm.sfx_volume = sfx_slider.value
			sm.bgm_volume = bgm_slider.value
			sm.apply_and_save()
			var target_linear = sm.master_volume * sm.bgm_volume
			for child in get_children():
				if child is AudioStreamPlayer:
					child.volume_db = -80.0 if target_linear <= 0.01 else linear_to_db(target_linear)
		master_slider.value_changed.connect(func(_v): update_audio.call())
		sfx_slider.value_changed.connect(func(_v): update_audio.call())
		bgm_slider.value_changed.connect(func(_v): update_audio.call())
		check_fast.toggled.connect(func(p): sm.fast_bot_mode = p; sm.apply_and_save())
		bot_slider.value_changed.connect(func(v):
			sm.num_bots = int(v)
			bot_lbl_ref.text = _tc("Opponents: ", "Đối thủ: ") + str(sm.num_bots)
			sm.apply_and_save()
		)

	var btn_close = PokerTheme.make_menu_button(_tc("SAVE & CLOSE", "LƯU & ĐÓNG"), PokerTheme.ACCENT_GREEN, Vector2(220, 44))
	btn_close.pressed.connect(func(): _play_ui_sound(); overlay.queue_free())
	var btn_box = CenterContainer.new()
	btn_box.add_child(btn_close)
	vbox.add_child(btn_box)

	overlay.add_child(panel)
	add_child(overlay)
	if sm: master_slider.value_changed.emit(master_slider.value)
	PokerTheme.popup_animate(panel, self)

# ============================================================
# MULTIPLAYER LOBBY — Production Quality
# ============================================================
func _show_multiplayer_panel() -> void:
	if has_node("MultiplayerPanel"): return

	var overlay = CenterContainer.new()
	overlay.name = "MultiplayerPanel"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Dim background
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var tw_dim = create_tween()
	tw_dim.tween_property(dim, "color:a", 0.6, 0.15)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 550)
	var style = PokerTheme.make_panel_style(Color(0.06, 0.08, 0.14, 0.97), PokerTheme.ACCENT_BLUE.darkened(0.3), PokerTheme.CORNER_LG, 2, 22)
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = _tc("MULTIPLAYER LOBBY", "PHÒNG CHƠI ONLINE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", PokerTheme.ACCENT_BLUE)
	vbox.add_child(title)

	# Name input
	var name_hbox = HBoxContainer.new()
	name_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	name_hbox.add_theme_constant_override("separation", 10)
	var name_lbl = Label.new()
	name_lbl.text = _tc("Your Name:", "Tên:")
	name_lbl.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var name_edit = LineEdit.new()
	name_edit.text = "Player" + str(randi() % 1000)
	name_edit.custom_minimum_size = Vector2(200, 34)
	name_edit.add_theme_font_size_override("font_size", 16)
	var ne_style = PokerTheme.make_panel_style(PokerTheme.BG_MEDIUM, PokerTheme.BORDER_SUBTLE, PokerTheme.CORNER_SM, 1, 8)
	name_edit.add_theme_stylebox_override("normal", ne_style)
	name_hbox.add_child(name_lbl); name_hbox.add_child(name_edit)
	vbox.add_child(name_hbox)

	var sep1 = HSeparator.new()
	sep1.modulate = PokerTheme.BORDER_SUBTLE
	vbox.add_child(sep1)

	# HOST / JOIN buttons
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	action_hbox.add_theme_constant_override("separation", 14)

	var btn_host = PokerTheme.make_action_button(_tc("HOST GAME", "TẠO PHÒNG"), PokerTheme.ACCENT_GREEN, Vector2(160, 44))
	btn_host.add_theme_font_size_override("font_size", 18)
	action_hbox.add_child(btn_host)

	var ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "Server IP"
	ip_edit.custom_minimum_size = Vector2(160, 34)
	ip_edit.add_theme_font_size_override("font_size", 15)
	var ip_style = PokerTheme.make_panel_style(PokerTheme.BG_MEDIUM, PokerTheme.BORDER_SUBTLE, PokerTheme.CORNER_SM, 1, 8)
	ip_edit.add_theme_stylebox_override("normal", ip_style)
	action_hbox.add_child(ip_edit)

	var btn_join = PokerTheme.make_action_button(_tc("JOIN", "THAM GIA"), PokerTheme.ACCENT_BLUE, Vector2(100, 44))
	btn_join.add_theme_font_size_override("font_size", 18)
	action_hbox.add_child(btn_join)

	vbox.add_child(action_hbox)

	# Status
	var status_lbl = Label.new()
	status_lbl.text = _tc("Status: Ready", "Trạng thái: Sẵn sàng")
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 15)
	status_lbl.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	vbox.add_child(status_lbl)

	# Ping label
	var ping_lbl = Label.new()
	ping_lbl.text = ""
	ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ping_lbl.add_theme_font_size_override("font_size", 13)
	ping_lbl.add_theme_color_override("font_color", PokerTheme.TEXT_MUTED)
	vbox.add_child(ping_lbl)

	# Player list in styled panel
	var list_panel = PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(0, 170)
	var lp_style = PokerTheme.make_panel_style(Color(0.04, 0.05, 0.08, 0.8), PokerTheme.BORDER_SUBTLE, PokerTheme.CORNER_SM, 1, 4)
	list_panel.add_theme_stylebox_override("panel", lp_style)
	vbox.add_child(list_panel)

	var player_list_vbox = VBoxContainer.new()
	player_list_vbox.add_theme_constant_override("separation", 4)
	list_panel.add_child(player_list_vbox)

	var list_title = Label.new()
	list_title.text = _tc("  PLAYERS", "  NGƯỜI CHƠI")
	list_title.add_theme_font_size_override("font_size", 14)
	list_title.add_theme_color_override("font_color", PokerTheme.TEXT_MUTED)
	player_list_vbox.add_child(list_title)

	# Chat input
	var chat_hbox = HBoxContainer.new()
	chat_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	chat_hbox.add_theme_constant_override("separation", 6)
	var chat_edit = LineEdit.new()
	chat_edit.placeholder_text = _tc("Type a message...", "Nhắn tin...")
	chat_edit.custom_minimum_size = Vector2(380, 32)
	chat_edit.add_theme_font_size_override("font_size", 14)
	var chat_style = PokerTheme.make_panel_style(PokerTheme.BG_MEDIUM, PokerTheme.BORDER_SUBTLE, PokerTheme.CORNER_SM, 1, 6)
	chat_edit.add_theme_stylebox_override("normal", chat_style)
	chat_hbox.add_child(chat_edit)

	var btn_send = PokerTheme.make_action_button(_tc("SEND", "GỬI"), PokerTheme.ACCENT_BLUE, Vector2(70, 32))
	btn_send.add_theme_font_size_override("font_size", 14)
	chat_hbox.add_child(btn_send)
	vbox.add_child(chat_hbox)

	# Chat display area (simple)
	var chat_scroll = ScrollContainer.new()
	chat_scroll.custom_minimum_size = Vector2(0, 60)
	chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var chat_vbox = VBoxContainer.new()
	chat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_scroll.add_child(chat_vbox)
	vbox.add_child(chat_scroll)

	# Bottom buttons
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 16)

	var btn_start = PokerTheme.make_action_button(_tc("START GAME", "BẮT ĐẦU"), PokerTheme.GOLD, Vector2(160, 44))
	btn_start.add_theme_font_size_override("font_size", 18)
	btn_start.disabled = true; btn_start.visible = false
	bottom_hbox.add_child(btn_start)

	var btn_back = PokerTheme.make_action_button(_tc("BACK", "QUAY LẠI"), PokerTheme.ACCENT_RED, Vector2(120, 44))
	btn_back.add_theme_font_size_override("font_size", 18)
	bottom_hbox.add_child(btn_back)

	vbox.add_child(bottom_hbox)

	# ---- LOGIC ----
	var nm = get_node("/root/NetworkManager") if has_node("/root/NetworkManager") else null
	if not nm:
		status_lbl.text = "[ERROR] NetworkManager not found"
		overlay.add_child(panel); add_child(overlay)
		return

	var _add_player_row = func(id: int, pname: String, is_host: bool = false):
		if not is_instance_valid(player_list_vbox): return
		var row = HBoxContainer.new()
		row.name = "player_" + str(id)
		row.add_theme_constant_override("separation", 8)
		var icon_lbl = Label.new()
		icon_lbl.text = "●"
		icon_lbl.add_theme_color_override("font_color", PokerTheme.ACCENT_GREEN)
		icon_lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(icon_lbl)
		var name_l = Label.new()
		name_l.text = pname + (" (HOST)" if is_host else "")
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.add_theme_color_override("font_color", PokerTheme.GOLD if is_host else PokerTheme.TEXT_PRIMARY)
		row.add_child(name_l)
		player_list_vbox.add_child(row)
		# Animate entry
		row.modulate.a = 0.0
		var tw2 = create_tween()
		tw2.tween_property(row, "modulate:a", 1.0, 0.2)

	var _add_chat_msg = func(sender: String, msg: String):
		if not is_instance_valid(chat_vbox): return
		var lbl2 = RichTextLabel.new()
		lbl2.bbcode_enabled = true; lbl2.fit_content = true
		lbl2.text = "[color=#80b0d0]" + sender + ":[/color] " + msg
		lbl2.add_theme_font_size_override("normal_font_size", 13)
		chat_vbox.add_child(lbl2)
		if chat_vbox.get_child_count() > 50:
			chat_vbox.get_child(0).queue_free()
		chat_scroll.scroll_vertical = 9999

	# Signal callables for cleanup
	var _on_player_connected = func(id: int, info: Dictionary):
		if not is_instance_valid(status_lbl): return
		var pname = info.get("name", "Player " + str(id))
		_add_player_row.call(id, pname, false)
		status_lbl.text = _tc("Player joined: ", "Người chơi mới: ") + pname
		status_lbl.add_theme_color_override("font_color", PokerTheme.ACCENT_GREEN)

	var _on_connection_failed = func():
		if not is_instance_valid(status_lbl): return
		status_lbl.text = _tc("Connection Failed!", "Kết nối thất bại!")
		status_lbl.add_theme_color_override("font_color", PokerTheme.ACCENT_RED)
		btn_host.disabled = false; btn_join.disabled = false

	var _on_server_disconnected = func():
		if not is_instance_valid(status_lbl): return
		status_lbl.text = _tc("Server Disconnected", "Mất kết nối")
		status_lbl.add_theme_color_override("font_color", PokerTheme.ACCENT_RED)
		# Clear player list
		for c in player_list_vbox.get_children():
			if c.name.begins_with("player_"): c.queue_free()
		btn_host.disabled = false; btn_join.disabled = false
		btn_start.visible = false

	var _on_chat_received: Callable
	if nm.has_signal("chat_received"):
		_on_chat_received = func(sender: String, msg: String):
			_add_chat_msg.call(sender, msg)
		nm.chat_received.connect(_on_chat_received)

	btn_host.pressed.connect(func():
		if not is_instance_valid(status_lbl): return
		_play_ui_sound()
		status_lbl.text = _tc("Hosting on port 9050...", "Tạo phòng cổng 9050...")
		status_lbl.add_theme_color_override("font_color", PokerTheme.GOLD)
		nm.host_game(name_edit.text)
		btn_host.disabled = true; btn_join.disabled = true
		btn_start.visible = true; btn_start.disabled = false
		_add_player_row.call(1, name_edit.text, true)
	)

	btn_join.pressed.connect(func():
		if not is_instance_valid(status_lbl): return
		_play_ui_sound()
		status_lbl.text = _tc("Connecting to ", "Đang kết nối ") + ip_edit.text + "..."
		status_lbl.add_theme_color_override("font_color", PokerTheme.ACCENT_BLUE)
		nm.join_game(ip_edit.text, name_edit.text)
		btn_host.disabled = true; btn_join.disabled = true
	)

	btn_start.pressed.connect(func():
		_play_ui_sound()
		nm.start_game()
	)

	btn_send.pressed.connect(func():
		if chat_edit.text.strip_edges().is_empty(): return
		_play_ui_sound()
		if nm.has_method("send_chat"):
			nm.send_chat(name_edit.text, chat_edit.text)
		_add_chat_msg.call(name_edit.text, chat_edit.text)
		chat_edit.text = ""
	)

	chat_edit.text_submitted.connect(func(_text):
		btn_send.pressed.emit()
	)

	btn_back.pressed.connect(func():
		_play_ui_sound()
		multiplayer.multiplayer_peer = null
		PokerTheme.fade_out_and_free(overlay, self, 0.15)
	)

	# Cleanup on free
	overlay.tree_exiting.connect(func():
		if nm.player_connected.is_connected(_on_player_connected):
			nm.player_connected.disconnect(_on_player_connected)
		if nm.connection_failed.is_connected(_on_connection_failed):
			nm.connection_failed.disconnect(_on_connection_failed)
		if nm.server_disconnected.is_connected(_on_server_disconnected):
			nm.server_disconnected.disconnect(_on_server_disconnected)
		if nm.has_signal("chat_received") and _on_chat_received.is_valid() and nm.chat_received.is_connected(_on_chat_received):
			nm.chat_received.disconnect(_on_chat_received)
	)

	nm.player_connected.connect(_on_player_connected)
	nm.connection_failed.connect(_on_connection_failed)
	nm.server_disconnected.connect(_on_server_disconnected)

	# Ping display loop
	var _ping_timer = Timer.new()
	_ping_timer.wait_time = 2.0
	_ping_timer.timeout.connect(func():
		if not is_instance_valid(ping_lbl): return
		if nm.has_method("get_ping"):
			ping_lbl.text = "Ping: " + str(nm.get_ping()) + "ms"
		elif multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			ping_lbl.text = _tc("Connected", "Đã kết nối")
		else:
			ping_lbl.text = ""
	)
	overlay.add_child(_ping_timer)
	_ping_timer.start()

	overlay.add_child(panel)
	add_child(overlay)
	PokerTheme.popup_animate(panel, self)

# ============================================================
# HELPERS
# ============================================================
func _add_slider_row(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, current: float) -> HSlider:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	lbl.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var slider = HSlider.new()
	slider.custom_minimum_size = Vector2(200, 28)
	slider.min_value = min_v; slider.max_value = max_v; slider.step = step_v
	slider.value = current; slider.focus_mode = Control.FOCUS_NONE
	hbox.add_child(lbl); hbox.add_child(slider)
	parent.add_child(hbox)
	return slider

func _play_ui_sound() -> void:
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth: synth.play_ui_click()

func _tc(en: String, vi: String) -> String:
	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	if sm and sm.has_method("tc"): return sm.tc(en, vi)
	return en

# ---- BACKGROUND FLOATING CARDS ----
func _spawn_floating_cards() -> void:
	for i in range(8):
		var card_rect = TextureRect.new()
		card_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card = Card.new(randi() % 4 as Card.Suit, randi_range(2, 14) as Card.Rank)
		card_rect.texture = CardTextureGenerator.get_card_texture(card)
		card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_rect.custom_minimum_size = Vector2(150, 210)
		card_rect.modulate = Color(1.0, 1.0, 1.0, 0.12)
		add_child(card_rect)
		_reset_card_and_animate(card_rect)

func _reset_card_and_animate(card_rect: TextureRect) -> void:
	var screen_rect = get_viewport_rect()
	var start_x = randf_range(-400, screen_rect.size.x + 400)
	var start_y = screen_rect.size.y + 250
	card_rect.position = Vector2(start_x, start_y)
	card_rect.rotation = randf_range(-PI, PI)
	var target_x = start_x + randf_range(-300, 300)
	var target_y = -300
	var target_rot = card_rect.rotation + randf_range(-PI, PI)
	var duration = randf_range(15.0, 25.0)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(card_rect, "position", Vector2(target_x, target_y), duration).set_delay(randf_range(0, 5))
	tw.tween_property(card_rect, "rotation", target_rot, duration).set_delay(randf_range(0, 5))
	tw.chain().tween_callback(self._reset_card_and_animate.bind(card_rect))
