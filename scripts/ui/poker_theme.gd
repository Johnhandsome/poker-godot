class_name PokerTheme
extends RefCounted

# ============================================================
# POKER THEME — Single source of truth for all UI styling
# ============================================================

# ---- PALETTE ----
const BG_DARK        = Color(0.04, 0.06, 0.05, 0.92)
const BG_MEDIUM      = Color(0.06, 0.10, 0.08, 0.94)
const BG_PANEL       = Color(0.07, 0.10, 0.09, 0.96)
const BG_OVERLAY     = Color(0, 0, 0, 0.78)

const BORDER         = Color(0.40, 0.58, 0.30, 0.55)
const BORDER_FOCUS   = Color(0.55, 0.80, 0.40, 0.80)
const BORDER_SUBTLE  = Color(0.25, 0.35, 0.20, 0.35)

const GOLD           = Color(1.0, 0.85, 0.25)
const GOLD_DIM       = Color(0.80, 0.65, 0.18)
const GOLD_BRIGHT    = Color(1.0, 0.92, 0.50)

const TEXT_PRIMARY    = Color(0.92, 0.94, 0.90)
const TEXT_SECONDARY  = Color(0.65, 0.72, 0.60)
const TEXT_MUTED      = Color(0.45, 0.50, 0.40)

const ACCENT_GREEN    = Color(0.30, 0.78, 0.42)
const ACCENT_BLUE     = Color(0.35, 0.70, 0.90)
const ACCENT_RED      = Color(0.90, 0.30, 0.25)
const ACCENT_ORANGE   = Color(0.95, 0.70, 0.15)
const ACCENT_PURPLE   = Color(0.72, 0.35, 0.90)

# Action button accent colours
const BTN_FOLD        = Color(0.85, 0.30, 0.25)
const BTN_CHECK       = Color(0.35, 0.70, 0.85)
const BTN_RAISE       = Color(0.92, 0.78, 0.20)
const BTN_ALLIN       = Color(0.80, 0.40, 0.90)

# ---- GEOMETRY ----
const CORNER_SM  = 6
const CORNER_MD  = 10
const CORNER_LG  = 14

# ---- ANIMATION CONSTANTS ----
const ANIM_FAST      = 0.12
const ANIM_NORMAL    = 0.22
const ANIM_SLOW      = 0.40
const ANIM_POPUP     = 0.25
const HOVER_SCALE    = Vector2(1.04, 1.04)

# ---- FONT SIZES ----
const FONT_TITLE     = 56
const FONT_SUBTITLE  = 28
const FONT_BODY      = 18
const FONT_BUTTON    = 17
const FONT_SMALL     = 14
const FONT_LOG       = 13

# ============================================================
# FACTORY METHODS
# ============================================================

## Builds a rounded panel StyleBoxFlat.
static func make_panel_style(
		bg: Color = BG_PANEL,
		border_color: Color = BORDER,
		corner: int = CORNER_MD,
		border_width: int = 1,
		padding: int = 12
	) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = corner
	s.corner_radius_top_right = corner
	s.corner_radius_bottom_left = corner
	s.corner_radius_bottom_right = corner
	s.border_width_left = border_width
	s.border_width_right = border_width
	s.border_width_top = border_width
	s.border_width_bottom = border_width
	s.border_color = border_color
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s


## Builds a standard action button with normal / hover / pressed states.
static func make_action_button(
		text: String,
		accent: Color,
		min_size: Vector2 = Vector2(115, 48)
	) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", FONT_BUTTON)
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	# normal
	var sn = StyleBoxFlat.new()
	sn.bg_color = Color(0.07, 0.09, 0.08, 0.96)
	_apply_round(sn, CORNER_SM)
	sn.border_width_bottom = 3; sn.border_width_top = 1
	sn.border_width_left = 1; sn.border_width_right = 1
	sn.border_color = accent.darkened(0.25)
	sn.shadow_color = Color(0, 0, 0, 0.25)
	sn.shadow_size = 2
	sn.shadow_offset = Vector2(0, 1)
	btn.add_theme_stylebox_override("normal", sn)
	# hover
	var sh = sn.duplicate()
	sh.bg_color = Color(0.12, 0.15, 0.13, 0.98)
	sh.border_color = accent
	sh.shadow_size = 4
	btn.add_theme_stylebox_override("hover", sh)
	# pressed
	var sp = sn.duplicate()
	sp.bg_color = accent.darkened(0.55)
	sp.border_color = accent.darkened(0.10)
	sp.border_width_bottom = 1; sp.border_width_top = 2
	btn.add_theme_stylebox_override("pressed", sp)
	# disabled
	var sd = sn.duplicate()
	sd.bg_color = Color(0.06, 0.06, 0.06, 0.70)
	sd.border_color = Color(0.25, 0.25, 0.25, 0.40)
	btn.add_theme_stylebox_override("disabled", sd)
	btn.add_theme_color_override("font_disabled_color", TEXT_MUTED)
	return btn


## Large menu button used in main menu and pause menu.
static func make_menu_button(text: String, accent: Color = GOLD, min_size: Vector2 = Vector2(280, 56)) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", TEXT_PRIMARY)
	var sn = make_panel_style(BG_DARK, accent.darkened(0.20), CORNER_MD, 1, 10)
	sn.border_width_bottom = 3
	btn.add_theme_stylebox_override("normal", sn)
	var sh = sn.duplicate()
	sh.bg_color = BG_MEDIUM
	sh.border_color = accent
	btn.add_theme_stylebox_override("hover", sh)
	var sp = sn.duplicate()
	sp.bg_color = accent.darkened(0.55)
	btn.add_theme_stylebox_override("pressed", sp)
	return btn


## Attach hover-scale tween to a button.
static func attach_hover_anim(ctrl: Control, parent_node: Node) -> void:
	ctrl.pivot_offset = ctrl.custom_minimum_size / 2.0
	ctrl.mouse_entered.connect(func():
		var tw = parent_node.create_tween()
		tw.tween_property(ctrl, "scale", HOVER_SCALE, ANIM_FAST).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)
	ctrl.mouse_exited.connect(func():
		var tw = parent_node.create_tween()
		tw.tween_property(ctrl, "scale", Vector2.ONE, ANIM_FAST).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	)


## Popup-scale-in animation for a panel node.
static func popup_animate(panel: Control, parent_node: Node, center: Vector2 = Vector2.ZERO) -> void:
	if center != Vector2.ZERO:
		panel.pivot_offset = center
	else:
		panel.pivot_offset = panel.custom_minimum_size / 2.0
	panel.scale = Vector2(0.6, 0.6)
	panel.modulate.a = 0.0
	var tw = parent_node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, ANIM_POPUP).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, ANIM_POPUP * 0.6)


## Fade-in helper.
static func fade_in(ctrl: CanvasItem, parent_node: Node, duration: float = ANIM_NORMAL) -> Tween:
	ctrl.modulate.a = 0.0
	var tw = parent_node.create_tween()
	tw.tween_property(ctrl, "modulate:a", 1.0, duration)
	return tw


## Fade-out and queue_free helper.
static func fade_out_and_free(ctrl: CanvasItem, parent_node: Node, duration: float = ANIM_NORMAL) -> void:
	var tw = parent_node.create_tween()
	tw.tween_property(ctrl, "modulate:a", 0.0, duration)
	tw.tween_callback(ctrl.queue_free)


# -- internal helpers --
static func _apply_round(s: StyleBoxFlat, r: int) -> void:
	s.corner_radius_top_left = r
	s.corner_radius_top_right = r
	s.corner_radius_bottom_left = r
	s.corner_radius_bottom_right = r
