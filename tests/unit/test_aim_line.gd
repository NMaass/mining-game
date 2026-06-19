extends GdUnitTestSuite
## UNIT AIM — AimLine (the _draw()-based dashed aim preview that replaced the broken Line2D +
## aim_dash.gdshader ShaderMaterial, which rendered nothing under GL-Compatibility/WebGL2 — see
## reports/aim-line-method.md). _draw() needs a real GL context (proven by the screenshot, not here),
## so these tests drive the PURE node state + march math that gate the visual: point storage, the
## has_points / point_count predicates _begin_aim_fade_out reads, and the bounded marching phase
## (advanced by mine.gd, frozen to "still" when the reduced-motion / pause gate passes 0).
##
## ACs: AC-5.3.1 (initial-arc preview while aiming), AC-5.10.4 (reduced-motion: dashes hold still).

func _line() -> AimLine:
	return auto_free(AimLine.new()) as AimLine

# ── Point storage + predicates (drives _update_preview / _clear_preview / fade gating) ──

func test_starts_empty() -> void:
	var l: AimLine = _line()
	assert_int(l.point_count()).is_equal(0)
	assert_bool(l.has_points()).is_false()

func test_set_points_stores_path() -> void:
	# AC-5.3.1: the AimLine holds the SAME Aim.preview_path points mine.gd used to push to Line2D.
	var l: AimLine = _line()
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(20, 30)])
	l.set_points(pts)
	assert_int(l.point_count()).is_equal(3)
	assert_bool(l.has_points()).is_true()

func test_has_points_needs_two() -> void:
	# A single point can't draw a dash (needs a segment) — has_points() is false (matches _draw's guard).
	var l: AimLine = _line()
	l.set_points(PackedVector2Array([Vector2(5, 5)]))
	assert_int(l.point_count()).is_equal(1)
	assert_bool(l.has_points()).is_false()

func test_clear_empties() -> void:
	var l: AimLine = _line()
	l.set_points(PackedVector2Array([Vector2(0, 0), Vector2(1, 1)]))
	l.clear()
	assert_int(l.point_count()).is_equal(0)
	assert_bool(l.has_points()).is_false()

# ── March math (the dash crawl; the reduced-motion / pause "still" contract) ──

func test_advance_march_wraps_within_period() -> void:
	# The march phase stays bounded by the dash period (no float drift over a long aim). 18+14 = 32.
	var l: AimLine = _line()
	l.dash_px = 18.0
	l.gap_px = 14.0
	l.advance_march(40.0)  # > one period
	assert_float(l._march_px).is_equal_approx(8.0, 0.0001)  # 40 mod 32

func test_advance_march_zero_is_noop() -> void:
	# AC-5.10.4: the reduced-motion / pause gate passes 0 → the pattern holds perfectly still.
	var l: AimLine = _line()
	l.advance_march(12.0)
	var held: float = l._march_px
	l.advance_march(0.0)
	assert_float(l._march_px).is_equal(held)  # unchanged: dashes don't crawl

func test_advance_march_accumulates() -> void:
	var l: AimLine = _line()
	l.dash_px = 18.0
	l.gap_px = 14.0  # period 32
	l.advance_march(10.0)
	l.advance_march(10.0)
	assert_float(l._march_px).is_equal_approx(20.0, 0.0001)

# ── Cosmetic setters used by the throw fade-out tween ──

func test_alpha_mult_and_width_are_settable() -> void:
	# _begin_aim_fade_out tweens alpha_mult + width to 0 (replacing the old self_modulate:a / width).
	var l: AimLine = _line()
	l.alpha_mult = 0.0
	l.width = 0.0
	assert_float(l.alpha_mult).is_equal(0.0)
	assert_float(l.width).is_equal(0.0)

# ── March-speed easing (the ←/→ "actively aiming" speed-up; v0.5 aim-indicator pass) ──
# AC-5.3.1 (the aim preview reads as alive while aiming). ease_march_mult is the pure speed-blend
# mine.gd._animate_aim_line drives; these prove the speed-up ramps in while aiming and back out on
# release, stays clamped, and is frame-rate independent.

func test_ease_march_mult_eases_up_while_aiming() -> void:
	# Holding ←/→ ramps the multiplier UP from 1.0 toward the boost peak (a single step moves part-way).
	var m: float = AimLine.ease_march_mult(1.0, true, 2.6, 8.0, 0.1)
	assert_float(m).is_greater(1.0)
	assert_float(m).is_less_equal(2.6)

func test_ease_march_mult_eases_back_down_on_release() -> void:
	# Releasing (aiming=false) eases the multiplier back DOWN toward 1.0 (base march speed).
	var m: float = AimLine.ease_march_mult(2.6, false, 2.6, 8.0, 0.1)
	assert_float(m).is_less(2.6)
	assert_float(m).is_greater_equal(1.0)

func test_ease_march_mult_clamps_to_boost_peak() -> void:
	# A huge step can't overshoot the boost peak (the multiplier is clamped to [1, boost_mult]).
	var m: float = AimLine.ease_march_mult(1.0, true, 2.6, 1000.0, 1.0)
	assert_float(m).is_equal_approx(2.6, 0.0001)

func test_ease_march_mult_clamps_to_base_floor() -> void:
	# A huge release step can't undershoot 1.0 (base speed is the floor).
	var m: float = AimLine.ease_march_mult(2.6, false, 2.6, 1000.0, 1.0)
	assert_float(m).is_equal_approx(1.0, 0.0001)

func test_ease_march_mult_snaps_when_no_ease_budget() -> void:
	# delta<=0 or ease_rate<=0 has no easing budget → snap straight to the (clamped) target.
	assert_float(AimLine.ease_march_mult(1.0, true, 2.6, 0.0, 0.1)).is_equal_approx(2.6, 0.0001)
	assert_float(AimLine.ease_march_mult(2.6, false, 2.6, 8.0, 0.0)).is_equal_approx(1.0, 0.0001)

func test_ease_march_mult_boost_below_one_treated_as_no_speedup() -> void:
	# A boost peak < 1 (shouldn't pass the data gate) can't slow the march below base: peak floors at 1.
	var m: float = AimLine.ease_march_mult(1.0, true, 0.5, 1000.0, 1.0)
	assert_float(m).is_equal_approx(1.0, 0.0001)

# ── Visibility gate (drives _update_preview; the "hidden while the platform is in motion" rule) ──
# AC-5.3.1 (preview while aiming) / AC-5.7.x (no stale arc from a moving launch point). preview_visible
# is the pure gate _update_preview reads; these prove each term hides the arc.

func test_preview_visible_when_aim_in_play() -> void:
	# A live aim with a still launch point: the arc is shown.
	assert_bool(AimLine.preview_visible(false, false, false, false)).is_true()

func test_preview_hidden_while_launch_point_moving() -> void:
	# Requirement (4): the arc is HIDDEN while the platform/elevator/supports are moving (a drawn arc
	# from a moving muzzle would be a stale lie); it reappears (recomputed) once they settle.
	assert_bool(AimLine.preview_visible(false, false, false, true)).is_false()

func test_preview_hidden_after_dig_ended() -> void:
	assert_bool(AimLine.preview_visible(true, false, false, false)).is_false()

func test_preview_hidden_while_charge_in_flight() -> void:
	assert_bool(AimLine.preview_visible(false, true, false, false)).is_false()

func test_preview_hidden_while_throw_fading() -> void:
	# The throw fade-out owns the line — the snap-redraw gate must not fight it.
	assert_bool(AimLine.preview_visible(false, false, true, false)).is_false()
