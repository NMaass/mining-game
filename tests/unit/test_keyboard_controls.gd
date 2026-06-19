extends GdUnitTestSuite
## D1 — Keyboard controls (input-handling half). Key/InputEvents do NOT fire headless, so the
## wiring in mine.gd (_input / _process / _apply_keyboard_aim) is driven through these PURE helpers,
## which are what the unit tests exercise directly (the spec's "test input math via pure funcs" rule).
##
## Covered:
##  - Mine.may_fire — the keyboard fire guard (mirrors the throw-button enabled rule).
##  - Mine.may_move_elevator — the keyboard elevator guard (mirrors the elevator-arrow enabled rule).
##  - AimController.set_angle — the shared angle API the keyboard-aim path pushes into.
##
## ACs: AC-5.3.3 (throw commits the active charge — fire routes through the SAME throw path),
##       AC-5.3.7 (mouse/touch/keyboard parity — keyboard is a third path through one shared logic),
##       AC-5.3.8 (no lose state — a throw is always possible when nothing blocks it),
##       AC-5.7.2 (platform lowering — elevator keys mirror the on-screen arrows + can_move guards),
##       AC-5.3.1 (drag/key adjusts the active charge angle through the shared AimController API).

# ── Mine.may_fire (keyboard fire guard) ──────────────────────────────────────

func test_may_fire_when_clear() -> void:
	# AC-5.3.3/5.3.8: nothing blocking → a throw is allowed (the free charge is always throwable).
	assert_bool(Mine.may_fire(false, false, true, false)).is_true()

func test_may_not_fire_when_paused() -> void:
	# A modal/overlay pauses the tree — the keyboard must NOT fire while paused, even if otherwise clear.
	assert_bool(Mine.may_fire(false, false, true, true)).is_false()

func test_may_not_fire_when_dig_ended() -> void:
	# AC-5.3.3: no throw once the dig has ended (the relic/prestige boundary).
	assert_bool(Mine.may_fire(true, false, true, false)).is_false()

func test_may_not_fire_while_charge_in_flight() -> void:
	# Only one charge at a time — no fire while one is already in flight.
	assert_bool(Mine.may_fire(false, true, true, false)).is_false()

func test_may_not_fire_during_cooldown() -> void:
	# can_throw=false models the throw cooldown still running — no fire until it expires.
	assert_bool(Mine.may_fire(false, false, false, false)).is_false()

# ── Mine.may_move_elevator (keyboard elevator guard, AC-5.7.2) ────────────────

func test_may_move_up_when_platform_allows() -> void:
	# dir -1 = up; allowed only when the platform reports can_move_up.
	assert_bool(Mine.may_move_elevator(-1, true, false, false)).is_true()

func test_may_not_move_up_at_top() -> void:
	# At the top of the mine can_move_up is false → the up key is inert (matches the greyed arrow).
	assert_bool(Mine.may_move_elevator(-1, false, true, false)).is_false()

func test_may_move_down_when_platform_allows() -> void:
	# dir +1 = down; allowed only when the platform reports can_move_down.
	assert_bool(Mine.may_move_elevator(1, false, true, false)).is_true()

func test_may_not_move_down_at_support_limit() -> void:
	# At the deepest supported row can_move_down is false → the down key is inert.
	assert_bool(Mine.may_move_elevator(1, true, false, false)).is_false()

func test_may_not_move_elevator_when_paused() -> void:
	# A modal pauses the tree — no elevator move while paused, even when the platform could otherwise.
	assert_bool(Mine.may_move_elevator(-1, true, true, true)).is_false()
	assert_bool(Mine.may_move_elevator(1, true, true, true)).is_false()

func test_zero_direction_never_moves() -> void:
	# A 0 direction (no key) never moves either way, regardless of platform state.
	assert_bool(Mine.may_move_elevator(0, true, true, false)).is_false()

# ── Mine.slot_index_for_keycode (number-key → hotbar slot index, AC-5.3.6) ────
# Pure mapping so the number-key→selection path is testable without firing key events (which don't
# fire headless). 1..9 map to 0..8; everything else (0, non-digit, out-of-range) maps to -1.

func test_number_key_maps_to_zero_based_slot_index() -> void:
	# AC-5.3.6: pressing "1" selects slot 0 (the free charge), "2" → slot 1, … "9" → slot 8.
	assert_int(Mine.slot_index_for_keycode(KEY_1)).is_equal(0)
	assert_int(Mine.slot_index_for_keycode(KEY_2)).is_equal(1)
	assert_int(Mine.slot_index_for_keycode(KEY_9)).is_equal(8)

func test_non_digit_keycode_maps_to_minus_one() -> void:
	# A non-digit (or KEY_0, which has no slot) maps to -1 → no selection attempt.
	assert_int(Mine.slot_index_for_keycode(KEY_0)).is_equal(-1)
	assert_int(Mine.slot_index_for_keycode(KEY_A)).is_equal(-1)
	assert_int(Mine.slot_index_for_keycode(KEY_SPACE)).is_equal(-1)

# ── AimController.set_angle (shared angle API the keyboard path pushes into) ──

func test_set_angle_updates_and_signals() -> void:
	# AC-5.3.1/5.3.7: the keyboard-aim path pushes a new angle through set_angle, which mutates the
	# SAME angle the drag path does and emits angle_changed so the preview/look-ahead update.
	var ac: AimController = auto_free(AimController.new())
	var seen: Array = []
	ac.angle_changed.connect(func(a: float) -> void: seen.append(a))
	ac.set_angle(0.5)
	assert_float(ac.angle).is_equal_approx(0.5, 0.0001)
	assert_int(seen.size()).is_equal(1)

func test_set_angle_clamps_to_useful_arc() -> void:
	var ac: AimController = auto_free(AimController.new())
	ac.set_angle(Aim.MAX_ANGLE + 0.5)
	assert_float(ac.angle).is_equal_approx(Aim.MAX_ANGLE, 0.0001)
	ac.set_angle(Aim.MIN_ANGLE - 0.5)
	assert_float(ac.angle).is_equal_approx(Aim.MIN_ANGLE, 0.0001)

func test_set_angle_blocks_straight_up() -> void:
	var ac: AimController = auto_free(AimController.new())
	ac.set_angle(PI)  # straight up
	assert_float(ac.angle).is_equal_approx(Aim.MAX_ANGLE, 0.0001)

func test_set_angle_ignored_when_disabled() -> void:
	# AC-5.3.8 parity gate: while input is disabled (charge in flight / overlay open) the keyboard
	# path can't move the aim — same _enabled gate the drag path obeys, so neither bypasses it.
	var ac: AimController = auto_free(AimController.new())
	ac.set_enabled(false)
	ac.set_angle(0.7)
	assert_float(ac.angle).is_equal_approx(Aim.DEFAULT_ANGLE, 0.0001)
