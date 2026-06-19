class_name AimController
extends Node
## Thin aim controller: turns drag input into a launch angle and an initial-arc
## preview, delegating all math to the pure `Aim` core. Mouse and single-touch run
## through ONE shared code path (`begin_drag` / `update_drag` / `end_drag`) so input
## parity is structural, not duplicated (AC-5.3.7). Holds no balance literals.
##
## Input events don't fire in headless tests, so `_unhandled_input` only unpacks the
## event and calls the shared methods below — the methods are what the unit tests
## drive directly (the spec's "test input math via pure funcs" rule).
##
## ACs: AC-5.3.1 (drag adjusts angle + initial-arc preview), AC-5.3.2 (power from
##       data), AC-5.3.7 (mouse/touch parity — shared path), AC-5.3.8 (no lose state).

## Emitted whenever the aim angle changes (so the view can redraw the preview).
signal angle_changed(angle: float)

## Current launch angle (radians; 0 = straight down). Starts at the data default.
var _angle: float = Aim.DEFAULT_ANGLE

## Where the active drag began (screen coords); valid only while `_is_dragging`.
var _drag_start: Vector2 = Vector2.ZERO

## Whether a drag is currently in progress.
var _is_dragging: bool = false

## Whether the controller responds to input. False while a charge is mid-flight or
## an overlay is open; the view sets this. Aim never enters a lose state (AC-5.3.8).
var _enabled: bool = true

# ── Public state ───────────────────────────────────────────────────────────

## The current launch angle in radians.
var angle: float:
	get:
		return _angle

## Whether a drag is currently active.
var is_dragging: bool:
	get:
		return _is_dragging

## Enable/disable input handling without resetting the aim angle.
func set_enabled(value: bool) -> void:
	_enabled = value
	if not value:
		_is_dragging = false

# ── Shared drag code path (mouse == single-touch) ──────────────────────────
# Both InputEventMouseButton/Motion and InputEventScreenTouch/Drag funnel here, so
# there is exactly one implementation of the gesture (AC-5.3.7).

## Begin a drag at `pos` (screen coords).
func begin_drag(pos: Vector2) -> void:
	if not _enabled:
		return
	_drag_start = pos
	_is_dragging = true

## Update the angle from the in-progress drag. Returns the (possibly unchanged)
## angle. Below the dead zone the angle is left as-is (AC-5.3.1, via Aim).
func update_drag(pos: Vector2) -> float:
	if not _enabled or not _is_dragging:
		return _angle
	var new_angle: float = Aim.angle_from_drag(_drag_start, pos, _angle)
	if new_angle != _angle:
		_angle = new_angle
		angle_changed.emit(_angle)
	return _angle

## End the active drag (the committed angle persists until the next drag/throw).
func end_drag() -> void:
	_is_dragging = false

## Reset the aim to the default angle (e.g. on a new dig).
func reset_angle() -> void:
	_angle = Aim.DEFAULT_ANGLE
	angle_changed.emit(_angle)

## Set the angle directly (clamped to the valid aim range), emitting `angle_changed` if it moved.
## Used by the keyboard-aim path (D1): held arrow keys glide the angle via Aim.keyboard_angle_step,
## then push it here so the preview + platform look-ahead update through the SAME signal the drag
## path uses (one shared aim API — AC-5.3.1/5.3.7). Ignored while input is disabled (charge in
## flight / overlay open), matching the drag path's `_enabled` gate so neither bypasses it.
func set_angle(value: float) -> void:
	if not _enabled:
		return
	var clamped: float = Aim.clamp_angle(value)
	if clamped != _angle:
		_angle = clamped
		angle_changed.emit(_angle)

# ── Initial-arc preview (AC-5.3.1) ─────────────────────────────────────────

## Build the initial-arc preview for `params` from the fixed `muzzle` at the
## current angle, stopping at the first bounce per `is_solid_cell`. Pure delegation
## to Aim.initial_arc (which delegates to the shared ThrowParams integrator).
func preview_path(
	params: ThrowParams,
	muzzle: Vector2,
	is_solid_cell: Callable = Callable(),
	max_steps: int = 240,
	block_pixel_size: int = 64,
) -> PackedVector2Array:
	return Aim.initial_arc(params, _angle, muzzle, is_solid_cell, max_steps, block_pixel_size)

# ── Input plumbing (thin; not exercised headless) ──────────────────────────
# Unpacks the raw event onto the shared methods above. Mouse and touch both land on
# the same begin/update/end path — no per-device branching beyond extracting `.position`.

func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				begin_drag(mb.position)
			else:
				end_drag()
	elif event is InputEventMouseMotion and _is_dragging:
		update_drag((event as InputEventMouseMotion).position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			begin_drag(st.position)
		else:
			end_drag()
	elif event is InputEventScreenDrag and _is_dragging:
		update_drag((event as InputEventScreenDrag).position)
