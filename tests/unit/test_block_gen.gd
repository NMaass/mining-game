extends GdUnitTestSuite
## U2 — BlockGen (v0.4): coherent, deterministic procedural generation + relic.
##
## v0.4 rework: generation uses FastNoiseLite (coherent -> ore veins) as a pure
## function of (mine_seed, cell). The old custom-hash salt-and-pepper version was
## replaced; the golden is re-pinned to the FastNoiseLite output.
##
## ACs: AC-5.1.3 (depth-banded), AC-5.1.4 (pure fn of mine_seed+cell),
##      AC-5.1.7 (coherent veins, NOT salt-and-pepper), AC-5.6.1 (relic placement).

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

# ── Determinism (AC-5.1.4) ──────────────────────────────────────────────────

func test_determinism_repeat_calls() -> void:
	# AC-5.1.4: block_at returns the same id across 1000 repeat calls (no mutable state).
	var seed_val: int = Registry.run_seed(_tables)
	var first: String = BlockGen.block_at(_tables, seed_val, 3, 10)
	for i in range(1000):
		assert_str(BlockGen.block_at(_tables, seed_val, 3, 10)).is_equal(first)

func test_determinism_fresh_region_matches_cell_calls() -> void:
	# AC-5.1.4: a fresh FastNoiseLite field (generate_region) must agree, cell-for-cell,
	# with independent per-cell block_at calls — proves no instance-to-instance drift.
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var region: Array = BlockGen.generate_region(_tables, seed_val, 0, 0, width, 30)
	for y in range(30):
		for x in range(width):
			assert_str(BlockGen.block_at(_tables, seed_val, x, y)).override_failure_message(
				"region vs block_at mismatch at (%d,%d)" % [x, y]
			).is_equal(region[y][x] as String)

func test_determinism_two_regions_identical() -> void:
	# AC-5.1.4: two independently generated regions (fresh noise each) are identical.
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var a: Array = BlockGen.generate_region(_tables, seed_val, 0, 0, width, 40)
	var b: Array = BlockGen.generate_region(_tables, seed_val, 0, 0, width, 40)
	assert_array(a).is_equal(b)

# ── Coherence: veins, not salt-and-pepper (AC-5.1.7) ─────────────────────────

func test_generation_is_coherent_not_salt_and_pepper() -> void:
	# AC-5.1.7: FastNoiseLite gen must produce spatially autocorrelated terrain —
	# neighbouring cells share a block type far MORE than chance. The chance baseline
	# is sum(p_i^2) over the band weights (the same-type probability of two independent
	# draws); coherent noise must clear it by a wide margin.
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var same: int = 0
	var pairs: int = 0
	for y in range(0, 160):
		for x in range(width):
			var a: String = BlockGen.block_at(_tables, seed_val, x, y)
			if x + 1 < width:
				if a == BlockGen.block_at(_tables, seed_val, x + 1, y):
					same += 1
				pairs += 1
			if a == BlockGen.block_at(_tables, seed_val, x, y + 1):
				same += 1
			pairs += 1
	var rate: float = float(same) / float(pairs)
	# Chance baseline averaged over the two bands the sample spans (surface + deep).
	var chance: float = maxf(
		_same_type_chance(Registry.band_weights_at(_tables, 10)),
		_same_type_chance(Registry.band_weights_at(_tables, 100))
	)
	assert_float(rate).override_failure_message(
		"neighbour same-type rate %.3f is not clearly above chance %.3f — gen looks like salt-and-pepper, not veins (AC-5.1.7)" % [rate, chance]
	).is_greater(chance + 0.20)

func _same_type_chance(weights: Dictionary) -> float:
	var total: float = 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return 1.0
	var p2: float = 0.0
	for k in weights.keys():
		var p: float = float(weights[k]) / total
		p2 += p * p
	return p2

# ── Depth-scaled selection (AC-5.1.3 / AC-5.5.2, continuous curve) ────────────

func _count_block(seed_val: int, block_id: String, x0: int, y0: int, w: int, h: int) -> int:
	var n: int = 0
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if BlockGen.block_at(_tables, seed_val, x, y) == block_id:
				n += 1
	return n

func test_cap_rich_ore_is_far_more_common_deep_than_shallow() -> void:
	# UNIT MAPGEN: the depth curve has NO hard band exclusion (it is a continuous lerp), but
	# cap-only rich ore (gold/gem) is DRAMATICALLY more frequent at the cap depth than near the
	# surface — the depth-reward signal the player feels (AC-5.5.2). Compare equal-size windows.
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var cap: int = Registry.cap_depth_cells(_tables)
	var rows: int = 40
	var surface_gold: int = _count_block(seed_val, "ore_gold", 0, 0, width, rows)
	var deep_gold: int = _count_block(seed_val, "ore_gold", 0, cap, width, rows)
	assert_int(deep_gold).override_failure_message(
		"gold at cap depth (%d) must far exceed gold near surface (%d) — depth reward (AC-5.5.2)" % [deep_gold, surface_gold]
	).is_greater(surface_gold)
	# Gold should be essentially absent near the very surface (its surface weight is 0).
	var surface_gold_top: int = _count_block(seed_val, "ore_gold", 0, 0, width, 8)
	assert_int(surface_gold_top).is_less(deep_gold)

func test_dirt_fades_out_with_depth() -> void:
	# AC-5.1.3: dirt is the surface filler and is absent from the cap table, so it fades from
	# common at the surface to (near-)none at the cap depth.
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var cap: int = Registry.cap_depth_cells(_tables)
	var surface_dirt: int = _count_block(seed_val, "dirt", 0, 0, width, 40)
	var deep_dirt: int = _count_block(seed_val, "dirt", 0, cap, width, 40)
	assert_int(surface_dirt).override_failure_message(
		"dirt should be common near the surface (got %d)" % surface_dirt
	).is_greater(0)
	assert_int(deep_dirt).override_failure_message(
		"dirt should fade out by the cap depth (surface %d, deep %d)" % [surface_dirt, deep_dirt]
	).is_less(surface_dirt)

func test_deep_has_hard_rock() -> void:
	# AC-5.1.3: hard_rock (a cap-table block) appears deep, where its weight has ramped up.
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var cap: int = Registry.cap_depth_cells(_tables)
	var found := false
	for y in range(cap, cap + 60):
		for x in range(width):
			if BlockGen.block_at(_tables, seed_val, x, y) == "hard_rock":
				found = true
				break
		if found:
			break
	assert_bool(found).override_failure_message(
		"No hard_rock found in 60 rows at the cap depth"
	).is_true()

# ── Distribution (AC-5.1.3) ──────────────────────────────────────────────────

func test_distribution_surface_within_tolerance() -> void:
	# AC-5.1.3: over a large surface sample, frequencies track band_weights. The
	# uniform-roll normalization is what keeps the coherent noise distribution-correct.
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var weights: Dictionary = Registry.band_weights_at(_tables, 10)
	var total_weight: float = 0.0
	for k in weights.keys():
		total_weight += float(weights[k])
	var counts: Dictionary = {}
	for k in weights.keys():
		counts[k] = 0
	var sample_count: int = 0
	for seed_offset in [0, 101, 202, 303]:
		for start_x in [-width * 4, -width * 2, 0, width * 2, width * 4]:
			var region: Array = BlockGen.generate_region(
				_tables, seed_val + seed_offset, start_x, 0, width, 40
			)
			for row in region:
				for cell in row:
					var id: String = str(cell)
					if counts.has(id):
						counts[id] += 1
					sample_count += 1
	for k in weights.keys():
		var expected_frac: float = float(weights[k]) / total_weight
		var actual_frac: float = float(counts[k]) / float(sample_count)
		var diff: float = absf(actual_frac - expected_frac)
		# 20% relative or 5% absolute, whichever is larger (coherent noise has more
		# spatial clumping than independent draws, so windows are noisier than IID).
		var tolerance: float = maxf(expected_frac * 0.20, 0.05)
		assert_bool(diff <= tolerance).override_failure_message(
			"Block '%s': expected ~%.1f%%, got %.1f%% (diff %.1f%%, tol %.1f%%)" % [
				k, expected_frac * 100, actual_frac * 100, diff * 100, tolerance * 100
			]
		).is_true()

# ── Relic placement (AC-5.6.1) ───────────────────────────────────────────────

func test_relic_placement_is_deterministic() -> void:
	# AC-5.6.1: relic placement is a pure fn of (mine_seed, cell) — same answer forever.
	var seed_val: int = Registry.run_seed(_tables)
	var cell: Vector2i = BlockGen.relic_cell(_tables, seed_val)
	for i in range(100):
		assert_vector(BlockGen.relic_cell(_tables, seed_val)).is_equal(cell)
	# relic_at agrees with relic_cell, and is true at exactly that one cell.
	assert_bool(BlockGen.relic_at(_tables, seed_val, cell)).is_true()
	assert_bool(BlockGen.relic_at(_tables, seed_val, cell + Vector2i(1, 0))).is_false()
	assert_bool(BlockGen.relic_at(_tables, seed_val, cell + Vector2i(0, 1))).is_false()

func test_relic_only_below_min_depth() -> void:
	# AC-5.6.1: the relic is located at/below the configured minimum depth, and never
	# anywhere above it — no relic cell exists in the shallow rows.
	var seed_val: int = Registry.run_seed(_tables)
	var relics: Dictionary = _tables.get("relics", {})
	var min_depth: int = int(relics.get("min_depth_cells", 0))
	assert_int(min_depth).is_greater(0)
	var width: int = Registry.mine_width_cells(_tables)
	# No cell above min_depth is the relic.
	for y in range(0, min_depth):
		for x in range(width):
			assert_bool(BlockGen.relic_at(_tables, seed_val, Vector2i(x, y))).override_failure_message(
				"relic placed above min depth at (%d,%d) — min_depth is %d" % [x, y, min_depth]
			).is_false()
	# The actual relic cell is at/below min depth and within the bounded mine.
	var cell: Vector2i = BlockGen.relic_cell(_tables, seed_val)
	assert_int(cell.y).is_greater_equal(min_depth)
	assert_int(cell.x).is_between(0, width - 1)

func test_relic_below_min_depth_for_many_seeds() -> void:
	# AC-5.6.1: the min-depth invariant holds for every mine seed, not just the shipped one.
	var relics: Dictionary = _tables.get("relics", {})
	var min_depth: int = int(relics.get("min_depth_cells", 0))
	var span: int = int(relics.get("depth_span_cells", 1))
	var width: int = Registry.mine_width_cells(_tables)
	for seed_val in [0, 1, 7, 42, 1337, 9999, 123456, 999999983]:
		var cell: Vector2i = BlockGen.relic_cell(_tables, seed_val)
		assert_int(cell.y).override_failure_message(
			"seed %d placed relic at depth %d, above min %d" % [seed_val, cell.y, min_depth]
		).is_greater_equal(min_depth)
		assert_int(cell.y).is_less(min_depth + span)
		assert_int(cell.x).is_between(0, width - 1)

func test_relic_varies_with_seed() -> void:
	# AC-5.6.1: different mine seeds generally place the relic differently (it is keyed
	# off the seed). Collect a handful of seeds and assert they are not all identical.
	var cells: Array = []
	for seed_val in [1, 2, 3, 4, 5, 6, 7, 8]:
		cells.append(BlockGen.relic_cell(_tables, seed_val))
	var distinct := {}
	for c in cells:
		distinct[c] = true
	assert_int(distinct.size()).override_failure_message(
		"relic placement does not vary with seed: %s" % str(cells)
	).is_greater(1)

func test_relic_column_in_center_band_for_many_seeds() -> void:
	# AC-5.6.1 (UNIT MAPGEN): the relic column is confined to |col - center| <= half (a 13-wide
	# band at half=6). Holds for EVERY seed, not just the shipped one, so the relic always sits
	# on/near the descent corridor in the infinite shaft.
	var width: int = Registry.mine_width_cells(_tables)
	var center: int = int(width / 2)
	var half: int = Registry.relic_band_half_cells(_tables)
	assert_int(half).is_greater_equal(0)
	for seed_val in [0, 1, 7, 42, 1337, 9999, 123456, 999999983, 555, 31337]:
		var cell: Vector2i = BlockGen.relic_cell(_tables, seed_val)
		assert_int(absi(cell.x - center)).override_failure_message(
			"seed %d placed relic col %d outside the center band |col-%d| <= %d" % [seed_val, cell.x, center, half]
		).is_less_equal(half)

func test_relic_column_spans_the_band_not_a_single_column() -> void:
	# AC-5.6.1: the relic column actually VARIES across the band (it isn't pinned to one column),
	# so the 13-wide band is meaningful. Sample many seeds and require > 1 distinct column.
	var cols := {}
	for seed_val in range(200):
		cols[BlockGen.relic_cell(_tables, seed_val).x] = true
	assert_int(cols.size()).override_failure_message(
		"relic column never varies across 200 seeds — band constraint is degenerate"
	).is_greater(1)

# ── Golden tests (pin gen determinism at surface, deep, + the cap transition) ─
# All goldens FAIL ON MISSING — never self-written by the test (AGENTS.md golden contract).
# Regenerate deliberately with: godot --headless --path . -s tools/gen_golden.gd

func _assert_golden(golden_path: String, region: Array) -> void:
	var serialized: String = _serialize_region(region)
	assert_bool(FileAccess.file_exists(golden_path)).override_failure_message(
		"Missing golden file: %s — commit the pinned golden; tests never self-write it." % golden_path
	).is_true()
	var f := FileAccess.open(golden_path, FileAccess.READ)
	var expected: String = f.get_as_text()
	f.close()
	assert_str(serialized).override_failure_message(
		"Golden %s mismatch — generation has drifted!" % golden_path
	).is_equal(expected)

func test_golden_gen_surface() -> void:
	# Shallow region: dirt/copper/silver dominated (the surface anchor weights).
	var seed_val: int = Registry.run_seed(_tables)
	_assert_golden("res://tests/golden/gen_surface.txt",
		BlockGen.generate_region(_tables, seed_val, 0, 0, 7, 16))

func test_golden_gen_deep() -> void:
	# UNIT MAPGEN: pin a region BELOW the cap depth so the frozen cap_weights are golden-locked.
	# Proves the infinite descent is deterministic far from the surface (hard_rock/gold/gem rich).
	var seed_val: int = Registry.run_seed(_tables)
	var cap: int = Registry.cap_depth_cells(_tables)
	_assert_golden("res://tests/golden/gen_deep.txt",
		BlockGen.generate_region(_tables, seed_val, 0, cap + 50, 7, 16))

func test_golden_gen_cap_transition() -> void:
	# UNIT MAPGEN: pin a region straddling cap_depth_cells so the lerp→clamp boundary is locked
	# (catches an off-by-one in t = clamp((y-surface)/(cap-surface), 0, 1)).
	var seed_val: int = Registry.run_seed(_tables)
	var cap: int = Registry.cap_depth_cells(_tables)
	_assert_golden("res://tests/golden/gen_cap_transition.txt",
		BlockGen.generate_region(_tables, seed_val, 0, cap - 8, 7, 16))

# ── generate_region shape & validity ─────────────────────────────────────────

func test_generate_region_dimensions() -> void:
	var region: Array = BlockGen.generate_region(_tables, 42, 0, 0, 5, 3)
	assert_int(region.size()).is_equal(3)
	for row in region:
		assert_int((row as Array).size()).is_equal(5)

func test_generate_region_all_valid_block_ids() -> void:
	var seed_val: int = Registry.run_seed(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	var region: Array = BlockGen.generate_region(_tables, seed_val, 0, 0, width, 60)
	for row in region:
		for cell in row:
			assert_bool(
				Registry.has_block(_tables, cell as String)
			).override_failure_message(
				"Invalid block id: '%s'" % str(cell)
			).is_true()

# ── Different seeds produce different terrain (AC-5.1.4) ──────────────────────

func test_different_seeds_differ() -> void:
	var width: int = Registry.mine_width_cells(_tables)
	var region_a: Array = BlockGen.generate_region(_tables, 1337, 0, 0, width, 16)
	var region_b: Array = BlockGen.generate_region(_tables, 9999, 0, 0, width, 16)
	var match_count: int = 0
	var total: int = 0
	for y in range(16):
		for x in range(width):
			if region_a[y][x] == region_b[y][x]:
				match_count += 1
			total += 1
	assert_bool(match_count < total).override_failure_message(
		"Two different seeds produced identical regions"
	).is_true()

# ── Helpers ──────────────────────────────────────────────────────────────────

func _serialize_region(region: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for row in region:
		var cells: PackedStringArray = PackedStringArray()
		for cell in row:
			cells.append(str(cell))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"
