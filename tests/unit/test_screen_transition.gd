extends GdUnitTestSuite
## ScreenTransition: pure fade/reveal envelope math (presentation polish for the
## smooth start → dig → run-end transitions + the relic confirmation toast).
##
## The runtime drives both the reveal veil and the relic toast through a single
## tween_method over elapsed time that evaluates THESE functions, so pinning the
## curve shape here (endpoints, plateau, monotonicity, zero-duration guards) proves
## the live alpha is well-behaved without a headless render.
##
## ACs: presentation support for AC-5.8.1 (relic feedback) + AC-5.8.4 (distinct
##      dig-end state) — no determinism/physics burden, pure f(elapsed, durations).

const ST := preload("res://scripts/core/screen_transition.gd")

# ── fade envelope: 0 → 1 (in) → 1 (hold) → 0 (out) ─────────────────────────────

func test_fade_starts_at_zero_when_there_is_a_fade_in() -> void:
	# AC-5.8.1: a toast with a fade-in begins fully transparent.
	assert_float(ST.fade_alpha_at(0.0, 0.2, 1.0, 0.4)).is_equal_approx(0.0, 0.0001)

func test_fade_ramps_up_linearly_through_the_in_phase() -> void:
	assert_float(ST.fade_alpha_at(0.1, 0.2, 1.0, 0.4)).is_equal_approx(0.5, 0.0001)

func test_fade_is_full_through_the_hold_plateau() -> void:
	# Anywhere in [in, in+hold) the banner sits at full alpha.
	assert_float(ST.fade_alpha_at(0.2, 0.2, 1.0, 0.4)).is_equal_approx(1.0, 0.0001)
	assert_float(ST.fade_alpha_at(0.7, 0.2, 1.0, 0.4)).is_equal_approx(1.0, 0.0001)
	assert_float(ST.fade_alpha_at(1.19, 0.2, 1.0, 0.4)).is_equal_approx(1.0, 0.0001)

func test_fade_ramps_down_through_the_out_phase() -> void:
	# Halfway through the out phase (elapsed = in + hold + out/2) → alpha 0.5.
	assert_float(ST.fade_alpha_at(0.2 + 1.0 + 0.2, 0.2, 1.0, 0.4)).is_equal_approx(0.5, 0.0001)

func test_fade_ends_at_zero_and_stays_there() -> void:
	var total: float = ST.fade_total_seconds(0.2, 1.0, 0.4)
	assert_float(ST.fade_alpha_at(total, 0.2, 1.0, 0.4)).is_equal_approx(0.0, 0.0001)
	# Past the end it never goes negative or revives.
	assert_float(ST.fade_alpha_at(total + 5.0, 0.2, 1.0, 0.4)).is_equal_approx(0.0, 0.0001)

func test_fade_alpha_is_always_within_unit_range() -> void:
	# Sweep the whole timeline (and beyond) — alpha must stay in [0,1] everywhere.
	var total: float = ST.fade_total_seconds(0.2, 1.0, 0.4)
	var steps: int = 200
	for i in range(steps + 1):
		var t: float = (total + 0.5) * float(i) / float(steps)
		var a: float = ST.fade_alpha_at(t, 0.2, 1.0, 0.4)
		assert_bool(a >= 0.0 and a <= 1.0).override_failure_message(
			"alpha %s out of [0,1] at t=%s" % [str(a), str(t)]).is_true()

func test_fade_rises_monotonically_then_falls_monotonically() -> void:
	# Non-decreasing across the in+hold span, then non-increasing across the out span.
	var prev: float = -1.0
	for i in range(0, 13):  # 0.0 .. 1.2 (in+hold = 1.2)
		var a: float = ST.fade_alpha_at(float(i) * 0.1, 0.2, 1.0, 0.4)
		assert_bool(a >= prev - 0.0001).override_failure_message(
			"fade not monotonic up at step %d (%s < %s)" % [i, str(a), str(prev)]).is_true()
		prev = a
	prev = 2.0
	for i in range(12, 17):  # 1.2 .. 1.6 (the out span)
		var a2: float = ST.fade_alpha_at(float(i) * 0.1, 0.2, 1.0, 0.4)
		assert_bool(a2 <= prev + 0.0001).override_failure_message(
			"fade not monotonic down at step %d (%s > %s)" % [i, str(a2), str(prev)]).is_true()
		prev = a2

# ── reveal envelope: 1 (hold) → 0 (out), starts OPAQUE ─────────────────────────

func test_reveal_starts_fully_opaque() -> void:
	# AC-5.8.4: the veil covers the screen at t=0 so a state swap behind it never shows.
	assert_float(ST.reveal_alpha_at(0.0, 0.05, 0.5)).is_equal_approx(1.0, 0.0001)

func test_reveal_holds_opaque_through_the_hold_then_fades_out() -> void:
	assert_float(ST.reveal_alpha_at(0.04, 0.05, 0.5)).is_equal_approx(1.0, 0.0001)
	# Halfway through the out phase (hold + out/2) → 0.5.
	assert_float(ST.reveal_alpha_at(0.05 + 0.25, 0.05, 0.5)).is_equal_approx(0.5, 0.0001)

func test_reveal_ends_clear() -> void:
	var total: float = ST.reveal_total_seconds(0.05, 0.5)
	assert_float(ST.reveal_alpha_at(total, 0.05, 0.5)).is_equal_approx(0.0, 0.0001)
	assert_float(ST.reveal_alpha_at(total + 2.0, 0.05, 0.5)).is_equal_approx(0.0, 0.0001)

func test_reveal_total_excludes_a_fade_in() -> void:
	# A reveal is a fade with no IN phase: total == hold + out.
	assert_float(ST.reveal_total_seconds(0.05, 0.5)).is_equal_approx(0.55, 0.0001)

# ── degenerate / defensive inputs ──────────────────────────────────────────────

func test_zero_in_phase_begins_opaque() -> void:
	# With no fade-in, t=0 is already full (this is exactly the reveal case).
	assert_float(ST.fade_alpha_at(0.0, 0.0, 0.1, 0.3)).is_equal_approx(1.0, 0.0001)

func test_zero_out_phase_snaps_to_clear_after_hold() -> void:
	# No fade-out: once the hold ends the alpha drops straight to 0 (no divide-by-zero).
	# Sample just PAST the in+hold boundary (0.3) to avoid float-equality fragility at the edge.
	assert_float(ST.fade_alpha_at(0.35, 0.1, 0.2, 0.0)).is_equal_approx(0.0, 0.0001)
	# During the hold it is still full.
	assert_float(ST.fade_alpha_at(0.2, 0.1, 0.2, 0.0)).is_equal_approx(1.0, 0.0001)

func test_negative_durations_are_treated_as_zero() -> void:
	# Defensive: a negative duration never produces NaN/inf and total stays finite/0-floored.
	assert_float(ST.fade_total_seconds(-1.0, -2.0, -3.0)).is_equal_approx(0.0, 0.0001)
	var a: float = ST.fade_alpha_at(0.5, -1.0, -2.0, -3.0)
	assert_bool(a >= 0.0 and a <= 1.0).is_true()

func test_negative_elapsed_clamps_to_start() -> void:
	# Before t=0 with a fade-in → transparent; with no fade-in → opaque.
	assert_float(ST.fade_alpha_at(-1.0, 0.2, 1.0, 0.4)).is_equal_approx(0.0, 0.0001)
	assert_float(ST.reveal_alpha_at(-1.0, 0.05, 0.5)).is_equal_approx(1.0, 0.0001)
