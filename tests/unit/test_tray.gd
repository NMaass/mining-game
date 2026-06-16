extends GdUnitTestSuite
## U10 — TrayUi non-color selection cue + ∞ label (v0.4). The tray indicates the SELECTED
## charge by shape/border/elevation, NOT color alone (AC-5.8.2 / AC-5.10.2), and shows ∞ for
## the free unlimited charge with a per-charge count for finite charges (AC-5.8.1/5.8.2). This
## was implemented in tray.gd but previously had no asserting test (flagged WEAK in the
## 2026-06-14 audit). Driven directly (no input events, which don't fire headless).
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

func test_free_slot_first_and_infinite_label() -> void:
	# AC-5.8.1 / AC-5.8.2: the free charge is the first slot; its count renders as ∞, while a
	# finite charge shows a numeric "xN" count.
	var tray := _make_tray()
	tray.rebuild([{"id": "free_charge", "count": -1}, {"id": "dynamite", "count": 3}], "free_charge")
	var buttons := tray.get_children()
	assert_int(buttons.size()).is_equal(2)
	assert_str((buttons[0] as Button).text).contains("∞")
	assert_str((buttons[1] as Button).text).contains("x3")

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
	var t1 := (tray.get_child(0) as Button).text
	var t2 := (tray.get_child(1) as Button).text
	var t3 := (tray.get_child(2) as Button).text
	assert_str(t1).contains("◆")
	assert_str(t2).contains("◆◆")
	assert_str(t3).contains("◆◆◆")
	# The scale is meaningful: a tier-1 charge shows exactly one pip (not two).
	assert_bool(t1.contains("◆◆")).is_false()

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
