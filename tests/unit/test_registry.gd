extends GdUnitTestSuite
## U1 — Registry: typed accessors over raw /data JSON tables.
## ACs: AC-5.1.5 (block id → fields), AC-5.4.1 (explosive resource shape), AC-5.5.4.

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

# ── Block lookups (AC-5.1.5) ────────────────────────────────────────────────

func test_block_returns_expected_fields() -> void:
	# AC-5.1.5: block(id) returns hardness/max_hp/ore/glyph
	var dirt: Dictionary = Registry.block(_tables, "dirt")
	assert_str(dirt.get("display_name", "")).is_equal("Dirt")
	assert_int(int(dirt.get("hardness", -1))).is_equal(1)
	assert_int(int(dirt.get("max_hp", -1))).is_equal(20)
	assert_bool(dirt.get("diggable", false) as bool).is_true()
	assert_str(dirt.get("glyph", "")).is_equal("dots")

func test_block_ore_value() -> void:
	# AC-5.1.5: ore blocks carry a value
	assert_int(Registry.block_ore_value(_tables, "ore_copper")).is_equal(10)
	assert_int(Registry.block_ore_value(_tables, "ore_gold")).is_equal(35)
	assert_int(Registry.block_ore_value(_tables, "dirt")).is_equal(0)
	assert_int(Registry.block_ore_value(_tables, "air")).is_equal(0)

func test_block_max_hp() -> void:
	assert_int(Registry.block_max_hp(_tables, "dirt")).is_equal(20)
	assert_int(Registry.block_max_hp(_tables, "rock")).is_equal(60)
	assert_int(Registry.block_max_hp(_tables, "hard_rock")).is_equal(140)
	assert_int(Registry.block_max_hp(_tables, "air")).is_equal(0)

func test_unknown_block_returns_safe_default() -> void:
	# AC-5.1.5: unknown id returns a safe default
	var unknown: Dictionary = Registry.block(_tables, "nonexistent_block_xyz")
	assert_str(unknown.get("display_name", "")).is_equal("Unknown")
	assert_bool(unknown.get("diggable", true) as bool).is_false()
	assert_int(int(unknown.get("max_hp", -1))).is_equal(0)

func test_has_block() -> void:
	assert_bool(Registry.has_block(_tables, "dirt")).is_true()
	assert_bool(Registry.has_block(_tables, "nonexistent")).is_false()

func test_diggable_block_ids() -> void:
	var ids: Array = Registry.diggable_block_ids(_tables)
	assert_bool(ids.has("dirt")).is_true()
	assert_bool(ids.has("rock")).is_true()
	assert_bool(ids.has("ore_copper")).is_true()
	assert_bool(ids.has("air")).is_false()  # air is not diggable

# ── Depth band lookups (AC-5.1.3, AC-5.1.4) ────────────────────────────────

func test_depth_band_at_boundaries() -> void:
	# AC-5.1.3: depth_band_for returns correct band at boundaries
	var surface: Dictionary = Registry.depth_band_for(_tables, 0)
	assert_str(surface.get("id", "")).is_equal("band_surface")

	var still_surface: Dictionary = Registry.depth_band_for(_tables, 39)
	assert_str(still_surface.get("id", "")).is_equal("band_surface")

	var deep: Dictionary = Registry.depth_band_for(_tables, 40)
	assert_str(deep.get("id", "")).is_equal("band_deep")

	var very_deep: Dictionary = Registry.depth_band_for(_tables, 9999)
	# 9999 is max_depth_cells for band_deep, so it should be out of range
	assert_bool(very_deep.is_empty()).is_true()

	var deep_but_valid: Dictionary = Registry.depth_band_for(_tables, 9998)
	assert_str(deep_but_valid.get("id", "")).is_equal("band_deep")

func test_band_weights_surface() -> void:
	var weights: Dictionary = Registry.band_weights_at(_tables, 10)
	assert_bool(weights.has("dirt")).is_true()
	assert_bool(weights.has("rock")).is_true()
	# Surface band should NOT have hard_rock
	assert_bool(weights.has("hard_rock")).is_false()

func test_band_weights_deep() -> void:
	var weights: Dictionary = Registry.band_weights_at(_tables, 50)
	assert_bool(weights.has("hard_rock")).is_true()
	# Deep band should NOT have dirt
	assert_bool(weights.has("dirt")).is_false()

func test_band_odds_sum_to_one() -> void:
	# AC-5.8.8: band odds normalize the band weights to probabilities.
	var odds: Dictionary = Registry.band_odds(_tables, 10)
	assert_bool(odds.has("dirt")).is_true()
	var total: float = 0.0
	for p in odds.values():
		total += float(p)
	assert_float(total).is_equal_approx(1.0, 0.0001)

func test_band_odds_deep_are_more_lucrative() -> void:
	# AC-5.8.8 / AC-5.5.2: deeper bands show higher resource odds.
	var surface: Dictionary = Registry.band_odds(_tables, 10)
	var deep: Dictionary = Registry.band_odds(_tables, 50)
	assert_float(float(deep.get("ore_gold", 0.0))).is_greater(float(surface.get("ore_gold", 0.0)))

func test_band_odds_empty_outside_mine() -> void:
	# AC-5.8.8: no band → no odds.
	var odds: Dictionary = Registry.band_odds(_tables, 99999)
	assert_bool(odds.is_empty()).is_true()

# ── Explosive lookups (AC-5.4.1) ────────────────────────────────────────────

func test_explosive_returns_expected_fields() -> void:
	# AC-5.4.1: explosive resource shape
	var dyn: Dictionary = Registry.explosive(_tables, "dynamite")
	assert_float(float(dyn.get("mass", 0.0))).is_equal(1.0)
	assert_float(float(dyn.get("base_impulse", 0.0))).is_equal(520.0)
	assert_str(dyn.get("detonation_mode", "")).is_equal("fuse_seconds")
	assert_int(int(dyn.get("blast_radius_cells", 0))).is_equal(2)
	assert_int(int(dyn.get("blast_intensity", 0))).is_equal(80)

func test_explosive_unknown_returns_empty() -> void:
	var ex: Dictionary = Registry.explosive(_tables, "nonexistent_explosive")
	assert_bool(ex.is_empty()).is_true()

func test_has_explosive() -> void:
	assert_bool(Registry.has_explosive(_tables, "dynamite")).is_true()
	assert_bool(Registry.has_explosive(_tables, "heavy_bomb")).is_true()
	assert_bool(Registry.has_explosive(_tables, "nope")).is_false()

# ── Pack lookups (AC-5.12.1) ────────────────────────────────────────────────

func test_pack_returns_expected_fields() -> void:
	# v0.4: packs grant ONLY finite, paid charges (the price-0 v0.3 "starter" pack was
	# removed — the free unlimited charge is the only free source). The shipped "basic"
	# pack has a positive price and a charge count.
	var basic: Dictionary = Registry.pack(_tables, "basic")
	assert_int(int(basic.get("price", -1))).is_greater(0)
	assert_int(int(basic.get("charge_count", 0))).is_greater(0)

func test_pack_unknown_returns_empty() -> void:
	var p: Dictionary = Registry.pack(_tables, "nonexistent_pack")
	assert_bool(p.is_empty()).is_true()

func test_no_price_zero_pack_remains() -> void:
	# VERTICAL_SLICE §0 salvage: the price-0 "starter" pack is removed in v0.4. No pack may
	# be free — packs sell efficiency; only the flagged free charge is free.
	for id in Registry.pack_ids(_tables):
		assert_int(int(Registry.pack(_tables, id).get("price", -1))).override_failure_message(
			"pack '%s' has price 0 — v0.4 removes the free starter pack" % id
		).is_greater(0)

# ── Free unlimited charge (AC-5.4.3, AC-5.12.1) ─────────────────────────────

func test_free_charge_id() -> void:
	# AC-5.12.1: exactly one flagged free unlimited charge is resolvable.
	var id: String = Registry.free_charge_id(_tables)
	assert_str(id).is_not_empty()
	var ex: Dictionary = Registry.explosive(_tables, id)
	assert_bool(ex.get("free", false) as bool).is_true()
	# AC-5.4.3: the free charge is the inefficient tier-1 baseline.
	assert_int(int(ex.get("tier", 0))).is_equal(1)

# ── Balance lookups ─────────────────────────────────────────────────────────

func test_balance_values() -> void:
	# AC-5.5.4: values from data
	assert_int(Registry.mine_width_cells(_tables)).is_equal(400)
	assert_int(Registry.mine_height_cells(_tables)).is_equal(400)
	assert_int(Registry.shaft_width(_tables)).is_equal(9)
	assert_int(Registry.shaft_left_cell(_tables)).is_equal(195)
	assert_int(Registry.chunk_height(_tables)).is_equal(16)
	assert_int(Registry.block_pixel_size(_tables)).is_equal(16)
	assert_int(Registry.starting_money(_tables)).is_equal(0)
	assert_int(Registry.run_seed(_tables)).is_equal(1337)
	assert_int(Registry.crack_stages(_tables)).is_equal(3)
	assert_float(Registry.camera_zoom(_tables)).is_equal(0.55)

func test_max_hp_consistent_with_block() -> void:
	# max_hp derivation is consistent: Registry.block_max_hp == block().max_hp
	for id in Registry.block_ids(_tables):
		var from_accessor: int = Registry.block_max_hp(_tables, id)
		var from_dict: int = int(Registry.block(_tables, id).get("max_hp", 0))
		assert_int(from_accessor).is_equal(from_dict)

# ── HP-scaling accessors (AC-5.2.1, AC-5.5.4) ───────────────────────────────

func test_hp_scaling_multipliers_from_data() -> void:
	# AC-5.2.1 / AC-5.5.4: the depth + per-mine HP multipliers are tunables read from data.
	assert_float(Registry.depth_hp_mult_per_cell(_tables)).is_equal(0.01)
	assert_float(Registry.mine_hardness_mult_max(_tables)).is_equal(3.0)

func test_scaled_block_hp_grows_with_depth_and_mine_hardness() -> void:
	# AC-5.2.1: HP = base_hp * (1 + depth_cells * per_cell) * mine_hardness_mult.
	# At depth 0, baseline mine: scaled HP == base HP.
	var base: int = Registry.block_max_hp(_tables, "rock")
	assert_int(Registry.scaled_block_hp(_tables, "rock", 0, 1.0)).is_equal(base)
	# Deeper cells are strictly harder (drives re-optimization).
	var shallow: int = Registry.scaled_block_hp(_tables, "rock", 0, 1.0)
	var deep: int = Registry.scaled_block_hp(_tables, "rock", 500, 1.0)
	assert_int(deep).is_greater(shallow)
	# A harder mine multiplies HP further than the baseline at the same depth.
	var baseline: int = Registry.scaled_block_hp(_tables, "rock", 100, 1.0)
	var hard: int = Registry.scaled_block_hp(_tables, "rock", 100, 3.0)
	assert_int(hard).is_greater(baseline)
	# Exact formula check at a known point: 60 * (1 + 100*0.01) * 2 = 60 * 2.0 * 2 = 240.
	assert_int(Registry.scaled_block_hp(_tables, "rock", 100, 2.0)).is_equal(240)
