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
	# AC-5.1.5: block(id) returns display_name/hardness/max_hp/diggable/palette_index/ore.
	var dirt: Dictionary = Registry.block(_tables, "dirt")
	assert_str(dirt.get("display_name", "")).is_equal("Dirt")
	assert_int(int(dirt.get("hardness", -1))).is_equal(1)
	assert_int(int(dirt.get("max_hp", -1))).is_equal(12)
	assert_bool(dirt.get("diggable", false) as bool).is_true()
	assert_int(int(dirt.get("palette_index", -1))).is_equal(3)

func test_block_ore_value() -> void:
	# AC-5.1.5: ore blocks carry a value. Unit economy: rock is a $5 ore (plain stone is
	# worth a little), copper is the prominent $10 tier, gold is the $90 tier.
	assert_int(Registry.block_ore_value(_tables, "rock")).is_equal(5)
	assert_int(Registry.block_ore_value(_tables, "ore_copper")).is_equal(10)
	assert_int(Registry.block_ore_value(_tables, "ore_gold")).is_equal(30)
	assert_int(Registry.block_ore_value(_tables, "dirt")).is_equal(0)
	assert_int(Registry.block_ore_value(_tables, "air")).is_equal(0)

func test_block_max_hp() -> void:
	assert_int(Registry.block_max_hp(_tables, "dirt")).is_equal(12)
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

# ── Depth-scaled weight curve (UNIT MAPGEN — infinite descent) ──────────────
# depth_bands.json is now a CONTINUOUS curve (surface_weights → cap_weights), not discrete
# bands. Weights interpolate with depth toward a finite cap, then freeze (AC-5.1.3/5.5.2).

func test_depth_weights_at_surface_equal_surface_anchor() -> void:
	# At surface_depth (0), the interpolated weights equal surface_weights exactly.
	var w: Dictionary = Registry.depth_weights_at(_tables, Registry.surface_depth_cells(_tables))
	var anchor: Dictionary = Registry.surface_weights(_tables)
	for id in anchor.keys():
		assert_float(float(w.get(id, 0.0))).override_failure_message(
			"surface weight for '%s' should equal the anchor" % id
		).is_equal_approx(float(anchor[id]), 0.0001)
	# A cap-only block (gold) has zero weight at the surface (omitted from the dict).
	assert_bool(w.has("ore_gold")).is_false()

func test_depth_weights_at_cap_equal_cap_anchor() -> void:
	# At cap_depth and below, the interpolated weights equal cap_weights exactly (the bound).
	var cap: int = Registry.cap_depth_cells(_tables)
	var w: Dictionary = Registry.depth_weights_at(_tables, cap)
	var anchor: Dictionary = Registry.cap_weights(_tables)
	for id in anchor.keys():
		assert_float(float(w.get(id, 0.0))).override_failure_message(
			"cap weight for '%s' should equal the anchor" % id
		).is_equal_approx(float(anchor[id]), 0.0001)
	# Dirt remains as rare filler at the cap because the cap anchor includes a small weight.
	assert_float(float(w.get("dirt", 0.0))).is_equal_approx(float(anchor.get("dirt", 0.0)), 0.0001)

func test_depth_weights_frozen_below_cap() -> void:
	# AC-5.5.2 (bounded): weights are identical at the cap and far below it (the clamp).
	var cap: int = Registry.cap_depth_cells(_tables)
	var at_cap: Dictionary = Registry.depth_weights_at(_tables, cap)
	var deep: Dictionary = Registry.depth_weights_at(_tables, cap + 5000)
	assert_int(deep.size()).is_equal(at_cap.size())
	for id in at_cap.keys():
		assert_float(float(deep.get(id, -1.0))).is_equal_approx(float(at_cap[id]), 0.0001)

func test_band_weights_alias_matches_curve() -> void:
	# The legacy band_weights_at alias is backed by the continuous curve.
	assert_dict(Registry.band_weights_at(_tables, 50)).is_equal(Registry.depth_weights_at(_tables, 50))

func test_band_odds_sum_to_one() -> void:
	# AC-5.8.8: depth odds normalize the curve weights to probabilities.
	var odds: Dictionary = Registry.depth_odds_at(_tables, 10)
	assert_bool(odds.has("dirt")).is_true()
	var total: float = 0.0
	for p in odds.values():
		total += float(p)
	assert_float(total).is_equal_approx(1.0, 0.0001)

func test_band_odds_deep_are_more_lucrative() -> void:
	# AC-5.8.8 / AC-5.5.2: deeper depths show higher gem/gold odds.
	var surface: Dictionary = Registry.full_odds_at(_tables, 10)
	var deep: Dictionary = Registry.full_odds_at(_tables, Registry.cap_depth_cells(_tables))
	assert_float(float(deep.get("ore_gold", 0.0))).is_greater(float(surface.get("ore_gold", 0.0)))
	assert_float(float(deep.get("diamond", 0.0))).is_greater(float(surface.get("diamond", 0.0)))

func test_band_odds_nonempty_far_below_in_infinite_shaft() -> void:
	# UNIT MAPGEN: the shaft is infinite — there is no "outside the mine". Far below the cap,
	# odds are still the (frozen) cap odds, never empty.
	var odds: Dictionary = Registry.depth_odds_at(_tables, 99999)
	assert_bool(odds.is_empty()).is_false()

func test_depth_odds_snap_to_hud_bucket() -> void:
	# AC-5.8.8: the HUD odds readout snaps depth to hud_sample_band_cells buckets so it doesn't
	# flicker per row. Two depths in the same bucket give identical odds.
	var bucket: int = Registry.hud_sample_band_cells(_tables)
	assert_int(bucket).is_greater(0)
	var a: Dictionary = Registry.depth_odds_at(_tables, bucket * 2)
	var b: Dictionary = Registry.depth_odds_at(_tables, bucket * 2 + bucket - 1)
	assert_dict(a).is_equal(b)

# ── Explosive lookups (AC-5.4.1) ────────────────────────────────────────────

func test_explosive_returns_expected_fields() -> void:
	# AC-5.4.1: explosive resource shape
	var dyn: Dictionary = Registry.explosive(_tables, "dynamite")
	assert_float(float(dyn.get("mass", 0.0))).is_equal(1.5)
	assert_float(float(dyn.get("base_impulse", 0.0))).is_equal(360.0)
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
	# v0.7: price-0 packs are allowed (starter_pack, basic_pack — the dig-flow safety
	# net). Only the basic_pack and starter_pack may be free; paid packs must cost > 0.
	for id in Registry.pack_ids(_tables):
		if id == "starter_pack" or id == "basic_pack":
			assert_int(int(Registry.pack(_tables, id).get("price", -1))).is_equal(0)
		else:
			assert_int(int(Registry.pack(_tables, id).get("price", -1))).override_failure_message(
				"pack '%s' has price 0 — only starter_pack and basic_pack may be free" % id
			).is_greater(0)

# ── Basic safety-net charge (AC-5.4.3 v0.7) ───────────────────────────────

func test_free_charge_id() -> void:
	# AC-5.4.3 (v0.7): the basic safety-net charge is resolvable (by `free: true` flag
	# or by the "free_charge" id fallback).
	var id: String = Registry.free_charge_id(_tables)
	assert_str(id).is_not_empty()
	var ex: Dictionary = Registry.explosive(_tables, id)
	# AC-5.4.3: the basic charge is the inefficient tier-1 baseline.
	assert_int(int(ex.get("tier", 0))).is_equal(1)

# ── Balance lookups ─────────────────────────────────────────────────────────

func test_balance_values() -> void:
	# AC-5.5.4: values from data
	assert_int(Registry.mine_width_cells(_tables)).is_equal(400)
	# UNIT MAPGEN: mine_height_cells 0 = the infinite-descent sentinel (no bottom).
	assert_int(Registry.mine_height_cells(_tables)).is_equal(0)
	assert_bool(Registry.is_infinite_depth(_tables)).is_true()
	assert_int(Registry.mine_bottom_row(_tables)).is_equal(Registry.INFINITE_BOTTOM_ROW)
	assert_int(Registry.shaft_width(_tables)).is_equal(9)
	assert_int(Registry.shaft_left_cell(_tables)).is_equal(195)
	assert_int(Registry.chunk_height(_tables)).is_equal(16)
	assert_int(Registry.block_pixel_size(_tables)).is_equal(16)
	assert_int(Registry.starting_money(_tables)).is_equal(60)
	assert_int(Registry.run_seed(_tables)).is_equal(1337)
	assert_int(Registry.crack_stages(_tables)).is_equal(3)
	assert_float(Registry.camera_zoom(_tables)).is_equal(2.2)

func test_light_dark_tint_resolves_hex() -> void:
	# UNIT TUNE: the headlamp mask fades toward an EARTHY-BROWN deep-terrain tint so the unlit
	# mine / cleared cells read as dirt, not gray/black. The accessor resolves the data-driven
	# hex to a Color; the shipped value is the brown earth cast.
	var tint: Color = Registry.light_dark_tint(_tables)
	assert_object(tint).is_equal(Color.html("#2a1c10"))
	# A warm brown tint: red dominant, blue minimal (so it reads as earth, not the old cool cast).
	assert_bool(tint.r > tint.b).is_true()

func test_max_hp_consistent_with_block() -> void:
	# max_hp derivation is consistent: Registry.block_max_hp == block().max_hp
	for id in Registry.block_ids(_tables):
		var from_accessor: int = Registry.block_max_hp(_tables, id)
		var from_dict: int = int(Registry.block(_tables, id).get("max_hp", 0))
		assert_int(from_accessor).is_equal(from_dict)

# ── Prestige-effective balance accessors (AC-5.6.4) ─────────────────────────

func test_throw_cooldown_seconds_from_data() -> void:
	# AC-5.6.4: the raw balance value is exposed for callers that need the base.
	assert_float(Registry.throw_cooldown_seconds(_tables)).is_equal(1.0)

func test_effective_light_radius_no_prestige_equals_base() -> void:
	# AC-5.6.4: with no Mining Torch purchases the effective radius equals the base data value.
	var prestige := Prestige.new(_tables)
	assert_float(Registry.effective_light_radius(_tables, prestige)).is_equal(Registry.light_radius_px(_tables))

func test_effective_throw_cooldown_no_prestige_equals_base() -> void:
	# AC-5.6.4: with no Charge Holster purchases the effective cooldown equals the base data value.
	var prestige := Prestige.new(_tables)
	assert_float(Registry.effective_throw_cooldown(_tables, prestige)).is_equal(Registry.throw_cooldown_seconds(_tables))

func test_effective_light_radius_increases_with_mining_torch() -> void:
	# AC-5.6.4: buying Mining Torch increases the effective light radius.
	var prestige := Prestige.new(_tables)
	prestige.bank(10)
	var base: float = Registry.effective_light_radius(_tables, prestige)
	assert_bool(prestige.buy_upgrade("mining_torch")).is_true()
	assert_float(Registry.effective_light_radius(_tables, prestige)).is_greater(base)

func test_effective_throw_cooldown_decreases_with_charge_holster() -> void:
	# AC-5.6.4: buying Charge Holster decreases the effective throw cooldown.
	var prestige := Prestige.new(_tables)
	prestige.bank(10)
	var base: float = Registry.effective_throw_cooldown(_tables, prestige)
	assert_bool(prestige.buy_upgrade("charge_holster")).is_true()
	assert_float(Registry.effective_throw_cooldown(_tables, prestige)).is_less(base)

# ── Shaft Engineering: required clearance width shrinks (Phase C, AC-5.12.x) ─────
# The reduction now comes from a per-dig MONEY upgrade (RunState.shaft_width_reduction);
# Registry.effective_shaft_width is the pure width math over a reduction-in-cells.

func test_effective_shaft_width_zero_reduction_equals_base() -> void:
	# No reduction → the required clearance width equals the base data value (9).
	assert_int(Registry.effective_shaft_width(_tables, 0)).is_equal(Registry.shaft_width(_tables))

func test_effective_shaft_width_reduction_narrows_to_seven_centered() -> void:
	# A reduction of 2 cells narrows the clearance 9 → 7, kept odd (center line), and the
	# band shrinks inward symmetrically (its left edge moves right by one cell).
	var base_w: int = Registry.effective_shaft_width(_tables, 0)
	var narrowed: int = Registry.effective_shaft_width(_tables, 2)
	assert_int(narrowed).is_equal(7)
	assert_int(narrowed).is_less(base_w)
	assert_int(narrowed % 2).is_equal(1)
	assert_int(Registry.effective_shaft_left_cell(_tables, narrowed)) \
		.is_equal(Registry.effective_shaft_left_cell(_tables, base_w) + 1)

func test_effective_shaft_width_never_below_platform_width() -> void:
	# Safety floor: an absurd reduction can't drop the clearance below the platform deck.
	assert_int(Registry.effective_shaft_width(_tables, 999)) \
		.is_greater_equal(Registry.platform_width_cells(_tables))

# ── Mines: surface + Deep Mine accessors ──────────────────────────────────────

func test_default_mine_is_free_surface() -> void:
	# The default mine is the free (access_cost 0) starting mine.
	var id: String = Registry.default_mine_id(_tables)
	assert_int(Registry.mine_access_cost(_tables, id)).is_equal(0)

func test_deep_mine_is_harder_richer_and_gated() -> void:
	# The Deep Mine costs money to access and is strictly harder + richer than the surface.
	assert_bool(Registry.mine_ids(_tables).has("deep")).is_true()
	assert_int(Registry.mine_access_cost(_tables, "deep")).is_greater(0)
	assert_float(Registry.mine_hardness_mult(_tables, "deep")) \
		.is_greater(Registry.mine_hardness_mult(_tables, "surface"))
	assert_float(Registry.mine_ore_value_mult(_tables, "deep")) \
		.is_greater(Registry.mine_ore_value_mult(_tables, "surface"))
	# Distinct seed offset → distinct layout/relic; darker tint than the surface.
	assert_int(Registry.mine_seed_offset(_tables, "deep")).is_not_equal(0)
	assert_bool(Registry.mine_tile_tint(_tables, "deep").v < 1.0).is_true()

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
