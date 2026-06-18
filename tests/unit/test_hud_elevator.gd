extends GdUnitTestSuite
## HUD elevator controls — Wave 4. Verifies the big blocky arrow buttons exist,
## fire the controller-facing signals, meet the thumb-safe touch target, and are
## positioned flush-right / vertically centered by the safe-area layout pass.

const HUD_SCENE := preload("res://scenes/mine.tscn")

var _tables: Dictionary

func before() -> void:
	GameData.load_all()
	_tables = GameData.tables


## Build a Hud instance with the ElevatorControls child tree so _ready wires the signals.
func _make_hud_with_elevator() -> Hud:
	var hud: Hud = Hud.new()
	# The real scene uses a plain Control container whose two children sit at FIXED slots (not a
	# reflowing VBoxContainer) — replicate that minimal structure for unit tests.
	var box := Control.new()
	box.name = "ElevatorControls"
	var up := Button.new()
	up.name = "ElevatorUp"
	up.custom_minimum_size = Vector2(64, 64)
	var down := Button.new()
	down.name = "ElevatorDown"
	down.custom_minimum_size = Vector2(64, 64)
	box.add_child(up)
	box.add_child(down)
	hud.add_child(box)
	add_child(hud)
	auto_free(hud)
	hud.configure(_tables)
	return hud


func test_mine_scene_has_elevator_buttons() -> void:
	# The authored mine.tscn must contain the elevator control nodes under Hud.
	var mine: Node = auto_free(HUD_SCENE.instantiate())
	add_child(mine)
	assert_object(mine.get_node_or_null("Hud/ElevatorControls")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/ElevatorControls/ElevatorUp")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/ElevatorControls/ElevatorDown")).is_not_null()


func test_elevator_buttons_fire_hud_signals() -> void:
	# Pressing the up/down buttons emits the controller-facing signals.
	var hud := _make_hud_with_elevator()
	var monitor := monitor_signals(hud)
	var up: Button = hud.get_node("ElevatorControls/ElevatorUp")
	var down: Button = hud.get_node("ElevatorControls/ElevatorDown")

	up.pressed.emit()
	await assert_signal(monitor).is_emitted("elevator_up_pressed")

	down.pressed.emit()
	await assert_signal(monitor).is_emitted("elevator_down_pressed")


func test_elevator_buttons_meet_touch_target() -> void:
	# AC-5.8.5: the arrow buttons are sized to the data-driven thumb-safe minimum.
	var mine: Node = auto_free(HUD_SCENE.instantiate())
	add_child(mine)
	var min_touch: float = Registry.ui_min_touch_target_px(_tables)
	for path in ["Hud/ElevatorControls/ElevatorUp", "Hud/ElevatorControls/ElevatorDown"]:
		var b := mine.get_node(path) as Control
		assert_bool(UiLayout.meets_touch_target(b.custom_minimum_size, min_touch)).override_failure_message(
			"%s custom_minimum_size %s below touch target %s" % [path, str(b.custom_minimum_size), str(min_touch)]
		).is_true()


func test_elevator_controls_positioned_right_and_centered() -> void:
	# The elevator controls sit flush against the right safe-area inset and are
	# vertically centered on the logical viewport.
	var hud: Hud = (auto_free(HUD_SCENE.instantiate()) as Node).get_node("Hud") as Hud
	add_child(hud.get_parent())
	var logical := Vector2i(720, 1280)
	hud.apply_layout_with(Vector2i(720, 1280), Rect2i(0, 0, 720, 1280), logical)

	var controls: Control = hud.get_node("ElevatorControls")
	var margin: float = Registry.ui_edge_margin_px(_tables)
	# Right edge is clear of the right inset (which is just the base margin here).
	assert_float(controls.offset_right).is_less_equal(float(logical.x) - margin + 0.5)
	# Vertically centered: the control's midpoint is near the viewport midpoint.
	var mid_y: float = (controls.offset_top + controls.offset_bottom) * 0.5
	assert_float(mid_y).is_equal_approx(float(logical.y) * 0.5, 2.0)


func test_elevator_disable_state_can_be_set() -> void:
	# The controller can drive the buttons' disabled state to gray them at limits.
	var mine: Node = auto_free(HUD_SCENE.instantiate())
	add_child(mine)
	var up: Button = mine.get_node("Hud/ElevatorControls/ElevatorUp")
	var down: Button = mine.get_node("Hud/ElevatorControls/ElevatorDown")
	up.disabled = true
	down.disabled = true
	assert_bool(up.disabled).is_true()
	assert_bool(down.disabled).is_true()
	up.disabled = false
	down.disabled = false
	assert_bool(up.disabled).is_false()
	assert_bool(down.disabled).is_false()


func test_up_slot_is_above_down_slot() -> void:
	# FIXED SLOTS: after a layout pass, the up button occupies the UPPER slot (smaller local Y) and
	# the down button the LOWER slot — they never overlap and never swap.
	var hud := _make_hud_with_elevator()
	hud.apply_layout_with(Vector2i(720, 1280), Rect2i(0, 0, 720, 1280), Vector2i(720, 1280))
	var up_y: float = hud.elevator_up_slot_position().y
	var down_y: float = hud.elevator_down_slot_position().y
	assert_float(down_y).override_failure_message(
		"down slot Y %.1f must be strictly BELOW up slot Y %.1f" % [down_y, up_y]
	).is_greater(up_y)


func test_hiding_up_does_not_move_down() -> void:
	# THE CORE FIX: hiding the UP button (the direction you can't go) must NOT move the DOWN button —
	# the down slot is fixed, so toggling up's visibility leaves down exactly where it was.
	var hud := _make_hud_with_elevator()
	hud.apply_layout_with(Vector2i(720, 1280), Rect2i(0, 0, 720, 1280), Vector2i(720, 1280))
	var down_before: Vector2 = hud.elevator_down_slot_position()
	# Hide up (and re-run the layout the way the controller would after a state change).
	hud.set_elevator_up_visible(false)
	hud.apply_layout_with(Vector2i(720, 1280), Rect2i(0, 0, 720, 1280), Vector2i(720, 1280))
	var down_after: Vector2 = hud.elevator_down_slot_position()
	assert_vector(down_after).override_failure_message(
		"hiding the UP button moved the DOWN button (was %s, now %s) — slots are not fixed"
		% [str(down_before), str(down_after)]
	).is_equal(down_before)


func test_hiding_down_does_not_move_up() -> void:
	# Symmetric: hiding the DOWN button must NOT move the UP button (up stays in the upper slot).
	var hud := _make_hud_with_elevator()
	hud.apply_layout_with(Vector2i(720, 1280), Rect2i(0, 0, 720, 1280), Vector2i(720, 1280))
	var up_before: Vector2 = hud.elevator_up_slot_position()
	hud.set_elevator_down_visible(false)
	hud.apply_layout_with(Vector2i(720, 1280), Rect2i(0, 0, 720, 1280), Vector2i(720, 1280))
	var up_after: Vector2 = hud.elevator_up_slot_position()
	assert_vector(up_after).override_failure_message(
		"hiding the DOWN button moved the UP button (was %s, now %s) — slots are not fixed"
		% [str(up_before), str(up_after)]
	).is_equal(up_before)


func test_individual_visibility_toggles_are_independent() -> void:
	# set_elevator_up_visible / set_elevator_down_visible toggle ONLY their own button (no swap, no
	# coupling) — proving the hide-not-disable behavior is per-button.
	var hud := _make_hud_with_elevator()
	var up: Button = hud.get_node("ElevatorControls/ElevatorUp")
	var down: Button = hud.get_node("ElevatorControls/ElevatorDown")
	hud.set_elevator_up_visible(false)
	assert_bool(up.visible).is_false()
	assert_bool(down.visible).is_true()  # unaffected
	hud.set_elevator_up_visible(true)
	hud.set_elevator_down_visible(false)
	assert_bool(up.visible).is_true()  # unaffected
	assert_bool(down.visible).is_false()
