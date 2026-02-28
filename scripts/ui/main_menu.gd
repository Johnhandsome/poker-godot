extends Control

func _ready() -> void:
	# Bắt buộc root Node bung toàn màn hình và bám sát độ phân giải thực tế của hệ điều hành
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Bật âm thanh Casino Ambience
	var ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = preload("res://assets/audio/freesound_community-poker-room-33521.mp3")
	ambient_player.volume_db = -5.0
	ambient_player.finished.connect(func(): ambient_player.play())
	add_child(ambient_player)
	ambient_player.play()

	# Tạo nền Gradient tỏa sáng nhẹ ở giữa bằng ColorRect đơn giản để tránh lỗi texture viền trắng
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 1.0) # Màu xanh đậm như màn hình in-game
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Gradient sáng ở giữa
	var glow = ColorRect.new()
	add_child(glow)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mat = ShaderMaterial.new()
	var shader_code = """
	shader_type canvas_item;
	void fragment() {
		vec2 uv = UV - vec2(0.5);
		float dist = length(uv);
		float alpha = smoothstep(0.6, 0.1, dist);
		COLOR = vec4(0.05, 0.10, 0.18, alpha * 0.8);
	}
	"""
	var shader = Shader.new()
	shader.code = shader_code
	mat.shader = shader
	glow.material = mat
	
	_spawn_floating_cards()
	
	var center = CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 25)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "TEXAS HOLD'EM\nGODOT POKER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64) # Slightly smaller font
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25)) # Màu vàng gold
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_x", 4)
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_outline_size", 4)
	vbox.add_child(title)
	
	# Hiển thị Bankroll của người chơi từ file Save
	var current_chips = 5000
	var save_mgr = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
	if save_mgr:
		current_chips = save_mgr.get_chips()
	var bankroll_lbl = Label.new()
	bankroll_lbl.text = "BANKROLL: $" + str(current_chips)
	bankroll_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bankroll_lbl.add_theme_font_size_override("font_size", 28)
	if current_chips > 0:
		bankroll_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	else:
		bankroll_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	vbox.add_child(bankroll_lbl)
	
	# Nút Play
	var btn_play = Button.new()
	if current_chips > 0:
		btn_play.text = _tc("PLAY GAME", "CHƠI TIẾP")
	else:
		btn_play.text = _tc("RESTART ($5000)", "CHƠI LẠI ($5000)")
	btn_play.custom_minimum_size = Vector2(300, 70)
	btn_play.add_theme_font_size_override("font_size", 32)
	btn_play.focus_mode = Control.FOCUS_NONE
	var style_play = StyleBoxFlat.new()
	style_play.bg_color = Color(0.12, 0.16, 0.13, 0.98)
	style_play.border_width_bottom = 4
	style_play.border_color = Color(1.0, 0.85, 0.25)
	style_play.corner_radius_top_left = 12
	style_play.corner_radius_top_right = 12
	style_play.corner_radius_bottom_left = 12
	style_play.corner_radius_bottom_right = 12
	var style_play_hover = style_play.duplicate()
	style_play_hover.bg_color = Color(0.18, 0.24, 0.20, 0.98) # Sáng hơn khi hover
	
	btn_play.add_theme_stylebox_override("normal", style_play)
	btn_play.add_theme_stylebox_override("hover", style_play_hover)
	btn_play.add_theme_stylebox_override("pressed", style_play)
	
	btn_play.pressed.connect(func():
		var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
		if synth: synth.play_ui_click()
		
		var sm = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
		if sm and sm.get_chips() <= 0:
			sm.reset_save()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	
	# Hover tween cho btn_play
	btn_play.mouse_entered.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_play, "scale", Vector2(1.05, 1.05), 0.1)
	)
	btn_play.mouse_exited.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_play, "scale", Vector2(1.0, 1.0), 0.1)
	)
	btn_play.pivot_offset = btn_play.custom_minimum_size / 2.0
	
	vbox.add_child(btn_play)
	
	# Nút Multiplayer
	var btn_multi = Button.new()
	btn_multi.text = _tc("MULTIPLAYER", "CHƠI ONLINE")
	btn_multi.custom_minimum_size = Vector2(300, 60)
	btn_multi.add_theme_font_size_override("font_size", 24)
	btn_multi.focus_mode = Control.FOCUS_NONE
	var style_multi = style_play.duplicate()
	style_multi.border_color = Color(0.2, 0.6, 0.9)
	var style_multi_hover = style_play_hover.duplicate()
	style_multi_hover.border_color = Color(0.3, 0.7, 1.0)
	
	btn_multi.add_theme_stylebox_override("normal", style_multi)
	btn_multi.add_theme_stylebox_override("hover", style_multi_hover)
	btn_multi.add_theme_stylebox_override("pressed", style_multi)
	
	btn_multi.pressed.connect(func():
		var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
		if synth: synth.play_ui_click()
		_show_multiplayer_panel()
	)
	
	btn_multi.mouse_entered.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_multi, "scale", Vector2(1.05, 1.05), 0.1)
	)
	btn_multi.mouse_exited.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_multi, "scale", Vector2(1.0, 1.0), 0.1)
	)
	btn_multi.pivot_offset = btn_multi.custom_minimum_size / 2.0
	
	vbox.add_child(btn_multi)
	
	# Nút Settings
	var btn_settings = Button.new()
	btn_settings.text = _tc("SETTINGS", "CÀI ĐẶT")
	btn_settings.custom_minimum_size = Vector2(300, 60)
	btn_settings.add_theme_font_size_override("font_size", 24)
	btn_settings.focus_mode = Control.FOCUS_NONE
	
	# Clone style từ btn_play
	var style_settings = style_play.duplicate()
	style_settings.border_width_bottom = 0 # Match với Quit
	var style_settings_hover = style_play_hover.duplicate()
	style_settings_hover.border_width_bottom = 0
	
	btn_settings.add_theme_stylebox_override("normal", style_settings)
	btn_settings.add_theme_stylebox_override("hover", style_settings_hover)
	btn_settings.add_theme_stylebox_override("pressed", style_settings)
	
	btn_settings.pressed.connect(func():
		var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
		if synth: synth.play_ui_click()
		_show_settings_panel()
	)
	
	btn_settings.mouse_entered.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_settings, "scale", Vector2(1.05, 1.05), 0.1)
	)
	btn_settings.mouse_exited.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_settings, "scale", Vector2(1.0, 1.0), 0.1)
	)
	btn_settings.pivot_offset = btn_settings.custom_minimum_size / 2.0
	
	vbox.add_child(btn_settings)
	
	# Nút Quit
	var btn_quit = Button.new()
	btn_quit.text = _tc("QUIT", "THOÁT")
	btn_quit.custom_minimum_size = Vector2(300, 60)
	btn_quit.add_theme_font_size_override("font_size", 24)
	btn_quit.focus_mode = Control.FOCUS_NONE
	var style_quit = StyleBoxFlat.new()
	style_quit.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	style_quit.corner_radius_top_left = 12
	style_quit.corner_radius_top_right = 12
	style_quit.corner_radius_bottom_left = 12
	style_quit.corner_radius_bottom_right = 12
	var style_quit_hover = style_quit.duplicate()
	style_quit_hover.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	
	btn_quit.add_theme_stylebox_override("normal", style_quit)
	btn_quit.add_theme_stylebox_override("hover", style_quit_hover)
	btn_quit.add_theme_stylebox_override("pressed", style_quit)
	
	btn_quit.pressed.connect(func():
		var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
		if synth: synth.play_ui_click()
		get_tree().quit()
	)
	
	btn_quit.mouse_entered.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_quit, "scale", Vector2(1.05, 1.05), 0.1)
	)
	btn_quit.mouse_exited.connect(func():
		var tw = create_tween()
		tw.tween_property(btn_quit, "scale", Vector2(1.0, 1.0), 0.1)
	)
	btn_quit.pivot_offset = btn_quit.custom_minimum_size / 2.0
	
	if OS.has_feature("web"):
		btn_quit.hide()
	else:
		vbox.add_child(btn_quit)

func _show_settings_panel() -> void:
	if has_node("SettingsPanel"): return
	
	var overlay = CenterContainer.new()
	overlay.name = "SettingsPanel"
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 400)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.6, 1.0, 0.5)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = _tc("SETTINGS", "CÀI ĐẶT")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	
	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	
	# Master Volume
	var master_box = HBoxContainer.new()
	master_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var master_lbl = Label.new()
	master_lbl.text = _tc("Master Vol:", "Âm lượng tổng:")
	master_lbl.custom_minimum_size = Vector2(140, 0)
	var master_slider = HSlider.new()
	master_slider.custom_minimum_size = Vector2(200, 30)
	master_slider.max_value = 1.0
	master_slider.step = 0.05
	master_slider.focus_mode = Control.FOCUS_NONE
	if sm: master_slider.value = sm.master_volume
	master_box.add_child(master_lbl)
	master_box.add_child(master_slider)
	vbox.add_child(master_box)
	
	# SFX Volume
	var sfx_box = HBoxContainer.new()
	sfx_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var sfx_lbl = Label.new()
	sfx_lbl.text = _tc("SFX Vol:", "Âm thanh (FX):")
	sfx_lbl.custom_minimum_size = Vector2(140, 0)
	var sfx_slider = HSlider.new()
	sfx_slider.custom_minimum_size = Vector2(200, 30)
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	if sm: sfx_slider.value = sm.sfx_volume
	sfx_box.add_child(sfx_lbl)
	sfx_box.add_child(sfx_slider)
	vbox.add_child(sfx_box)
	
	# BGM Volume
	var bgm_box = HBoxContainer.new()
	bgm_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var bgm_lbl = Label.new()
	bgm_lbl.text = _tc("Music Vol:", "Nhạc nền:")
	bgm_lbl.custom_minimum_size = Vector2(140, 0)
	var bgm_slider = HSlider.new()
	bgm_slider.custom_minimum_size = Vector2(200, 30)
	bgm_slider.max_value = 1.0
	bgm_slider.step = 0.05
	if sm: bgm_slider.value = sm.bgm_volume
	bgm_box.add_child(bgm_lbl)
	bgm_box.add_child(bgm_slider)
	vbox.add_child(bgm_box)
	
	# Fast Bot Mode
	var fast_box = HBoxContainer.new()
	fast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var fast_lbl = Label.new()
	fast_lbl.text = _tc("Bot Speed:", "Tốc độ Đánh của Bot:")
	fast_lbl.custom_minimum_size = Vector2(140, 0)
	var check_fast_bot = CheckButton.new()
	check_fast_bot.text = _tc("Skip Delays", "Bỏ qua thời gian chờ")
	check_fast_bot.focus_mode = Control.FOCUS_NONE
	if sm: check_fast_bot.button_pressed = sm.fast_bot_mode
	fast_box.add_child(fast_lbl)
	fast_box.add_child(check_fast_bot)
	vbox.add_child(fast_box)
	
	# Bot Count
	var bot_box = HBoxContainer.new()
	bot_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var bot_lbl = Label.new()
	bot_lbl.text = _tc("Num Bots:", "Số lượng Bot:")
	bot_lbl.custom_minimum_size = Vector2(140, 0)
	var bot_slider = HSlider.new()
	bot_slider.custom_minimum_size = Vector2(200, 30)
	bot_slider.min_value = 1
	bot_slider.max_value = 8
	bot_slider.step = 1
	bot_slider.focus_mode = Control.FOCUS_NONE
	if sm:
		bot_slider.value = sm.num_bots
		bot_lbl.text = _tc("Num Bots: ", "Số lượng Bot: ") + str(sm.num_bots)
	bot_box.add_child(bot_lbl)
	bot_box.add_child(bot_slider)
	vbox.add_child(bot_box)
	
	# Tín hiệu cập nhật
	if sm:
		var update_audio = func():
			sm.master_volume = master_slider.value
			sm.sfx_volume = sfx_slider.value
			sm.apply_and_save()
			
			var target_linear = sm.master_volume
			# Sửa lỗi ambient player: dò tìm tất cả child thay vì dùng tên
			for child in get_parent().get_children() if get_parent() else get_children():
				if child is AudioStreamPlayer and child.stream and child.stream.resource_path.ends_with("33521.mp3"):
					if target_linear <= 0.01:
						child.volume_db = -80.0
					else:
						child.volume_db = linear_to_db(target_linear)

				
		master_slider.value_changed.connect(func(_val): update_audio.call())
		sfx_slider.value_changed.connect(func(_val): update_audio.call())
		
		check_fast_bot.toggled.connect(func(pressed):
			sm.fast_bot_mode = pressed
			sm.apply_and_save()
		)
		
		bot_slider.value_changed.connect(func(val):
			sm.num_bots = int(val)
			bot_lbl.text = _tc("Num Bots: ", "Số lượng Bot: ") + str(sm.num_bots)
			sm.apply_and_save()
		)
		
	# Language Selection
	var lang_box = HBoxContainer.new()
	lang_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var lang_lbl = Label.new()
	lang_lbl.text = _tc("Language:", "Ngôn ngữ:")
	lang_lbl.custom_minimum_size = Vector2(140, 0)
	var lang_btn = OptionButton.new()
	lang_btn.add_item("English")
	lang_btn.add_item("Tiếng Việt")
	lang_btn.focus_mode = Control.FOCUS_NONE
	if sm:
		if sm.language == "vi":
			lang_btn.selected = 1
		else:
			lang_btn.selected = 0
		lang_btn.item_selected.connect(func(idx):
			var selected_lang = "en"
			if idx == 1:
				selected_lang = "vi"
			
			var lang_changed = (sm.language != selected_lang)
			if lang_changed:
				sm.language = selected_lang
				sm.save_settings()
				get_tree().reload_current_scene()
		)
	lang_box.add_child(lang_lbl)
	lang_box.add_child(lang_btn)
	vbox.add_child(lang_box)
	
	# Đệm
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer2)
	
	# Nút đóng
	var btn_close = Button.new()
	btn_close.text = _tc("CLOSE", "ĐÓNG")
	btn_close.custom_minimum_size = Vector2(150, 40)
	btn_close.focus_mode = Control.FOCUS_NONE
	var style_close = StyleBoxFlat.new()
	style_close.bg_color = Color(0.12, 0.3, 0.15, 0.9) # Xanh lá tối
	style_close.corner_radius_top_left = 8
	style_close.corner_radius_top_right = 8
	style_close.corner_radius_bottom_left = 8
	style_close.corner_radius_bottom_right = 8
	btn_close.add_theme_stylebox_override("normal", style_close)
	btn_close.pressed.connect(func():
		var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
		if synth: synth.play_ui_click()
		overlay.queue_free()
	)
	var btn_box = CenterContainer.new()
	btn_box.add_child(btn_close)
	vbox.add_child(btn_box)
	
	overlay.add_child(panel)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Call update once immediately to apply current slider states
	if sm:
		master_slider.value_changed.emit(master_slider.value)
	
	# Hiện ứng scale to
	panel.scale = Vector2(0.5, 0.5)
	panel.pivot_offset = Vector2(250, 200) # Căn giữa pivot để scale mượt
	var tw = create_tween()
	tw.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---- BACKGROUND ANIMATIONS ----
func _spawn_floating_cards() -> void:
	# Spawn 8 random floating cards
	for i in range(8):
		var card_rect = TextureRect.new()
		var card = Card.new(randi_range(2, 14), randi() % 4)
		card_rect.texture = CardTextureGenerator.get_card_texture(card)
		card_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_rect.custom_minimum_size = Vector2(150, 210)
		card_rect.modulate = Color(1.0, 1.0, 1.0, 0.15) # Mờ chìm vào nền (15% opacity)
		
		add_child(card_rect)
		
		# Random starting positions (outside screen)
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
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(card_rect, "position", Vector2(target_x, target_y), duration).set_delay(randf_range(0, 5))
	tw.tween_property(card_rect, "rotation", target_rot, duration).set_delay(randf_range(0, 5))
	
	# Loop back when done
	tw.chain().tween_callback(self._reset_card_and_animate.bind(card_rect))

func _tc(en: String, vi: String) -> String:
	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	if sm and sm.has_method("tc"):
		return sm.tc(en, vi)
	return en

func _show_multiplayer_panel() -> void:
	if has_node("MultiplayerPanel"): return
	
	var overlay = CenterContainer.new()
	overlay.name = "MultiplayerPanel"
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 500)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18, 0.95)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.2, 0.6, 0.9, 0.5)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "MULTIPLAYER LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox.add_child(title)
	
	# Name Input
	var name_box = HBoxContainer.new()
	name_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_lbl = Label.new()
	name_lbl.text = "Name:"
	var name_edit = LineEdit.new()
	name_edit.text = "Player" + str(randi() % 1000)
	name_edit.custom_minimum_size = Vector2(200, 0)
	name_box.add_child(name_lbl)
	name_box.add_child(name_edit)
	vbox.add_child(name_box)
	
	var hsep = HSeparator.new()
	vbox.add_child(hsep)
	
	# HOST Section
	var host_box = HBoxContainer.new()
	host_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn_host = Button.new()
	btn_host.text = "HOST GAME"
	btn_host.custom_minimum_size = Vector2(150, 40)
	host_box.add_child(btn_host)
	vbox.add_child(host_box)
	
	# JOIN Section
	var join_box = HBoxContainer.new()
	join_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "Server IP"
	ip_edit.custom_minimum_size = Vector2(150, 0)
	var btn_join = Button.new()
	btn_join.text = "JOIN GAME"
	btn_join.custom_minimum_size = Vector2(100, 40)
	join_box.add_child(ip_edit)
	join_box.add_child(btn_join)
	vbox.add_child(join_box)
	
	var status_lbl = Label.new()
	status_lbl.text = "Status: Idle"
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_lbl)
	
	var player_list = ItemList.new()
	player_list.custom_minimum_size = Vector2(0, 150)
	vbox.add_child(player_list)
	
	var btn_start = Button.new()
	btn_start.text = "START GAME"
	btn_start.disabled = true
	btn_start.visible = false
	vbox.add_child(btn_start)
	
	var btn_close = Button.new()
	btn_close.text = "BACK"
	vbox.add_child(btn_close)
	
	# Logic
	var nm = get_node("/root/NetworkManager")
	
	btn_host.pressed.connect(func():
		status_lbl.text = "Hosting..."
		nm.host_game(name_edit.text)
		btn_host.disabled = true
		btn_join.disabled = true
		btn_start.visible = true
		btn_start.disabled = false
	)
	
	btn_join.pressed.connect(func():
		status_lbl.text = "Connecting..."
		nm.join_game(ip_edit.text, name_edit.text)
		btn_host.disabled = true
		btn_join.disabled = true
	)
	
	btn_start.pressed.connect(func():
		nm.start_game()
	)
	
	btn_close.pressed.connect(func():
		overlay.queue_free()
		multiplayer.multiplayer_peer = null # Disconnect
	)
	
	# Network signals
	nm.player_connected.connect(func(id, info):
		player_list.add_item(str(id) + ": " + info.get("name", "Unknown"))
		status_lbl.text = "Player Connected: " + str(id)
	)
	
	nm.connection_failed.connect(func():
		status_lbl.text = "Connection Failed!"
		btn_host.disabled = false
		btn_join.disabled = false
	)
	
	nm.server_disconnected.connect(func():
		status_lbl.text = "Server Disconnected"
		player_list.clear()
		btn_host.disabled = false
		btn_join.disabled = false
		btn_start.visible = false
	)
	
	overlay.add_child(panel)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
