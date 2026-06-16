extends GdUnitTestSuite
## U7 — Platform descent + camera tests (v0.4).
## Pure descent logic (PlatformLogic) + the thin Platform system (platform.tscn):
## descent counts, threshold behavior, ONE descent step per trigger, the tween-not-
## snap target, the camera anchored to the platform TARGET (logic-level, AC-5.7.3),
## and that the descent depth / tween / camera offset are DATA, not code literals.
##
## ACs: AC-5.7.1 (platform anchor / muzzle), AC-5.7.2 (tweened descent, not snap),
##      AC-5.7.3 (camera follows the platform target via smoothing, not hard-set).

const PLATFORM_SCENE := preload("res://scenes/platform.tscn")

var _tables: Dictionary

func before() -> void:
	_tables = _load_real_tables()

func _load_real_tables() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/")
	assert_object(dir).is_not_null()
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open("res://data/" + file_name, FileAccess.READ)
		var json := JSON.new()
		assert_int(json.parse(f.get_as_text())).is_equal(OK)
		out[file_name.get_basename()] = json.data
	return out

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_solid_row(row: int, width: int, hp: int, start_x: int = 0) -> Dictionary:
	var grid: Dictionary = {}
	for x in range(start_x, start_x + width):
		grid[Vector2i(x, row)] = hp
	return grid

## Instantiate + configure the real Platform system from the authored scene, freed
## automatically by gdUnit (auto_free) so no orphan nodes leak.
func _make_platform(start_row: int = 0) -> Platform:
	var p: Platform = auto_free(PLATFORM_SCENE.instantiate())
	add_child(p)  # runs _ready → @onready Body/Camera resolve
	p.configure(_tables, start_row)
	return p

# ══════════════════════════════════════════════════════════════════════════════
# PURE LOGIC — PlatformLogic.cleared_beneath
# ══════════════════════════════════════════════════════════════════════════════

func test_all_solid_beneath() -> void:
	# AC-5.7.2: platform at row 0; row 1 fully solid → 0 cleared.
	var grid: Dictionary = _make_solid_row(1, 7, 100)
	assert_int(PlatformLogic.cleared_beneath(grid, 0, 7)).is_equal(0)

func test_all_cleared_beneath() -> void:
	# AC-5.7.2: no cells below platform → all cleared (7).
	assert_int(PlatformLogic.cleared_beneath({}, 0, 7)).is_equal(7)

func test_partial_cleared() -> void:
	# AC-5.7.2: 3 of 7 cells cleared beneath platform.
	var grid: Dictionary = {}
	for x in range(4):  # 4 solid cells
		grid[Vector2i(x, 1)] = 50
	assert_int(PlatformLogic.cleared_beneath(grid, 0, 7)).is_equal(3)

func test_zero_hp_counts_as_cleared() -> void:
	# AC-5.7.2: cells with HP = 0 count as cleared.
	var grid: Dictionary = {}
	for x in range(7):
		grid[Vector2i(x, 1)] = 0
	assert_int(PlatformLogic.cleared_beneath(grid, 0, 7)).is_equal(7)

# ── should_descend ────────────────────────────────────────────────────────────

func test_below_threshold_no_descent() -> void:
	# AC-5.7.2: threshold = 5; only 3 cleared → no descent.
	var grid: Dictionary = {}
	for x in range(4):
		grid[Vector2i(x, 1)] = 50
	assert_bool(PlatformLogic.should_descend(grid, 0, 7, 5)).is_false()

func test_at_threshold_descent() -> void:
	# AC-5.7.2: threshold = 5; exactly 5 cleared → descend.
	var grid: Dictionary = {}
	for x in range(2):  # 2 solid, 5 cleared
		grid[Vector2i(x, 1)] = 50
	assert_bool(PlatformLogic.should_descend(grid, 0, 7, 5)).is_true()

func test_above_threshold_descent() -> void:
	# AC-5.7.2: all cleared → descend.
	assert_bool(PlatformLogic.should_descend({}, 0, 7, 5)).is_true()

# ── descent_steps (consecutive cleared rows, capped) ──────────────────────────

func test_descent_one_step() -> void:
	# AC-5.7.2: row 1 cleared, row 2 solid → exactly 1 step.
	var grid: Dictionary = _make_solid_row(2, 7, 100)
	assert_int(PlatformLogic.descent_steps(grid, 0, 7, 5)).is_equal(1)

func test_descent_zero_steps() -> void:
	# AC-5.7.2: row 1 solid → 0 steps (no trigger).
	var grid: Dictionary = _make_solid_row(1, 7, 100)
	assert_int(PlatformLogic.descent_steps(grid, 0, 7, 5)).is_equal(0)

func test_descent_step_count_is_data_driven_not_hardcoded() -> void:
	# AC-5.7.2: the descent depth cap is DATA, not a code literal. With everything
	# below cleared, descent_steps must equal the /data descent_max_steps (not some
	# magic number baked into the call site).
	var max_steps: int = Registry.descent_max_steps(_tables)
	assert_int(max_steps).is_greater(0)
	# Empty grid → every row below is "cleared" → steps caps at max_steps.
	assert_int(PlatformLogic.descent_steps({}, 0, 7, 1, max_steps)).is_equal(max_steps)

# ══════════════════════════════════════════════════════════════════════════════
# PLATFORM SYSTEM — descent target, tween-not-snap, camera anchor (AC-5.7.1/2/3)
# ══════════════════════════════════════════════════════════════════════════════

func test_platform_uses_data_threshold_no_magic_literal() -> void:
	# AC-5.7.2: the system reads its threshold from /data (no hardcoded 5).
	var p := _make_platform()
	var threshold: int = Registry.platform_clear_threshold(_tables)
	var width: int = Registry.shaft_width(_tables)
	var start_x: int = Registry.shaft_left_cell(_tables)
	# One below threshold → no descent; at threshold → descend.
	var below: Dictionary = {}
	for x in range(start_x, start_x + width - (threshold - 1)):
		below[Vector2i(x, 1)] = 50  # leave threshold-1 cleared
	assert_bool(p.should_descend(below)).is_false()
	assert_bool(p.should_descend({})).is_true()  # all cleared → descend

func test_platform_descends_one_step_per_trigger() -> void:
	# AC-5.7.2: one descent step per trigger when only the row directly below clears.
	var p := _make_platform()
	var width: int = Registry.shaft_width(_tables)
	var start_x: int = Registry.shaft_left_cell(_tables)
	# Row 1 fully cleared, row 2 solid → exactly one step; target_row goes 0 → 1.
	var grid: Dictionary = _make_solid_row(2, width, 100, start_x)
	var steps: int = p.try_descend(grid)
	assert_int(steps).is_equal(1)
	assert_int(p.target_row).is_equal(1)

func test_platform_no_descent_below_threshold() -> void:
	# AC-5.7.2: below threshold → no row change, no descent.
	var p := _make_platform()
	var width: int = Registry.shaft_width(_tables)
	var start_x: int = Registry.shaft_left_cell(_tables)
	var grid: Dictionary = _make_solid_row(1, width, 100, start_x)  # row below solid
	assert_int(p.try_descend(grid)).is_equal(0)
	assert_int(p.target_row).is_equal(0)

func test_descent_emits_descended_signal_with_new_row() -> void:
	# AC-5.7.2: a committed descent announces the new target row exactly once.
	var p := _make_platform()
	var width: int = Registry.shaft_width(_tables)
	var start_x: int = Registry.shaft_left_cell(_tables)
	var monitor := monitor_signals(p)
	p.try_descend(_make_solid_row(2, width, 100, start_x))  # one step → row 1
	await assert_signal(monitor).is_emitted("descended", [1])

func test_descent_tweens_target_not_instant_snap() -> void:
	# AC-5.7.2: descent is a TWEEN toward the new target, not an instant snap. The
	# target position updates immediately, but the BODY does not jump there in the
	# same frame (it is still near its old position until the tween advances).
	var p := _make_platform()
	var width: int = Registry.shaft_width(_tables)
	var start_x: int = Registry.shaft_left_cell(_tables)
	var body := p.get_node("Body") as Node2D
	var start_y: float = body.position.y
	p.try_descend(_make_solid_row(2, width, 100, start_x))  # one step down
	# Target advanced down a full cell; the body has NOT yet reached it.
	var target_y: float = p.platform_target_position().y
	assert_float(target_y).is_greater(start_y)
	assert_float(body.position.y).is_less(target_y)

func test_camera_target_equals_platform_target_derived() -> void:
	# AC-5.7.3: the camera anchor follows the PLATFORM TARGET (same x, offset down by
	# the data-driven lookahead) — it tracks the platform target, not a raw position.
	var p := _make_platform()
	var pt: Vector2 = p.platform_target_position()
	var ct: Vector2 = p.camera_target_position()
	var cell: int = Registry.block_pixel_size(_tables)
	var lookahead: int = Registry.camera_lookahead_cells(_tables)
	assert_float(ct.x).is_equal(pt.x)
	assert_float(ct.y).is_equal(pt.y + float(lookahead * cell))

func test_camera_target_tracks_platform_target_through_descent() -> void:
	# AC-5.7.3: after a descent, the camera target moves WITH the platform target
	# (the invariant ct == pt + lookahead holds at the new row too).
	var p := _make_platform()
	var width: int = Registry.shaft_width(_tables)
	var start_x: int = Registry.shaft_left_cell(_tables)
	p.try_descend(_make_solid_row(2, width, 100, start_x))  # descend one row
	var pt: Vector2 = p.platform_target_position()
	var ct: Vector2 = p.camera_target_position()
	var cell: int = Registry.block_pixel_size(_tables)
	var lookahead: int = Registry.camera_lookahead_cells(_tables)
	assert_float(ct.y).is_equal(pt.y + float(lookahead * cell))

func test_camera_smoothing_enabled_not_hard_set() -> void:
	# AC-5.7.3: the camera uses position smoothing (so re-anchoring to the platform
	# target eases rather than snapping). The system must NOT disable smoothing.
	var p := _make_platform()
	var cam := p.get_node("Camera") as Camera2D
	assert_bool(cam.position_smoothing_enabled).is_true()

# ── AC-5.7.1: physical platform + muzzle launch point (was untested) ───────────

func test_platform_is_physical_object_and_camera_anchor() -> void:
	# AC-5.7.1: the platform SHALL be a physical object and the camera's anchor. Assert the
	# authored Body is a StaticBody2D with a real collision shape (charges bounce off it) and
	# the Camera2D is a child anchor. (Previously AC-5.7.1 was cited in the header but no test
	# asserted the physical-anchor clause — flagged MISSING in the 2026-06-14 audit.)
	var p := _make_platform()
	var body := p.get_node_or_null("Body")
	assert_object(body).is_not_null()
	assert_bool(body is StaticBody2D).is_true()
	var shape := p.get_node_or_null("Body/CollisionShape2D") as CollisionShape2D
	assert_object(shape).is_not_null()
	assert_object(shape.shape).is_not_null()
	assert_object(p.get_node_or_null("Camera")).is_not_null()

func test_muzzle_position_derives_from_authored_marker() -> void:
	# AC-5.7.1: the predicted arc + live charges launch FROM the platform's muzzle. The
	# muzzle is the AUTHORED `Body/Muzzle` marker (not a code constant) — assert the marker
	# exists and muzzle_position() == platform_target + marker.position, so a charge spawns
	# exactly at the authored muzzle. (mine.gd previously hardcoded a -bps/2 offset and the
	# authored marker was orphaned — flagged in the audit.)
	var p := _make_platform()
	var marker := p.get_node_or_null("Body/Muzzle") as Node2D
	assert_object(marker).override_failure_message(
		"platform.tscn must author a Body/Muzzle marker (AC-5.7.1 launch point)"
	).is_not_null()
	var expected: Vector2 = p.platform_target_position() + marker.position
	assert_vector(p.muzzle_position()).is_equal(expected)
	# AC-5.3.9: the muzzle sits BELOW the platform target (positive local y) so a default
	# downward throw spawns under the platform body and enters the mine, never resting on it.
	assert_float(p.muzzle_position().y).is_greater(p.platform_target_position().y)
