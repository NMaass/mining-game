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

# Internal layout spacing (presentation detail, not game balance): the gap between the
# control bars and surrounding chrome, and how far the bottom background extends behind
# the controls. The accessibility-meaningful values (touch target, edge margin) are data.
const _BAR_PAD := 10.0
const _NAV_RESERVE := 220.0  # horizontal room kept for the top-right buttons

@onready var _top: Control = get_node_or_null("Top")
@onready var _money_box: Control = get_node_or_null("Top/MoneyBox")
@onready var _money_icon: Control = get_node_or_null("Top/MoneyBox/MoneyIcon")
@onready var _money_label: Label = get_node_or_null("Top/MoneyBox/Money")
@onready var _depth_label: Label = get_node_or_null("Top/DepthBox/Depth")
@onready var _relic_label: Label = get_node_or_null("Top/RelicBox/Relic")
@onready var _odds_label: Label = get_node_or_null("Top/Odds")
@onready var _top_right: Control = get_node_or_null("TopRight")
@onready var _nav_button: Button = get_node_or_null("TopRight/NavButton")
@onready var _end_dig_button: Button = get_node_or_null("TopRight/EndDigButton")
@onready var _bottom: Control = get_node_or_null("Bottom")
@onready var _bottom_bg: Control = get_node_or_null("BottomBg")
## Full-screen flash overlay (authored in mine.tscn, modulate.a = 0 at rest) — the relic/prestige
## screen wash. A legitimate full-screen flash ColorRect (like the light-mask ColorRect), distinct
## from the no-ColorRect-for-EXPLOSIONS rule. mouse_filter = IGNORE so it never eats input.
@onready var _flash_rect: ColorRect = get_node_or_null("FlashRect")

## Tables (for the data-driven touch-target + edge-margin values). Set via configure().
var _tables: Dictionary = {}
## The most recent computed safe-area insets (logical px), for inspection/tests.
var _last_insets: Dictionary = {"top": 0.0, "bottom": 0.0, "left": 0.0, "right": 0.0}
## UI text scale (AC-5.10.1 / AC-5.8.6): multiplies the top-bar label font sizes from their
## authored bases. Captured once per label so repeated set_text_scale calls don't compound.
var _text_scale: float = 1.0
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


func _ready() -> void:
	if _nav_button != null and not _nav_button.pressed.is_connected(_on_nav_pressed):
		_nav_button.pressed.connect(_on_nav_pressed)
	if _end_dig_button != null and not _end_dig_button.pressed.is_connected(_on_end_dig_pressed):
		_end_dig_button.pressed.connect(_on_end_dig_pressed)
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


func _on_nav_pressed() -> void:
	nav_pressed.emit()


func _on_end_dig_pressed() -> void:
	end_dig_pressed.emit()


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
	if _top != null:
		var top_h: float = maxf(min_touch, 44.0)
		_set_rect(_top, insets["left"], insets["top"],
			float(logical.x) - insets["right"] - _NAV_RESERVE, insets["top"] + top_h)

	# Top-right button group (End Dig + Nav), clear of the right inset.
	if _top_right != null:
		var tr_h: float = maxf(min_touch, 56.0)
		var right: float = float(logical.x) - insets["right"]
		_set_rect(_top_right, right - _NAV_RESERVE, insets["top"], right, insets["top"] + tr_h)
		# Let the container right-align its children.
		_top_right.alignment = BoxContainer.ALIGNMENT_END

	# Bottom control bar (tray + throw + pack), its BOTTOM edge above the bottom inset.
	if _bottom != null:
		var bottom_h: float = maxf(min_touch, 72.0) + _BAR_PAD
		var bottom_edge: float = float(logical.y) - insets["bottom"]
		_set_rect(_bottom, insets["left"], bottom_edge - bottom_h,
			float(logical.x) - insets["right"], bottom_edge)
		# A grounded background behind the bar (reaches the screen edge so the inset gap
		# reads as part of the bar, not a floating row over the rubble).
		if _bottom_bg != null:
			_set_rect(_bottom_bg, 0.0, bottom_edge - bottom_h - _BAR_PAD,
				float(logical.x), float(logical.y))


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
	for b: Button in [_nav_button, _end_dig_button]:
		if b != null:
			b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, m), maxf(b.custom_minimum_size.y, m))


func _min_touch() -> float:
	if _tables.is_empty():
		return 48.0
	var v: float = Registry.ui_min_touch_target_px(_tables)
	return v if v > 0.0 else 48.0


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


func _apply_text_scale() -> void:
	for label: Label in [_money_label, _depth_label, _relic_label]:
		if label == null:
			continue
		if not _base_font_sizes.has(label):
			var base: int = label.get_theme_font_size("font_size")
			_base_font_sizes[label] = base if base > 0 else 28
		var b: int = int(_base_font_sizes[label])
		label.add_theme_font_size_override("font_size", maxi(8, int(round(float(b) * _text_scale))))


## Update the depth readout in cells (AC-5.8.1: depth top-left).
func set_depth(depth_cells: int) -> void:
	if _depth_label != null:
		_depth_label.text = "Depth %d" % depth_cells


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


## Update the depth resource-odds readout (AC-5.8.8). `odds` is {block_id: probability 0..1}.
## Filters to ore-bearing blocks and displays short "NAME XX%" entries.
func set_depth_odds(odds: Dictionary) -> void:
	if _odds_label == null:
		return
	var parts: Array = []
	var keys: Array = odds.keys()
	keys.sort()
	for id in keys:
		var p: float = float(odds.get(id, 0.0))
		if p <= 0.0:
			continue
		# Only show ore/resource-bearing blocks to keep the readout compact.
		# Fall back to a short id-derived label if no display_name is available.
		var short: String = _short_resource_label(str(id))
		if short.is_empty():
			continue
		parts.append("%s %d%%" % [short, int(round(p * 100.0))])
	_odds_label.text = " | ".join(parts) if not parts.is_empty() else ""


## Short label for a block id in the odds readout. Returns "" for non-resource blocks.
func _short_resource_label(id: String) -> String:
	if id == "ore_copper":
		return "Cu"
	if id == "ore_gold":
		return "Au"
	# Add other ore/resource ids here as they are authored.
	return ""
