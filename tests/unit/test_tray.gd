extends GdUnitTestSuite
## U10 — TrayUi non-color selection cue + ∞ label + owned-only hotbar (v0.5). The tray indicates
## the SELECTED charge by shape/border/elevation, NOT color alone (AC-5.8.2 / AC-5.10.2), and shows
## ∞ for the free unlimited charge with a per-charge count for finite charges (AC-5.8.1/5.8.2). The
## hotbar is OWNED-ONLY — un-owned charges DO NOT APPEAR (no locked/greyed slots) — and each slot
## carries a NUMBER BADGE keycap (1..9). Driven directly (no input events, which don't fire headless).
##
## ACs: AC-5.8.1 (free charge first slot), AC-5.8.2 (∞ for free, count for finite, selected
##      shown by shape/border/elevation not color), AC-5.8.5 (>= 44px touch target).

const TrayScript := preload("res://scripts/ui/tray.gd")

func _make_tray() -> TrayUi:
	# Display names are not needed for the cue/label assertions, so configure with {} —
	# _display_name falls back to the id.
	var tray: TrayUi = auto_free(TrayScript.new())
	add_child(tray)
	tray.configure({})
	return tray

func _make_tray_with_tables() -> TrayUi:
	var tray: TrayUi = auto_free(TrayScript.new())
	add_child(tray)
	tray.configure(GameData.tables)
	return tray

func _slot(tray: TrayUi, charge_id: String) -> Button:
	return tray.get_node("Slot_%s" % charge_id) as Button

func _label(slot: Button, path: String) -> Label:
	return slot.get_node(path) as Label

func test_free_slot_first_and_infinite_label() -> void:
	# AC-5.8.1 / AC-5.8.2: the free charge is the first slot; its count renders as ∞, while a
	# finite charge shows a numeric "xN" count.
	var tray := _make_tray()
	tray.rebuild([{"id": "free_charge", "count": -1}, {"id": "dynamite", "count": 3}], "free_charge")
	var buttons := tray.get_children()
	assert_int(buttons.size()).is_equal(2)
	assert_str(_label(buttons[0] as Button, "SlotBox/Top/CountBadge").text).is_equal("∞")
	assert_str(_label(buttons[1] as Button, "SlotBox/Top/CountBadge").text).is_equal("x3")

func test_selected_slot_indicated_by_border_and_elevation_not_color() -> void:
	# AC-5.8.2 / AC-5.10.2: the SELECTED slot is shown by a thicker border (shape) and a raised
	# elevation (position), NOT by color alone. Select the finite slot and assert its cue differs
	# from the unselected free slot along the non-color axes; the bg color is identical between
	# them (so the signal cannot be color).
	var tray := _make_tray()
	tray.rebuild([{"id": "free_charge", "count": -1}, {"id": "dynamite", "count": 3}], "dynamite")
	var free_btn := tray.get_child(0) as Button
	var sel_btn := tray.get_child(1) as Button
	var free_sb := free_btn.get_theme_stylebox("normal") as StyleBoxFlat
	var sel_sb := sel_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(free_sb).is_not_null()
	assert_object(sel_sb).is_not_null()
	# Shape cue: the selected slot's border is strictly thicker.
	assert_int(sel_sb.border_width_left).is_greater(free_sb.border_width_left)
	# Elevation cue: the selected slot sits higher (more negative y).
	assert_float(sel_btn.position.y).is_less(free_btn.position.y)
	# NOT color: the background color is the SAME for selected and unselected (so color carries
	# no information — only the border/elevation does).
	assert_bool(sel_sb.bg_color.is_equal_approx(free_sb.bg_color)).is_true()

func test_common_slot_uses_common_rarity_color() -> void:
	# AC-5.8.2 / AC-5.10.2: rarity may be shown by border tint, but the selection signal
	# itself remains non-color. A common charge's slot border uses the common rarity color.
	GameData.load_all()
	var tray := _make_tray_with_tables()
	tray.rebuild([{"id": "dynamite", "count": 3}], "dynamite")
	var sb := (tray.get_child(0) as Button).get_theme_stylebox("normal") as StyleBoxFlat
	var expected: Color = Registry.rarity_color(GameData.tables, "common")
	assert_object(sb).is_not_null()
	assert_bool(sb.border_color.is_equal_approx(expected)).is_true()

func test_uncommon_and_rare_slots_use_rarity_color() -> void:
	# Rarity colors flow from data/rarity.json through Registry.rarity_color to the slot border.
	GameData.load_all()
	var tray := _make_tray_with_tables()
	tray.rebuild([
		{"id": "charge_sticky", "count": 2},  # uncommon
		{"id": "heavy_bomb", "count": 1},     # rare
	], "charge_sticky")
	var uncommon_sb := (tray.get_child(0) as Button).get_theme_stylebox("normal") as StyleBoxFlat
	var rare_sb := (tray.get_child(1) as Button).get_theme_stylebox("normal") as StyleBoxFlat
	assert_bool(uncommon_sb.border_color.is_equal_approx(Registry.rarity_color(GameData.tables, "uncommon"))).is_true()
	assert_bool(rare_sb.border_color.is_equal_approx(Registry.rarity_color(GameData.tables, "rare"))).is_true()

func test_selected_slot_keeps_non_color_border_and_elevation_cue_with_rarity_colors() -> void:
	# Even when rarity colors are present on the border, the SELECTED slot is still
	# distinguished by a thicker border (shape) and raised elevation (position), and the
	# background color is identical — so selection never relies on color alone.
	GameData.load_all()
	var tray := _make_tray_with_tables()
	tray.rebuild([
		{"id": "dynamite", "count": 3},       # common, unselected
		{"id": "charge_sticky", "count": 2},  # uncommon, selected
	], "charge_sticky")
	var unsel_btn := tray.get_child(0) as Button
	var sel_btn := tray.get_child(1) as Button
	var unsel_sb := unsel_btn.get_theme_stylebox("normal") as StyleBoxFlat
	var sel_sb := sel_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_object(unsel_sb).is_not_null()
	assert_object(sel_sb).is_not_null()
	assert_int(sel_sb.border_width_left).is_greater(unsel_sb.border_width_left)
	assert_float(sel_btn.position.y).is_less(unsel_btn.position.y)
	assert_bool(sel_sb.bg_color.is_equal_approx(unsel_sb.bg_color)).is_true()

func test_tier_glyph_scales_with_tier() -> void:
	# AC-5.10.2: each tray charge shows a non-color TIER glyph (◆ pips) that scales with tier,
	# so tier reads by shape/count — never color. Needs real tables for the tier lookup.
	GameData.load_all()
	var tray: TrayUi = auto_free(TrayScript.new())
	add_child(tray)
	tray.configure(GameData.tables)
	tray.rebuild([
		{"id": "free_charge", "count": -1},   # tier 1
		{"id": "charge_sticky", "count": 2},  # tier 2
		{"id": "heavy_bomb", "count": 1},     # tier 3
	], "free_charge")
	var t1 := _label(_slot(tray, "free_charge"), "SlotBox/Bottom/TierPips").text
	var t2 := _label(_slot(tray, "charge_sticky"), "SlotBox/Bottom/TierPips").text
	var t3 := _label(_slot(tray, "heavy_bomb"), "SlotBox/Bottom/TierPips").text
	assert_str(t1).contains("◆")
	assert_str(t2).contains("◆◆")
	assert_str(t3).contains("◆◆◆")
	# The scale is meaningful: a tier-1 charge shows exactly one pip (not two).
	assert_bool(t1.contains("◆◆")).is_false()

func test_unowned_charges_do_not_appear_owned_only_roster() -> void:
	# AC-5.3.6 / AC-5.8.1 (owned-only roster): the hotbar renders EXACTLY the controller's slots —
	# un-owned explosives DO NOT APPEAR (no locked/greyed silhouette, no LOCK badge). With only the
	# free charge owned, the tray has exactly ONE slot and no slot exists for an un-owned id.
	GameData.load_all()
	var tray := _make_tray_with_tables()
	tray.rebuild([{"id": "free_charge", "count": -1}], "free_charge")
	assert_int(tray.get_child_count()).is_equal(1)
	assert_object(tray.get_node_or_null("Slot_dynamite")).is_null()
	assert_array(tray.slot_ids()).is_equal(["free_charge"])

func test_number_badge_keycap_matches_slot_index() -> void:
	# Requirement 2: each slot carries a NUMBER BADGE (1..9) that maps 1:1 to its visible index — the
	# free charge (slot 1) is always badge "1". The keycap label lives at SlotBox/Bottom/HotkeyPill/Hotkey.
	var tray := _make_tray()
	tray.rebuild([
		{"id": "free_charge", "count": -1},
		{"id": "dynamite", "count": 3},
		{"id": "heavy_bomb", "count": 1},
	], "free_charge")
	var slots := tray.get_children()
	assert_str(_label(slots[0] as Button, "SlotBox/Bottom/HotkeyPill/Hotkey").text).is_equal("1")
	assert_str(_label(slots[1] as Button, "SlotBox/Bottom/HotkeyPill/Hotkey").text).is_equal("2")
	assert_str(_label(slots[2] as Button, "SlotBox/Bottom/HotkeyPill/Hotkey").text).is_equal("3")

func test_set_selected_is_idempotent_on_reselect() -> void:
	# Requirement 4: re-selecting the ALREADY-selected slot is a no-op — it must not re-run the pop
	# (so an unrelated refresh can't churn selection feedback). After selecting "dynamite", calling
	# set_selected("dynamite") again leaves the visible child set + the slot's selected styling intact,
	# and slot_selected is never (re)emitted by set_selected (it's a view-only restyle path anyway).
	var tray := _make_tray()
	tray.rebuild([{"id": "free_charge", "count": -1}, {"id": "dynamite", "count": 3}], "free_charge")
	tray.set_selected("dynamite", 1.0)
	var children_before := tray.get_children().duplicate()
	var sel_sb_before := (tray.get_node("Slot_dynamite") as Button).get_theme_stylebox("normal") as StyleBoxFlat
	var border_before := sel_sb_before.border_width_left
	# Re-select the same id (the no-op path).
	tray.set_selected("dynamite", 1.0)
	assert_array(tray.get_children()).is_equal(children_before)  # no rebuild
	var sel_sb_after := (tray.get_node("Slot_dynamite") as Button).get_theme_stylebox("normal") as StyleBoxFlat
	assert_int(sel_sb_after.border_width_left).is_equal(border_before)  # still the selected (thick) border

func test_slot_meets_minimum_touch_target() -> void:
	# AC-5.8.5: interactive controls meet a ~44px minimum touch target.
	var tray := _make_tray()
	tray.rebuild([{"id": "free_charge", "count": -1}], "free_charge")
	var btn := tray.get_child(0) as Button
	assert_float(btn.custom_minimum_size.x).is_greater_equal(44.0)
	assert_float(btn.custom_minimum_size.y).is_greater_equal(44.0)

func test_tap_emits_slot_selected_with_charge_id() -> void:
	# AC-5.3.6 / AC-5.3.7: tapping a slot emits slot_selected(charge_id) via the one shared
	# Button.pressed path (mouse == touch). Drive the button's pressed signal directly.
	var tray := _make_tray()
	tray.rebuild([{"id": "free_charge", "count": -1}, {"id": "dynamite", "count": 2}], "free_charge")
	var monitor := monitor_signals(tray)
	(tray.get_child(1) as Button).pressed.emit()
	await assert_signal(monitor).is_emitted("slot_selected", ["dynamite"])
