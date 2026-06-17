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

## Angle clamp range (radians). 0 = straight down, -PI/2 = left, PI/2 = right.
## Aiming is allowed slightly past horizontal, including shallow upward angles.
const MIN_ANGLE := -PI / 2.0 - 0.35  # ~-1.92 rad (shallow upward left)
const MAX_ANGLE := PI / 2.0 + 0.35   # ~1.92 rad (shallow upward right)

## Default angle (straight down).
const DEFAULT_ANGLE := 0.0

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
	var angle: float = atan2(delta.x, delta.y)

	# Clamp to valid range.
	return clampf(angle, MIN_ANGLE, MAX_ANGLE)

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
