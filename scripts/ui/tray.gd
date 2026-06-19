class_name TrayUi
extends HBoxContainer
## 8-bit charge selector hotbar (AC-5.3.6, AC-5.8.1, AC-5.8.2, AC-5.10.2).
##
## OWNED-ONLY roster: the controller pushes the owned tray slots verbatim ([free] + owned finite
## charges, collapsed by id) and this view renders EXACTLY those — no locked/greyed placeholders for
## un-owned explosives. The free charge is always the first slot (badge 1). Each slot carries a
## NUMBER BADGE keycap (1..9) that maps 1:1 to the selection hotkey, so the index is stable + truthful.
## Selection still emits the original `slot_selected(charge_id)` signal, keeping mine.gd's control
## path unchanged.

signal slot_selected(charge_id: String)

const _ChargeIcon := preload("res://scripts/ui/charge_icon.gd")
const _PixelUi := preload("res://scripts/ui/pixel_ui.gd")
const PIXEL_FONT := preload("res://art/fonts/PixelifySans.ttf")

var _tables: Dictionary = {}
var _slot_ids: Array = []
var _slot_counts: Dictionary = {}
var _slot_buttons: Dictionary = {}
var _selected_index: int = 0
var _selected_id: String = ""
var _motion: float = 1.0
var _text_scale: float = 1.0
var _bob_t: float = 0.0
var _pop_tween: Tween = null
var _popover: PanelContainer = null
var _popover_timer: SceneTreeTimer = null

func _ready() -> void:
	set_process(true)
	clip_contents = false

func configure(tables: Dictionary) -> void:
	_tables = tables

func set_text_scale(scale: float) -> void:
	_text_scale = clampf(scale, 0.8, 2.0)
	_apply_text_scale_to_tree(self)
	if _popover != null:
		_apply_text_scale_to_tree(_popover)

## Rebuild the hotbar from the controller's OWNED slot set (verbatim — no locked placeholders). Each
## entry is {id, count}; the free charge (count -1 → ∞) is first by construction. Dedupes by id so a
## malformed double-entry never spawns two slots. The slot at visible index i gets keycap (i+1).
func rebuild(slots: Array, selected_id: String) -> void:
	_slot_ids.clear()
	_slot_counts.clear()
	_slot_buttons.clear()
	_selected_id = selected_id
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_hide_popover()

	var seen: Dictionary = {}
	var index: int = 0
	for slot in slots:
		if not (slot is Dictionary):
			continue
		var charge_id: String = str((slot as Dictionary).get("id", ""))
		if charge_id.is_empty() or seen.has(charge_id):
			continue
		seen[charge_id] = true
		var count: int = int((slot as Dictionary).get("count", 0))
		_slot_ids.append(charge_id)
		_slot_counts[charge_id] = count
		if charge_id == selected_id:
			_selected_index = index
		var b := _make_slot_button(charge_id, count, charge_id == selected_id, index + 1)
		_slot_buttons[charge_id] = b
		add_child(b)
		index += 1
	queue_redraw()

## Set the selected slot WITHOUT rebuilding the row (a non-destructive in-place restyle + pop). Used
## on the common selection-only path so the hotbar never queue_frees/reflows on a tap or a refresh.
## IDEMPOTENT GUARD (requirement 4): if `charge_id` is already the selected, currently-present slot,
## this is a no-op — it does NOT retrigger the selection pop tween or replay the select SFX. That is
## what keeps an unrelated refresh (a platform move re-pushing the SAME selection) from churning the
## hotbar's selection feedback. The continuous bob lives in _process keyed on _selected_id and is
## unaffected either way.
func set_selected(charge_id: String, motion: float = 1.0) -> void:
	_motion = clampf(motion, 0.0, 1.0)
	if not _slot_buttons.has(charge_id):
		return
	# No-op re-selection: same slot already selected + present → don't replay the pop/SFX (so a
	# generic refresh can't retrigger selection feedback). Keep _motion updated above for the bob.
	if charge_id == _selected_id:
		return
	_selected_id = charge_id
	for i in range(_slot_ids.size()):
		var id: String = str(_slot_ids[i])
		var b := _slot_buttons.get(id, null) as Button
		if b == null:
			continue
		_style_slot(b, id, id == charge_id)
		if id == charge_id:
			_selected_index = i
	var sel_btn := _slot_buttons.get(charge_id, null) as Button
	if sel_btn == null:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	if _motion <= 0.01:
		return
	Audio.play_charge_select()
	sel_btn.pivot_offset = sel_btn.size * 0.5
	var base_y: float = -6.0
	var seconds: float = Registry.ui_tray_pop_seconds(_tables) if not _tables.is_empty() else 0.14
	var half: float = maxf(0.01, seconds * 0.5)
	sel_btn.scale = Vector2.ONE
	_pop_tween = create_tween()
	_pop_tween.set_parallel(true)
	_pop_tween.tween_property(sel_btn, "scale", Vector2(1.14, 1.14), half) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(sel_btn, "position:y", base_y - 4.0, half) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pop_tween.chain().tween_property(sel_btn, "scale", Vector2.ONE, half) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _make_slot_button(charge_id: String, count: int, is_selected: bool, hotkey_index: int) -> Button:
	var b := Button.new()
	b.name = "Slot_%s" % charge_id
	b.toggle_mode = false
	b.text = ""
	b.tooltip_text = _detail_text(charge_id, count)
	b.focus_mode = Control.FOCUS_ALL
	var slot_w: float = Registry.ui_selector_f(_tables, "slot_width_px", 88.0) if not _tables.is_empty() else 88.0
	var slot_h: float = Registry.ui_selector_f(_tables, "slot_height_px", 78.0) if not _tables.is_empty() else 78.0
	var min_touch: float = Registry.ui_min_touch_target_px(_tables) if not _tables.is_empty() else 48.0
	b.custom_minimum_size = Vector2(maxf(slot_w, min_touch), maxf(slot_h, min_touch))
	_style_slot(b, charge_id, is_selected)
	_PixelUi.bind_button_feel(b, Callable(self, "_motion_value"))
	b.pressed.connect(_on_slot_pressed.bind(charge_id))

	var box := VBoxContainer.new()
	box.name = "SlotBox"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 5
	box.offset_top = 4
	box.offset_right = -5
	box.offset_bottom = -4
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	b.add_child(box)

	var top := HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 2)
	box.add_child(top)
	var rarity := _small_label(_rarity_glyph(charge_id), 13)
	rarity.name = "RarityGlyph"
	top.add_child(rarity)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var count_label := _small_label(_count_text(count), 13)
	count_label.name = "CountBadge"
	top.add_child(count_label)

	var icon := TextureRect.new()
	icon.name = "Icon"
	var icon_px: float = Registry.ui_selector_f(_tables, "icon_px", 48.0) if not _tables.is_empty() else 48.0
	icon.custom_minimum_size = Vector2(icon_px, icon_px)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.texture = _ChargeIcon.texture_for(_tables, charge_id, 64)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)

	var bottom := HBoxContainer.new()
	bottom.name = "Bottom"
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 3)
	box.add_child(bottom)
	# Number BADGE keycap (1..9): the digit that selects this slot. A filled dark pill with a bright
	# digit so it reads as a keycap, not loose text. Slots past 9 show no badge (still tap/cycle-able).
	# Because the roster is owned-only the index↔badge mapping is stable + truthful (free = 1).
	bottom.add_child(_make_hotkey_keycap(hotkey_index))
	var tier := _small_label(_tier_pips(charge_id), 13)
	tier.name = "TierPips"
	tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(tier)
	return b


## The number-key BADGE keycap for visible slot `hotkey_index` (1-based). Indices 1..9 render a filled
## pill (dark bg, bright digit); past 9 the pill is hidden (no badge, but the slot is still selectable
## by tap / ←→ / Tab). The Label child is always named "Hotkey" so tests/inspection have a stable path.
func _make_hotkey_keycap(hotkey_index: int) -> Control:
	var pill := PanelContainer.new()
	pill.name = "HotkeyPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.045, 0.07, 0.92)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.45, 0.48, 0.58, 0.8)
	pill.add_theme_stylebox_override("panel", sb)
	var key := _small_label(str(hotkey_index) if hotkey_index <= 9 else "", 12)
	key.name = "Hotkey"
	key.add_theme_color_override("font_color", Color(1.0, 0.93, 0.55, 1))
	pill.add_child(key)
	# Hide the whole pill (not just the text) past 9 so it leaves no empty box.
	pill.visible = hotkey_index <= 9
	return pill

func _style_slot(b: Button, charge_id: String, is_selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.bg_color = Color(0.12, 0.13, 0.17, 1)
	var border: int = 4 if is_selected else 2
	sb.border_width_left = border
	sb.border_width_right = border
	sb.border_width_top = border
	sb.border_width_bottom = border + (2 if is_selected else 1)
	var rarity: String = str(Registry.explosive(_tables, charge_id).get("rarity", "common"))
	sb.border_color = Registry.rarity_color(_tables, rarity)
	if is_selected:
		sb.shadow_color = Color(1.0, 0.85, 0.25, 0.30)
		sb.shadow_size = 5
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("focus", sb)
	b.position.y = -6.0 if is_selected else 0.0

func _small_label(text: String, base_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", maxi(8, int(round(float(base_size) * _text_scale))))
	label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.88, 1))
	return label

## Tap → select; tapping the ALREADY-selected slot shows its stats popover instead (a non-timed
## "tap-again for details" affordance — AC-5.3.7: no timing-precision inputs, so the old long
## press is gone). Every VISIBLE slot is owned (the roster is owned-only), so there is no
## locked/disabled branch — a tap on an unselected slot always selects. Re-selecting is a no-op
## for selection (set_selected is idempotent), so the second tap is repurposed for info without an
## extra gesture or a timed hold.
func _on_slot_pressed(charge_id: String) -> void:
	if charge_id == _selected_id:
		_show_popover(charge_id)
		return
	slot_selected.emit(charge_id)

func _show_popover(charge_id: String) -> void:
	_hide_popover()
	_popover = PanelContainer.new()
	_popover.name = "ChargeStatsPopover"
	_popover.custom_minimum_size = Vector2(250, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.98)
	sb.border_color = Registry.rarity_color(_tables, str(Registry.explosive(_tables, charge_id).get("rarity", "common")))
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 4
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_popover.add_theme_stylebox_override("panel", sb)
	_popover.set_as_top_level(true)
	add_child(_popover)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_popover.add_child(box)
	var title := _small_label(str(Registry.explosive(_tables, charge_id).get("display_name", charge_id)), 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(title)
	var stats := Label.new()
	stats.text = _detail_text(charge_id, int(_slot_counts.get(charge_id, 0)))
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats.add_theme_font_override("font", PIXEL_FONT)
	stats.add_theme_font_size_override("font_size", maxi(10, int(round(14.0 * _text_scale))))
	stats.add_theme_color_override("font_color", Color(0.86, 0.88, 0.90, 1))
	box.add_child(stats)
	var btn := _slot_buttons.get(charge_id, null) as Control
	var target: Vector2 = Vector2(24, 24)
	if btn != null:
		target = btn.global_position + Vector2(0, -150)
	_popover.global_position = target
	var ttl: float = Registry.ui_selector_f(_tables, "popover_seconds", 3.0) if not _tables.is_empty() else 3.0
	_popover_timer = get_tree().create_timer(ttl, true, false, true)
	_popover_timer.timeout.connect(_hide_popover)

func _hide_popover() -> void:
	if _popover != null:
		_popover.queue_free()
	_popover = null

func _detail_text(charge_id: String, count: int) -> String:
	var ex: Dictionary = Registry.explosive(_tables, charge_id)
	var fuse: String = "%.1fs" % float(ex.get("fuse_seconds", 0.0)) if float(ex.get("fuse_seconds", 0.0)) > 0.0 else "none"
	var sticky: String = "yes" if bool(ex.get("sticky", false)) else "no"
	var have: String = "Owned: unlimited" if count < 0 else "Owned: x%d" % count
	return "%s\nRadius %d | Intensity %d\nMode %s | Fuse %s\nSticky %s | Mass %.1f" % [
		have,
		int(ex.get("blast_radius_cells", 0)),
		int(ex.get("blast_intensity", 0)),
		str(ex.get("detonation_mode", "")),
		fuse,
		sticky,
		float(ex.get("mass", 0.0)),
	]

## Count badge text: ∞ for the free charge (count -1), else "xN". No LOCK branch — the roster is
## owned-only so every visible slot has a real count.
func _count_text(count: int) -> String:
	if count < 0:
		return "∞"
	return "x%d" % count

func _tier_pips(charge_id: String) -> String:
	var tier: int = maxi(1, int(Registry.explosive(_tables, charge_id).get("tier", 1)))
	return "◆".repeat(tier)

func _rarity_glyph(charge_id: String) -> String:
	var rarity: String = str(Registry.explosive(_tables, charge_id).get("rarity", "common"))
	if rarity == "rare":
		return "R"
	if rarity == "uncommon":
		return "U"
	return "C"

func _motion_value() -> float:
	return _motion

func _process(delta: float) -> void:
	if _motion > 0.01 and not _selected_id.is_empty() and _slot_buttons.has(_selected_id):
		_bob_t += delta
		var b := _slot_buttons[_selected_id] as Button
		var amp: float = Registry.ui_selector_f(_tables, "selected_bob_px", 3.0) if not _tables.is_empty() else 3.0
		var secs: float = Registry.ui_selector_f(_tables, "selected_bob_seconds", 1.2) if not _tables.is_empty() else 1.2
		b.position.y = -6.0 + sin(_bob_t / maxf(0.01, secs) * TAU) * amp
	queue_redraw()

func _draw() -> void:
	var sc := get_parent() as ScrollContainer
	if sc == null or size.x <= sc.size.x + 1.0:
		return
	var left: float = float(sc.scroll_horizontal)
	var view_w: float = sc.size.x
	draw_rect(Rect2(left, 0, 18, size.y), Color(0.02, 0.025, 0.03, 0.42))
	draw_rect(Rect2(left + view_w - 18, 0, 18, size.y), Color(0.02, 0.025, 0.03, 0.42))

func _apply_text_scale_to_tree(root: Node) -> void:
	if root is Label:
		var label := root as Label
		var base: int = int(label.get_meta("_base_font_size", label.get_theme_font_size("font_size")))
		if base <= 0:
			base = 14
		label.set_meta("_base_font_size", base)
		label.add_theme_font_size_override("font_size", maxi(8, int(round(float(base) * _text_scale))))
	for child in root.get_children():
		_apply_text_scale_to_tree(child)

var selected_index: int:
	get:
		return _selected_index

func slot_ids() -> Array:
	return _slot_ids.duplicate()
