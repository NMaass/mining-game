class_name Aim
extends RefCounted
## Pure aim computation. No Node/scene deps; headless-testable.
## Converts drag input to a launch angle and previews the initial throw arc.
##
## v0.4: the predicted arc is an INITIAL-ARC hint up to the FIRST bounce only
## (REMOVED AC-5.3.4 — preview is no longer required to match actual flight).
## The ballistic integration itself lives in ThrowParams.initial_arc (core, shared
## with the live charge's cell conversion); Aim.initial_arc is the thin entry point
## named in the U6 contract so callers go through Aim for the whole aim/preview API.
##
## ACs: AC-5.3.1 (drag adjusts angle + initial-arc preview), AC-5.3.2 (power from
##       data, not input), AC-5.3.6 (tap selects a tray slot), AC-5.3.7 (mouse/touch
##       parity — one shared function), AC-5.3.8 (no lose state — a throw is always
##       possible, the free slot can never be deselected away).

## Minimum drag distance (pixels) before angle changes. Below this → "no change".
const DEAD_ZONE_PX := 10.0

## Full 360° aim (v0.5): the angle is unrestricted. 0 = straight down, -PI/2 = left, +PI/2 = right,
## ±PI = straight up. The player may aim ANY direction including upward (a forgiving lob). The angle
## is kept normalized to (-PI, PI] (atan2's natural range) — there is no directional clamp anymore;
## these bounds exist only so the keyboard glide / set_angle paths can wrap instead of saturate.
const MIN_ANGLE := -PI  # straight up (wraps to MAX_ANGLE)
const MAX_ANGLE := PI    # straight up

## Default angle (straight down).
const DEFAULT_ANGLE := 0.0

## Wrap an angle into (-PI, PI] so the full-circle aim never accumulates past one turn (forgiving:
## no hard stop at the top — passing straight up wraps continuously left↔right).
static func wrap_angle(angle: float) -> float:
	return wrapf(angle, -PI, PI)

## Compute the launch angle from a drag gesture.
## start: where the drag began (screen coords).
## current: where the finger/mouse currently is (screen coords).
## Returns the angle in radians (0 = straight down, negative = left, positive = right).
## If the drag is within the dead zone, returns the provided current_angle unchanged.
## AC-5.3.1: drag adjusts angle.
## AC-5.3.7: same function for mouse and touch.
static func angle_from_drag(start: Vector2, current: Vector2, current_angle: float = DEFAULT_ANGLE) -> float:
	var delta: Vector2 = current - start
	var dist: float = delta.length()

	# Dead zone: too small a drag → no change.
	if dist < DEAD_ZONE_PX:
		return current_angle

	# atan2 with x as the horizontal offset, y pointing down.
	# We want: drag right = positive angle, drag left = negative angle.
	# delta.x > 0 = dragging right, delta.y > 0 = dragging down.
	# atan2 already yields (-PI, PI] — the FULL 360° range (v0.5: aim any direction, incl. up).
	# No clamp: the drag direction is honored exactly, so an upward drag aims upward.
	return atan2(delta.x, delta.y)

## Nudge the launch angle from a held keyboard direction (D1, AC-5.3.1/5.3.2).
## `current_angle`: the angle in radians before this frame (0 = straight down).
## `dir`: held-direction sign — -1 = aim_left, +1 = aim_right, 0 = nothing held (no change).
## `deg_per_sec`: the data-driven keyboard aim speed (balance.feel.keyboard_aim_deg_per_sec).
## `delta`: the frame time in seconds.
## Returns the new angle, advanced by `dir * deg_per_sec * delta` (converted to radians) and WRAPPED
## into (-PI, PI] — the SAME full-360° range the drag path uses (v0.5: aim any direction, incl. up).
## Holding a direction glides continuously around the circle (no hard stop at straight-up). Smooth +
## frame-rate independent (scales with delta) and forgiving (no precision/timing requirement —
## AC-5.3.2): the angle just glides while a key is held. Pure; no Node deps; headless-testable (key
## events don't fire headless, so this is what the unit tests drive — the spec's "test input math" rule).
static func keyboard_angle_step(current_angle: float, dir: int, deg_per_sec: float, delta: float) -> float:
	if dir == 0 or deg_per_sec <= 0.0 or delta <= 0.0:
		return wrap_angle(current_angle)
	var step_rad: float = deg_to_rad(deg_per_sec * delta) * signf(float(dir))
	return wrap_angle(current_angle + step_rad)

## Convert a launch angle to a direction vector (unit vector).
## Angle 0 = straight down = Vector2(0, 1).
## Negative = left, Positive = right.
static func angle_to_direction(angle: float) -> Vector2:
	return Vector2(sin(angle), cos(angle))

## Compute the launch impulse vector for a given angle and base impulse.
## AC-5.3.2: power = charge base impulse (data-driven, not player input).
static func launch_impulse(angle: float, base_impulse: float) -> Vector2:
	return angle_to_direction(angle) * base_impulse

# ── Initial-arc preview (v0.4: pre-first-bounce only) ──────────────────────
# AC-5.3.1: WHILE dragging, display a predicted arc that shows ONLY the initial
# throw up to the first bounce, from a fixed muzzle (never under the finger).
# The integrator (gravity/dt from project settings, the floored cell conversion)
# is owned by ThrowParams so the preview and the live charge agree on cells —
# Aim.initial_arc is the named U6 entry point that delegates to it. Pure; no Node
# deps; headless-testable.

## Predict the initial throw arc for `params` launched from `muzzle` at `angle`,
## up to (and including) the first cell the projectile would enter that
## `is_solid_cell` reports as solid (the first bounce). Returns the sampled path
## (PackedVector2Array) starting at `muzzle`.
##
## `is_solid_cell`: Callable(cell: Vector2i) -> bool. Pass an empty Callable for a
## pure ballistic hint with no surface test (preview before the grid exists).
##
## v0.4 AC-5.3.1: initial throw up to the first bounce only (not multi-bounce);
## post-bounce flight is intentionally unpredicted (REMOVED AC-5.3.4).
static func initial_arc(
	params: ThrowParams,
	angle: float,
	muzzle: Vector2,
	is_solid_cell: Callable = Callable(),
	max_steps: int = 240,
	block_pixel_size: int = 64,
) -> PackedVector2Array:
	if params == null:
		return PackedVector2Array()
	return params.initial_arc(muzzle, angle, is_solid_cell, max_steps, block_pixel_size)
