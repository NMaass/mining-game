class_name TrayUi
extends HBoxContainer
## Thin charge tray (AC-5.8.1, AC-5.8.2): a horizontal row of slot buttons, the free
## unlimited charge always first. Each slot shows the charge's display name + remaining
## count (∞ for the free charge) + a non-color tier glyph (◆ pips scaling with tier —
## AC-5.10.2 icon+count+tier glyph). The selected slot is indicated by a non-color cue —
## a thick border + raised elevation (AC-5.8.2 / AC-10.2: never color alone). Tapping a
## slot emits `slot_selected(charge_id)`; the same call path serves mouse and touch
## (AC-5.3.7). It is rebuilt from a list the controller pushes in; it owns no game state.
##
## ACs: AC-5.8.1 (tray bottom, free charge first slot), AC-5.8.2 (per-charge counts,
##      ∞ for free, selected shown by shape/border/elevation not color),
##      AC-5.3.6 (tap selects), AC-5.3.7 (one shared tap path).

## Emitted when a tray slot is tapped/clicked. Carries the charge id of that slot.
signal slot_selected(charge_id: String)

## Tables (for display names); set via configure(). No balance is read here.
var _tables: Dictionary = {}

## Parallel arrays describing the current slots, in display order.
var _slot_ids: Array = []        # charge id per slot (index 0 = free charge)
var _selected_index: int = 0     # currently selected slot index


## Configure the tray with the data tables (used only for display names). Idempotent.
func configure(tables: Dictionary) -> void:
	_tables = tables


## Rebuild the tray from `slots`: an Array of { "id": String, "count": int } where
## count == -1 means infinite (the free charge). `selected_id` marks the active slot.
## Pure view rebuild; called by the controller whenever the tray or selection changes.
func rebuild(slots: Array, selected_id: String) -> void:
	_slot_ids.clear()
	for child in get_children():
		child.queue_free()

	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var charge_id: String = str(slot.get("id", ""))
		var count: int = int(slot.get("count", 0))
		_slot_ids.append(charge_id)
		if charge_id == selected_id:
			_selected_index = i
		var button := _make_slot_button(charge_id, count, charge_id == selected_id)
		add_child(button)


func _make_slot_button(charge_id: String, count: int, is_selected: bool) -> Button:
	var b := Button.new()
	# Thumb-safe touch target (AC-5.8.5): the slot height is at least the data-driven
	# minimum; the width is wider to fit the name + count + tier glyph.
	var min_touch: float = Registry.ui_min_touch_target_px(_tables) if not _tables.is_empty() else 48.0
	if min_touch <= 0.0:
		min_touch = 48.0
	b.custom_minimum_size = Vector2(maxf(96.0, min_touch), maxf(64.0, min_touch))
	b.toggle_mode = false
	var label: String = _display_name(charge_id)
	# Count line: ∞ for the free unlimited charge (count == -1), else the number.
	var count_text: String = "∞" if count < 0 else "x%d" % count
	# Non-color TIER glyph (AC-5.10.2: icon + count + tier glyph). Tier reads as a row of
	# diamond pips that scales with tier — shape/count, never color — so a higher-tier charge
	# is identifiable without relying on hue.
	var tier: int = maxi(1, int(Registry.explosive(_tables, charge_id).get("tier", 1)))
	var tier_glyph: String = "◆".repeat(tier)
	b.text = "%s\n%s  %s" % [label, count_text, tier_glyph]
	b.clip_text = true
	# Non-color selection cue (AC-5.8.2): a thick border + slight upward elevation on
	# the selected slot; unselected slots get a thin border. No color-only signalling.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.16, 0.2)
	var border: int = 4 if is_selected else 1
	sb.border_width_left = border
	sb.border_width_right = border
	sb.border_width_top = border
	sb.border_width_bottom = border
	sb.border_color = Color(0.95, 0.95, 0.95)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.position.y = -6.0 if is_selected else 0.0  # elevation cue
	b.pressed.connect(_on_slot_pressed.bind(charge_id))
	return b


func _display_name(charge_id: String) -> String:
	var ex: Dictionary = Registry.explosive(_tables, charge_id)
	return str(ex.get("display_name", charge_id))


## One shared tap path for mouse + touch (AC-5.3.7): the Button's `pressed` fires for
## both, and we forward the slot's charge id.
func _on_slot_pressed(charge_id: String) -> void:
	slot_selected.emit(charge_id)


## The currently selected slot index (for inspection/tests).
var selected_index: int:
	get:
		return _selected_index


## The charge ids currently shown, in order (for inspection/tests).
func slot_ids() -> Array:
	return _slot_ids.duplicate()
