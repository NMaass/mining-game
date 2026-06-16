extends GdUnitTestSuite
## U4 — Blast: pure, FUZZY (seeded-rng) blast damage computation.
## ACs: AC-5.2.3 (fuzzy radial damage, injected rng, pre-blast snapshot),
##       AC-5.2.4 (single-source radius grid walk, fixed rng walk order),
##       AC-5.2.5 (crack stage), AC-5.2.6 (block break), AC-5.2.7 (harder rock
##       survives / retains damage), AC-5.4.6 (free charge can break the floor).
const _Blast := preload("res://scripts/core/blast.gd")

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

# ── Helper: build a simple HP snapshot grid ─────────────────────────────────

func _make_grid(width: int, height: int, hp: int) -> Dictionary:
	var snapshot: Dictionary = {}
	for y in range(height):
		for x in range(width):
			snapshot[Vector2i(x, y)] = hp
	return snapshot

# ── Damage falloff (AC-5.2.3) ──────────────────────────────────────────────

func test_center_gets_full_intensity() -> void:
	# AC-5.2.3: damage at center = full intensity
	var snapshot: Dictionary = _make_grid(5, 5, 1000)
	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(2, 2), 2, 80, [1.0, 0.6, 0.25]
	)
	assert_int(int(result["damaged"][Vector2i(2, 2)])).is_equal(80)

func test_falloff_at_distance() -> void:
	# AC-5.2.3: falls off by falloff[dist] at grid-cell distance
	var snapshot: Dictionary = _make_grid(7, 7, 1000)
	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(3, 3), 2, 100, [1.0, 0.6, 0.25]
	)
	# Center (dist 0): 100 * 1.0 = 100
	assert_int(int(result["damaged"][Vector2i(3, 3)])).is_equal(100)
	# Adjacent (dist 1): 100 * 0.6 = 60
	assert_int(int(result["damaged"][Vector2i(4, 3)])).is_equal(60)
	assert_int(int(result["damaged"][Vector2i(3, 4)])).is_equal(60)
	# Diagonal dist 1 (Chebyshev): 100 * 0.6 = 60
	assert_int(int(result["damaged"][Vector2i(4, 4)])).is_equal(60)
	# Dist 2: 100 * 0.25 = 25
	assert_int(int(result["damaged"][Vector2i(5, 3)])).is_equal(25)

func test_zero_damage_beyond_radius() -> void:
	# AC-5.2.3: 0 beyond radius
	var snapshot: Dictionary = _make_grid(9, 9, 1000)
	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(4, 4), 2, 100, [1.0, 0.6, 0.25]
	)
	# Cell at dist 3 should NOT be in damaged.
	assert_bool(result["damaged"].has(Vector2i(7, 4))).is_false()

# ── Pre-blast snapshot / no chain prop (AC-5.2.3) ───────────────────────────

func test_no_chain_propagation() -> void:
	# AC-5.2.3: computed against pre-blast snapshot — cells broken this blast
	# do not let damage "pass through".
	# Set up: center has low HP (will break), cell behind has high HP.
	var snapshot: Dictionary = {}
	snapshot[Vector2i(2, 2)] = 10   # Will break (intensity 100 * 1.0 = 100)
	snapshot[Vector2i(3, 2)] = 50   # Dist 1: gets 100 * 0.6 = 60 > 50 → clears
	snapshot[Vector2i(4, 2)] = 100  # Dist 2: gets 100 * 0.25 = 25

	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(2, 2), 2, 100, [1.0, 0.6, 0.25]
	)

	# Both cells should be independently evaluated against the ORIGINAL HP.
	# Cell (4,2) at dist 2 gets 25 damage regardless of (3,2) breaking.
	assert_int(int(result["damaged"][Vector2i(4, 2)])).is_equal(25)
	assert_int(int(result["new_hp"][Vector2i(4, 2)])).is_equal(75)

# ── Harder rock survives (AC-5.2.7) ────────────────────────────────────────

func test_harder_rock_survives() -> void:
	# AC-5.2.7: harder rock (higher HP) survives a blast that clears softer rock.
	var snapshot: Dictionary = {}
	# Dirt at center: 20 HP
	snapshot[Vector2i(3, 3)] = 20
	# Rock adjacent: 60 HP
	snapshot[Vector2i(4, 3)] = 60
	# Hard rock adjacent: 140 HP
	snapshot[Vector2i(2, 3)] = 140

	# Dynamite-like blast: intensity 80, falloff [1.0, 0.6, 0.25]
	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(3, 3), 2, 80, [1.0, 0.6, 0.25]
	)

	# Center dirt (20 HP, 80 dmg) → cleared
	assert_bool((result["cleared"] as Array).has(Vector2i(3, 3))).is_true()
	# Adjacent rock (60 HP, 48 dmg) → survives with 12 HP
	assert_int(int(result["new_hp"][Vector2i(4, 3)])).is_equal(12)
	assert_bool((result["cleared"] as Array).has(Vector2i(4, 3))).is_false()
	# Adjacent hard rock (140 HP, 48 dmg) → survives with 92 HP
	assert_int(int(result["new_hp"][Vector2i(2, 3)])).is_equal(92)

# ── Block break at 0 HP (AC-5.2.6) ─────────────────────────────────────────

func test_block_clears_at_zero_hp() -> void:
	# AC-5.2.6: block breaks when HP reaches 0
	var snapshot: Dictionary = {}
	snapshot[Vector2i(0, 0)] = 50  # Exactly enough to clear with intensity 50

	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(0, 0), 0, 50, [1.0]
	)
	assert_bool((result["cleared"] as Array).has(Vector2i(0, 0))).is_true()
	assert_int(int(result["new_hp"][Vector2i(0, 0)])).is_equal(0)

func test_surviving_block_retains_damage() -> void:
	# AC-5.2.7: surviving block retains accumulated damage.
	var snapshot: Dictionary = {}
	snapshot[Vector2i(0, 0)] = 100

	# First blast: 30 damage
	var r1: Dictionary = Blast.resolve(snapshot, Vector2i(0, 0), 0, 30, [1.0])
	assert_int(int(r1["new_hp"][Vector2i(0, 0)])).is_equal(70)

	# Second blast on updated HP
	var updated: Dictionary = {Vector2i(0, 0): 70}
	var r2: Dictionary = Blast.resolve(updated, Vector2i(0, 0), 0, 30, [1.0])
	assert_int(int(r2["new_hp"][Vector2i(0, 0)])).is_equal(40)

# ── Crack stage (AC-5.2.5) ─────────────────────────────────────────────────

func test_crack_stage_full_hp() -> void:
	# AC-5.2.5: full HP = stage 0
	assert_int(Blast.crack_stage(100, 100, 3)).is_equal(0)

func test_crack_stage_near_zero() -> void:
	# AC-5.2.5: near-0 HP = max stage - 1 (stages is at exactly 0)
	assert_int(Blast.crack_stage(1, 100, 3)).is_equal(2)

func test_crack_stage_at_zero() -> void:
	# AC-5.2.5: exactly 0 HP = stages (broken)
	assert_int(Blast.crack_stage(0, 100, 3)).is_equal(3)

func test_crack_stage_monotonic() -> void:
	# AC-5.2.5: monotonically increasing as HP decreases
	var prev_stage: int = -1
	for hp in range(100, -1, -1):
		var stage: int = Blast.crack_stage(hp, 100, 3)
		assert_bool(stage >= prev_stage).override_failure_message(
			"Crack stage not monotonic: HP %d → stage %d (prev %d)" % [hp, stage, prev_stage]
		).is_true()
		prev_stage = stage

func test_crack_stage_edge_cases() -> void:
	# Edge: max_hp 0 or stages 0
	assert_int(Blast.crack_stage(50, 0, 3)).is_equal(0)
	assert_int(Blast.crack_stage(50, 100, 0)).is_equal(0)

# ── resolve_explosive convenience (AC-5.4.6) ───────────────────────────────

func test_resolve_explosive_with_data() -> void:
	# AC-5.4.6: blast using explosive data fields
	var snapshot: Dictionary = _make_grid(7, 7, 30)
	var dyn: Dictionary = Registry.explosive(_tables, "dynamite")
	var result: Dictionary = Blast.resolve_explosive(snapshot, Vector2i(3, 3), dyn)

	# Center (dist 0): 80 * 1.0 = 80 > 30 → cleared
	assert_bool((result["cleared"] as Array).has(Vector2i(3, 3))).is_true()
	# Dist 1: 80 * 0.6 = 48 > 30 → cleared
	assert_bool((result["cleared"] as Array).has(Vector2i(4, 3))).is_true()

func test_resolve_explosive_heavy_bomb() -> void:
	# Heavy bomb has radius 3, intensity 170, larger blast.
	var snapshot: Dictionary = _make_grid(9, 9, 50)
	var bomb: Dictionary = Registry.explosive(_tables, "heavy_bomb")
	var result: Dictionary = Blast.resolve_explosive(snapshot, Vector2i(4, 4), bomb)

	# Center: 170 * 1.0 = 170 > 50 → cleared
	assert_bool((result["cleared"] as Array).has(Vector2i(4, 4))).is_true()
	# Dist 3: 170 * 0.25 = 42, 50-42 = 8 → survives
	assert_int(int(result["new_hp"][Vector2i(7, 4)])).is_equal(8)

func test_free_charge_breaks_shallow_floor() -> void:
	# AC-5.4.6: the SHIPPED free unlimited charge SHALL break the floor (slowly) — proven here
	# end to end through Blast with the REAL free-charge data against the shallowest scaled floor
	# (the other resolve-explosive cases use PAID charges; the data gate proves no-stall abstractly,
	# this proves it for the actual free charge). No rng → flat baseline; worst-case fuzz is the
	# data gate's job (AC-5.5.5).
	var free_id: String = Registry.free_charge_id(_tables)
	var free: Dictionary = Registry.explosive(_tables, free_id)
	var floor_hp: int = Registry.scaled_block_hp(_tables, "dirt", 0, 1.0)  # softest shallow floor
	var snapshot: Dictionary = {Vector2i(0, 0): floor_hp}
	var result: Dictionary = Blast.resolve_explosive(snapshot, Vector2i(0, 0), free)
	assert_int(int((result["damaged"] as Dictionary).get(Vector2i(0, 0), 0))).override_failure_message(
		"free charge dealt 0 to the shallow floor — would stall (AC-5.4.6)"
	).is_greater(0)
	assert_bool((result["cleared"] as Array).has(Vector2i(0, 0))).is_true()

# ── Fuzzy blast via injected seeded RNG (AC-5.2.3, AC-5.2.4) ────────────────

func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func test_no_rng_is_flat_no_fuzz() -> void:
	# AC-5.2.4: with rng == null the fuzz factor is a flat 1.0, so the fuzzy resolve
	# reduces EXACTLY to the deterministic baseline (this is what keeps the golden +
	# the rng-less callers green). Same call, with-null vs without-the-arg, is equal.
	var snapshot: Dictionary = _make_grid(7, 7, 1000)
	var base: Dictionary = Blast.resolve(snapshot, Vector2i(3, 3), 2, 100, [1.0, 0.6, 0.25])
	var null_rng: Dictionary = Blast.resolve(snapshot, Vector2i(3, 3), 2, 100, [1.0, 0.6, 0.25], null)
	assert_int(int(null_rng["damaged"][Vector2i(3, 3)])).is_equal(int(base["damaged"][Vector2i(3, 3)]))
	assert_int(int(null_rng["damaged"][Vector2i(4, 3)])).is_equal(int(base["damaged"][Vector2i(4, 3)]))
	# fuzz_pct == 0 with an rng present also disables fuzz (no draw effect on damage).
	var zero_fuzz: Dictionary = Blast.resolve(
		snapshot, Vector2i(3, 3), 2, 100, [1.0, 0.6, 0.25], _seeded_rng(99), 0.0
	)
	assert_int(int(zero_fuzz["damaged"][Vector2i(3, 3)])).is_equal(int(base["damaged"][Vector2i(3, 3)]))

func test_fixed_seed_is_reproducible() -> void:
	# AC-5.2.3 / AC-5.2.4: a fixed seed yields a fixed result run-to-run. Two fresh
	# RNGs with the same seed must produce identical damaged/cleared/new_hp.
	var snapshot: Dictionary = _make_grid(9, 9, 60)
	var a: Dictionary = Blast.resolve(
		snapshot, Vector2i(4, 4), 3, 120, [1.0, 0.75, 0.5, 0.25], _seeded_rng(42), 0.4
	)
	var b: Dictionary = Blast.resolve(
		snapshot, Vector2i(4, 4), 3, 120, [1.0, 0.75, 0.5, 0.25], _seeded_rng(42), 0.4
	)
	# Identical damage on every damaged cell.
	assert_int(a["damaged"].size()).is_equal(b["damaged"].size())
	for cell in a["damaged"]:
		assert_int(int(b["damaged"][cell])).override_failure_message(
			"Fixed seed not reproducible at %s: %d vs %d" % [cell, int(a["damaged"][cell]), int(b["damaged"][cell])]
		).is_equal(int(a["damaged"][cell]))
	# Identical cleared SET (order-independent).
	assert_int((a["cleared"] as Array).size()).is_equal((b["cleared"] as Array).size())
	for cell in a["cleared"]:
		assert_bool((b["cleared"] as Array).has(cell)).is_true()

func test_different_seeds_vary_cleared_set() -> void:
	# AC-5.2.3: the fuzz ACTUALLY fuzzes — different seeds produce a different cleared
	# set. Tune HP near the un-fuzzed damage so the +/- spread tips cells across the
	# break threshold either way. We scan seeds to prove at least two distinct cleared
	# sets exist (a single fixed pair could coincide by chance; the variance is real).
	var snapshot: Dictionary = _make_grid(9, 9, 50)  # near intensity*0.5 .. *1.0 band
	var signatures: Dictionary = {}
	for s in range(0, 24):
		var r: Dictionary = Blast.resolve(
			snapshot, Vector2i(4, 4), 3, 80, [1.0, 0.75, 0.5, 0.25], _seeded_rng(s), 0.4
		)
		var cleared: Array = (r["cleared"] as Array).duplicate()
		cleared.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
			if p.y != q.y:
				return p.y < q.y
			return p.x < q.x
		)
		var sig := PackedStringArray()
		for c in cleared:
			sig.append("%d,%d" % [c.x, c.y])
		signatures["|".join(sig)] = true
	assert_int(signatures.size()).override_failure_message(
		"Fuzz did not vary the cleared set across 24 seeds — fuzz is not actually fuzzing (AC-5.2.3)."
	).is_greater(1)

func test_rng_walk_is_grid_content_independent() -> void:
	# AC-5.2.4: the rng is advanced once per IN-RADIUS cell in a fixed walk order,
	# BEFORE the solid/air branch — so the draw sequence depends only on (center,
	# radius, seed), never on which cells are solid. A cell present in BOTH a dense
	# grid and a sparse grid must receive the same fuzzed damage under the same seed.
	var center := Vector2i(4, 4)
	var probe := Vector2i(6, 4)  # dist 2 from center, in radius
	var dense: Dictionary = _make_grid(9, 9, 1000)        # every cell solid
	var sparse: Dictionary = {center: 1000, probe: 1000}  # only two cells solid
	var rd: Dictionary = Blast.resolve(dense, center, 3, 100, [1.0, 0.75, 0.5, 0.25], _seeded_rng(7), 0.4)
	var rs: Dictionary = Blast.resolve(sparse, center, 3, 100, [1.0, 0.75, 0.5, 0.25], _seeded_rng(7), 0.4)
	assert_int(int(rs["damaged"][probe])).override_failure_message(
		"rng walk is grid-content-dependent: probe got %d (dense) vs %d (sparse) under the same seed" % [int(rd["damaged"][probe]), int(rs["damaged"][probe])]
	).is_equal(int(rd["damaged"][probe]))

func test_fuzz_stays_in_bounds() -> void:
	# AC-5.2.3: the fuzz factor is bounded by fuzz_pct, so per-cell damage stays within
	# [intensity*falloff*(1-pct), intensity*falloff*(1+pct)] (int-floored). Verified at
	# the center cell (falloff 1.0) across many seeds.
	var snapshot: Dictionary = _make_grid(3, 3, 100000)
	var pct := 0.3
	var lo: int = int(100.0 * 1.0 * (1.0 - pct))
	var hi: int = int(100.0 * 1.0 * (1.0 + pct))
	for s in range(0, 40):
		var r: Dictionary = Blast.resolve(
			snapshot, Vector2i(1, 1), 1, 100, [1.0, 0.5], _seeded_rng(s), pct
		)
		var dmg: int = int(r["damaged"][Vector2i(1, 1)])
		assert_bool(dmg >= lo and dmg <= hi).override_failure_message(
			"Center fuzzed damage %d out of bounds [%d, %d] for seed %d" % [dmg, lo, hi, s]
		).is_true()

func test_radius_is_single_source_of_truth() -> void:
	# AC-5.2.4: radius is the ONE reach bound. Even if the falloff array is longer than
	# radius+1 (malformed), no cell beyond `radius` is ever damaged. Walk never exceeds
	# the Chebyshev radius regardless of falloff length.
	var snapshot: Dictionary = _make_grid(11, 11, 1000)
	# radius 1 but an over-long falloff that would "reach" to dist 3 if it leaked.
	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(5, 5), 1, 100, [1.0, 0.5, 0.5, 0.5]
	)
	# dist 2 and beyond must NOT be damaged — radius caps the walk, not the falloff length.
	assert_bool(result["damaged"].has(Vector2i(7, 5))).is_false()  # dist 2
	assert_bool(result["damaged"].has(Vector2i(8, 5))).is_false()  # dist 3
	# dist 1 still damaged.
	assert_bool(result["damaged"].has(Vector2i(6, 5))).is_true()

func test_fuzzy_pre_blast_snapshot_no_chain() -> void:
	# AC-5.2.3: even with fuzz, damage is computed against the PRE-blast snapshot — a
	# cell breaking does not let damage chain to the cell behind it. The far cell's
	# damage is a function of its own distance + its own fuzz draw, not its neighbour.
	var snapshot: Dictionary = {}
	snapshot[Vector2i(2, 2)] = 5     # center, breaks
	snapshot[Vector2i(3, 2)] = 5     # dist 1, breaks
	snapshot[Vector2i(4, 2)] = 1000  # dist 2, must only take its own dist-2 damage
	var r: Dictionary = Blast.resolve(
		snapshot, Vector2i(2, 2), 2, 100, [1.0, 0.6, 0.25], _seeded_rng(3), 0.2
	)
	# Far cell took SOME damage but is computed from the original 1000, not "after" the
	# nearer cells broke — i.e. it survives with high HP, never cleared.
	assert_bool((r["cleared"] as Array).has(Vector2i(4, 2))).is_false()
	assert_int(int(r["new_hp"][Vector2i(4, 2)])).is_greater(900)

# ── Golden blast test ───────────────────────────────────────────────────────

func test_golden_blast_basic() -> void:
	# AC-5.2.4: pins the NO-FUZZ (rng == null, flat 1.0) baseline — the deterministic
	# reference the fuzzy path collapses to when no rng is injected.
	var snapshot: Dictionary = {}
	for y in range(7):
		for x in range(7):
			# HP pattern: center area has varied HP.
			snapshot[Vector2i(x, y)] = 20 + (x * 10) + (y * 5)

	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(3, 3), 2, 80, [1.0, 0.6, 0.25]
	)
	_assert_golden(result, "res://tests/golden/blast_basic.txt", "blast_basic.txt")

func test_golden_blast_fuzzy_seeded() -> void:
	# AC-5.2.3 / AC-5.2.4: with a FIXED-SEED rng the fuzzy blast is identical run-to-run.
	# This golden pins the seeded-fuzz walk so the rng draw order / scaling can't drift.
	var snapshot: Dictionary = {}
	for y in range(7):
		for x in range(7):
			snapshot[Vector2i(x, y)] = 20 + (x * 10) + (y * 5)

	var result: Dictionary = Blast.resolve(
		snapshot, Vector2i(3, 3), 2, 80, [1.0, 0.6, 0.25], _seeded_rng(1337), 0.25
	)
	_assert_golden(result, "res://tests/golden/blast_fuzzy_seeded.txt", "blast_fuzzy_seeded.txt")

## Golden helper: serialize + compare against a COMMITTED pin. A missing golden is a
## hard failure — the test never self-writes it (audit hardening).
func _assert_golden(result: Dictionary, golden_path: String, label: String) -> void:
	var serialized: String = _serialize_blast_result(result)
	assert_bool(FileAccess.file_exists(golden_path)).override_failure_message(
		"Missing golden file: %s — commit the pinned golden; tests never self-write it." % golden_path
	).is_true()
	if not FileAccess.file_exists(golden_path):
		return
	var f := FileAccess.open(golden_path, FileAccess.READ)
	var expected: String = f.get_as_text()
	f.close()
	assert_str(serialized).override_failure_message(
		"Golden %s mismatch — blast has drifted!" % label
	).is_equal(expected)

func _serialize_blast_result(result: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()

	# Sort cleared cells for deterministic output.
	var cleared: Array = result["cleared"]
	cleared.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	lines.append("cleared:")
	for cell in cleared:
		lines.append("  %d,%d" % [cell.x, cell.y])

	# Sort damaged cells.
	var damaged_cells: Array = result["damaged"].keys()
	damaged_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)

	lines.append("damaged:")
	for cell in damaged_cells:
		lines.append("  %d,%d: %d -> %d" % [
			cell.x, cell.y,
			int(result["damaged"][cell]),
			int(result["new_hp"][cell])
		])

	return "\n".join(lines) + "\n"
