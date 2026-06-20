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
	p.support_row = 100  # supports already deep so the platform may descend freely
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
	p.support_row = 100
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
	p.support_row = 100
	p.try_descend(_make_solid_row(2, width, 100, start_x))  # one step → row 1
	await assert_signal(monitor).is_emitted("descended", [1])

func test_descent_tweens_target_not_instant_snap() -> void:
	# AC-5.7.2: descent is a TWEEN toward the new target, not an instant snap. The
	# target position updates immediately, but the BODY does not jump there in the
	# same frame (it is still near its old position until the tween advances).
	var p := _make_platform()
	p.support_row = 100
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
	# AC-5.7.3: the camera anchor follows the PLATFORM TARGET (same x, offset by the
	# data-driven screen fraction so the platform sits at the intended viewport height).
	var p := _make_platform()
	var pt: Vector2 = p.platform_target_position()
	var ct: Vector2 = p.camera_target_position()
	assert_float(ct.x).is_equal(pt.x)
	# The vertical offset is computed from viewport height, zoom, and the configured fraction.
	# We can only assert it is a finite, deterministic value (the test viewport is fixed headless).
	assert_float(ct.y).is_not_equal(pt.y)
	assert_float(ct.y - pt.y).is_equal_approx(p._camera_vertical_offset_px, 0.001)

func test_camera_target_tracks_platform_target_through_descent() -> void:
	# AC-5.7.3: after a descent, the camera target moves WITH the platform target
	# (the vertical offset invariant holds at the new row too).
	var p := _make_platform()
	var width: int = Registry.shaft_width(_tables)
	var start_x: int = Registry.shaft_left_cell(_tables)
	p.support_row = 100
	p.try_descend(_make_solid_row(2, width, 100, start_x))  # descend one row
	var pt: Vector2 = p.platform_target_position()
	var ct: Vector2 = p.camera_target_position()
	assert_float(ct.y - pt.y).is_equal_approx(p._camera_vertical_offset_px, 0.001)

func test_camera_smoothing_enabled_not_hard_set() -> void:
	# AC-5.7.3: the camera uses position smoothing (so re-anchoring to the platform
	# target eases rather than snapping). The system must NOT disable smoothing.
	var p := _make_platform()
	var cam := p.get_node("Camera") as Camera2D
	assert_bool(cam.position_smoothing_enabled).is_true()

# ── AC-5.7.1: physical platform + muzzle launch point (was untested) ───────────

func test_platform_is_visual_anchor_with_camera() -> void:
	# AC-5.7.1: the platform is the camera anchor and launch origin; it is intentionally
	# NOT a physics collider so charges pass through cleanly. Assert the authored Body is
	# a plain Node2D, there is no collision shape, and the Camera2D is a child anchor.
	var p := _make_platform()
	var body := p.get_node_or_null("Body")
	assert_object(body).is_not_null()
	assert_bool(body is Node2D).is_true()
	var shape := p.get_node_or_null("Body/CollisionShape2D") as CollisionShape2D
	assert_object(shape).is_null()
	assert_object(p.get_node_or_null("Camera")).is_not_null()

# ══════════════════════════════════════════════════════════════════════════════
# TRAUMA-BASED CAMERA SHAKE + ZOOM PUNCH (v0.5 arcade pass — offset/zoom only)
# ══════════════════════════════════════════════════════════════════════════════

func test_add_trauma_then_decay_returns_offset_exactly_to_zero() -> void:
	# AC-5.7.3 (shake must not fight position smoothing): after trauma fully decays, the
	# camera OFFSET is hard-set back to EXACTLY Vector2.ZERO — no residual drift that would
	# permanently bias the smoothed follow. Drive _process with a delta large enough to
	# exhaust the trauma (decay_per_sec * delta >> 1).
	var p := _make_platform()
	var cam := p.get_node("Camera") as Camera2D
	p.add_trauma(0.5, Vector2(123.0, 456.0))
	assert_float(p.trauma).is_greater(0.0)
	p._process(0.05)  # advance one frame → a non-zero shake offset while trauma > 0
	assert_vector(cam.offset).is_not_equal(Vector2.ZERO)
	# Now exhaust the trauma in one big step (decay 1.8/s * 10s >> 1).
	p._process(10.0)
	assert_float(p.trauma).is_equal(0.0)
	# The offset is back to dead center, EXACTLY (no sub-pixel residue).
	assert_vector(cam.offset).is_equal(Vector2.ZERO)

func test_shake_writes_offset_not_camera_position_or_target() -> void:
	# AC-5.7.3 (CRITICAL): shake/zoom write camera.offset/zoom ONLY — never camera.position
	# or the platform target. The camera POSITION + the derived target must be unchanged by a
	# trauma kick (only the OFFSET moves), so the smoothed follow is never fought.
	var p := _make_platform()
	var cam := p.get_node("Camera") as Camera2D
	var pos_before: Vector2 = cam.position
	var target_before: Vector2 = p.camera_target_position()
	p.add_trauma(0.8, Vector2(50.0, 50.0))
	p._process(0.05)
	assert_vector(cam.position).is_equal(pos_before)              # position untouched
	assert_vector(p.camera_target_position()).is_equal(target_before)  # target untouched
	assert_vector(cam.offset).is_not_equal(Vector2.ZERO)         # the shake lives in OFFSET

func test_more_cleared_cells_yield_more_trauma() -> void:
	# Feel contract: a bigger break adds more trauma (the caller scales trauma by cleared
	# cells in mine.gd; here assert the model is additive + clamped to 1).
	var small := _make_platform()
	small.add_trauma(0.2, Vector2.ZERO)
	var big := _make_platform()
	big.add_trauma(0.8, Vector2.ZERO)
	assert_float(big.trauma).is_greater(small.trauma)
	# Trauma is clamped to 1 even when overdriven (a megablast doesn't overflow).
	var clamped := _make_platform()
	clamped.add_trauma(5.0, Vector2.ZERO)
	assert_float(clamped.trauma).is_equal(1.0)

func test_zoom_punch_kicks_zoom_then_can_settle_back_to_base() -> void:
	# Zoom punch writes camera.zoom (never position): immediately after a punch the zoom is
	# ABOVE the base (zoomed in); a process_frame lets the settle tween advance back toward base.
	var p := _make_platform()
	var cam := p.get_node("Camera") as Camera2D
	var base: float = Registry.camera_zoom(_tables)
	p.zoom_punch(1.0)
	# Punched IN: zoom is strictly greater than the base on the punch frame.
	assert_float(cam.zoom.x).is_greater(base)
	# A zero-strength punch is a no-op (no kick).
	var q := _make_platform()
	var qcam := q.get_node("Camera") as Camera2D
	var z_before: Vector2 = qcam.zoom
	q.zoom_punch(0.0)
	assert_vector(qcam.zoom).is_equal(z_before)

func test_recoil_kicks_only_the_visual_not_body_muzzle_or_camera() -> void:
	# Launch recoil (v0.5 arcade pass) is a TACTILE deck kick that must stay cosmetic: it writes
	# ONLY the Body/Visual child's local position. The Body (descent target), the muzzle marker,
	# and the camera/target are contract surfaces and MUST be untouched (AC-5.7.x: recoil can
	# never fight the descent tween or drift the launch point). Assert the Visual moves once the
	# kick tween advances, while every contract surface is byte-identical.
	var p := _make_platform()
	var body := p.get_node("Body") as Node2D
	var visual := p.get_node("Body/Visual") as Node2D
	var muzzle := p.get_node("Body/Muzzle") as Marker2D
	var cam := p.get_node("Camera") as Camera2D
	var visual_rest: Vector2 = visual.position
	var body_before: Vector2 = body.position
	var muzzle_before: Vector2 = muzzle.position
	var cam_before: Vector2 = cam.position
	var muzzle_world_before: Vector2 = p.muzzle_position()
	p.recoil(0.0, 6.0)  # straight-down launch → the deck kicks UP (applied immediately)
	# The Visual deck moved off its rest position (the kick is applied synchronously)...
	assert_vector(visual.position).override_failure_message(
		"recoil did not move the Body/Visual deck off its rest position"
	).is_not_equal(visual_rest)
	# ...but NOTHING contract-related moved: Body, muzzle marker, camera, and the world-space
	# muzzle launch point are all exactly as before.
	assert_vector(body.position).is_equal(body_before)
	assert_vector(muzzle.position).is_equal(muzzle_before)
	assert_vector(cam.position).is_equal(cam_before)
	assert_vector(p.muzzle_position()).is_equal(muzzle_world_before)

func test_recoil_zero_px_is_a_noop() -> void:
	# Motion-intensity 0 (reduced motion) passes 0px recoil → the deck never moves. A 0/negative
	# recoil must be a clean no-op (the deck stays exactly at rest).
	var p := _make_platform()
	var visual := p.get_node("Body/Visual") as Node2D
	var rest: Vector2 = visual.position
	p.recoil(0.0, 0.0)
	assert_vector(visual.position).is_equal(rest)

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
	# AC-5.3.9: the muzzle sits at the CHARACTER (above the platform target, negative local y) so
	# the aim line + live charge originate from the visible thrower. A thrown charge passes THROUGH
	# the visual-only platform into the cleared shaft, so it still enters the mine and never rests
	# on the platform line.
	assert_float(p.muzzle_position().y).is_less(p.platform_target_position().y)

# ══════════════════════════════════════════════════════════════════════════════
# MANUAL ELEVATOR MOVES (Wave 4: big blocky HUD arrows move the platform)
# ══════════════════════════════════════════════════════════════════════════════

func test_can_move_up_false_at_top() -> void:
	var p := _make_platform(0)
	assert_bool(p.can_move_up()).is_false()

func test_can_move_down_false_at_support_limit() -> void:
	# UNIT MAPGEN: the infinite shaft has no mine floor — the deepest the platform can move is
	# its current support row. At the support limit, move-down is disabled.
	var p := _make_platform(50)
	p.support_row = 50
	assert_bool(p.can_move_down()).is_false()

func test_move_up_clamps_at_top() -> void:
	var p := _make_platform(0)
	assert_bool(p.move_up()).is_false()
	assert_int(p.target_row).is_equal(0)

func test_move_down_clamps_at_support_limit() -> void:
	# UNIT MAPGEN: with no mine floor, the platform clamps at the deepest SUPPORTED row.
	var p := _make_platform(80)
	p.support_row = 80
	assert_bool(p.move_down()).is_false()
	assert_int(p.target_row).is_equal(80)

func test_move_down_stops_at_support_row() -> void:
	# UNIT MAPGEN: the platform descends one row toward the support row, then stops there — the
	# support row, not a mine floor, is the bottom in the infinite shaft.
	var p := _make_platform(78)
	p.support_row = 79
	assert_bool(p.move_down()).is_true()
	assert_int(p.target_row).is_equal(79)
	assert_bool(p.move_down()).is_false()
	assert_int(p.target_row).is_equal(79)

func test_move_up_then_down_returns_to_start() -> void:
	var p := _make_platform(1)
	p.support_row = 1
	assert_bool(p.move_up()).is_true()
	assert_int(p.target_row).is_equal(0)
	assert_bool(p.move_down()).is_true()
	assert_int(p.target_row).is_equal(1)

func test_manual_move_emits_descended_signal() -> void:
	var p := _make_platform(0)
	p.support_row = 1
	var monitor := monitor_signals(p)
	p.move_down()
	await assert_signal(monitor).is_emitted("descended", [1])

func test_manual_move_tweens_target_not_snap() -> void:
	# AC-5.7.2: manual elevator movement reuses the descent tween path.
	var p := _make_platform(0)
	p.support_row = 1
	var body := p.get_node("Body") as Node2D
	var start_y: float = body.position.y
	p.move_down()
	var target_y: float = p.platform_target_position().y
	assert_float(target_y).is_greater(start_y)
	assert_float(body.position.y).is_less(target_y)

func test_manual_move_reanchors_camera() -> void:
	# AC-5.7.3: the camera target follows the new platform target after a manual move,
	# preserving the same vertical screen-fraction offset.
	var p := _make_platform(0)
	p.move_down()
	var pt: Vector2 = p.platform_target_position()
	var ct: Vector2 = p.camera_target_position()
	assert_float(ct.x).is_equal(pt.x)
	assert_float(ct.y - pt.y).is_equal_approx(p._camera_vertical_offset_px, 0.001)
