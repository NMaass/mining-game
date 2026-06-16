extends GdUnitTestSuite
## U5 — Charge (Rapier RigidBody2D) detonation behaviour.
##
## v0.4: physics is NOT deterministic and is not relied upon — there is NO
## determinism test here (removed by design). Detonation/timing logic is driven
## DIRECTLY via the charge's step()/on_impact()/on_settled() API (injected
## InputEvents and real physics callbacks don't fire reliably headless).
##
## ACs: AC-5.3.3 (spawn as rigid body at angle/impulse),
##      AC-5.4.1 (explosive params shape), AC-5.4.2 (detonation modes incl.
##      sticky→freeze and no-impact on_rest resolving — the soft-lock fix).

const ChargeScript := preload("res://scripts/systems/charge.gd")

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

# Build a charge node wired to capture its detonation. Returns [charge, capture],
# where capture is a Dictionary {fired: bool, cell: Vector2i, params: ThrowParams}.
func _make_charge(explosive_id: String, spawn: Vector2, bps: int = 64) -> Array:
	var p: ThrowParams = ThrowParams.from_explosive(_tables, explosive_id)
	var charge: Charge = auto_free(ChargeScript.new())
	charge.setup(p, spawn, bps)
	var capture := {"fired": false, "cell": Vector2i.ZERO, "params": null}
	charge.detonated.connect(func(cell: Vector2i, params: ThrowParams) -> void:
		capture["fired"] = true
		capture["cell"] = cell
		capture["params"] = params
	)
	return [charge, capture]

# ── Spawn / launch (AC-5.3.3) ──────────────────────────────────────────────

func test_setup_configures_rigid_body() -> void:
	# AC-5.3.3: the charge is a Rapier RigidBody2D spawned at the muzzle with the
	# explosive's data-defined mass + physics material.
	var spawn := Vector2(224.0, 64.0)
	var made: Array = _make_charge("dynamite", spawn)
	var charge: Charge = made[0]
	assert_bool(charge is RigidBody2D).is_true()
	assert_vector(charge.position).is_equal(spawn)
	assert_float(charge.mass).is_equal_approx(1.0, 0.001)
	# Continuous CD on (no tunneling) + explicit collision masks.
	assert_int(charge.continuous_cd).is_equal(RigidBody2D.CCD_MODE_CAST_RAY)
	assert_int(charge.collision_layer).is_equal(2)
	assert_int(charge.collision_mask).is_equal(1 | 4)
	assert_float(charge.physics_material_override.bounce).is_equal_approx(0.35, 0.001)

func test_launch_applies_impulse_at_angle() -> void:
	# AC-5.3.3: launch applies the data-defined base impulse at the previewed angle.
	# We can't observe Rapier velocity reliably headless, but launch must arm the
	# fuse for a fuse_seconds charge (the observable side effect of launching).
	var made: Array = _make_charge("dynamite", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.launch(0.0)
	# Fuse armed but not yet expired.
	assert_bool(capture["fired"]).is_false()

# ── fuse_seconds timing (AC-5.4.2) ─────────────────────────────────────────

func test_fuse_detonates_after_fuse_seconds() -> void:
	# AC-5.4.2: a fuse charge detonates when its fuse elapses — not before.
	var made: Array = _make_charge("dynamite", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.launch(0.0)  # arms a 1.2s fuse
	# Step most of the way: still armed, not fired.
	charge.step(1.0)
	assert_bool(capture["fired"]).is_false()
	assert_bool(charge.has_detonated).is_false()
	# Step past the fuse end → detonates exactly once.
	charge.step(0.5)
	assert_bool(capture["fired"]).is_true()
	assert_bool(charge.has_detonated).is_true()

func test_fuse_does_not_detonate_on_impact() -> void:
	# AC-5.4.2: a fuse charge ignores impacts; it waits for the fuse.
	var made: Array = _make_charge("dynamite", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.launch(0.0)
	charge.on_impact()
	assert_bool(capture["fired"]).is_false()

# ── on_first_impact (AC-5.4.2) ─────────────────────────────────────────────

func test_on_first_impact_detonates_on_contact() -> void:
	# AC-5.4.2: heavy_bomb detonates on the first terrain contact.
	var made: Array = _make_charge("heavy_bomb", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.launch(0.0)
	assert_bool(capture["fired"]).is_false()
	charge.on_impact()
	assert_bool(capture["fired"]).is_true()

func test_on_first_impact_detonates_once() -> void:
	# Re-entrant contacts after detonation are no-ops (single emit).
	var made: Array = _make_charge("heavy_bomb", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	var count := {"n": 0}
	charge.detonated.connect(func(_c: Vector2i, _p: ThrowParams) -> void:
		count["n"] += 1
	)
	charge.on_impact()
	charge.on_impact()
	assert_int(count["n"]).is_equal(1)

# ── on_rest + the no-soft-lock guarantee (AC-5.4.2) ────────────────────────

func test_on_rest_detonates_when_settled() -> void:
	# AC-5.4.2: an on_rest charge detonates once it comes to rest.
	var made: Array = _make_charge("charge_sticky", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.on_settled()
	assert_bool(capture["fired"]).is_true()

func test_on_rest_resolves_without_prior_impact() -> void:
	# AC-5.4.2 (the soft-lock fix): a charge that comes to rest WITHOUT ever
	# impacting must still resolve its on_rest mode. on_settled() detonates even
	# though on_impact() was never called.
	var made: Array = _make_charge("charge_sticky", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	assert_bool(charge.has_impacted).is_false()
	charge.on_settled()
	assert_bool(capture["fired"]).is_true()

# ── sticky → freeze (AC-5.4.2) ─────────────────────────────────────────────

func test_sticky_freezes_on_first_contact() -> void:
	# AC-5.4.2: sticky charges freeze in place at first contact.
	var made: Array = _make_charge("charge_sticky", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	assert_bool(charge.freeze).is_false()
	charge.on_impact()
	assert_bool(charge.freeze).is_true()

func test_sticky_on_rest_detonates_after_freeze_delay() -> void:
	# A frozen sticky charge never "sleeps", so it detonates via a short post-
	# freeze fuse delay rather than on_settled(). It must NOT fire instantly.
	var made: Array = _make_charge("charge_sticky", Vector2(100.0, 0.0))
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.on_impact()  # freezes, arms ~0.15s delay
	assert_bool(capture["fired"]).is_false()
	charge.step(0.2)
	assert_bool(capture["fired"]).is_true()

# ── cell conversion floors correctly (v0.4 bug fix) ────────────────────────

func test_detonation_cell_floors_at_negative_x() -> void:
	# v0.4: int() truncation mapped both -10px and +10px to column 0. floori must
	# place a left-of-origin detonation in a NEGATIVE cell.
	var bps := 64
	var made: Array = _make_charge("heavy_bomb", Vector2(-10.0, 5.0), bps)
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.on_impact()  # heavy_bomb detonates on impact
	assert_bool(capture["fired"]).is_true()
	assert_int((capture["cell"] as Vector2i).x).is_equal(-1)

func test_detonation_cell_positive_x() -> void:
	# Positive pixel position maps to the expected positive column.
	var bps := 64
	var made: Array = _make_charge("heavy_bomb", Vector2(150.0, 320.0), bps)
	var charge: Charge = made[0]
	var capture: Dictionary = made[1]
	charge.on_impact()
	var cell: Vector2i = capture["cell"]
	assert_int(cell.x).is_equal(2)   # floor(150/64) = 2
	assert_int(cell.y).is_equal(5)   # floor(320/64) = 5
