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

## Motion/airtime gate (the "sticky bomb explodes instantly" fix — path (a)). A freshly-LAUNCHED
## RigidBody2D reports sleeping==true for the first physics frame(s) before Rapier integrates the
## launch impulse, so linear_velocity is ~0 and the body reads "at rest" on frame 0. Without a gate,
## tick(delta, is_sleeping=true) sees `on_rest && sleeping && !freeze` and detonates the charge in
## mid-air before it has ever moved or stuck. An on_rest charge may therefore only resolve via the
## sleeping/settled path AFTER it has actually been in motion: it was launched AND has either been
## airborne past MIN_AIRTIME_SEC or travelled past the muzzle by MIN_TRAVEL_PX. The no-soft-lock
## guarantee survives — a charge that genuinely drifts to rest still resolves, it just has to clear
## the (tiny) airtime gate first, which any airborne charge does within a few frames.
var _launched: bool = false
var _spawn_pos: Vector2 = Vector2.ZERO
var _airborne_time: float = 0.0
## Min motion before an on_rest charge may resolve via the sleeping path. Data-driven
## (data/balance.json: charge_min_airtime_seconds / charge_min_travel_px); these are the code-side
## FLOORS used when no /data value is injected (e.g. the headless charge tests). The data gate keeps
## the airtime under the smallest sticky fuse so it never delays a real stick.
const MIN_AIRTIME_SEC := 0.12      # ~7 physics frames at 60 Hz
const MIN_TRAVEL_PX := 8.0         # must have left the muzzle by at least this far
var _min_airtime_sec: float = MIN_AIRTIME_SEC
var _min_travel_px: float = MIN_TRAVEL_PX

## The visual Sprite2D child (charge.tscn). Spin + squash-stretch are applied to THIS node ONLY,
## never the CollisionShape2D, so the circle collider stays intact (charge/physics tests unchanged).
@onready var _sprite: Sprite2D = get_node_or_null("Sprite2D")
## Tumble speed in radians per (px/sec) of travel — a thrown charge visibly spins along its arc.
const SPIN_PER_SPEED := 0.018
## Squash-stretch gain: at this speed (px/s) the sprite reaches the full stretch_max elongation.
const STRETCH_REF_SPEED := 600.0
const STRETCH_MAX := 0.35
## Floor for a sticky charge's post-stick fuse: even a 0-fuse sticky reads as a brief stick, never
## an instant pop. A sticky charge with a longer authored fuse_seconds uses that instead.
const STICKY_MIN_DELAY := 0.15

## Set up the charge with throw parameters.
## `min_airtime_sec` / `min_travel_px` are the motion gate (data-driven from balance.json); a
## value <= 0 keeps the code-side floor (the headless tests rely on the default). The spawn position
## is recorded so the gate can measure travel away from the muzzle.
func setup(params: ThrowParams, spawn_pos: Vector2, block_pixel_size: int = 64,
		min_airtime_sec: float = -1.0, min_travel_px: float = -1.0) -> void:
	_params = params
	_block_pixel_size = block_pixel_size
	position = spawn_pos
	_spawn_pos = spawn_pos
	mass = params.mass
	if min_airtime_sec > 0.0:
		_min_airtime_sec = min_airtime_sec
	if min_travel_px > 0.0:
		_min_travel_px = min_travel_px

	# Physics material.
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.bounce = params.bounce
	physics_material_override.friction = params.friction

	# Continuous collision detection to prevent tunneling.
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY

	# Collision: charge layer = 2, collides with terrain (layer 1) only.
	# The platform and player are visual-only anchors; charges pass through them.
	collision_layer = 2
	collision_mask = 1  # terrain=1

	# Connect body_entered for impact detection.
	body_entered.connect(_on_body_entered)

## Launch the charge at the given angle. Starts fuse timer for fuse_seconds mode.
func launch(angle: float) -> void:
	var impulse: Vector2 = _params.impulse_at_angle(angle)
	apply_central_impulse(impulse)
	# Launch is the ONLY thing that enables the settled/sleeping resolution path (the motion gate):
	# until a charge has been launched and then actually moved, the frame-0 "fresh body reports
	# sleeping before the impulse integrates" state must NOT count as "at rest".
	_launched = true
	_airborne_time = 0.0
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
	tick(delta, sleeping)

## Advance one frame of detonation logic: run the fuse, and (for on_rest) resolve when the body
## has come to rest. Split out of _physics_process with `is_sleeping` injected so the REAL per-frame
## path — including the sticky-freeze interaction — is headless-testable (physics callbacks don't
## fire headless). This is the path the instant-sticky-detonation bug lived in.
func tick(delta: float, is_sleeping: bool) -> void:
	if _detonated:
		return
	step(delta)
	if _launched:
		_airborne_time += delta
	# on_rest detonates when the body comes to rest (resolves even with NO prior impact, so a charge
	# that drifts to a stop can't soft-lock — AC-5.4.2). But a STUCK sticky charge is "at rest" only
	# because it froze; a frozen body reports sleeping=true, which would otherwise detonate it
	# instantly on contact. Its stick-fuse (armed in on_impact) owns its detonation, so skip the
	# sleeping path while frozen. AND a freshly-launched body reports sleeping=true on frame 0 before
	# the impulse integrates — _has_been_in_motion() gates that out so the charge never resolves as
	# "settled" before it has actually moved (the "explodes instantly" fix, path a).
	if _params and _params.detonation_mode == "on_rest" and is_sleeping and not freeze:
		if _has_been_in_motion():
			on_settled()

## True once the charge has actually moved after launch: it was launched AND (enough airtime has
## elapsed OR it has travelled past the muzzle by _min_travel_px). Blocks the frame-0 "fresh body
## reports sleeping before the impulse integrates" instant detonation while preserving the
## no-soft-lock guarantee (any genuinely airborne charge clears the small airtime gate within a few
## frames). An UNLAUNCHED charge (only setup) never counts as in-motion.
func _has_been_in_motion() -> bool:
	if not _launched:
		return false
	if _airborne_time >= _min_airtime_sec:
		return true
	return position.distance_to(_spawn_pos) >= _min_travel_px

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


func _on_body_entered(body: Node) -> void:
	on_impact(body)

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

## Handle a terrain contact (sticky freeze, on_first_impact, sticky on_rest delay).
## Idempotent-ish: re-entrant contacts after detonation are no-ops.
## The platform and player are NOT on the charge's collision mask, so the charge
## passes through them cleanly — no grace-window hack is needed.
func on_impact(body: Node = null) -> void:
	if _detonated:
		return
	_has_impacted = true

	# Sticky: freeze in place on first contact.
	if _params.sticky and not freeze:
		freeze = true
		# A frozen sticky charge can never resolve via on_settled() (a frozen body is treated as
		# "sleeping", which the tick() guard now ignores), so its detonation is owned by a stick-fuse
		# armed HERE: the authored fuse_seconds, floored to STICKY_MIN_DELAY so it sticks for a beat
		# instead of popping instantly. THIS is the fix for "the sticky bomb explodes instantly".
		if _params.detonation_mode == "on_rest":
			_fuse_timer = maxf(_params.fuse_seconds, STICKY_MIN_DELAY)

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
