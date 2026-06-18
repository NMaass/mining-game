extends GdUnitTestSuite
## Elevator hold-to-move RAMP — pure logic (ElevatorRamp). Holding an elevator button/key moves
## the platform CONTINUOUSLY (row by row), ramping the speed from a slow start to a capped max.
## Key/InputEvents do NOT fire headless, so the continuous-glide behavior is proven here through the
## pure ramp math (the spec's "test input math via pure funcs" rule); mine.gd's _process just feeds
## this delta + the /data constants and steps the returned rows through the same _on_elevator_*().
##
## ACs: AC-5.7.2 (manual platform movement — the ramp decides how many rows a hold requests; the
##      Platform still clamps to the supported, row-by-row reachable span via can_move_up/down).

# Ramp constants used across the tests (mirror the shape of balance.elevator; the real values are
# data, exercised by the integration/data gate — here we pin the MATH for known inputs).
const START := 2.0   # rows/sec at the start of a fresh hold
const ACCEL := 6.0   # rows/sec² ramp
const MAXV := 14.0   # capped top speed (rows/sec)


# ── speed_at: the clamped linear ramp (slow start → cap) ──────────────────────

func test_speed_starts_at_start_value() -> void:
	# At t=0 a fresh hold moves at exactly the slow start speed.
	assert_float(ElevatorRamp.speed_at(0.0, START, ACCEL, MAXV)).is_equal_approx(START, 0.0001)

func test_speed_ramps_up_over_time() -> void:
	# The held speed CLIMBS: speed at 1s > speed at start (2 + 6*1 = 8 rows/sec).
	var v0: float = ElevatorRamp.speed_at(0.0, START, ACCEL, MAXV)
	var v1: float = ElevatorRamp.speed_at(1.0, START, ACCEL, MAXV)
	assert_float(v1).is_equal_approx(8.0, 0.0001)
	assert_float(v1).is_greater(v0)

func test_speed_caps_at_max() -> void:
	# The ramp never exceeds the capped max, no matter how long the hold (cap reached at t=2s here).
	assert_float(ElevatorRamp.speed_at(2.0, START, ACCEL, MAXV)).is_equal_approx(MAXV, 0.0001)
	assert_float(ElevatorRamp.speed_at(100.0, START, ACCEL, MAXV)).is_equal_approx(MAXV, 0.0001)

func test_speed_monotonic_until_cap() -> void:
	# Strictly non-decreasing as the hold gets longer (a ramp UP, never down).
	var prev: float = -1.0
	for i in range(0, 40):
		var v: float = ElevatorRamp.speed_at(float(i) * 0.1, START, ACCEL, MAXV)
		assert_float(v).is_greater_equal(prev)
		prev = v


# ── advance: whole-row stepping over a hold ──────────────────────────────────

func test_tap_moves_exactly_one_row() -> void:
	# A single short frame (a tap) always yields exactly one row — the first-frame guarantee.
	var r := ElevatorRamp.new()
	var rows: int = r.advance(0.016, START, ACCEL, MAXV)  # one ~60fps frame
	assert_int(rows).is_equal(1)

func test_reset_makes_next_hold_start_slow_again() -> void:
	# After a reset (release), a fresh first frame is again a single row (the ramp restarts slow).
	var r := ElevatorRamp.new()
	# Hold for a while so the speed has ramped up.
	for _i in range(60):
		r.advance(0.05, START, ACCEL, MAXV)
	r.reset()
	assert_bool(r.is_held()).is_false()
	var rows: int = r.advance(0.016, START, ACCEL, MAXV)
	assert_int(rows).is_equal(1)

func test_held_longer_moves_more_rows_per_second() -> void:
	# A LATER second of an ongoing hold covers MORE rows than the FIRST second (the ramp is faster).
	# First second: integrate in small frames and count the rows.
	var early := ElevatorRamp.new()
	var early_rows: int = 0
	var t: float = 0.0
	while t < 1.0:
		early_rows += early.advance(0.02, START, ACCEL, MAXV)
		t += 0.02
	# Continue the SAME hold into the next second and count those rows.
	var late_rows: int = 0
	t = 0.0
	while t < 1.0:
		late_rows += early.advance(0.02, START, ACCEL, MAXV)
		t += 0.02
	assert_int(late_rows).override_failure_message(
		"later second (%d rows) should cover more than the first second (%d rows)" % [late_rows, early_rows]
	).is_greater(early_rows)

func test_total_rows_match_integrated_distance() -> void:
	# Over a 1s hold the whole-row count tracks the analytic area under v(t): the ramp goes 2→8 rows/sec
	# linearly (cap not reached), area = (2+8)/2 * 1 = 5 rows. The stepped count equals floor(5) = 5
	# (the first-frame guarantee only adds a row if the integral is BELOW 1 on frame one — it isn't).
	var r := ElevatorRamp.new()
	var rows: int = 0
	var t: float = 0.0
	while t < 1.0:
		rows += r.advance(0.01, START, ACCEL, MAXV)
		t += 0.01
	assert_int(rows).is_equal(5)

func test_frame_rate_independent_total() -> void:
	# The total rows for the SAME 1s hold is the same at a coarse vs a fine frame rate (within the
	# 1-row quantization) — the speed is integrated over elapsed time, not multiplied per frame.
	var coarse := ElevatorRamp.new()
	var coarse_rows: int = 0
	var t: float = 0.0
	while t < 1.0:
		coarse_rows += coarse.advance(0.1, START, ACCEL, MAXV)  # 10 fps
		t += 0.1
	var fine := ElevatorRamp.new()
	var fine_rows: int = 0
	t = 0.0
	while t < 1.0:
		fine_rows += fine.advance(0.004, START, ACCEL, MAXV)  # 250 fps
		t += 0.004
	assert_int(absi(coarse_rows - fine_rows)).override_failure_message(
		"coarse (%d) vs fine (%d) row totals differ by more than the 1-row quantization"
		% [coarse_rows, fine_rows]
	).is_less_equal(1)

func test_zero_delta_yields_no_rows() -> void:
	# A zero/negative delta never advances (no spurious movement).
	var r := ElevatorRamp.new()
	assert_int(r.advance(0.0, START, ACCEL, MAXV)).is_equal(0)
	assert_int(r.advance(-1.0, START, ACCEL, MAXV)).is_equal(0)

func test_speed_caps_the_glide_rate() -> void:
	# With the speed pinned at the cap (a long ongoing hold), a 1s span covers ~MAXV rows — the glide
	# never runs away above the capped rate. Pre-ramp past the cap, then measure a steady second.
	var r := ElevatorRamp.new()
	for _i in range(200):
		r.advance(0.05, START, ACCEL, MAXV)  # well past t_cap (2s)
	var rows: int = 0
	var t: float = 0.0
	while t < 1.0:
		rows += r.advance(0.01, START, ACCEL, MAXV)
		t += 0.01
	# At the cap exactly MAXV rows/sec → 14 rows (allow the 1-row fractional carry boundary).
	assert_int(rows).is_between(int(MAXV) - 1, int(MAXV) + 1)
