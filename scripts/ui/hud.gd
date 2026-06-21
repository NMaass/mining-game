class_name Hud
extends CanvasLayer
## Thin HUD: money + depth (top-left), a nav button (top-right), and a compact
## relic-progress indicator (AC-5.8.1). It owns no game state — the mine controller
## pushes values in via `set_money` / `set_depth` / `set_relic_progress`. No balance
## literals; everything displayed is passed in. Headless-safe: the labels are looked
## up with get_node_or_null so a bare instance (no children) is a no-op, not a crash.
##
## Portrait layout (AC-5.8.5): the top bar, nav button and bottom control bar are
## positioned RESPONSIVELY each layout pass inside the device safe area — bottom
## controls sit above the home-indicator/gesture zone, top controls below the
## notch/status bar — via the pure UiLayout helper fed live DisplayServer metrics.
## Interactive controls are sized to the data-driven thumb-safe touch-target minimum.
## The layout recomputes on viewport resize so it reflows across the portrait
## aspect-ratio range (AC-5.8.6, partial — full text-scale abbreviation is ROADMAP).
##
## ACs: AC-5.8.1 (money + depth top-left, nav top-right, compact relic progress),
##      AC-5.8.4 (the dig-end is a distinct panel — see DigEndPanel, shown by mine.gd),
##      AC-5.8.5 (safe-area insets + >= ~44–48px touch targets).

## Emitted when the nav button is pressed (the controller opens overlays).
signal nav_pressed
## Emitted when the player presses the prominent "End Dig" / "Prestige" button.
signal end_dig_pressed
## Emitted when the elevator "up" arrow is PRESSED DOWN (button_down). Drives the
## hold-to-glide poll in the controller — fire on press, not on release, so a tap
## starts the move immediately and a hold glides (the poll's first-frame guarantee
## covers the single-row tap).
signal elevator_up_pressed
## Emitted when the elevator "up" arrow is RELEASED (button_up) — stops the glide.
signal elevator_up_released
## Emitted when the elevator "down" arrow is PRESSED DOWN (button_down).
signal elevator_down_pressed
## Emitted when the elevator "down" arrow is RELEASED (button_up) — stops the glide.
signal elevator_down_released

# Internal layout spacing (presentation detail, not game balance): the gap between the
# control bars and surrounding chrome, and how far the bottom background extends behind
# the controls. The accessibility-meaningful values (touch target, edge margin) are data.
const _BAR_PAD := 10.0
const _NAV_RESERVE := 220.0  # horizontal room kept for the top-right buttons
## Vertical gap between the selector row and the action row inside the bottom VBox. Presentation
## spacing (like _BAR_PAD), matching the authored VBoxContainer separation — not game balance.
const _STACK_GAP := 8.0
## Fixed vertical gap (logical px) between the up slot and the down slot. Presentation spacing
## (like _BAR_PAD), not game balance — the slot POSITIONS are what must stay fixed.
const _ELEVATOR_SLOT_GAP := 12.0
const PIXEL_UI_SCRIPT := preload("res://scripts/ui/pixel_ui.gd")
const _ScreenTransition := preload("res://scripts/core/screen_transition.gd")

@onready var _top: Control = get_node_or_null("Top")
@onready var _money_box: Control = get_node_or_null("Top/MoneyBox")
@onready var _money_icon: Control = get_node_or_null("Top/MoneyBox/Row/MoneyIcon")
@onready var _money_label: Label = get_node_or_null("Top/MoneyBox/Row/Money")
@onready var _depth_label: Label = get_node_or_null("Top/DepthBox/Row/Depth")
@onready var _relic_label: Label = get_node_or_null("Top/RelicBox/Row/Relic")
## Dedicated resource-odds strip (AC-5.8.8): a styled panel below the top bar. `_odds_label`
## is the legible, test-read STRING; `_odds_entries` is the colour-coded chip row players see.
@onready var _odds_bar: Control = get_node_or_null("OddsBar")
@onready var _odds_label: Label = get_node_or_null("OddsBar/Row/Odds")
@onready var _odds_entries: Control = get_node_or_null("OddsBar/Row/Entries")
@onready var _top_right: Control = get_node_or_null("TopRight")
@onready var _nav_button: Button = get_node_or_null("TopRight/NavButton")
@onready var _end_dig_button: Button = get_node_or_null("TopRight/EndDigButton")
@onready var _elevator_controls: Control = get_node_or_null("ElevatorControls")
@onready var _elevator_up: Button = get_node_or_null("ElevatorControls/ElevatorUp")
@onready var _elevator_down: Button = get_node_or_null("ElevatorControls/ElevatorDown")
@onready var _bottom: Control = get_node_or_null("Bottom")
@onready var _bottom_bg: Control = get_node_or_null("BottomBg")
## Full-screen flash overlay (authored in mine.tscn, modulate.a = 0 at rest) — the relic/prestige
## screen wash. A legitimate full-screen flash ColorRect (like the light-mask ColorRect), distinct
## from the no-ColorRect-for-EXPLOSIONS rule. mouse_filter = IGNORE so it never eats input.
@onready var _flash_rect: ColorRect = get_node_or_null("FlashRect")
## Full-screen reveal veil (authored in mine.tscn, modulate.a = 0 at rest, near-black): fades a
## fresh dig / app boot up FROM black so a state swap (terrain rebuild, panel dismiss) never
## hard-cuts. mouse_filter = IGNORE so it never eats input. Distinct from the warm FlashRect wash.
@onready var _veil: ColorRect = get_node_or_null("TransitionVeil")
## Non-blocking confirmation banner (authored in mine.tscn, modulate.a = 0 at rest): the
## "Relic recovered  +1 Prestige" toast fades in → holds → fades out. Informational, never modal.
@onready var _toast: PanelContainer = get_node_or_null("Toast")
@onready var _toast_label: Label = get_node_or_null("Toast/ToastLabel")

## Tables (for the data-driven touch-target + edge-margin values). Set via configure().
var _tables: Dictionary = {}
## The most recent computed safe-area insets (logical px), for inspection/tests.
var _last_insets: Dictionary = {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
## UI text scale (AC-5.10.1 / AC-5.8.6): multiplies the top-bar label font sizes from their
## authored bases. Captured once per label so repeated set_text_scale calls don't compound.
var _text_scale: float = 1.0
## Which screen edge the elevator controls are laid out against ("left"|"right") — a controls
## accessibility setting (AC-5.10.1). Drives apply_layout_with's ElevatorControls placement.
var _elevator_side: String = "right"
var _base_font_sizes: Dictionary = {}  # Label -> int authored base font size
## Last money value pushed in, so a text-scale change re-renders it with the right abbreviation.
var _money_value: int = 0
## The currently-DISPLAYED money during a rolling count-up (a float so the tween can interpolate
## fractionally between the old and new balance). Independent of _money_value, which is the
## canonical (snap-exact) target the deterministic/test path writes via set_money.
var _displayed_money: float = 0.0
## Live tween handles so a new roll/pop kills the prior one (no compounding scale / stale value).
var _money_roll_tween: Tween = null
var _money_pop_tween: Tween = null
## Live tween handles for the relic/prestige screen flash, the relic-chip pulse, and the depth bump
## (each killed before a re-trigger so rapid beats don't compound scale / leave a stuck alpha).
var _flash_tween: Tween = null
var _relic_pulse_tween: Tween = null
var _depth_bump_tween: Tween = null
## Live tween handles for the reveal veil + the relic toast (killed before a re-trigger so a rapid
## re-show never compounds alpha or strands the veil opaque / the banner on-screen).
var _veil_tween: Tween = null
var _toast_tween: Tween = null
var _button_motion: float = 1.0


func _ready() -> void:
	if _nav_button != null and not _nav_button.pressed.is_connected(_on_nav_pressed):
		_nav_button.pressed.connect(_on_nav_pressed)
	if _end_dig_button != null and not _end_dig_button.pressed.is_connected(_on_end_dig_pressed):
		_end_dig_button.pressed.connect(_on_end_dig_pressed)
	# Elevator arrows: button_down starts the move (tap OR hold), button_up stops it.
	# `pressed` (fires on release) is NOT used — it would fire too late for a tap and
	# double-fire with the controller's hold poll. button_down fires the instant the
	# arrow is pressed, so the poll's first-frame guarantee yields one row for a tap and
	# the held flag drives the continuous glide for a hold.
	if _elevator_up != null:
		if not _elevator_up.button_down.is_connected(_on_elevator_up_pressed):
			_elevator_up.button_down.connect(_on_elevator_up_pressed)
		if not _elevator_up.button_up.is_connected(_on_elevator_up_released):
			_elevator_up.button_up.connect(_on_elevator_up_released)
	if _elevator_down != null:
		if not _elevator_down.button_down.is_connected(_on_elevator_down_pressed):
			_elevator_down.button_down.connect(_on_elevator_down_pressed)
		if not _elevator_down.button_up.is_connected(_on_elevator_down_released):
			_elevator_down.button_up.connect(_on_elevator_down_released)
	for button in [_nav_button, _end_dig_button, _elevator_up, _elevator_down]:
		if button != null:
			PIXEL_UI_SCRIPT.apply_button(button, "secondary", 20)
			PIXEL_UI_SCRIPT.bind_button_feel(button, Callable(self, "_button_motion_value"))
	# The relic toast reuses the shared pixel-panel bevel so the banner reads as part of the HUD.
	if _toast != null:
		PIXEL_UI_SCRIPT.apply_panel(_toast)
	# Reflow when the window/viewport resizes (portrait aspect range — AC-5.8.6).
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(apply_layout):
		vp.size_changed.connect(apply_layout)


## Provide the data tables (touch-target + edge-margin tunables) and run the first
## layout pass. Called by the controller once /data is loaded. Idempotent.
func configure(tables: Dictionary) -> void:
	_tables = tables
	_enforce_touch_targets()
	apply_layout()


func set_button_motion(motion: float) -> void:
	_button_motion = clampf(motion, 0.0, 1.0)


func _button_motion_value() -> float:
	return _button_motion


func _on_nav_pressed() -> void:
	nav_pressed.emit()


func _on_end_dig_pressed() -> void:
	end_dig_pressed.emit()


func _on_elevator_up_pressed() -> void:
	elevator_up_pressed.emit()


func _on_elevator_up_released() -> void:
	elevator_up_released.emit()


func _on_elevator_down_pressed() -> void:
	elevator_down_pressed.emit()


func _on_elevator_down_released() -> void:
	elevator_down_released.emit()


## Show/hide the prominent "End Dig" / "Prestige" button. When visible the button reads
## as the session-control escape hatch (Diggin-style "Stop Mining").
func set_end_dig_visible(visible: bool, text: String = "PRESTIGE") -> void:
	if _end_dig_button != null:
		_end_dig_button.visible = visible
		_end_dig_button.text = text


# ── Responsive safe-area layout (AC-5.8.5 / AC-5.8.6) ──────────────────────────

## Read the live device metrics and lay the HUD out inside the safe area. The pure math
## lives in UiLayout (headless-tested); this only sources DisplayServer + applies offsets.
func apply_layout() -> void:
	var logical := Vector2i(720, 1280)
	var vp := get_viewport()
	if vp != null:
		logical = Vector2i(vp.get_visible_rect().size)
	var window_px := DisplayServer.window_get_size()
	var safe_px := DisplayServer.get_display_safe_area()
	apply_layout_with(window_px, safe_px, logical)


## Layout seam: position the HUD bars for explicit device metrics. The production path
## (apply_layout) feeds live DisplayServer values; tests feed synthetic device profiles
## (notch / gesture-bar / desktop) so the safe-region placement is proven headless.
func apply_layout_with(window_px: Vector2i, safe_px: Rect2i, logical: Vector2i) -> void:
	var margin: float = Registry.ui_edge_margin_px(_tables) if not _tables.is_empty() else 16.0
	var insets: Dictionary = UiLayout.safe_insets(window_px, safe_px, logical, margin)
	_last_insets = insets
	var min_touch: float = _min_touch()

	# Top bar (money/depth/relic), below the top inset, left of the nav reserve.
	var top_h: float = maxf(min_touch, 44.0)
	if _top != null:
		_set_rect(_top, insets["left"], insets["top"],
			float(logical.x) - insets["right"] - _NAV_RESERVE, insets["top"] + top_h)

	# Resource-odds strip (AC-5.8.8): a distinct styled panel directly below the top bar,
	# left-aligned inside the safe area. It auto-sizes to its content width (the chip row), so
	# it never collides with the nav reserve; the width is capped to clear both side insets.
	if _odds_bar != null:
		var odds_top: float = insets["top"] + top_h + _BAR_PAD
		var odds_min: Vector2 = _odds_bar.get_combined_minimum_size()
		var odds_h: float = maxf(odds_min.y, 30.0)
		var odds_w: float = maxf(odds_min.x, 120.0)
		odds_w = minf(odds_w, float(logical.x) - insets["left"] - insets["right"])
		_set_rect(_odds_bar, insets["left"], odds_top, insets["left"] + odds_w, odds_top + odds_h)

	# Top-right button group (End Dig + Nav), clear of the right inset.
	if _top_right != null:
		var tr_h: float = maxf(min_touch, 56.0)
		var right: float = float(logical.x) - insets["right"]
		_set_rect(_top_right, right - _NAV_RESERVE, insets["top"], right, insets["top"] + tr_h)
		# Let the container right-align its children.
		_top_right.alignment = BoxContainer.ALIGNMENT_END

	# Elevator controls (up/down arrows), vertically centered, against the player-chosen edge
	# (AC-5.10.1 controls side: "left" hugs the left inset, "right" the right inset).
	#
	# FIXED SLOTS: up always occupies the UPPER slot, down always the LOWER slot. Each button is
	# positioned INDIVIDUALLY (not by a reflowing container), so hiding one (the hide-not-disable
	# behavior for a direction you can't go) never moves the other — toggling `visible` is purely
	# show/hide, never a swap. The container is a plain Control (no auto-layout); the two buttons
	# anchor to its top / bottom with a fixed gap between the slots.
	if _elevator_controls != null:
		var btn_w: float = maxf(_elevator_button_size(_elevator_up).x, min_touch)
		var btn_h: float = maxf(_elevator_button_size(_elevator_up).y, min_touch)
		var down_w: float = maxf(_elevator_button_size(_elevator_down).x, min_touch)
		var down_h: float = maxf(_elevator_button_size(_elevator_down).y, min_touch)
		var w: float = maxf(btn_w, down_w)
		# Two slots stacked with a fixed gap: total height = up + gap + down.
		var h: float = btn_h + _ELEVATOR_SLOT_GAP + down_h
		var center_y: float = float(logical.y) / 2.0
		var left_edge: float
		if _elevator_side == "left":
			left_edge = insets["left"] + margin
		else:
			left_edge = float(logical.x) - insets["right"] - margin - w
		var top: float = center_y - h * 0.5
		_set_rect(_elevator_controls, left_edge, top, left_edge + w, top + h)
		# Each button is placed at its FIXED slot in the container's LOCAL space (offsets relative to
		# the container origin). The up button's rect depends only on the container geometry; the down
		# button's rect depends only on the container geometry + the up slot height — NEITHER depends on
		# the other button's `visible`, so hiding one cannot move the other.
		if _elevator_up != null:
			_set_rect(_elevator_up, 0.0, 0.0, btn_w, btn_h)
		if _elevator_down != null:
			var down_top: float = btn_h + _ELEVATOR_SLOT_GAP
			_set_rect(_elevator_down, 0.0, down_top, down_w, down_top + down_h)

	# Bottom control area, its BOTTOM edge above the bottom inset. It is now a VBox of TWO stacked
	# rows (AC-5.8.1): the charge SELECTOR in its own bar on top, then the THROW/SHOP/MINES action
	# row below — so the selector reads as a dedicated hotbar, not crammed into the button row. The
	# band height fits both rows + the VBox separation; the selector-row height is data-driven.
	if _bottom != null:
		var action_h: float = maxf(min_touch, 72.0)
		var selector_h: float = _selector_bar_height()
		var bottom_h: float = selector_h + _STACK_GAP + action_h + _BAR_PAD
		var bottom_edge: float = float(logical.y) - insets["bottom"]
		_set_rect(_bottom, insets["left"], bottom_edge - bottom_h,
			float(logical.x) - insets["right"], bottom_edge)
		# A grounded background behind BOTH rows (reaches the screen edge so the inset gap reads as
		# part of the bar, not a floating row over the rubble).
		if _bottom_bg != null:
			_set_rect(_bottom_bg, 0.0, bottom_edge - bottom_h - _BAR_PAD,
				float(logical.x), float(logical.y))


	# Relic confirmation toast: a content-hugging banner centred horizontally in the safe area,
	# in the upper third (clear of the top bar/odds strip above and gameplay below). Re-centred
	# every layout pass so it tracks its own text width (show_toast re-runs the layout on a new
	# message). Purely positional — visibility is driven by the toast's own modulate.a tween.
	if _toast != null:
		var t_min: Vector2 = _toast.get_combined_minimum_size()
		var t_w: float = clampf(t_min.x, 140.0, float(logical.x) - insets["left"] - insets["right"])
		var t_h: float = maxf(t_min.y, 44.0)
		var t_x: float = (float(logical.x) - t_w) * 0.5
		var t_y: float = insets["top"] + maxf(_min_touch(), 44.0) + _BAR_PAD * 2.0 + 56.0
		_set_rect(_toast, t_x, t_y, t_x + t_w, t_y + t_h)


## Set a Control's rect via absolute offsets (anchors are pinned at top-left so offsets are
## logical-pixel positions). Guards against an inverted rect from extreme insets.
func _set_rect(c: Control, left: float, top: float, right: float, bottom: float) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = left
	c.offset_top = top
	c.offset_right = maxf(left, right)
	c.offset_bottom = maxf(top, bottom)


## Size every interactive control to at least the data-driven thumb-safe minimum (AC-5.8.5).
func _enforce_touch_targets() -> void:
	var m: float = _min_touch()
	for b: Button in [_nav_button, _end_dig_button, _elevator_up, _elevator_down]:
		if b != null:
			b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, m), maxf(b.custom_minimum_size.y, m))


func _min_touch() -> float:
	if _tables.is_empty():
		return 48.0
	var v: float = Registry.ui_min_touch_target_px(_tables)
	return v if v > 0.0 else 48.0


## Height of the dedicated charge-selector row (data-driven; AC-5.8.1). Floors at the touch target
## so the hotbar never collapses a slot below the thumb-safe minimum even on a tiny /data value.
func _selector_bar_height() -> float:
	if _tables.is_empty():
		return maxf(88.0, _min_touch())
	var v: float = Registry.ui_selector_f(_tables, "selector_bar_height_px", 88.0)
	return maxf(v, _min_touch())


## The authored minimum size of an elevator button (its custom_minimum_size). Used to size the two
## fixed slots. Null-safe (a bare headless instance with no button returns the touch-target square).
func _elevator_button_size(b: Button) -> Vector2:
	if b == null:
		var m: float = _min_touch()
		return Vector2(m, m)
	return b.custom_minimum_size


## The container-local top-left of the elevator UP button's FIXED slot (for tests). Always the
## upper slot — independent of either button's visibility.
func elevator_up_slot_position() -> Vector2:
	if _elevator_up == null:
		return Vector2.ZERO
	return _elevator_up.position


## The container-local top-left of the elevator DOWN button's FIXED slot (for tests). Always the
## lower slot — independent of either button's visibility.
func elevator_down_slot_position() -> Vector2:
	if _elevator_down == null:
		return Vector2.ZERO
	return _elevator_down.position


## Show/hide the elevator buttons INDIVIDUALLY (the hide-not-disable behavior for a direction you
## cannot go). Toggling either `visible` never moves the other — each sits at a fixed slot. Called
## by the controller from its UI refresh. Headless-safe (no-op on a missing button).
func set_elevator_up_visible(v: bool) -> void:
	if _elevator_up != null:
		_elevator_up.visible = v


func set_elevator_down_visible(v: bool) -> void:
	if _elevator_down != null:
		_elevator_down.visible = v


## The most recent safe-area insets (logical px): {top,bottom,left,right}. For tests.
func last_insets() -> Dictionary:
	return _last_insets.duplicate()


# ── Readout pushers (AC-5.8.1) ─────────────────────────────────────────────────

## Update the money readout (AC-5.8.1: money top-left). Large values ABBREVIATE (e.g. $12.3K,
## $4.5M) so the digit count stays bounded and the top bar doesn't overflow at maximum text
## scale on the smallest portrait res (AC-5.8.6: numbers reflow/abbreviate).
func set_money(amount: int) -> void:
	_money_value = amount
	# Keep the rolling-display float in lockstep so a later tick_money_to starts from the exact
	# snapped balance (and a snap mid-roll, e.g. the test path, leaves no stale interpolation behind).
	_displayed_money = float(amount)
	if _money_label != null:
		_money_label.text = _format_money(amount)


## Animated count-up to `amount` (v0.5 money juice). SEPARATE from set_money so the canonical,
## test-read label stays snap-exact: this tweens a private _displayed_money float (formatting each
## step with the same _format_money) and a brief label scale-pop, then SNAPS to set_money(amount) on
## finish so the final readout is byte-identical to the deterministic path. At motion ~0 (or no label)
## it snaps immediately. Called ONLY from the live credit path; tests/determinism use set_money.
func tick_money_to(amount: int, motion: float = 1.0) -> void:
	if _money_label == null or motion <= 0.01:
		set_money(amount)
		return
	var start: float = _displayed_money
	if is_equal_approx(start, float(amount)):
		set_money(amount)
		return
	var seconds: float = Registry.ui_money_roll_seconds(_tables) if not _tables.is_empty() else 0.35
	# Track the target so a tween that started before another credit still lands on the final balance.
	_money_value = amount
	if _money_roll_tween != null and _money_roll_tween.is_valid():
		_money_roll_tween.kill()
	_money_roll_tween = create_tween()
	_money_roll_tween.tween_method(_set_rolling_money, start, float(amount), seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_money_roll_tween.finished.connect(func() -> void: set_money(amount))
	pop_money()


## Tween callback: write the interpolated rolling value to the label (formatted like the final text).
func _set_rolling_money(value: float) -> void:
	_displayed_money = value
	if _money_label != null:
		_money_label.text = _format_money(int(round(value)))


## A quick scale-pop + gold flash on the money readout when a coin lands (v0.5 money juice). Kills a
## prior pop so rapid arrivals don't compound. No-op headless if the label is absent.
func pop_money() -> void:
	if _money_label == null:
		return
	_money_label.pivot_offset = _money_label.size * 0.5
	if _money_pop_tween != null and _money_pop_tween.is_valid():
		_money_pop_tween.kill()
	_money_label.scale = Vector2.ONE
	_money_pop_tween = create_tween()
	_money_pop_tween.tween_property(_money_label, "scale", Vector2(1.18, 1.18), 0.07) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_money_pop_tween.tween_property(_money_label, "scale", Vector2.ONE, 0.09) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Brief gold modulate flash on the label + the wallet icon, eased back to white.
	var gold := Color(1.0, 0.85, 0.3)
	var flash := create_tween().set_parallel(true)
	flash.tween_property(_money_label, "modulate", gold, 0.06)
	if _money_icon != null:
		flash.tween_property(_money_icon, "modulate", gold, 0.06)
	var back := create_tween().set_parallel(true)
	back.tween_interval(0.06)
	back.chain().tween_property(_money_label, "modulate", Color.WHITE, 0.18)
	if _money_icon != null:
		back.tween_property(_money_icon, "modulate", Color.WHITE, 0.18)


## A brief full-screen screen flash on a big beat (v0.5 arcade pass): the relic break (warm gold) and
## the prestige bank (brighter). Tweens the FlashRect modulate.a from `peak`→0 over `seconds`. The
## peak alpha is HARD-gated on motion intensity AND capped by the caller's data value (ui_flash_alpha
## in [0,1]) — never a full-white opaque strobe — so it stays photosensitivity-safe (AC-5.10.4). Only
## the two big beats call this (never every blast). No-op headless if the FlashRect is absent.
func flash(color: Color, peak_alpha: float, seconds: float, motion: float = 1.0) -> void:
	if _flash_rect == null:
		return
	var m: float = clampf(motion, 0.0, 1.0)
	# Scale the peak by motion so reduced-motion players get a barely-there (or zero) wash. Cap to
	# [0,1] defensively even though the data gate already bounds ui_flash_alpha.
	var a: float = clampf(peak_alpha, 0.0, 1.0) * m
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color = Color(color.r, color.g, color.b, 1.0)
	if a <= 0.001:
		_flash_rect.modulate = Color(1, 1, 1, 0)
		return
	_flash_rect.modulate = Color(1, 1, 1, a)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "modulate", Color(1, 1, 1, 0.0), maxf(0.01, seconds)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Reveal the screen FROM black: snap the veil opaque, hold for `hold_s`, then fade it out over
## `out_s` (a "smooth transitions across screen states" beat — used at dig-start / app-boot so a
## terrain rebuild + panel dismiss never hard-cuts). The alpha curve is the pure ScreenTransition
## reveal envelope, driven by a single tween_method over elapsed time so the runtime matches the
## unit-tested math exactly. Motion-gated: at motion ~0 there is NO veil (snaps clear instantly) so
## reduced-motion players never get a flash of black. The veil ALWAYS lands at alpha 0 (a finish
## callback guarantees it) so it can never strand the screen behind black. No-op headless if absent.
func reveal(hold_s: float, out_s: float, motion: float = 1.0) -> void:
	if _veil == null:
		return
	if _veil_tween != null and _veil_tween.is_valid():
		_veil_tween.kill()
	if clampf(motion, 0.0, 1.0) <= 0.01:
		_veil.modulate = Color(1, 1, 1, 0)
		return
	_veil.modulate = Color(1, 1, 1, 1)
	_veil_hold = hold_s
	_veil_out = out_s
	var total: float = _ScreenTransition.reveal_total_seconds(hold_s, out_s)
	if total <= 0.0:
		_veil.modulate = Color(1, 1, 1, 0)
		return
	_veil_tween = create_tween()
	_veil_tween.tween_method(_set_veil_alpha, 0.0, total, total) \
		.set_trans(Tween.TRANS_LINEAR)
	_veil_tween.tween_callback(func() -> void: _veil.modulate = Color(1, 1, 1, 0))


func _set_veil_alpha(elapsed: float) -> void:
	if _veil != null:
		_veil.modulate.a = _ScreenTransition.reveal_alpha_at(elapsed, _veil_hold, _veil_out)


# The hold/out durations the live veil tween is animating (captured so the tween_method callback can
# evaluate the pure envelope without rebinding a lambda per call).
var _veil_hold: float = 0.0
var _veil_out: float = 0.0


## Show the non-blocking confirmation toast (e.g. "Relic recovered  +1 Prestige"). Fades IN over
## `in_s`, HOLDS for `hold_s`, fades OUT over `out_s` via the pure ScreenTransition envelope. Never
## modal, never eats input (mouse_filter IGNORE). Motion-gated: at motion ~0 the banner still shows
## (it is INFORMATION, not just eye-candy) for the in+hold window, then clears — but with no fade
## ramps. Always lands at alpha 0. No-op headless if the toast is absent.
func show_toast(text: String, in_s: float, hold_s: float, out_s: float, motion: float = 1.0) -> void:
	if _toast == null:
		return
	if _toast_label != null:
		_toast_label.text = text
	# Re-centre on the new text width (the banner hugs its content).
	apply_layout()
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_in = in_s
	_toast_hold = hold_s
	_toast_out = out_s
	if clampf(motion, 0.0, 1.0) <= 0.01:
		# Reduced motion: present the information without the fade ramps — snap visible, hold, clear.
		_toast.modulate = Color(1, 1, 1, 1)
		_toast_tween = create_tween()
		_toast_tween.tween_interval(maxf(0.01, maxf(0.0, in_s) + maxf(0.0, hold_s)))
		_toast_tween.tween_callback(func() -> void: _toast.modulate = Color(1, 1, 1, 0))
		return
	_toast.modulate = Color(1, 1, 1, 0)
	var total: float = _ScreenTransition.fade_total_seconds(in_s, hold_s, out_s)
	if total <= 0.0:
		_toast.modulate = Color(1, 1, 1, 0)
		return
	_toast_tween = create_tween()
	_toast_tween.tween_method(_set_toast_alpha, 0.0, total, total) \
		.set_trans(Tween.TRANS_LINEAR)
	_toast_tween.tween_callback(func() -> void: _toast.modulate = Color(1, 1, 1, 0))


func _set_toast_alpha(elapsed: float) -> void:
	if _toast != null:
		_toast.modulate.a = _ScreenTransition.fade_alpha_at(elapsed, _toast_in, _toast_hold, _toast_out)


var _toast_in: float = 0.0
var _toast_hold: float = 0.0
var _toast_out: float = 0.0


## A quick vertical squash on the depth chip when the platform drops (v0.5 arcade pass). Presentation
## only (no new tunable). No-op headless if the label is absent.
func bump_depth() -> void:
	if _depth_label == null:
		return
	_depth_label.pivot_offset = _depth_label.size * 0.5
	if _depth_bump_tween != null and _depth_bump_tween.is_valid():
		_depth_bump_tween.kill()
	_depth_label.scale = Vector2.ONE
	_depth_bump_tween = create_tween()
	_depth_bump_tween.tween_property(_depth_label, "scale", Vector2(1.15, 1.15), 0.06) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_depth_bump_tween.tween_property(_depth_label, "scale", Vector2.ONE, 0.08) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Screen-space (canvas) center of the wallet icon, the target a flying coin homes to. Falls back to
## the money box, then the top-left edge, so a coin always has a sane destination even if a node is
## missing. Returns the global RECT center in viewport pixels (coins are spawned on the same HUD
## CanvasLayer space the mine projects world→canvas into).
func money_icon_screen_position() -> Vector2:
	var target: Control = _money_icon if _money_icon != null else _money_box
	if target != null:
		var r: Rect2 = target.get_global_rect()
		return r.position + r.size * 0.5
	return Vector2(40.0, 40.0)


## Compact money string: exact under 10k; K above 10k; M above 10M. Keeps the label short so a
## large balance can't push past the nav reserve at max text scale (AC-5.8.6).
func _format_money(amount: int) -> String:
	var a: int = absi(amount)
	var sign_str: String = "-" if amount < 0 else ""
	if a >= 10_000_000:
		return "%s$%.1fM" % [sign_str, float(a) / 1_000_000.0]
	if a >= 10_000:
		return "%s$%.1fK" % [sign_str, float(a) / 1_000.0]
	return "%s$%d" % [sign_str, a]


## Set the UI text scale (AC-5.10.1) and reflow the bars (AC-5.8.6). Scales the top-bar label
## font sizes from their authored bases (captured once so repeated calls don't compound), then
## re-runs the safe-area layout so the larger text reflows without overlap/clipping.
func set_text_scale(scale: float) -> void:
	_text_scale = maxf(0.1, scale)
	_apply_text_scale()
	apply_layout()


## Set which screen edge the elevator up/down controls lay out against (AC-5.10.1 controls).
## "left"|"right"; anything else coerces to "right". Re-runs the layout so the change is immediate.
func set_elevator_side(side: String) -> void:
	_elevator_side = "left" if side == "left" else "right"
	apply_layout()


## The current elevator side ("left"|"right") — for tests/inspection.
func elevator_side() -> String:
	return _elevator_side


func _apply_text_scale() -> void:
	for label: Label in [_money_label, _depth_label, _relic_label]:
		if label == null:
			continue
		if not _base_font_sizes.has(label):
			var base: int = label.get_theme_font_size("font_size")
			_base_font_sizes[label] = base if base > 0 else 28
		var b: int = int(_base_font_sizes[label])
		label.add_theme_font_size_override("font_size", maxi(8, int(round(float(b) * _text_scale))))


## Update the depth readout in cells (AC-5.8.1: depth top-left). Rendered compactly as "<N>m"
## (one cell ≈ one metre) so the depth chip stays narrow and the top bar fits at max text scale.
func set_depth(depth_cells: int) -> void:
	if _depth_label != null:
		_depth_label.text = "%dm" % depth_cells


## Tracks the last relic-found state so the chip pulse fires ONLY on the false→true transition
## (the relic break), not on every _refresh_all_ui that re-pushes the same state.
var _relic_found_shown: bool = false


## Update the compact relic-progress indicator (AC-5.8.1). `found` toggles between the
## "objective: relic" hint and the collected state. v0.5 arcade pass: on the false→true transition
## (the relic break) the chip PULSES (scale 1.0→1.4→1.0), motion-gated. `motion` defaults to 1.0 so
## the refresh path keeps working; mine.gd passes the real motion intensity at the break beat.
func set_relic_progress(found: bool, motion: float = 1.0) -> void:
	if _relic_label != null:
		_relic_label.text = "Relic ✓" if found else "Relic …"
	if found and not _relic_found_shown:
		_pulse_relic(motion)
	_relic_found_shown = found


func _pulse_relic(motion: float) -> void:
	if _relic_label == null or clampf(motion, 0.0, 1.0) <= 0.01:
		return
	_relic_label.pivot_offset = _relic_label.size * 0.5
	if _relic_pulse_tween != null and _relic_pulse_tween.is_valid():
		_relic_pulse_tween.kill()
	_relic_label.scale = Vector2.ONE
	_relic_pulse_tween = create_tween()
	_relic_pulse_tween.tween_property(_relic_label, "scale", Vector2(1.4, 1.4), 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_relic_pulse_tween.tween_property(_relic_label, "scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The font size of an odds-entry chip's text (presentation detail). Scaled by _text_scale so the
## resource strip tracks the accessibility text-scale setting alongside the top-bar readouts.
const _ODDS_FONT_SIZE := 18

const _BlockArt := preload("res://scripts/core/block_art.gd")


## Update the depth resource-odds readout (AC-5.8.8). `odds` is {block_id: probability 0..1}.
## Filters to ore-bearing blocks; renders a colour-coded chip row (a swatch in the ore's block
## colour + "NAME XX%") players read, and keeps the hidden `_odds_label` STRING in sync so the
## same information is exposed for tests and never depends on per-chip layout.
func set_depth_odds(odds: Dictionary) -> void:
	var parts: Array = []
	var entries: Array = []  # [{short, pct, color}]
	var keys: Array = odds.keys()
	keys.sort()
	for id in keys:
		var p: float = float(odds.get(id, 0.0))
		if p <= 0.0:
			continue
		# Only show ore/resource-bearing blocks to keep the readout compact.
		var short: String = _short_resource_label(str(id))
		if short.is_empty():
			continue
		var pct: int = int(round(p * 100.0))
		parts.append("%s %d%%" % [short, pct])
		var col: Color = _BlockArt.block_color(_tables, str(id)) if not _tables.is_empty() else Color(0.8, 0.8, 0.85)
		entries.append({"short": short, "pct": pct, "color": col})
	if _odds_label != null:
		_odds_label.text = " | ".join(parts) if not parts.is_empty() else ""
	_rebuild_odds_chips(entries)
	# Hide the whole strip when there is nothing to show (keeps the screen clean at empty bands).
	if _odds_bar != null:
		_odds_bar.visible = not entries.is_empty()
	apply_layout()


## Rebuild the colour-coded odds chip row from [{short,pct,color}] entries. Each chip is a small
## styled box holding a colour swatch (the ore's block colour) + "NAME XX%". Rebuilt wholesale so a
## band change never leaves a stale entry; child count tracks the entry count exactly.
func _rebuild_odds_chips(entries: Array) -> void:
	if _odds_entries == null:
		return
	for c: Node in _odds_entries.get_children():
		_odds_entries.remove_child(c)
		c.queue_free()
	for e: Dictionary in entries:
		var chip := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.15, 0.19, 0.9)
		sb.set_corner_radius_all(7)
		sb.content_margin_left = 7.0
		sb.content_margin_right = 8.0
		sb.content_margin_top = 2.0
		sb.content_margin_bottom = 2.0
		chip.add_theme_stylebox_override("panel", sb)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		chip.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = e["color"]
		swatch.custom_minimum_size = Vector2(10, 10)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var lbl := Label.new()
		lbl.text = "%s %d%%" % [e["short"], int(e["pct"])]
		lbl.add_theme_font_size_override("font_size", maxi(8, int(round(float(_ODDS_FONT_SIZE) * _text_scale))))
		lbl.add_theme_color_override("font_color", Color(0.9, 0.93, 0.98))
		row.add_child(lbl)
		_odds_entries.add_child(chip)


## Short label for a block id in the odds readout. Returns "" for non-resource blocks.
func _short_resource_label(id: String) -> String:
	if id == "ore_copper":
		return "Cu"
	if id == "ore_gold":
		return "Au"
	# Add other ore/resource ids here as they are authored.
	return ""
