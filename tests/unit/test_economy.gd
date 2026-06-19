extends GdUnitTestSuite
## U8 — Economy: ore crediting, money tracking, loot sampling.
## ACs: AC-5.5.1, AC-5.5.2, AC-5.5.3, AC-5.5.4.

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
	# These tests verify crediting/debit MATH from a clean zero balance; pin the
	# starting grant to 0 so they stay decoupled from the production dig stipend.
	(out["balance"] as Dictionary)["starting_money"] = 0
	return out

# ── Per-mine ore-value multiplier (Deep Mine — richer ore) ────────────────────

func test_ore_value_mult_scales_credit() -> void:
	# A deeper mine's ore-value multiplier scales every credit (richer ore pays more).
	var econ := Economy.new(_tables)
	var base: int = Registry.block_ore_value(_tables, "ore_gold")
	econ.set_ore_value_mult(2.5)
	assert_int(econ.credit(Vector2i(0, 0), "ore_gold")).is_equal(int(round(float(base) * 2.5)))
	assert_int(econ.money).is_equal(int(round(float(base) * 2.5)))

func test_ore_value_mult_default_is_one() -> void:
	# Without a multiplier set, credits are unscaled (surface mine behavior).
	var econ := Economy.new(_tables)
	var base: int = Registry.block_ore_value(_tables, "ore_copper")
	assert_int(econ.credit(Vector2i(1, 1), "ore_copper")).is_equal(base)

# ── Ore crediting (AC-5.5.1) ───────────────────────────────────────────────

func test_credit_ore_block() -> void:
	# AC-5.5.1: breaking an ore block credits exactly its value (copper = $10 prominent tier)
	var econ := Economy.new(_tables)
	var value: int = econ.credit(Vector2i(0, 0), "ore_copper")
	assert_int(value).is_equal(10)
	assert_int(econ.money).is_equal(10)

func test_credit_gold_ore() -> void:
	var econ := Economy.new(_tables)
	var value: int = econ.credit(Vector2i(1, 1), "ore_gold")
	assert_int(value).is_equal(30)
	assert_int(econ.money).is_equal(30)

func test_credit_non_ore_block() -> void:
	# AC-5.5.1: non-ore credits 0
	var econ := Economy.new(_tables)
	var value: int = econ.credit(Vector2i(0, 0), "dirt")
	assert_int(value).is_equal(0)
	assert_int(econ.money).is_equal(0)

func test_credit_air_block() -> void:
	var econ := Economy.new(_tables)
	var value: int = econ.credit(Vector2i(0, 0), "air")
	assert_int(value).is_equal(0)

func test_no_double_credit() -> void:
	# No double-credit for the same cell.
	var econ := Economy.new(_tables)
	econ.credit(Vector2i(0, 0), "ore_copper")
	var second: int = econ.credit(Vector2i(0, 0), "ore_copper")
	assert_int(second).is_equal(0)
	assert_int(econ.money).is_equal(10)  # Only credited once

func test_credit_accumulates() -> void:
	var econ := Economy.new(_tables)
	econ.credit(Vector2i(0, 0), "ore_copper")
	econ.credit(Vector2i(1, 0), "ore_gold")
	econ.credit(Vector2i(2, 0), "dirt")
	assert_int(econ.money).is_equal(40)  # 10 + 30 + 0

# ── Credit blast (convenience) ──────────────────────────────────────────────

func test_credit_blast() -> void:
	var econ := Economy.new(_tables)
	var cleared: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
	var block_ids: Dictionary = {
		Vector2i(0, 0): "ore_copper",
		Vector2i(1, 0): "ore_gold",
		Vector2i(2, 0): "rock",
	}
	var total: int = econ.credit_blast(cleared, block_ids)
	assert_int(total).is_equal(45)  # 10 + 30 + 5 (rock is now a $5 ore)
	assert_int(econ.money).is_equal(45)

# ── Debit / can_afford ──────────────────────────────────────────────────────

func test_debit_affordable() -> void:
	var econ := Economy.new(_tables)
	econ.credit(Vector2i(0, 0), "ore_gold")  # +30
	assert_bool(econ.can_afford(20)).is_true()
	assert_bool(econ.debit(20)).is_true()
	assert_int(econ.money).is_equal(10)

func test_debit_unaffordable() -> void:
	var econ := Economy.new(_tables)
	assert_bool(econ.can_afford(1)).is_false()
	assert_bool(econ.debit(1)).is_false()
	assert_int(econ.money).is_equal(0)

# ── Depth reward: EV + gem probability rise with depth (AC-5.5.2) ───────────
# These test the production loot contract: BlockGen lays filler from depth_bands, then
# stamps ore from the ore_overlays layer. We assert the property the player feels —
# deeper is strictly more rewarding — over Registry.full_odds_at(), the same combined
# odds function used by the HUD and validator.

## Expected ore value per cell for the band that contains `depth_cells`.
func _band_expected_value(depth_cells: int) -> float:
	var weights: Dictionary = Registry.full_odds_at(_tables, depth_cells)
	var total: float = 0.0
	var value_sum: float = 0.0
	for k in weights.keys():
		var w: float = float(weights[k])
		total += w
		value_sum += w * float(Registry.block_ore_value(_tables, k))
	return value_sum / total if total > 0.0 else 0.0

## Probability of the highest-value (gem) block in the band at `depth_cells`.
func _band_gem_probability(depth_cells: int) -> float:
	# Gem = the single highest ore value across the whole registry.
	var gem_value: int = 0
	for id in Registry.block_ids(_tables):
		gem_value = maxi(gem_value, Registry.block_ore_value(_tables, id))
	var weights: Dictionary = Registry.full_odds_at(_tables, depth_cells)
	var total: float = 0.0
	var gem_weight: float = 0.0
	for k in weights.keys():
		var w: float = float(weights[k])
		total += w
		if gem_value > 0 and Registry.block_ore_value(_tables, k) == gem_value:
			gem_weight += w
	return gem_weight / total if total > 0.0 else 0.0

func test_loot_expected_value_strictly_rises_with_depth() -> void:
	# AC-5.5.2: expected ore value per cell rises from the surface band to the deep band.
	# (Surface depth 10, deep depth 50 in the shipped bands.)
	var surface_ev: float = _band_expected_value(10)
	var deep_ev: float = _band_expected_value(50)
	assert_float(deep_ev).override_failure_message(
		"deep-band EV %.3f must exceed surface-band EV %.3f (AC-5.5.2 depth reward)" % [deep_ev, surface_ev]
	).is_greater(surface_ev)
	# Sanity: both bands actually carry some value (not a degenerate all-filler config).
	assert_float(surface_ev).is_greater(0.0)

func test_rare_gem_probability_strictly_rises_with_depth() -> void:
	# AC-5.5.2: the rare-gem (highest-value block) probability rises with depth.
	var surface_gem: float = _band_gem_probability(10)
	var deep_gem: float = _band_gem_probability(50)
	assert_float(deep_gem).override_failure_message(
		"deep-band gem prob %.3f must exceed surface-band gem prob %.3f (AC-5.5.2)" % [deep_gem, surface_gem]
	).is_greater(surface_gem)

func test_filler_rock_allowed_at_all_depths() -> void:
	# AC-5.5.2 (v0.4.1): value-0 filler MAY exist at any depth — the reward signal is EV +
	# gem chance, NOT a per-cell minimum. Assert the deep band still contains a value-0 block
	# (this documents the design intent that the old "floor rises" clause wrongly forbade).
	var deep_weights: Dictionary = Registry.band_weights_at(_tables, 50)
	var has_zero_value := false
	for k in deep_weights.keys():
		if Registry.block_ore_value(_tables, k) == 0:
			has_zero_value = true
			break
	assert_bool(has_zero_value).override_failure_message(
		"deep band has no value-0 filler — fine, but update AC-5.5.2 intent note if intentional"
	).is_true()

# ── Run reset (AC-5.5.3) ───────────────────────────────────────────────────

func test_reset_run() -> void:
	# AC-5.5.3: reset returns money to starting_money
	var econ := Economy.new(_tables)
	econ.credit(Vector2i(0, 0), "ore_gold")
	assert_int(econ.money).is_equal(30)
	econ.reset_run()
	assert_int(econ.money).is_equal(0)  # starting_money = 0

func test_reset_run_clears_credit_tracking() -> void:
	# After reset, the same cell can be credited again (new run).
	var econ := Economy.new(_tables)
	econ.credit(Vector2i(0, 0), "ore_copper")
	assert_int(econ.money).is_equal(10)
	econ.reset_run()
	var value: int = econ.credit(Vector2i(0, 0), "ore_copper")
	assert_int(value).is_equal(10)
	assert_int(econ.money).is_equal(10)
