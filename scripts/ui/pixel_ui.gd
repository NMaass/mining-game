class_name PixelUi
extends RefCounted
## Shared 8-bit UI styling and button feel.
##
## This is intentionally small: it standardizes bevels, font, press/reset animation,
## focus outline, and button SFX without moving gameplay logic into UI widgets.

const PIXEL_FONT := preload("res://art/fonts/PixelifySans.ttf")

static func apply_button(button: Button, variant: String = "secondary", font_size: int = 22) -> void:
	if button == null:
		return
	button.add_theme_font_override("font", PIXEL_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	var normal: StyleBoxFlat = button_style(variant, false)
	var hover: StyleBoxFlat = button_style(variant, true)
	var pressed: StyleBoxFlat = button_style(variant, true)
	var disabled: StyleBoxFlat = button_style("disabled", false)
	var focus: StyleBoxFlat = button_style("focus", true)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus)
	button.focus_mode = Control.FOCUS_ALL

static func button_style(variant: String = "secondary", raised: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	var bg := Color(0.18, 0.20, 0.25, 1)
	var border := Color(0.35, 0.38, 0.45, 1)
	if variant == "primary":
		bg = Color(0.88, 0.38, 0.13, 1)
		border = Color(0.62, 0.20, 0.06, 1)
	elif variant == "disabled":
		bg = Color(0.20, 0.20, 0.22, 1)
		border = Color(0.30, 0.30, 0.33, 1)
	elif variant == "focus":
		bg = Color(0.20, 0.22, 0.28, 1)
		border = Color(1.0, 0.88, 0.34, 1)
	elif variant == "danger":
		bg = Color(0.62, 0.18, 0.12, 1)
		border = Color(0.35, 0.08, 0.05, 1)
	if raised and variant != "disabled":
		bg = bg.lightened(0.10)
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 4
	if variant == "focus":
		sb.border_width_left = 4
		sb.border_width_top = 4
		sb.border_width_right = 4
		sb.border_width_bottom = 4
	return sb

static func apply_panel(panel: PanelContainer, kind: String = "panel") -> void:
	if panel == null:
		return
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 4
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.98) if kind == "panel" else Color(0.13, 0.14, 0.18, 0.96)
	sb.border_color = Color(0.42, 0.38, 0.30, 1)
	panel.add_theme_stylebox_override("panel", sb)

static func bind_button_feel(button: Button, motion_getter: Callable = Callable()) -> void:
	if button == null or bool(button.get_meta("_pixel_feel_bound", false)):
		return
	button.set_meta("_pixel_feel_bound", true)
	button.button_down.connect(func() -> void:
		if button.disabled:
			_play("button_disabled")
			return
		_play("button_press")
		_press_scale(button, _motion(motion_getter), true)
	)
	button.button_up.connect(func() -> void:
		_press_scale(button, _motion(motion_getter), false)
	)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			_play("button_hover")
	)
	button.focus_entered.connect(func() -> void:
		if not button.disabled:
			_play("button_hover")
	)
	button.visibility_changed.connect(func() -> void:
		_reset(button)
	)
	button.tree_exiting.connect(func() -> void:
		_reset(button)
	)

static func _press_scale(button: Button, motion: float, down: bool) -> void:
	if motion <= 0.01:
		_reset(button)
		return
	var existing: Variant = button.get_meta("_pixel_feel_tween", null)
	if existing is Tween and (existing as Tween).is_valid():
		(existing as Tween).kill()
	button.pivot_offset = button.size * 0.5
	var target := Vector2(0.96, 0.90) if down else Vector2.ONE
	var tw: Tween = button.create_tween()
	button.set_meta("_pixel_feel_tween", tw)
	tw.tween_property(button, "scale", target, 0.06 if down else 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func _reset(button: Button) -> void:
	var existing: Variant = button.get_meta("_pixel_feel_tween", null)
	if existing is Tween and (existing as Tween).is_valid():
		(existing as Tween).kill()
	button.scale = Vector2.ONE
	button.modulate.a = 1.0

static func _motion(getter: Callable) -> float:
	if getter.is_valid():
		return clampf(float(getter.call()), 0.0, 1.0)
	return 1.0

static func _play(event: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var audio: Node = tree.root.get_node_or_null("Audio")
	if audio != null and audio.has_method("play"):
		audio.call("play", event)
