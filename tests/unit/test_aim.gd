extends GdUnitTestSuite
## U6 — Aim & initial-arc preview (v0.4 salvage).
## ACs: AC-5.3.1 (drag adjusts angle + initial-arc preview to first bounce),
##       AC-5.3.2 (power from data, not input), AC-5.3.6 (tap selects tray slot),
##       AC-5.3.7 (mouse/touch parity — one shared code path),
##       AC-5.3.8 (no lose state — a throw is always possible).
##
## v0.3's determinism tautology (test_same_coords_same_angle: f(x)==f(x)) was DELETED
## per the salvage map — it asserted nothing about parity. Parity is now structural:
## the controller exposes ONE shared drag path for mouse and touch (tests below).

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

# ── angle_from_drag (AC-5.3.1) ─────────────────────────────────────────────

func test_drag_right_positive_angle() -> void:
	# AC-5.3.1: dragging right = positive angle
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(150, 200))
	assert_bool(angle > 0.0).is_true()

func test_drag_left_negative_angle() -> void:
	# AC-5.3.1: dragging left = negative angle
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(50, 200))
	assert_bool(angle < 0.0).is_true()

func test_drag_straight_down_zero() -> void:
	# AC-5.3.1: dragging straight down = angle near 0
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(100, 200))
	assert_float(angle).is_equal_approx(0.0, 0.01)

func test_dead_zone_no_change() -> void:
	# AC-5.3.1: below the dead zone → returns the current angle unchanged.
	var current: float = 0.5
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(102, 103), current)
	assert_float(angle).is_equal(current)

func test_angle_in_full_circle_range() -> void:
	# AC-5.3.1 (v0.5 full 360°): any drag yields an angle in atan2's (-PI, PI] range — the whole
	# circle is reachable, there is no forward-arc clamp.
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(500, 100))
	assert_bool(angle <= Aim.MAX_ANGLE).is_true()
	assert_bool(angle >= Aim.MIN_ANGLE).is_true()

# ── Full 360° aim (v0.5): the player can aim ANY direction, including straight/shallow upward ──
# Old behavior clamped to a forward arc (~±1.92 rad), blocking upward lobs. Those clamp tests are
# replaced by these: an upward drag now produces an upward (|angle| > PI/2) launch angle.

func test_drag_up_right_aims_upward() -> void:
	# Dragging up-and-right (delta = +x, -y) aims into the upper-right hemisphere: angle > PI/2.
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(150, 0))
	# atan2(50, -100) ≈ 2.677 rad — past horizontal, pointing upward (NOT clamped to ~1.92).
	assert_float(angle).is_equal_approx(atan2(50.0, -100.0), 0.001)
	assert_bool(absf(angle) > PI / 2.0).is_true()  # genuinely upward, beyond the old clamp

func test_drag_up_left_aims_upward() -> void:
	# Dragging up-and-left aims into the upper-left hemisphere: angle < -PI/2.
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(0, 0))
	assert_float(angle).is_equal_approx(atan2(-100.0, -100.0), 0.001)  # ≈ -2.356 rad
	assert_bool(angle < -PI / 2.0).is_true()

func test_drag_straight_up_aims_up() -> void:
	# Dragging straight up (delta = (0, -y)) aims straight up: |angle| == PI. atan2(0, -1) == PI.
	var angle: float = Aim.angle_from_drag(Vector2(100, 100), Vector2(100, 0))
	assert_float(absf(angle)).is_equal_approx(PI, 0.001)

func test_drag_direction_is_honored_unclamped() -> void:
	# AC-5.3.1: the launch direction matches the drag direction exactly (no clamp warps it). The
	# direction vector built from the angle points the same way as the (down-y) drag delta.
	var start := Vector2(100, 100)
	var current := Vector2(40, 10)  # up-and-left
	var angle: float = Aim.angle_from_drag(start, current)
	var dir: Vector2 = Aim.angle_to_direction(angle)  # (sin a, cos a) — same x/y convention as drag
	var drag := (current - start).normalized()
	assert_float(dir.x).is_equal_approx(drag.x, 0.001)
	assert_float(dir.y).is_equal_approx(drag.y, 0.001)

func test_wrap_angle_normalizes_to_circle() -> void:
	# AC-5.3.1 (v0.5): wrap_angle keeps the angle in (-PI, PI] so a continuous glide never runs away.
	assert_float(Aim.wrap_angle(0.0)).is_equal_approx(0.0, 0.0001)
	# 1.5 turns past straight-down wraps back to the half-turn (straight up), within the circle.
	var wrapped: float = Aim.wrap_angle(3.0 * PI)
	assert_bool(wrapped > -PI - 0.0001 and wrapped <= PI + 0.0001).is_true()
	assert_float(absf(wrapped)).is_equal_approx(PI, 0.0001)

func test_default_angle_is_straight_down() -> void:
	# The default launch angle is 0.0 radians = straight down.
	assert_float(Aim.DEFAULT_ANGLE).is_equal(0.0)

# ── angle_to_direction ──────────────────────────────────────────────────────

func test_straight_down_direction() -> void:
	var dir: Vector2 = Aim.angle_to_direction(0.0)
	assert_float(dir.x).is_equal_approx(0.0, 0.001)
	assert_float(dir.y).is_equal_approx(1.0, 0.001)

func test_angled_direction() -> void:
	# 45 degrees right (PI/4)
	var dir: Vector2 = Aim.angle_to_direction(PI / 4.0)
	assert_float(dir.x).is_equal_approx(sin(PI / 4.0), 0.001)
	assert_float(dir.y).is_equal_approx(cos(PI / 4.0), 0.001)

# ── launch_impulse (AC-5.3.2) ──────────────────────────────────────────────

func test_launch_impulse_magnitude() -> void:
	# AC-5.3.2: power = base impulse from data (not a separate player input).
	var impulse: Vector2 = Aim.launch_impulse(0.0, 520.0)
	assert_float(impulse.length()).is_equal_approx(520.0, 0.1)

func test_launch_impulse_direction() -> void:
	var impulse: Vector2 = Aim.launch_impulse(0.0, 520.0)
	assert_float(impulse.x).is_equal_approx(0.0, 0.1)
	assert_float(impulse.y).is_equal_approx(520.0, 0.1)

func test_launch_impulse_uses_data_sourced_base_impulse() -> void:
	# AC-5.3.2: launch power is the charge's DATA-defined base impulse — not a literal and not a
	# separate player input. Prove the linkage end to end: two real explosives with DIFFERENT
	# /data base_impulse yield launch impulses of those exact magnitudes through the shared
	# ThrowParams→Aim path (was WEAK: the impulse tests used literal magnitudes, not real data).
	var free_id: String = Registry.free_charge_id(_tables)
	var data_free: float = float(Registry.explosive(_tables, free_id).get("base_impulse", -1.0))
	assert_float(data_free).is_greater(0.0)  # the data actually carries base_impulse
	var p_free := ThrowParams.from_explosive(_tables, free_id)
	assert_float(p_free.base_impulse).is_equal(data_free)
	# Straight-down launch: |impulse| == base_impulse (unit direction), so the magnitude is the
	# data value, routed through ThrowParams.impulse_at_angle → Aim.launch_impulse.
	assert_float(p_free.impulse_at_angle(0.0).length()).is_equal_approx(data_free, 0.01)
	# A different real charge with a different base_impulse yields a different impulse (linkage,
	# not a constant): heavy_bomb has its own base_impulse in /data.
	var data_heavy: float = float(Registry.explosive(_tables, "heavy_bomb").get("base_impulse", -1.0))
	assert_float(data_heavy).is_not_equal(data_free)  # the two really differ in /data
	var p_heavy := ThrowParams.from_explosive(_tables, "heavy_bomb")
	assert_float(p_heavy.impulse_at_angle(0.0).length()).is_equal_approx(data_heavy, 0.01)

# ── Aim.initial_arc preview (AC-5.3.1, v0.4 pre-first-bounce only) ──────────

func test_initial_arc_starts_at_muzzle() -> void:
	# AC-5.3.1: the predicted arc originates at the fixed muzzle, never the finger.
	var params: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var muzzle := Vector2(300.0, 50.0)
	var path: PackedVector2Array = Aim.initial_arc(params, 0.0, muzzle)
	assert_int(path.size()).is_greater(0)
	assert_float(path[0].x).is_equal_approx(muzzle.x, 0.001)
	assert_float(path[0].y).is_equal_approx(muzzle.y, 0.001)

func test_initial_arc_null_params_empty() -> void:
	# Defensive: a null params (no charge yet) yields an empty path, not a crash.
	var path: PackedVector2Array = Aim.initial_arc(null, 0.0, Vector2.ZERO)
	assert_int(path.size()).is_equal(0)

func test_initial_arc_stops_at_first_bounce() -> void:
	# AC-5.3.1: the preview ends at/just past the FIRST solid cell the throw enters,
	# NOT a full multi-bounce projection (post-bounce is intentionally unpredicted).
	var params: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var bps: int = Registry.block_pixel_size(_tables)
	var muzzle := Vector2(float(bps) * 3.5, 0.0)  # muzzle in column 3, row 0
	var is_solid := func(cell: Vector2i) -> bool:
		return cell.y >= 5  # solid floor at row 5 and below
	var full_steps: int = 240
	var path: PackedVector2Array = Aim.initial_arc(params, 0.0, muzzle, is_solid, full_steps, bps)
	# Stopped early → not a full projection to the step cap.
	assert_int(path.size()).is_less(full_steps + 1)
	# The last point is in (or just past) the first solid row...
	var last_cell: Vector2i = ThrowParams.cell_at(path[path.size() - 1], bps)
	assert_int(last_cell.y).is_greater_equal(5)
	# ...and no earlier sample was solid (single bounce, not multi).
	for i in range(path.size() - 1):
		assert_bool(is_solid.call(ThrowParams.cell_at(path[i], bps))).is_false()

func test_initial_arc_open_when_no_surface_hit() -> void:
	# AC-5.3.1: with no reachable solid cell, the arc runs the full sample (open hint).
	var params: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var never_solid := func(_cell: Vector2i) -> bool:
		return false
	var path: PackedVector2Array = Aim.initial_arc(params, 0.0, Vector2.ZERO, never_solid, 20)
	assert_int(path.size()).is_equal(21)  # muzzle + 20 steps

# ── AimController: shared mouse/touch path (AC-5.3.7) ───────────────────────
# Input events don't fire headless, so we drive the SHARED begin/update/end methods
# directly. Parity is structural: a mouse drag and a touch drag with the same coords
# call the identical code and produce the identical angle.

func test_controller_drag_sets_angle() -> void:
	# AC-5.3.1: a drag through the shared path adjusts the angle off the default.
	var ctrl: AimController = auto_free(AimController.new())
	ctrl.begin_drag(Vector2(200, 300))
	var angle: float = ctrl.update_drag(Vector2(260, 420))  # drag down-right
	assert_bool(angle > 0.0).is_true()
	assert_float(ctrl.angle).is_equal(angle)
	ctrl.end_drag()
	assert_bool(ctrl.is_dragging).is_false()

func test_controller_mouse_touch_parity() -> void:
	# AC-5.3.7: mouse and touch are ONE code path → identical coords give the
	# identical angle. We exercise the shared begin/update/end methods twice (the
	# same methods _unhandled_input dispatches both event kinds to).
	var start := Vector2(150, 200)
	var current := Vector2(230, 360)

	var mouse_ctrl: AimController = auto_free(AimController.new())
	mouse_ctrl.begin_drag(start)
	var mouse_angle: float = mouse_ctrl.update_drag(current)

	var touch_ctrl: AimController = auto_free(AimController.new())
	touch_ctrl.begin_drag(start)
	var touch_angle: float = touch_ctrl.update_drag(current)

	# Parity is STRUCTURAL: both the "mouse" and "touch" paths delegate to the SAME pure
	# Aim.angle_from_drag — that shared code path IS the parity guarantee (AC-5.3.7). Pinning
	# BOTH outputs to the pure function proves it; asserting mouse_angle == touch_angle alone
	# would be a tautology (identical code on identical input), so it is dropped.
	var expected: float = Aim.angle_from_drag(start, current, Aim.DEFAULT_ANGLE)
	assert_float(mouse_angle).is_equal(expected)
	assert_float(touch_angle).is_equal(expected)

func test_controller_dead_zone_no_change() -> void:
	# AC-5.3.1: a sub-dead-zone drag leaves the committed angle untouched.
	var ctrl: AimController = auto_free(AimController.new())
	ctrl.begin_drag(Vector2(100, 100))
	var angle: float = ctrl.update_drag(Vector2(103, 104))  # < DEAD_ZONE_PX
	assert_float(angle).is_equal(Aim.DEFAULT_ANGLE)

func test_controller_disabled_ignores_drag() -> void:
	# AC-5.3.8 plumbing: while disabled (e.g. charge in flight) input is inert; the
	# aim never enters a broken/lose state, it just holds.
	var ctrl: AimController = auto_free(AimController.new())
	ctrl.set_enabled(false)
	ctrl.begin_drag(Vector2(100, 100))
	var angle: float = ctrl.update_drag(Vector2(300, 400))
	assert_float(angle).is_equal(Aim.DEFAULT_ANGLE)
	assert_bool(ctrl.is_dragging).is_false()

func test_controller_preview_delegates_to_aim() -> void:
	# AC-5.3.1: the controller's preview is the same initial-arc path Aim produces
	# for the controller's current angle (single source of truth).
	var params: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var ctrl: AimController = auto_free(AimController.new())
	ctrl.begin_drag(Vector2(100, 100))
	ctrl.update_drag(Vector2(160, 220))
	var muzzle := Vector2(300, 0)
	var via_ctrl: PackedVector2Array = ctrl.preview_path(params, muzzle)
	var via_aim: PackedVector2Array = Aim.initial_arc(params, ctrl.angle, muzzle)
	assert_int(via_ctrl.size()).is_equal(via_aim.size())
	assert_vector(via_ctrl[0]).is_equal(via_aim[0])
	assert_vector(via_ctrl[via_ctrl.size() - 1]).is_equal(via_aim[via_aim.size() - 1])

# ── ThrowControls: tray selection (AC-5.3.6) + no lose state (AC-5.3.8) ─────

func test_tap_selects_tray_slot() -> void:
	# AC-5.3.6: tapping a tray slot selects it as the active charge.
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.set_slot_count(3)
	assert_int(tc.selected_index).is_equal(0)  # free slot active by default
	assert_int(tc.select_slot(2)).is_equal(2)
	assert_int(tc.selected_index).is_equal(2)

func test_tap_out_of_range_keeps_selection() -> void:
	# AC-5.3.6: a tap outside the tray is ignored (selection unchanged).
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.set_slot_count(2)
	tc.select_slot(1)
	assert_int(tc.select_slot(5)).is_equal(1)
	assert_int(tc.select_slot(-1)).is_equal(1)

func test_free_slot_always_selectable() -> void:
	# AC-5.3.6/AC-5.3.8: the free slot (index 0) is always present + selectable, even
	# with no bought charges — the tray can never be empty.
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.set_slot_count(0)  # caller under-reports; controller floors to the free slot
	assert_int(tc.slot_count).is_equal(1)
	assert_int(tc.select_slot(0)).is_equal(0)

func test_selection_clamped_when_tray_shrinks() -> void:
	# AC-5.3.6: when bought charges are consumed and the tray shrinks, the selection
	# falls back to a valid slot (never dangles past the end).
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.set_slot_count(3)
	tc.select_slot(2)
	tc.set_slot_count(1)  # only the free slot remains
	assert_int(tc.selected_index).is_equal(0)

func test_throw_always_possible() -> void:
	# AC-5.3.8: a throw is always possible (free charge) — commit succeeds with only
	# the free slot present and emits a throw request.
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.set_slot_count(1)
	var fired: Array = [false]
	tc.throw_requested.connect(func(_i: int) -> void: fired[0] = true)
	assert_bool(tc.can_throw()).is_true()
	assert_bool(tc.commit_throw()).is_true()
	assert_bool(fired[0]).is_true()

func test_throw_blocked_only_while_in_flight() -> void:
	# AC-5.3.3: throw commits the active charge; it is blocked ONLY while a charge is
	# already in flight (not by an empty tray — there is no empty-tray state).
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.set_can_throw(false)
	assert_bool(tc.commit_throw()).is_false()
	tc.set_can_throw(true)
	assert_bool(tc.commit_throw()).is_true()

func test_throw_blocked_during_cooldown() -> void:
	# v0.5: a 2s throw cooldown prevents spamming; commit is rejected while cooling.
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.start_cooldown(1.0)
	assert_bool(tc.can_throw()).is_false()
	assert_bool(tc.commit_throw()).is_false()

func test_cooldown_expires_and_allows_throw() -> void:
	# v0.5: advancing the cooldown eventually re-enables throwing.
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.start_cooldown(0.5)
	assert_bool(tc.can_throw()).is_false()
	tc.advance_cooldown(0.25)
	assert_bool(tc.can_throw()).is_false()
	tc.advance_cooldown(0.3)
	assert_bool(tc.can_throw()).is_true()
	assert_bool(tc.commit_throw()).is_true()

func test_cooldown_progress_and_text() -> void:
	# v0.5: cooldown exposes progress [0,1] and countdown text for the UI fill.
	var tc: ThrowControls = auto_free(ThrowControls.new())
	tc.start_cooldown(2.0)
	assert_float(tc.cooldown_progress).is_equal(0.0)
	assert_str(tc.cooldown_text).contains("2.0")
	tc.advance_cooldown(1.0)
	assert_float(tc.cooldown_progress).is_equal(0.5)
	assert_str(tc.cooldown_text).contains("1.0")
	tc.advance_cooldown(1.0)
	assert_float(tc.cooldown_progress).is_equal(1.0)
	assert_str(tc.cooldown_text).is_empty()

# ── Keyboard held-aim (D1) — Aim.keyboard_angle_step (AC-5.3.1/5.3.2) ────────
# Key events do NOT fire headless, so the wiring (mine.gd._apply_keyboard_aim) drives this PURE
# helper; the helper is what we test directly. It maps a held direction + frame delta to a new
# clamped angle (forgiving/smooth — no precision requirement).

func test_keyboard_aim_right_increases_angle() -> void:
	# AC-5.3.1: holding aim_right (+1) nudges the angle positive (toward the right).
	var a: float = Aim.keyboard_angle_step(0.0, 1, 90.0, 0.1)
	assert_bool(a > 0.0).is_true()

func test_keyboard_aim_left_decreases_angle() -> void:
	# AC-5.3.1: holding aim_left (-1) nudges the angle negative (toward the left).
	var a: float = Aim.keyboard_angle_step(0.0, -1, 90.0, 0.1)
	assert_bool(a < 0.0).is_true()

func test_keyboard_aim_no_direction_is_unchanged() -> void:
	# dir 0 (nothing held / both held) leaves the angle exactly where it was.
	assert_float(Aim.keyboard_angle_step(0.4, 0, 90.0, 0.1)).is_equal(0.4)

func test_keyboard_aim_scales_with_delta() -> void:
	# AC-5.3.2 forgiving + frame-rate independent: a larger delta moves the angle proportionally more.
	var small: float = Aim.keyboard_angle_step(0.0, 1, 90.0, 0.05)
	var big: float = Aim.keyboard_angle_step(0.0, 1, 90.0, 0.10)
	assert_float(big).is_equal_approx(small * 2.0, 0.0001)

func test_keyboard_aim_uses_data_rate() -> void:
	# AC-5.3.2: the step magnitude is exactly rate(deg/sec)*delta converted to radians — proves the
	# data-driven rate is honored (not a code constant).
	var a: float = Aim.keyboard_angle_step(0.0, 1, 90.0, 1.0)
	assert_float(a).is_equal_approx(deg_to_rad(90.0), 0.0001)

func test_keyboard_aim_wraps_past_straight_up() -> void:
	# AC-5.3.1 (v0.5 full 360°): the keyboard glide WRAPS at the top instead of saturating, so a held
	# key sweeps continuously around the circle (no hard stop). Stepping right from just-below-PI by a
	# bit more than the remaining arc lands just past -PI (i.e. wraps into the negative hemisphere).
	var a: float = Aim.keyboard_angle_step(PI - 0.05, 1, rad_to_deg(0.1), 1.0)  # +0.1 rad step
	assert_bool(a <= PI + 0.0001 and a > -PI - 0.0001).is_true()  # stayed in the circle
	assert_bool(a < 0.0).is_true()  # wrapped from +near-PI to the -PI side

func test_keyboard_aim_result_always_in_circle() -> void:
	# A huge step never escapes (-PI, PI]: the wrap keeps the angle bounded (no runaway).
	var a: float = Aim.keyboard_angle_step(0.0, 1, 100000.0, 1.0)
	assert_bool(a > -PI - 0.0001 and a <= PI + 0.0001).is_true()

func test_keyboard_aim_zero_rate_is_inert() -> void:
	# A 0/negative rate (gate-rejected, but defensive) makes no change — the early-return path.
	assert_float(Aim.keyboard_angle_step(0.3, 1, 0.0, 0.1)).is_equal(0.3)

func test_keyboard_aim_zero_delta_is_inert() -> void:
	# A 0 delta (paused / first frame) makes no change.
	assert_float(Aim.keyboard_angle_step(0.3, 1, 90.0, 0.0)).is_equal(0.3)
