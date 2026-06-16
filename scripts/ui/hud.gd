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
@onready var _money_label: Label = get_node_or_null("Top/MoneyBox/Money")
@onready var _depth_label: Label = get_node_or_null("Top/DepthBox/Depth")
@onready var _relic_label: Label = get_node_or_null("Top/RelicBox/Relic")
@onready var _odds_label: Label = get_node_or_null("Top/Odds")
@onready var _top_right: Control = get_node_or_null("TopRight")
@onready var _nav_button: Button = get_node_or_null("TopRight/NavButton")
@onready var _end_dig_button: Button = get_node_or_null("TopRight/EndDigButton")
@onready var _bottom: Control = get_node_or_null("Bottom")
@onready var _bottom_bg: Control = get_node_or_null("BottomBg")

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
	if _money_label != null:
		_money_label.text = _format_money(amount)


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


## Update the compact relic-progress indicator (AC-5.8.1). `found` toggles between the
## "objective: relic" hint and the collected state.
func set_relic_progress(found: bool) -> void:
	if _relic_label != null:
		_relic_label.text = "Relic ✓" if found else "Relic …"


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
