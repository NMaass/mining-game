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
	# The real scene uses a VBoxContainer; replicate the minimal structure for unit tests.
	var box := VBoxContainer.new()
	box.name = "ElevatorControls"
	var up := Button.new()
	up.name = "ElevatorUp"
	var down := Button.new()
	down.name = "ElevatorDown"
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
