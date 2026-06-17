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

## Tables (for display names + the data-driven select-pop duration); set via configure(). No
## game balance is read here.
var _tables: Dictionary = {}

## Parallel arrays describing the current slots, in display order.
var _slot_ids: Array = []        # charge id per slot (index 0 = free charge)
var _selected_index: int = 0     # currently selected slot index
## Live tween for the select pop so a rapid re-tap kills the prior one (no compounding scale).
var _pop_tween: Tween = null


## Configure the tray with the data tables (used only for display names). Idempotent.
func configure(tables: Dictionary) -> void:
	_tables = tables


## Rebuild the tray from `slots`: an Array of { "id": String, "count": int } where
## count == -1 means infinite (the free charge). `selected_id` marks the active slot.
## Pure view rebuild; called by the controller whenever the tray or selection changes.
func rebuild(slots: Array, selected_id: String) -> void:
	_slot_ids.clear()
	# remove_child FIRST so the tree's child set is consistent SYNCHRONOUSLY (queue_free alone is
	# deferred to end-of-frame — a same-frame rebuild would otherwise stack zombie children and make
	# get_child_count() diverge from the slot count). queue_free then reclaims them next frame.
	for child in get_children():
		remove_child(child)
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


## Selection-ONLY change (v0.5 arcade pass): re-cue the slots for the new selection and POP the
## tapped slot (scale 1.0→1.18→1.0 + a brief upward bounce) IN PLACE — no queue_free/rebuild of the
## row, so the row never flickers and an animation can actually play. Keeps the static border/elevation
## cue (the AC-5.8.2 non-color signal) on the now-selected slot. The slot-SET path stays rebuild().
## At motion ~0 (reduced motion) it re-cues with no pop. Safe if the id isn't present (no-op pop).
func set_selected(charge_id: String, motion: float = 1.0) -> void:
	var children: Array = get_children()
	if children.is_empty():
		return
	var sel_index: int = -1
	for i in range(_slot_ids.size()):
		if i < children.size() and str(_slot_ids[i]) == charge_id:
			sel_index = i
	if sel_index < 0:
		return
	_selected_index = sel_index
	# Re-apply the non-color cue to every slot for the new selection (border thickness + base
	# elevation). This also re-bases position.y so the pop animates from the resting elevation.
	for i in range(children.size()):
		var b := children[i] as Button
		if b == null:
			continue
		_style_slot(b, _slot_ids[i], i == sel_index)
	var sel_btn := children[sel_index] as Button
	if sel_btn == null:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	if clampf(motion, 0.0, 1.0) <= 0.01:
		return  # reduced motion: cue updated, no pop
	sel_btn.pivot_offset = sel_btn.size * 0.5
	var base_y: float = sel_btn.position.y          # the selected resting elevation (-6)
	var seconds: float = Registry.ui_tray_pop_seconds(_tables) if not _tables.is_empty() else 0.14
	var half: float = maxf(0.01, seconds * 0.5)
	sel_btn.scale = Vector2.ONE
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(sel_btn, "scale", Vector2(1.18, 1.18), half) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(sel_btn, "position:y", base_y - 4.0, half) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tween.chain().tween_property(sel_btn, "scale", Vector2.ONE, half) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.parallel().tween_property(sel_btn, "position:y", base_y, half) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


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
	_style_slot(b, charge_id, is_selected)
	b.pressed.connect(_on_slot_pressed.bind(charge_id))
	return b


## Apply the non-color SELECTION cue (AC-5.8.2 / AC-5.10.2) to a slot button: a thick border (shape)
## + a slight upward elevation on the selected slot; a thin border + ground level otherwise. The
## border is TINTED by the charge's data-driven rarity color, but selected vs unselected is still
## conveyed by thickness + elevation, never by color alone. Shared by rebuild + set_selected so the
## selected/unselected look is identical whether the row was rebuilt or only the selection changed.
func _style_slot(b: Button, charge_id: String, is_selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.16, 0.2)
	var border: int = 4 if is_selected else 1
	sb.border_width_left = border
	sb.border_width_right = border
	sb.border_width_top = border
	sb.border_width_bottom = border
	var rarity: String = str(Registry.explosive(_tables, charge_id).get("rarity", ""))
	sb.border_color = Registry.rarity_color(_tables, rarity)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.position.y = -6.0 if is_selected else 0.0  # elevation cue


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
