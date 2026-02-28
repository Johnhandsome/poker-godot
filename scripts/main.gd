extends Node3D

class_name MainScene

const PokerTheme = preload("res://scripts/ui/poker_theme.gd")

# =================================================================
# MAIN GAME SCENE — Polished production UI with PokerTheme
# =================================================================

var pot_label: Label
var state_label: Label
var turn_label: Label
var blinds_label: Label
var timer_bar: ProgressBar
var btn_fold: Button
var btn_call_check: Button
var btn_raise: Button
var btn_all_in: Button
var raise_slider: HSlider
var raise_value_label: Label
var log_vbox: VBoxContainer
var log_scroll: ScrollContainer
var log_panel: PanelContainer
var is_log_minimized: bool = false
var btn_minimize_log: Button
var card_display: HBoxContainer
var chips_label: Label
var _game_message_callable: Callable
var _turn_timer: Timer
var _turn_timer_max: float = 30.0
var _my_turn: bool = false
var _action_bar: PanelContainer
var _turn_pulse_tween: Tween = null

func _ready() -> void:
	# Ambient sound
	var ambient_player = AudioStreamPlayer.new()
	ambient_player.stream = preload("res://assets/audio/freesound_community-poker-room-33521.mp3")
	ambient_player.volume_db = -8.0
	ambient_player.finished.connect(func(): ambient_player.play())
	add_child(ambient_player)
	ambient_player.play()

	# Reset game state for new game
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		gm.players.clear()
		gm.active_players.clear()
		gm.community_cards.clear()

	# Build 3D scene
	var table_builder = TableBuilder.new()
	table_builder.name = "TableBuilder"
	add_child(table_builder)

	var physical_manager = PhysicalManager.new()
	physical_manager.name = "PhysicalManager"
	add_child(physical_manager)

	# Build UI
	_setup_ui()

	# Connect game signals
	gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		gm.state_changed.connect(_on_state_changed)
		gm.action_received.connect(_on_action_received)
		gm.player_turn_started.connect(_on_player_turn)
		gm.community_cards_changed.connect(_on_community_changed)
		gm.winners_declared.connect(_on_winners_declared_ui)
		gm.game_over.connect(_on_game_over)
		_game_message_callable = func(msg): _add_log_message("[color=white]" + msg + "[/color]")
		gm.game_message.connect(_game_message_callable)
		gm.blinds_level_changed.connect(_on_blinds_level_changed)

	# Wait one frame for players to register
	await get_tree().process_frame
	if not is_instance_valid(self): return

	if gm:
		if gm.multiplayer_mode:
			var my_id = str(multiplayer.get_unique_id())
			var p = gm._get_player_by_id(my_id)
			if p:
				p.card_drawn.connect(_on_human_card_drawn)
				p.card_updated.connect(_on_human_card_updated)
		else:
			for p in gm.players:
				if !p.is_ai:
					p.card_drawn.connect(_on_human_card_drawn)
					break

	# Turn timer
	_turn_timer = Timer.new()
	_turn_timer.one_shot = false
	_turn_timer.wait_time = 0.05
	_turn_timer.timeout.connect(_on_turn_timer_tick)
	add_child(_turn_timer)

var dealer_btn: MeshInstance3D

func _exit_tree() -> void:
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		if gm.state_changed.is_connected(_on_state_changed):
			gm.state_changed.disconnect(_on_state_changed)
		if gm.action_received.is_connected(_on_action_received):
			gm.action_received.disconnect(_on_action_received)
		if gm.player_turn_started.is_connected(_on_player_turn):
			gm.player_turn_started.disconnect(_on_player_turn)
		if gm.community_cards_changed.is_connected(_on_community_changed):
			gm.community_cards_changed.disconnect(_on_community_changed)
		if gm.winners_declared.is_connected(_on_winners_declared_ui):
			gm.winners_declared.disconnect(_on_winners_declared_ui)
		if gm.game_over.is_connected(_on_game_over):
			gm.game_over.disconnect(_on_game_over)
		if _game_message_callable.is_valid() and gm.game_message.is_connected(_game_message_callable):
			gm.game_message.disconnect(_game_message_callable)
		if gm.blinds_level_changed.is_connected(_on_blinds_level_changed):
			gm.blinds_level_changed.disconnect(_on_blinds_level_changed)

# ============================================================
# UI SETUP
# ============================================================
func _setup_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "GameUI"
	add_child(canvas)

	# ---- TOP BAR ----
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_panel.custom_minimum_size = Vector2(0, 52)
	var top_style = PokerTheme.make_panel_style(PokerTheme.BG_DARK, PokerTheme.BORDER_SUBTLE, 0, 0, 0)
	top_style.content_margin_left = 20; top_style.content_margin_right = 20
	top_style.content_margin_top = 6; top_style.content_margin_bottom = 6
	top_style.border_width_bottom = 1; top_style.border_color = PokerTheme.BORDER
	top_panel.add_theme_stylebox_override("panel", top_style)
	canvas.add_child(top_panel)

	var top_hbox = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top_hbox.add_theme_constant_override("separation", 30)
	top_panel.add_child(top_hbox)

	pot_label = Label.new()
	pot_label.text = "POT: $0"
	pot_label.add_theme_font_size_override("font_size", 22)
	pot_label.add_theme_color_override("font_color", PokerTheme.GOLD)
	top_hbox.add_child(pot_label)

	state_label = Label.new()
	state_label.text = _tc("Waiting...", "Chờ người chơi...")
	state_label.add_theme_font_size_override("font_size", PokerTheme.FONT_BODY)
	state_label.add_theme_color_override("font_color", PokerTheme.TEXT_PRIMARY)
	top_hbox.add_child(state_label)

	turn_label = Label.new()
	turn_label.text = ""
	turn_label.add_theme_font_size_override("font_size", PokerTheme.FONT_BODY)
	turn_label.add_theme_color_override("font_color", PokerTheme.ACCENT_GREEN)
	top_hbox.add_child(turn_label)

	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer1)

	blinds_label = Label.new()
	blinds_label.text = "BLINDS: 10/20 (Lvl 1)"
	blinds_label.add_theme_font_size_override("font_size", 15)
	blinds_label.add_theme_color_override("font_color", PokerTheme.ACCENT_RED)
	top_hbox.add_child(blinds_label)

	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_hbox.add_child(spacer2)

	# Turn timer bar
	timer_bar = ProgressBar.new()
	timer_bar.min_value = 0; timer_bar.max_value = 100; timer_bar.value = 0
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(120, 6)
	timer_bar.modulate = PokerTheme.ACCENT_GREEN
	top_hbox.add_child(timer_bar)

	# Menu button
	var btn_pause = PokerTheme.make_action_button("MENU", PokerTheme.TEXT_SECONDARY, Vector2(80, 38))
	btn_pause.pressed.connect(_show_pause_menu)
	top_hbox.add_child(btn_pause)

	# ---- BOTTOM BAR ----
	_action_bar = PanelContainer.new()
	_action_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_bar.custom_minimum_size = Vector2(0, 82)
	var bottom_style = PokerTheme.make_panel_style(PokerTheme.BG_DARK, PokerTheme.BORDER_SUBTLE, 0, 0, 0)
	bottom_style.content_margin_left = 15; bottom_style.content_margin_right = 15
	bottom_style.content_margin_top = 8; bottom_style.content_margin_bottom = 8
	bottom_style.border_width_top = 1; bottom_style.border_color = PokerTheme.BORDER
	_action_bar.add_theme_stylebox_override("panel", bottom_style)
	canvas.add_child(_action_bar)

	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 10)
	_action_bar.add_child(bottom_hbox)

	# Card wrapper
	var card_wrapper = PanelContainer.new()
	var cw_style = PokerTheme.make_panel_style(PokerTheme.BG_MEDIUM, PokerTheme.BORDER, PokerTheme.CORNER_SM, 1, 6)
	card_wrapper.add_theme_stylebox_override("panel", cw_style)
	card_wrapper.custom_minimum_size = Vector2(140, 60)
	bottom_hbox.add_child(card_wrapper)

	card_display = HBoxContainer.new()
	card_display.alignment = BoxContainer.ALIGNMENT_CENTER
	card_display.add_theme_constant_override("separation", 6)
	card_wrapper.add_child(card_display)

	_add_vsep(bottom_hbox)

	chips_label = Label.new()
	chips_label.text = "CHIPS: $1500"
	chips_label.add_theme_font_size_override("font_size", PokerTheme.FONT_BODY)
	chips_label.add_theme_color_override("font_color", PokerTheme.GOLD)
	chips_label.custom_minimum_size = Vector2(130, 0)
	bottom_hbox.add_child(chips_label)

	_add_vsep(bottom_hbox)

	# Action buttons
	btn_fold = PokerTheme.make_action_button("FOLD", PokerTheme.BTN_FOLD)
	btn_fold.pressed.connect(func(): _play_ui_sound(); _on_ui_action_pressed("Fold"))
	bottom_hbox.add_child(btn_fold)

	btn_call_check = PokerTheme.make_action_button("CHECK", PokerTheme.BTN_CHECK)
	btn_call_check.pressed.connect(func(): _play_ui_sound(); _on_ui_action_pressed("Call"))
	bottom_hbox.add_child(btn_call_check)

	btn_raise = PokerTheme.make_action_button("RAISE", PokerTheme.BTN_RAISE)
	btn_raise.pressed.connect(func(): _play_ui_sound(); _on_ui_action_pressed("Raise"))
	bottom_hbox.add_child(btn_raise)

	# Raise container
	var raise_container = VBoxContainer.new()
	raise_container.custom_minimum_size = Vector2(240, 70)
	raise_container.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_child(raise_container)

	raise_value_label = Label.new()
	raise_value_label.text = "$40"
	raise_value_label.add_theme_font_size_override("font_size", PokerTheme.FONT_SMALL)
	raise_value_label.add_theme_color_override("font_color", PokerTheme.GOLD)
	raise_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raise_container.add_child(raise_value_label)

	var shortcuts_hbox = HBoxContainer.new()
	shortcuts_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	shortcuts_hbox.add_theme_constant_override("separation", 3)
	raise_container.add_child(shortcuts_hbox)

	var fractions = [
		{"text": "¼", "frac": 0.25}, {"text": "⅓", "frac": 0.3333},
		{"text": "½", "frac": 0.5}, {"text": "⅔", "frac": 0.6666},
		{"text": "¾", "frac": 0.75}, {"text": "POT", "frac": 1.0}
	]
	for f in fractions:
		var btn = Button.new()
		btn.text = f.text
		btn.custom_minimum_size = Vector2(34, 22)
		btn.add_theme_font_size_override("font_size", 11)
		btn.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
		btn.focus_mode = Control.FOCUS_NONE
		var frac_val = f.frac
		btn.pressed.connect(func(): _on_quick_raise_pressed(frac_val))
		var sb = StyleBoxFlat.new()
		sb.bg_color = PokerTheme.BG_MEDIUM
		sb.corner_radius_top_left = 3; sb.corner_radius_top_right = 3
		sb.corner_radius_bottom_left = 3; sb.corner_radius_bottom_right = 3
		btn.add_theme_stylebox_override("normal", sb)
		var sbh = sb.duplicate()
		sbh.bg_color = PokerTheme.BG_PANEL
		btn.add_theme_stylebox_override("hover", sbh)
		shortcuts_hbox.add_child(btn)

	raise_slider = HSlider.new()
	raise_slider.custom_minimum_size = Vector2(240, 20)
	raise_slider.step = 10; raise_slider.min_value = 40; raise_slider.max_value = 1500; raise_slider.value = 40
	raise_slider.value_changed.connect(_on_raise_slider_changed)
	raise_slider.value_changed.connect(func(_val): _play_ui_sound())
	raise_container.add_child(raise_slider)

	btn_all_in = PokerTheme.make_action_button("ALL-IN", PokerTheme.BTN_ALLIN)
	btn_all_in.pressed.connect(func(): _play_ui_sound(); _on_ui_action_pressed("AllIn"))
	bottom_hbox.add_child(btn_all_in)

	# ---- LOG PANEL ----
	_setup_log_panel(canvas)

	# Network disconnect handler
	var nm = get_node("/root/NetworkManager") if has_node("/root/NetworkManager") else null
	if nm:
		nm.server_disconnected.connect(func():
			_add_log_message("[color=red]Server disconnected.[/color]", true)
			await get_tree().create_timer(2.0).timeout
			get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		)

func _add_vsep(parent: HBoxContainer) -> void:
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 36)
	sep.modulate = PokerTheme.BORDER_SUBTLE
	parent.add_child(sep)

func _setup_log_panel(canvas: CanvasLayer) -> void:
	log_panel = PanelContainer.new()
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(log_panel)
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT, true)
	log_panel.offset_left = 16; log_panel.offset_bottom = -128
	log_panel.offset_right = 310; log_panel.offset_top = -328

	var log_style = PokerTheme.make_panel_style(Color(0.03, 0.05, 0.04, 0.65), PokerTheme.BORDER_SUBTLE, PokerTheme.CORNER_SM, 1, 0)
	log_panel.add_theme_stylebox_override("panel", log_style)

	var log_header_margin = MarginContainer.new()
	log_header_margin.add_theme_constant_override("margin_right", 5)
	log_header_margin.add_theme_constant_override("margin_left", 5)
	log_header_margin.add_theme_constant_override("margin_top", 4)

	var log_header_box = HBoxContainer.new()
	log_header_box.alignment = BoxContainer.ALIGNMENT_END
	log_header_margin.add_child(log_header_box)

	btn_minimize_log = Button.new()
	btn_minimize_log.text = "[-]"
	btn_minimize_log.custom_minimum_size = Vector2(28, 20)
	btn_minimize_log.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_minimize_log.add_theme_font_size_override("font_size", 11)
	btn_minimize_log.pressed.connect(_toggle_log_size)
	log_header_box.add_child(btn_minimize_log)

	var log_outer_vbox = VBoxContainer.new()
	log_outer_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_outer_vbox.add_child(log_header_margin)

	log_scroll = ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_outer_vbox.add_child(log_scroll)
	log_panel.add_child(log_outer_vbox)

	var margin_container = MarginContainer.new()
	margin_container.add_theme_constant_override("margin_left", 8)
	margin_container.add_theme_constant_override("margin_top", 6)
	margin_container.add_theme_constant_override("margin_bottom", 6)
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(margin_container)

	log_vbox = VBoxContainer.new()
	log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_vbox.alignment = BoxContainer.ALIGNMENT_END
	margin_container.add_child(log_vbox)

	log_scroll.get_v_scroll_bar().changed.connect(func():
		log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)
	)

# ============================================================
# LOG
# ============================================================
func _add_log_message(msg: String, is_important: bool = false) -> void:
	if not log_vbox: return
	var rt = RichTextLabel.new()
	rt.bbcode_enabled = true; rt.text = msg; rt.fit_content = true
	rt.add_theme_font_size_override("normal_font_size", 15 if is_important else PokerTheme.FONT_LOG)
	rt.add_theme_color_override("default_color", PokerTheme.TEXT_PRIMARY.lerp(Color.WHITE, 0.1))
	log_vbox.add_child(rt)
	rt.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(rt, "modulate:a", 1.0, 0.15)
	if log_vbox.get_child_count() > 40:
		log_vbox.get_child(0).queue_free()
	if is_log_minimized:
		var log_header_box = btn_minimize_log.get_parent()
		if log_header_box.get_child_count() > 1:
			log_header_box.get_child(0).queue_free()
		var new_preview = rt.duplicate()
		new_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		log_header_box.add_child(new_preview)
		log_header_box.move_child(new_preview, 0)

func _toggle_log_size() -> void:
	is_log_minimized = !is_log_minimized
	if is_log_minimized:
		btn_minimize_log.text = "[+]"
		log_scroll.hide()
		log_panel.offset_top = -168
		if log_vbox.get_child_count() > 0:
			var last_msg = log_vbox.get_child(log_vbox.get_child_count() - 1).duplicate()
			last_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var log_header_box = btn_minimize_log.get_parent()
			if log_header_box.get_child_count() > 1:
				log_header_box.get_child(0).queue_free()
			log_header_box.add_child(last_msg)
			log_header_box.move_child(last_msg, 0)
	else:
		btn_minimize_log.text = "[-]"
		log_scroll.show()
		log_panel.offset_top = -328
		var log_header_box = btn_minimize_log.get_parent()
		if log_header_box.get_child_count() > 1:
			log_header_box.get_child(0).queue_free()

# ============================================================
# ACTION HANDLING
# ============================================================
func _play_ui_sound() -> void:
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth: synth.play_ui_click()

func _on_ui_action_pressed(action_type: String) -> void:
	var game_manager = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if !game_manager: return
	var human = null
	if game_manager.multiplayer_mode:
		human = game_manager._get_player_by_id(str(multiplayer.get_unique_id()))
	else:
		for p in game_manager.players:
			if !p.is_ai:
				human = p; break
	if !human: return

	match action_type:
		"Fold": human.receive_ui_input(GameManager.PlayerAction.FOLD, 0)
		"Call":
			var amount_to_call = game_manager.current_bet - human.current_bet
			if amount_to_call > 0:
				human.receive_ui_input(GameManager.PlayerAction.CALL, 0)
			else:
				human.receive_ui_input(GameManager.PlayerAction.CHECK, 0)
		"Raise": human.receive_ui_input(GameManager.PlayerAction.RAISE, int(raise_slider.value))
		"AllIn": human.receive_ui_input(GameManager.PlayerAction.ALL_IN, human.chips)

	_set_action_buttons_disabled(true)
	_my_turn = false
	_turn_timer.stop()
	timer_bar.value = 0
	if _turn_pulse_tween and _turn_pulse_tween.is_running():
		_turn_pulse_tween.kill()
		turn_label.modulate.a = 1.0

	# Brief press feedback
	var tw = create_tween()
	tw.tween_property(_action_bar, "modulate", Color(1.2, 1.2, 1.2), 0.06)
	tw.tween_property(_action_bar, "modulate", Color.WHITE, 0.12)

func _set_action_buttons_disabled(disabled: bool) -> void:
	if btn_fold: btn_fold.disabled = disabled
	if btn_call_check: btn_call_check.disabled = disabled
	if btn_raise: btn_raise.disabled = disabled
	if btn_all_in: btn_all_in.disabled = disabled
	if raise_slider: raise_slider.editable = !disabled

func _on_raise_slider_changed(value: float) -> void:
	if raise_value_label:
		raise_value_label.text = "$" + str(int(value))

func _on_quick_raise_pressed(frac_val: float) -> void:
	if not raise_slider: return
	_play_ui_sound()
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm and gm.pot_manager:
		var current_pot = _get_current_pot()
		var target_raise = int(current_pot * frac_val)
		if gm.big_blind > 0:
			target_raise = int(round(float(target_raise) / float(gm.big_blind)) * gm.big_blind)
		var final_val = clamp(target_raise, raise_slider.min_value, raise_slider.max_value)
		raise_slider.value = final_val

# ============================================================
# TURN TIMER
# ============================================================
func _on_turn_timer_tick() -> void:
	if not _my_turn: return
	timer_bar.value -= (100.0 / _turn_timer_max) * _turn_timer.wait_time
	if timer_bar.value <= 0:
		timer_bar.value = 0
		_on_ui_action_pressed("Fold")
	var pct = timer_bar.value / 100.0
	if pct > 0.5:
		timer_bar.modulate = PokerTheme.ACCENT_GREEN.lerp(PokerTheme.GOLD, 1.0 - (pct - 0.5) * 2.0)
	else:
		timer_bar.modulate = PokerTheme.GOLD.lerp(PokerTheme.ACCENT_RED, 1.0 - pct * 2.0)

# ============================================================
# UI UPDATE CALLBACKS
# ============================================================
func _on_state_changed(new_state: int, _old_state: int) -> void:
	if not state_label: return
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null

	match new_state:
		GameManager.GameState.WAITING_FOR_PLAYERS: state_label.text = _tc("Preparing...", "Đang chuẩn bị...")
		GameManager.GameState.DEALING_HOLE_CARDS:
			state_label.text = _tc("Dealing...", "Chia bài...")
			_clear_card_display()
		GameManager.GameState.PREFLOP_BETTING: state_label.text = "Pre-Flop"
		GameManager.GameState.DEALING_FLOP: state_label.text = _tc("Flop...", "Lật Flop...")
		GameManager.GameState.FLOP_BETTING: state_label.text = "Flop"
		GameManager.GameState.DEALING_TURN: state_label.text = _tc("Turn...", "Lật Turn...")
		GameManager.GameState.TURN_BETTING: state_label.text = "Turn"
		GameManager.GameState.DEALING_RIVER: state_label.text = _tc("River...", "Lật River...")
		GameManager.GameState.RIVER_BETTING: state_label.text = "River"
		GameManager.GameState.SHOWDOWN: state_label.text = "Showdown!"
		GameManager.GameState.DISTRIBUTING_POTS: state_label.text = _tc("Distributing...", "Chia tiền...")
		GameManager.GameState.ROUND_END: state_label.text = _tc("Round End", "Kết thúc ván")

	# State text pop
	var tw_st = create_tween()
	state_label.modulate = Color(1.3, 1.3, 1.3)
	tw_st.tween_property(state_label, "modulate", Color.WHITE, 0.3)

	if new_state in [GameManager.GameState.PREFLOP_BETTING, GameManager.GameState.FLOP_BETTING,
			GameManager.GameState.TURN_BETTING, GameManager.GameState.RIVER_BETTING]:
		var txt = _tc("--- Betting: ", "--- Vòng Cược: ")
		_add_log_message("[color=#66ccff]" + txt + state_label.text + " ---[/color]", true)
	elif new_state == GameManager.GameState.SHOWDOWN:
		_add_log_message("[color=#ffcc66]" + _tc("--- Showdown ---", "--- Lật Bài ---") + "[/color]", true)

	_set_action_buttons_disabled(true)
	_my_turn = false
	_turn_timer.stop()
	timer_bar.value = 0
	if _turn_pulse_tween and _turn_pulse_tween.is_running():
		_turn_pulse_tween.kill()
		turn_label.modulate.a = 1.0

	if gm and pot_label:
		_animate_pot_label(_get_current_pot())
	_update_chips_label()

var _displayed_pot: int = 0
func _animate_pot_label(target: int) -> void:
	if not pot_label: return
	var start = _displayed_pot
	_displayed_pot = target
	if start == target:
		pot_label.text = "POT: $" + str(target)
		return
	var tw = create_tween()
	tw.tween_method(func(v: float):
		pot_label.text = "POT: $" + str(int(v))
	, float(start), float(target), 0.35)

func _on_blinds_level_changed(level: int, sb: int, bb: int) -> void:
	if blinds_label:
		blinds_label.text = "BLINDS: " + str(sb) + "/" + str(bb) + " (Lvl " + str(level) + ")"
		var tw = create_tween()
		blinds_label.modulate = Color(1.6, 1.2, 1.2)
		tw.tween_property(blinds_label, "modulate", Color.WHITE, 0.6)

func _on_action_received(player_id: String, action: int, amount: int) -> void:
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm and pot_label:
		_animate_pot_label(_get_current_pot())
	_update_chips_label()
	if action < 0: return

	var action_str = ""
	var p_color = "yellow" if (player_id == "You" or player_id == _tc("You", "Bạn")) else "lightblue"
	match action:
		GameManager.PlayerAction.FOLD: action_str = _tc("[color=#e85555]folded[/color]", "[color=#e85555]Fold[/color]")
		GameManager.PlayerAction.CHECK: action_str = _tc("[color=#999]checked[/color]", "[color=#999]Check[/color]")
		GameManager.PlayerAction.CALL: action_str = _tc("[color=#6be87a]called[/color]", "[color=#6be87a]Call[/color]")
		GameManager.PlayerAction.RAISE: action_str = _tc("[color=#f0b030]raised $" + str(amount) + "[/color]", "[color=#f0b030]Raise $" + str(amount) + "[/color]")
		GameManager.PlayerAction.ALL_IN: action_str = _tc("[color=#c86ef0]ALL-IN $" + str(amount) + "[/color]", "[color=#c86ef0]ALL-IN $" + str(amount) + "[/color]")
	_add_log_message("[color=" + p_color + "]" + player_id + "[/color] " + action_str)

func _on_player_turn(player_id: String) -> void:
	if not turn_label: return
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if not gm: return
	var p = gm._get_player_by_id(player_id)
	if not p: return

	# Kill previous pulse
	if _turn_pulse_tween and _turn_pulse_tween.is_running():
		_turn_pulse_tween.kill()
		turn_label.modulate.a = 1.0

	if p.is_ai:
		turn_label.text = _tc("Turn: ", "Lượt: ") + p.id + _tc(" ...", " ...")
		turn_label.add_theme_color_override("font_color", PokerTheme.ACCENT_GREEN.darkened(0.2))
		_set_action_buttons_disabled(true)
		_my_turn = false
		_turn_timer.stop(); timer_bar.value = 0
	else:
		var my_id = "You" if not gm.multiplayer_mode else str(multiplayer.get_unique_id())
		if p.id == my_id:
			turn_label.text = _tc(">>> YOUR TURN <<<", ">>> LƯỢT CỦA BẠN <<<")
			turn_label.add_theme_color_override("font_color", PokerTheme.GOLD_BRIGHT)
			# Pulse animation
			_turn_pulse_tween = create_tween().set_loops(0)
			_turn_pulse_tween.tween_property(turn_label, "modulate:a", 0.5, 0.6).set_trans(Tween.TRANS_SINE)
			_turn_pulse_tween.tween_property(turn_label, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)

			_set_action_buttons_disabled(false)
			_my_turn = true
			timer_bar.value = 100
			_turn_timer.start()

			var amount_to_call = gm.current_bet - p.current_bet
			if btn_call_check:
				if amount_to_call > 0:
					btn_call_check.text = "CALL $" + str(min(amount_to_call, p.chips)) if amount_to_call < p.chips else "CALL ALL-IN"
					btn_call_check.modulate = Color(1.0, 0.85, 0.85)
				else:
					btn_call_check.text = "CHECK"
					btn_call_check.modulate = Color.WHITE
			if btn_raise:
				btn_raise.disabled = (p.chips <= amount_to_call)
			if btn_raise and raise_slider:
				var min_r = gm.current_bet + gm.min_raise
				raise_slider.max_value = p.chips + p.current_bet
				raise_slider.min_value = min(min_r, raise_slider.max_value)
				raise_slider.step = gm.big_blind
				raise_slider.value = raise_slider.min_value
				btn_raise.text = "RAISE"
				if raise_value_label:
					raise_value_label.text = "$" + str(int(raise_slider.value))

			# Flash bottom bar
			var tw_bar = create_tween()
			tw_bar.tween_property(_action_bar, "modulate", Color(1.15, 1.10, 0.95), 0.15)
			tw_bar.tween_property(_action_bar, "modulate", Color.WHITE, 0.25)
		else:
			turn_label.text = _tc("Turn: ", "Lượt: ") + p.id
			turn_label.add_theme_color_override("font_color", PokerTheme.ACCENT_BLUE)
			_set_action_buttons_disabled(true)
			_my_turn = false
			_turn_timer.stop(); timer_bar.value = 0

func _on_community_changed(_cards: Array) -> void:
	_update_chips_label()

func _update_chips_label() -> void:
	if not chips_label: return
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		for p in gm.players:
			if !p.is_ai:
				var new_text = "CHIPS: $" + str(p.chips)
				if chips_label.text != new_text:
					chips_label.text = new_text
					var tw = create_tween()
					chips_label.modulate = Color(1.3, 1.2, 0.9)
					tw.tween_property(chips_label, "modulate", Color.WHITE, 0.25)
				break

func _on_winners_declared_ui(payouts: Dictionary, _best_cards: Dictionary) -> void:
	_update_chips_label()
	for pid in payouts:
		var amt = payouts[pid]
		if amt > 0:
			var p_color = "yellow" if pid == "You" else "lightblue"
			var win_text = _tc(" won ", " thắng ")
			_add_log_message("[color=" + p_color + "]" + pid + "[/color]" + win_text + "[color=gold]$" + str(amt) + "[/color]!")
			if pid == "You" or (get_node("/root/GameManager") and get_node("/root/GameManager").multiplayer_mode and pid == str(multiplayer.get_unique_id())):
				_show_win_banner(amt)

func _show_win_banner(amt: int) -> void:
	var canvas = get_node_or_null("GameUI")
	if not canvas: return
	var win_lbl = Label.new()
	win_lbl.text = _tc("YOU WON $", "BẠN THẮNG $") + str(amt)
	win_lbl.add_theme_font_size_override("font_size", 52)
	win_lbl.add_theme_color_override("font_color", PokerTheme.GOLD)
	win_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	win_lbl.add_theme_constant_override("outline_size", 10)
	win_lbl.set_anchors_preset(Control.PRESET_CENTER)
	win_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(win_lbl)
	win_lbl.scale = Vector2.ZERO; win_lbl.modulate.a = 0.0
	var tw = create_tween()
	tw.set_parallel(true)
	tw.tween_property(win_lbl, "scale", Vector2(1.15, 1.15), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(win_lbl, "modulate:a", 1.0, 0.15)
	tw.chain().tween_property(win_lbl, "scale", Vector2.ONE, 0.15)
	tw.tween_interval(1.8)
	tw.tween_property(win_lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(win_lbl.queue_free)
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if synth: synth.play_win()

func _on_human_card_drawn(card: Card) -> void:
	if not card_display: return
	var tex_rect = TextureRect.new()
	tex_rect.texture = CardTextureGenerator.get_card_texture(card)
	tex_rect.custom_minimum_size = Vector2(42, 58)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	tex_rect.modulate.a = 0.0; tex_rect.scale = Vector2(0.5, 0.5)
	tex_rect.pivot_offset = Vector2(21, 29)
	card_display.add_child(tex_rect)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(tex_rect, "modulate:a", 1.0, 0.2)
	tw.tween_property(tex_rect, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _clear_card_display() -> void:
	if not card_display: return
	for child in card_display.get_children():
		child.queue_free()

func _on_human_card_updated(card: Card) -> void:
	if not card_display: return
	var children = card_display.get_children()
	if children.size() > 0:
		var last_tex_rect = children.back() as TextureRect
		if last_tex_rect:
			last_tex_rect.texture = CardTextureGenerator.get_card_texture(card)

# ============================================================
# GAME OVER OVERLAY
# ============================================================
func _on_game_over(human_won: bool) -> void:
	var synth = get_node("/root/AudioSynthesizer") if has_node("/root/AudioSynthesizer") else null
	if human_won and synth: synth.play_win()

	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var popup_bg = ColorRect.new()
	popup_bg.color = Color(0, 0, 0, 0)
	popup_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(popup_bg)
	var tw_bg = create_tween()
	tw_bg.tween_property(popup_bg, "color:a", 0.85, 0.5)

	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_bg.add_child(center_container)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	center_container.add_child(vbox)

	var lbl = Label.new()
	lbl.text = _tc("YOU WIN!\nCHAMPION", "BẠN THẮNG!\nVÔ ĐỊCH") if human_won else _tc("BANKRUPT\nGAME OVER", "PHÁ SẢN\nHẾT TIỀN")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 60)
	lbl.add_theme_color_override("font_color", PokerTheme.GOLD if human_won else PokerTheme.ACCENT_RED)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 8)
	vbox.add_child(lbl)

	lbl.scale = Vector2(0.5, 0.5); lbl.modulate.a = 0.0; lbl.pivot_offset = Vector2(200, 50)
	var tw_t = create_tween().set_parallel(true)
	tw_t.tween_property(lbl, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw_t.tween_property(lbl, "modulate:a", 1.0, 0.25)

	if not human_won:
		var btn_rebuy = PokerTheme.make_menu_button("REBUY ($5000)", PokerTheme.ACCENT_GREEN)
		btn_rebuy.pressed.connect(func():
			var sm2 = get_node("/root/SaveManager") if has_node("/root/SaveManager") else null
			if sm2: sm2.update_chips(5000)
			get_tree().reload_current_scene()
		)
		PokerTheme.attach_hover_anim(btn_rebuy, self)
		vbox.add_child(btn_rebuy)

	var btn_menu = PokerTheme.make_menu_button(_tc("MAIN MENU", "VỀ MENU"), PokerTheme.GOLD)
	btn_menu.pressed.connect(func():
		var gm2 = get_node("/root/GameManager") if has_node("/root/GameManager") else null
		if gm2 and gm2.multiplayer_mode:
			multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	PokerTheme.attach_hover_anim(btn_menu, self)
	vbox.add_child(btn_menu)

# ============================================================
# PAUSE / SETTINGS
# ============================================================
func _show_pause_menu() -> void:
	_play_ui_sound()
	if has_node("PauseOverlay"): return

	var overlay = ColorRect.new()
	overlay.name = "PauseOverlay"
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)

	var title = Label.new()
	title.text = _tc("PAUSED", "TẠM DỪNG")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", PokerTheme.GOLD)
	vbox.add_child(title)

	var btn_resume = PokerTheme.make_menu_button(_tc("RESUME", "TIẾP TỤC"), PokerTheme.ACCENT_GREEN)
	btn_resume.pressed.connect(func(): _play_ui_sound(); PokerTheme.fade_out_and_free(overlay, self, 0.15))
	PokerTheme.attach_hover_anim(btn_resume, self)
	vbox.add_child(btn_resume)

	var btn_settings = PokerTheme.make_menu_button(_tc("SETTINGS", "CÀI ĐẶT"), PokerTheme.ACCENT_BLUE)
	btn_settings.pressed.connect(func(): _play_ui_sound(); _show_settings_panel())
	PokerTheme.attach_hover_anim(btn_settings, self)
	vbox.add_child(btn_settings)

	var btn_quit = PokerTheme.make_menu_button(_tc("QUIT TO MENU", "VỀ MENU"), PokerTheme.ACCENT_RED)
	btn_quit.pressed.connect(func():
		_play_ui_sound()
		var gm3 = get_node("/root/GameManager") if has_node("/root/GameManager") else null
		if gm3 and gm3.multiplayer_mode: multiplayer.multiplayer_peer = null
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	PokerTheme.attach_hover_anim(btn_quit, self)
	vbox.add_child(btn_quit)

	get_node("GameUI").add_child(overlay)
	var tw = create_tween()
	tw.tween_property(overlay, "color:a", 0.75, 0.2)

func _show_settings_panel() -> void:
	if has_node("SettingsPanel"): return

	var overlay = CenterContainer.new()
	overlay.name = "SettingsPanel"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 420)
	var style = PokerTheme.make_panel_style(Color(0.08, 0.08, 0.12, 0.96), PokerTheme.ACCENT_BLUE.darkened(0.4), PokerTheme.CORNER_LG, 2, 20)
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
	var master_slider = _add_settings_slider(vbox, _tc("Master Vol:", "Tổng:"), 0.0, 1.0, 0.05, sm.master_volume if sm else 1.0)
	var sfx_slider = _add_settings_slider(vbox, _tc("SFX Vol:", "Hiệu ứng:"), 0.0, 1.0, 0.05, sm.sfx_volume if sm else 1.0)
	var bgm_slider = _add_settings_slider(vbox, _tc("Music Vol:", "Nhạc:"), 0.0, 1.0, 0.05, sm.bgm_volume if sm else 0.5)

	var fast_box = HBoxContainer.new()
	fast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var fast_lbl = Label.new()
	fast_lbl.text = _tc("Fast Bot:", "Bot Nhanh:")
	fast_lbl.custom_minimum_size = Vector2(130, 0)
	fast_lbl.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var fast_check = CheckButton.new()
	fast_check.text = _tc("Skip Delays", "Bỏ Chờ")
	fast_check.focus_mode = Control.FOCUS_NONE
	if sm: fast_check.button_pressed = sm.fast_bot_mode
	fast_box.add_child(fast_lbl); fast_box.add_child(fast_check)
	vbox.add_child(fast_box)

	var bot_lbl_ref: Label
	var bot_box = HBoxContainer.new()
	bot_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_lbl_ref = Label.new()
	bot_lbl_ref.text = _tc("Opponents: ", "Đối thủ: ") + str(sm.num_bots if sm else 4)
	bot_lbl_ref.custom_minimum_size = Vector2(130, 0)
	bot_lbl_ref.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var bot_slider = HSlider.new()
	bot_slider.custom_minimum_size = Vector2(200, 28)
	bot_slider.min_value = 1; bot_slider.max_value = 8; bot_slider.step = 1
	bot_slider.focus_mode = Control.FOCUS_NONE
	if sm: bot_slider.value = sm.num_bots
	bot_box.add_child(bot_lbl_ref); bot_box.add_child(bot_slider)
	vbox.add_child(bot_box)

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
		fast_check.toggled.connect(func(pressed): sm.fast_bot_mode = pressed; sm.apply_and_save())
		bot_slider.value_changed.connect(func(val):
			sm.num_bots = int(val)
			bot_lbl_ref.text = _tc("Opponents: ", "Đối thủ: ") + str(sm.num_bots)
			sm.apply_and_save()
		)

	var btn_close = PokerTheme.make_menu_button(_tc("SAVE & CLOSE", "LƯU & ĐÓNG"), PokerTheme.ACCENT_GREEN, Vector2(220, 44))
	btn_close.pressed.connect(func(): _play_ui_sound(); overlay.queue_free())
	var btn_box = CenterContainer.new()
	btn_box.add_child(btn_close)
	vbox.add_child(btn_box)

	overlay.add_child(panel)
	get_node("GameUI").add_child(overlay)
	if sm: master_slider.value_changed.emit(master_slider.value)
	PokerTheme.popup_animate(panel, self)

func _add_settings_slider(parent: VBoxContainer, label_text: String, min_v: float, max_v: float, step_v: float, current: float) -> HSlider:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(130, 0)
	lbl.add_theme_color_override("font_color", PokerTheme.TEXT_SECONDARY)
	var slider = HSlider.new()
	slider.custom_minimum_size = Vector2(200, 28)
	slider.min_value = min_v; slider.max_value = max_v; slider.step = step_v
	slider.value = current; slider.focus_mode = Control.FOCUS_NONE
	hbox.add_child(lbl); hbox.add_child(slider)
	parent.add_child(hbox)
	return slider

# ============================================================
# HELPERS
# ============================================================
func _tc(en: String, vi: String) -> String:
	var sm = get_node("/root/SettingsManager") if has_node("/root/SettingsManager") else null
	if sm and sm.has_method("tc"): return sm.tc(en, vi)
	return en

func _get_current_pot() -> int:
	var gm = get_node("/root/GameManager") if has_node("/root/GameManager") else null
	if gm:
		if gm.multiplayer_mode: return gm.client_pot
		elif gm.pot_manager: return gm.pot_manager.get_total_pot()
	return 0
