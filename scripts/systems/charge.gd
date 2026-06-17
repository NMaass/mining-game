class_name Charge
extends RigidBody2D
## Charge — the thrown explosive rigid body.
## Spawns as a Rapier RigidBody2D, applies launch impulse, detonates per
## the explosive's detonation_mode. Emits `detonated` when it goes off.
##
## v0.4: physics is NOT deterministic and is not relied upon (no physics golden).
## The aim preview lives in ThrowParams.initial_arc (core), not here.
## Detonation/timing logic is delegated to step()/on_impact()/on_settled() so it
## can be driven directly in headless tests without real physics callbacks.
##
## ACs: AC-5.3.3 (rigid body), AC-5.4.1 (explosive params), AC-5.4.2 (detonation
##      modes incl. sticky→freeze and no-impact on_rest resolving — no soft-lock).

signal detonated(center_cell: Vector2i, params: ThrowParams)

var _params: ThrowParams
var _fuse_timer: float = -1.0
var _has_impacted: bool = false
var _detonated: bool = false
var _block_pixel_size: int = 64

## The visual Sprite2D child (charge.tscn). Spin + squash-stretch are applied to THIS node ONLY,
## never the CollisionShape2D, so the circle collider stays intact (charge/physics tests unchanged).
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D")
## Tumble speed in radians per (px/sec) of travel — a thrown charge visibly spins along its arc.
const SPIN_PER_SPEED := 0.018
## Squash-stretch gain: at this speed (px/s) the sprite reaches the full stretch_max elongation.
const STRETCH_REF_SPEED := 600.0
const STRETCH_MAX := 0.35

## Set up the charge with throw parameters.
func setup(params: ThrowParams, spawn_pos: Vector2, block_pixel_size: int = 64) -> void:
	_params = params
	_block_pixel_size = block_pixel_size
	position = spawn_pos
	mass = params.mass

	# Physics material.
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = params.bounce
	physics_material_override.friction = params.friction

	# Continuous collision detection to prevent tunneling.
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	# Collision: charge layer = 2, collides with terrain (layer 1) + platform (layer 3).
	collision_layer = 2
	collision_mask = 1 | 4  # terrain=1, platform=4

	# Connect body_entered for impact detection.
	body_entered.connect(_on_body_entered)

## Launch the charge at the given angle. Starts fuse timer for fuse_seconds mode.
func launch(angle: float) -> void:
	var impulse: Vector2 = _params.impulse_at_angle(angle)
	apply_central_impulse(impulse)
	# Start fuse timer on launch (not setup) so the countdown begins when thrown.
	if _params.detonation_mode == "fuse_seconds":
		_fuse_timer = _params.fuse_seconds

func _physics_process(delta: float) -> void:
	if _detonated:
		return
	# Cosmetic-only flight feel: the thrown charge tumbles + squash-stretches by its speed. This
	# scales/rotates the SPRITE CHILD ONLY — never the CollisionShape2D — so the circle collider is
	# untouched and the physics/charge tests stay green (the gate_risk for this cluster).
	_update_flight_visual(delta)
	# Advance fuse/timer logic.
	step(delta)
	# on_rest: detonate when the body has come to rest. v0.4 fix: this resolves
	# even with NO prior impact (a charge that drifts to a stop must not soft-lock).
	if _params and _params.detonation_mode == "on_rest" and sleeping:
		on_settled()

## Tumble + squash-stretch the visual Sprite2D child by the charge's speed (cosmetic only).
## The sprite spins proportional to speed (a thrown charge visibly rolls) and elongates along its
## travel as it gets faster, easing back to round as it slows. Touches ONLY the Sprite2D child —
## the CollisionShape2D circle is never scaled/rotated, so the collider is exactly the authored
## radius and the charge/physics tests are unaffected.
func _update_flight_visual(delta: float) -> void:
	if _sprite == null:
		return
	var vel: Vector2 = linear_velocity
	var speed: float = vel.length()
	# Spin: accumulate rotation by speed so the tumble reads at a glance (faster → faster spin).
	_sprite.rotation += speed * SPIN_PER_SPEED * delta
	# Squash-stretch: stretch along the sprite's local X (its current facing), squash on Y, by speed.
	var s: float = clampf(speed / STRETCH_REF_SPEED, 0.0, 1.0) * STRETCH_MAX
	_sprite.scale = Vector2(1.0 + s, 1.0 - s * 0.6)


func _on_body_entered(_body: Node) -> void:
	on_impact()

# ── Testable detonation logic (driven by physics OR directly by tests) ──────

## Advance timers by `delta`. Detonates if a running fuse reaches zero.
## Pure of physics callbacks; callable headless to test fuse/sticky-delay timing.
func step(delta: float) -> void:
	if _detonated:
		return
	if _fuse_timer > 0.0:
		_fuse_timer -= delta
		if _fuse_timer <= 0.0:
			_detonate()

## Handle a terrain/platform contact (sticky freeze, on_first_impact, sticky
## on_rest delay). Idempotent-ish: re-entrant contacts after detonation are no-ops.
func on_impact() -> void:
	if _detonated:
		return
	_has_impacted = true

	# Sticky: freeze in place on first contact.
	if _params.sticky and not freeze:
		freeze = true
		# A sticky on_rest charge is now at rest by definition: detonate (after a
		# short delay for visual feedback). It will never "sleep" once frozen, so
		# we cannot rely on on_settled() here.
		if _params.detonation_mode == "on_rest":
			_fuse_timer = 0.15

	# on_first_impact: detonate immediately on first terrain contact.
	if _params.detonation_mode == "on_first_impact":
		_detonate()

## Handle the body coming to rest (on_rest mode). Resolves regardless of whether
## an impact was ever registered — this is the no-soft-lock guarantee (AC-5.4.2).
func on_settled() -> void:
	if _detonated:
		return
	if _params and _params.detonation_mode == "on_rest":
		_detonate()

func _detonate() -> void:
	if _detonated:
		return
	_detonated = true

	# Convert pixel position to cell coordinates. floori (not int() truncation)
	# so negative-x positions map to the correct (negative) cell, not column 0.
	var center_cell: Vector2i = ThrowParams.cell_at(position, _block_pixel_size)
	detonated.emit(center_cell, _params)
	# Queue free after detonation (the mine scene handles blast logic).
	queue_free()

## Whether the charge has already detonated.
var has_detonated: bool:
	get:
		return _detonated

## Whether the charge has registered at least one impact (for tests/inspection).
var has_impacted: bool:
	get:
		return _has_impacted
