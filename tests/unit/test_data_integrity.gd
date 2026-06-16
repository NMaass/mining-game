extends GdUnitTestSuite
## U1 — Data integrity: verifies the shipped /data set passes DataValidator, and
## that the validator actually catches representative breakages (so the gate has
## teeth). Preloaded so the rules are exercised even with a cold class cache.
##
## ACs: AC-5.4.1 (fuse-mode needs fuse_seconds; falloff length == radius+1),
##      AC-5.4.3 / AC-5.12.1 (free unlimited charge exists, flagged),
##      AC-5.5.4 (tunables are data), AC-5.5.5 (no-stall: free charge breaks floor).

const Validator := preload("res://scripts/core/data_validator.gd")

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

func test_shipped_data_is_valid() -> void:
	# AC-5.5.4: the shipped, schema-validated /data set is internally consistent.
	var errors: Array = Validator.validate(_load_real_tables())
	# If this fails, the printed list tells you exactly which rule broke.
	assert_array(errors).override_failure_message(str(errors)).is_empty()

func test_validator_catches_unknown_block_in_band() -> void:
	var t := _load_real_tables()
	(t["depth_bands"][0]["block_weights"])["does_not_exist"] = 5
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_catches_zero_weight() -> void:
	var t := _load_real_tables()
	var first_block: String = (t["depth_bands"][0]["block_weights"] as Dictionary).keys()[0]
	(t["depth_bands"][0]["block_weights"])[first_block] = 0
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_catches_blast_radius_over_cap() -> void:
	var t := _load_real_tables()
	var first_ex: String = (t["explosives"] as Dictionary).keys()[0]
	(t["explosives"][first_ex])["blast_radius_cells"] = 999
	assert_array(Validator.validate(t)).is_not_empty()

# ── Depth reward: EV + gem probability rise with depth (AC-5.5.2) ───────────
# v0.4.1 replaced the old "floor (minimum value) rises" clause with a hard, gate-checked
# invariant. Each negative test breaks exactly ONE branch (EV or gem) and asserts the
# AC-5.5.2 error fires — so the rule isn't passing for an unrelated reason.

func _ac552_errors(t: Dictionary) -> Array:
	# Subset of validator errors attributable to the depth-reward rule.
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("AC-5.5.2"):
			out.append(e)
	return out

func test_shipped_data_passes_depth_reward() -> void:
	# AC-5.5.2 (positive): the shipped bands DO have strictly-rising EV + gem probability.
	assert_array(_ac552_errors(_load_real_tables())).override_failure_message(
		"shipped depth_bands must satisfy AC-5.5.2 depth reward"
	).is_empty()

func test_validator_rejects_non_rising_expected_value() -> void:
	# AC-5.5.2: deeper band with LOWER expected value (but still-rising gem prob, to isolate
	# the EV branch). Deep = {ore_gold:3, rock:97} → gem 0.03 > surface 0.02, but EV 1.05 < 1.70.
	var t := _load_real_tables()
	(t["depth_bands"][1])["block_weights"] = {"ore_gold": 3, "rock": 97}
	var errs := _ac552_errors(t)
	assert_array(errs).override_failure_message(
		"validator must reject a deeper band with non-rising expected value (AC-5.5.2)"
	).is_not_empty()
	# The EV branch specifically must be the one that fired.
	var ev_hit := false
	for e in errs:
		if str(e).contains("expected ore value"):
			ev_hit = true
	assert_bool(ev_hit).override_failure_message(str(errs)).is_true()

func test_validator_rejects_non_rising_gem_probability() -> void:
	# AC-5.5.2: deeper band with LOWER gem probability (but rising EV, to isolate the gem
	# branch). Deep = {ore_copper:50, rock:50} → EV 5.0 > 1.70, but gem prob 0.0 < 0.02.
	var t := _load_real_tables()
	(t["depth_bands"][1])["block_weights"] = {"ore_copper": 50, "rock": 50}
	var errs := _ac552_errors(t)
	assert_array(errs).override_failure_message(
		"validator must reject a deeper band with non-rising gem probability (AC-5.5.2)"
	).is_not_empty()
	var gem_hit := false
	for e in errs:
		if str(e).contains("rare-gem probability"):
			gem_hit = true
	assert_bool(gem_hit).override_failure_message(str(errs)).is_true()

# ── Free unlimited charge (AC-5.4.3, AC-5.12.1) ─────────────────────────────

func test_shipped_data_has_exactly_one_free_charge() -> void:
	# AC-5.12.1: exactly one flagged free unlimited charge exists.
	var t := _load_real_tables()
	var free_count := 0
	for id in (t["explosives"] as Dictionary).keys():
		if bool((t["explosives"][id] as Dictionary).get("free", false)):
			free_count += 1
	assert_int(free_count).is_equal(1)

func test_validator_requires_a_free_charge() -> void:
	# AC-5.12.1: removing the free flag fails the gate (no free charge at all).
	var t := _load_real_tables()
	for id in (t["explosives"] as Dictionary).keys():
		(t["explosives"][id])["free"] = false
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_two_free_charges() -> void:
	# AC-5.12.1: more than one free charge is ambiguous → fail.
	var t := _load_real_tables()
	for id in (t["explosives"] as Dictionary).keys():
		(t["explosives"][id])["free"] = true
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_unsolvable_free_charge() -> void:
	# AC-5.5.5 / AC-5.4.6: the free charge breaks the floor "eventually / slowly", so the
	# no-stall condition is per-throw damage >= 1 (surviving blocks retain damage,
	# AC-5.2.7, no regen). The ONLY genuine stall is 0 integer damage per hit. Drive the
	# centre damage to 0 via a zero centre-falloff and confirm the gate rejects it.
	var t := _load_real_tables()
	for id in (t["explosives"] as Dictionary).keys():
		if bool((t["explosives"][id] as Dictionary).get("free", false)):
			# intensity * falloff[0] floors to 0 -> never damages a cell -> stall forever.
			var f: Array = ((t["explosives"][id] as Dictionary).get("blast_falloff") as Array).duplicate()
			f[0] = 0.0
			(t["explosives"][id])["blast_falloff"] = f
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_accepts_slow_free_charge_against_scaled_floor() -> void:
	# AC-5.4.6: a free charge that does NOT one-hit the deepest *scaled* floor (it is
	# weak/slow) is still VALID — it breaks the floor eventually. This guards against the
	# old one-hit semantics regressing back: the shipped free charge is far weaker than
	# the worst-case scaled floor HP, yet the gate must accept it.
	var t := _load_real_tables()
	var free_id := ""
	for id in (t["explosives"] as Dictionary).keys():
		if bool((t["explosives"][id] as Dictionary).get("free", false)):
			free_id = id
	assert_str(free_id).is_not_empty()
	# Premise check: the free charge's centre damage is genuinely far below the worst-case
	# scaled floor HP (so this test would FAIL under the old one-hit rule).
	var ex: Dictionary = t["explosives"][free_id]
	var centre_damage: int = int(float(ex.get("blast_intensity", 0)) * float((ex.get("blast_falloff") as Array)[0]))
	var b: Dictionary = t["balance"]
	var deep_band: Dictionary = (t["depth_bands"] as Array).back()
	var min_base_hp := 1 << 30
	for bid in (deep_band["block_weights"] as Dictionary).keys():
		var blk: Dictionary = t["block_types"][bid]
		if bool(blk.get("diggable", false)):
			min_base_hp = mini(min_base_hp, int(blk.get("max_hp", 0)))
	var depth_mult: float = 1.0 + float(int(deep_band["max_depth_cells"]) - 1) * float(b["depth_hp_mult_per_cell"])
	var scaled_floor: int = int(round(float(min_base_hp) * depth_mult * float(b["mine_hardness_mult_max"])))
	assert_int(centre_damage).override_failure_message(
		"test premise broken: free charge already one-hits the scaled floor (%d >= %d)" % [centre_damage, scaled_floor]
	).is_less(scaled_floor)
	# The gate must still accept the shipped data: slow-but-solvable is valid.
	assert_array(Validator.validate(t)).is_empty()

func test_validator_rejects_free_charge_in_pack_table() -> void:
	# Packs grant paid charges only; the free charge must never be poolable.
	var t := _load_real_tables()
	var free_id := ""
	for id in (t["explosives"] as Dictionary).keys():
		if bool((t["explosives"][id] as Dictionary).get("free", false)):
			free_id = id
	var first_pack: String = (t["packs"] as Dictionary).keys()[0]
	(t["packs"][first_pack]["weights"])[free_id] = 10
	assert_array(Validator.validate(t)).is_not_empty()

# ── Full explosive resource shape required (AC-5.4.1) ────────────────────────

func test_validator_requires_explosive_physics_fields() -> void:
	# AC-5.4.1: bounce/friction are part of the explosive resource and are consumed by the
	# live charge (charge.gd). A missing physics field used to fall back to a code default
	# (throw_params.gd) and pass the gate — now it must FAIL ("balance is data, never code").
	var t := _load_real_tables()
	var first_ex: String = (t["explosives"] as Dictionary).keys()[0]
	(t["explosives"][first_ex] as Dictionary).erase("bounce")
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must require 'bounce' on every explosive (AC-5.4.1)"
	).is_not_empty()

func test_validator_requires_explosive_tier_and_efficiency() -> void:
	# AC-5.4.1: tier and efficiency are named resource fields. Missing either must fail.
	var t := _load_real_tables()
	var first_ex: String = (t["explosives"] as Dictionary).keys()[0]
	(t["explosives"][first_ex] as Dictionary).erase("tier")
	assert_array(Validator.validate(t)).is_not_empty()
	var t2 := _load_real_tables()
	var ex2: String = (t2["explosives"] as Dictionary).keys()[0]
	(t2["explosives"][ex2] as Dictionary).erase("efficiency")
	assert_array(Validator.validate(t2)).is_not_empty()

func test_validator_requires_paid_charges_more_efficient_than_free() -> void:
	# AC-5.4.3: every paid charge SHALL be MORE efficient than the free charge (that is what
	# money buys). Make the free charge the MOST efficient and the gate must reject it — the
	# shipped ordering (free 1.0 < dynamite 2.0 < sticky 2.6 < heavy 3.4) is otherwise unpinned.
	var t := _load_real_tables()
	for id in (t["explosives"] as Dictionary).keys():
		if bool((t["explosives"][id] as Dictionary).get("free", false)):
			(t["explosives"][id])["efficiency"] = 9.9  # free now beats every paid charge
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a free charge more efficient than the paid charges (AC-5.4.3)"
	).is_not_empty()

func test_validator_rejects_free_charge_zero_worst_case_fuzz_damage() -> void:
	# AC-5.5.5: the no-stall check folds WORST-CASE fuzz. A free charge whose UNFUZZED centre
	# damage is >= 1 but whose worst fuzz roll floors to 0 would pass the old (unfuzzed) check
	# yet can deal 0 on a bad roll. With intensity 1, falloff[0] 1.0, fuzz 0.25 →
	# int(1*1*0.75)=0 → must be rejected now (was accepted before the fuzz fold).
	var t := _load_real_tables()
	for id in (t["explosives"] as Dictionary).keys():
		if bool((t["explosives"][id] as Dictionary).get("free", false)):
			(t["explosives"][id])["blast_intensity"] = 1
			(t["explosives"][id])["blast_falloff"] = [1.0, 0.3]  # keep length == radius+1
	# Sanity: unfuzzed centre damage int(1*1.0)=1 > 0, so ONLY the fuzz-fold catches this.
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a free charge whose worst-case fuzz damage is 0 (AC-5.5.5)"
	).is_not_empty()

# ── Falloff length == radius+1 single source of truth (AC-5.2.4) ────────────

func test_validator_requires_falloff_length_equals_radius_plus_one() -> void:
	# AC-5.2.4: falloff array length must be exactly blast_radius_cells+1.
	var t := _load_real_tables()
	var first_ex: String = (t["explosives"] as Dictionary).keys()[0]
	var r: int = int((t["explosives"][first_ex] as Dictionary).get("blast_radius_cells", 1))
	# Make falloff too long (r+2) — previously this was tolerated; now it must fail.
	var bad: Array = []
	for i in range(r + 2):
		bad.append(1.0)
	(t["explosives"][first_ex])["blast_falloff"] = bad
	assert_array(Validator.validate(t)).is_not_empty()

# ── Fuse-mode requires fuse_seconds (AC-5.4.1) ──────────────────────────────

func test_validator_requires_fuse_seconds_for_fuse_mode() -> void:
	# AC-5.4.1: a fuse_seconds detonation mode with fuse_seconds == 0 must fail.
	var t := _load_real_tables()
	for id in (t["explosives"] as Dictionary).keys():
		if (t["explosives"][id] as Dictionary).get("detonation_mode", "") == "fuse_seconds":
			(t["explosives"][id])["fuse_seconds"] = 0.0
	assert_array(Validator.validate(t)).is_not_empty()

# ── Balance keys present & sane (AC-5.5.4) ──────────────────────────────────

func test_validator_requires_run_seed() -> void:
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("run_seed")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_requires_starting_money() -> void:
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("starting_money")
	assert_array(Validator.validate(t)).is_not_empty()

# ── Relic prestige value is exactly 1 (AC-5.6.6 v0.5) ─────────────────────────

func test_shipped_relic_prestige_value_is_exactly_one() -> void:
	# AC-5.6.6: prestige is exactly 1 point per relic in v0.5.
	var t := _load_real_tables()
	assert_int(int((t["relics"] as Dictionary).get("prestige_value", 0))).is_equal(1)
	assert_array(Validator.validate(t)).is_empty()

func test_validator_rejects_relic_prestige_value_not_one() -> void:
	# AC-5.6.6: a relic prestige value other than 1 must fail the gate.
	var t := _load_real_tables()
	(t["relics"])["prestige_value"] = 5
	var errs: Array = Validator.validate(t)
	var hit := false
	for e in errs:
		if str(e).contains("prestige_value") and str(e).contains("exactly 1"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

# ── Bounded mine geometry (AC-5.1.1 v0.5) ─────────────────────────────────────

func test_validator_requires_bounded_mine_dimensions() -> void:
	# AC-5.1.1: the mine must declare positive width and depth in cells.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("mine_width_cells")
	assert_array(Validator.validate(t)).is_not_empty()
	var t2 := _load_real_tables()
	(t2["balance"] as Dictionary).erase("mine_height_cells")
	assert_array(Validator.validate(t2)).is_not_empty()

func test_validator_rejects_shaft_wider_than_mine() -> void:
	# AC-5.1.1: the shaft must fit inside the bounded mine width.
	var t := _load_real_tables()
	(t["balance"])["shaft_width_cells"] = int((t["balance"]).get("mine_width_cells", 0)) + 2
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_requires_body_caps() -> void:
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("active_body_cap_web")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_web_cap_above_desktop_cap() -> void:
	var t := _load_real_tables()
	(t["balance"])["active_body_cap_web"] = int((t["balance"] as Dictionary).get("active_body_cap_desktop", 0)) + 1
	assert_array(Validator.validate(t)).is_not_empty()

# ── Platform descent + camera tunables are data (U7 / AC-5.7.2, AC-5.7.3) ─────

func test_validator_requires_descent_max_steps() -> void:
	# AC-5.7.2: the descent depth cap is data — missing fails the gate.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("descent_max_steps")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_zero_descent_max_steps() -> void:
	# AC-5.7.2: 0 steps would make the platform never descend — reject.
	var t := _load_real_tables()
	(t["balance"])["descent_max_steps"] = 0
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_requires_descent_tween_seconds() -> void:
	# AC-5.7.2: the tween duration is data — missing fails the gate.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("descent_tween_seconds")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_zero_descent_tween_seconds() -> void:
	# AC-5.7.2: a 0-second tween is an instant snap — reject (descent must animate).
	var t := _load_real_tables()
	(t["balance"])["descent_tween_seconds"] = 0.0
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_requires_camera_lookahead() -> void:
	# AC-5.7.3: the camera anchor offset is data — missing fails the gate.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("camera_lookahead_cells")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_negative_camera_lookahead() -> void:
	# AC-5.7.3: a negative camera lookahead is nonsensical — reject.
	var t := _load_real_tables()
	(t["balance"])["camera_lookahead_cells"] = -1
	assert_array(Validator.validate(t)).is_not_empty()

# ── Portrait HUD layout tunables (AC-5.8.5) ──────────────────────────────────
# The touch-target floor + edge margin are data, gate-enforced. Each negative breaks one
# branch and asserts the AC-5.8.5 error fires (so the rule isn't passing for another reason).

func _ac585_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("AC-5.8.5"):
			out.append(e)
	return out

func test_shipped_data_passes_ui_layout() -> void:
	# AC-5.8.5 (positive): the shipped balance has a sane touch target + edge margin.
	assert_array(_ac585_errors(_load_real_tables())).override_failure_message(
		"shipped balance must satisfy the AC-5.8.5 UI-layout rule"
	).is_empty()

func test_validator_rejects_tiny_touch_target() -> void:
	# AC-5.8.5: a touch target below the ~44px floor is rejected (un-tappable on a phone).
	var t := _load_real_tables()
	(t["balance"])["ui_min_touch_target_px"] = 20
	assert_array(_ac585_errors(t)).is_not_empty()

func test_validator_requires_touch_target_present() -> void:
	# AC-5.8.5: a missing touch-target value fails the gate (balance is data, never a code default).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("ui_min_touch_target_px")
	assert_array(_ac585_errors(t)).is_not_empty()

func test_validator_rejects_negative_edge_margin() -> void:
	# AC-5.8.5: a negative HUD edge margin is nonsensical — reject.
	var t := _load_real_tables()
	(t["balance"])["ui_edge_margin_px"] = -5
	assert_array(_ac585_errors(t)).is_not_empty()

# ── HP-scaling multipliers present & positive (AC-5.2.1, AC-5.5.4) ───────────

func test_validator_requires_depth_hp_mult() -> void:
	# AC-5.2.1: the depth HP multiplier is data, required by the gate.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("depth_hp_mult_per_cell")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_requires_mine_hardness_mult() -> void:
	# AC-5.2.1: the per-mine hardness HP multiplier is data, required by the gate.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("mine_hardness_mult_max")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_nonpositive_hp_mults() -> void:
	# A zero/negative multiplier would zero out floor HP (or invert scaling) — reject.
	var t := _load_real_tables()
	(t["balance"])["depth_hp_mult_per_cell"] = 0.0
	assert_array(Validator.validate(t)).is_not_empty()
	var t2 := _load_real_tables()
	(t2["balance"])["mine_hardness_mult_max"] = 0.0
	assert_array(Validator.validate(t2)).is_not_empty()

# ── hardness is load-bearing: max_hp monotonic with hardness (AC-5.2.1) ──────

func test_validator_rejects_hp_inverted_against_hardness() -> void:
	# AC-5.2.1 / AC-5.1.5: `hardness` is wired into the HP contract — a HARDER block
	# may not have LESS base HP than a softer one. Make hard_rock (hardness 4) weaker
	# than dirt (hardness 1) and the gate must reject it (proves hardness governs HP,
	# i.e. the field is not vestigial).
	var t := _load_real_tables()
	(t["block_types"]["hard_rock"])["max_hp"] = 1
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a harder block with lower base HP"
	).is_not_empty()

func test_validator_rejects_negative_hardness() -> void:
	# hardness must be a non-negative ordinal.
	var t := _load_real_tables()
	(t["block_types"]["rock"])["hardness"] = -1
	assert_array(Validator.validate(t)).is_not_empty()

# ── Non-color block identity: palette + glyph (AC-5.10.2 / AC-5.10.3) ───────────
# Each negative test breaks exactly ONE thing and asserts the matching AC error fires, so
# the rule isn't passing for an unrelated reason (mirrors the depth-reward isolation pattern).

func _palette_errors(t: Dictionary, tag: String) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains(tag):
			out.append(e)
	return out

func test_shipped_data_passes_palette_and_glyph_rules() -> void:
	# AC-5.10.2/5.10.3 (positive): the shipped palette + glyphs satisfy the gate.
	var errs: Array = _palette_errors(_load_real_tables(), "AC-5.10")
	assert_array(errs).override_failure_message(str(errs)).is_empty()

func test_validator_requires_palette_table() -> void:
	var t := _load_real_tables()
	t.erase("palette")
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a missing palette.json"
	).is_not_empty()

func test_validator_rejects_palette_index_out_of_range() -> void:
	var t := _load_real_tables()
	(t["block_types"]["dirt"])["palette_index"] = 9999
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_invalid_hex_color() -> void:
	var t := _load_real_tables()
	(t["palette"]["colors"])[3] = "not-a-color"
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_duplicate_glyph() -> void:
	# AC-5.10.2: two diggable block types sharing a glyph is a non-color-identity failure.
	var t := _load_real_tables()
	var dirt_glyph: String = str((t["block_types"]["dirt"])["glyph"])
	(t["block_types"]["rock"])["glyph"] = dirt_glyph
	assert_array(_palette_errors(t, "AC-5.10.2")).override_failure_message(
		"validator must reject two diggable blocks with the same glyph"
	).is_not_empty()

func test_validator_rejects_none_glyph_on_diggable() -> void:
	# AC-5.10.2: a diggable block with glyph "none" would convey identity by color alone.
	var t := _load_real_tables()
	(t["block_types"]["rock"])["glyph"] = "none"
	assert_array(_palette_errors(t, "AC-5.10.2")).is_not_empty()

func test_validator_rejects_unknown_glyph_shape() -> void:
	var t := _load_real_tables()
	(t["block_types"]["rock"])["glyph"] = "spiral"
	assert_array(_palette_errors(t, "AC-5.10.2")).is_not_empty()

func test_validator_rejects_low_luminance_contrast() -> void:
	# AC-5.10.3: two diggable block colors that differ in hue but NOT luminance must fail
	# (a colorblind player couldn't tell them apart). Point dirt + rock at near-identical
	# luminance colors (different hue, ~same brightness).
	var t := _load_real_tables()
	(t["palette"]["colors"])[int((t["block_types"]["dirt"])["palette_index"])] = "#808060"
	(t["palette"]["colors"])[int((t["block_types"]["rock"])["palette_index"])] = "#608080"
	assert_array(_palette_errors(t, "AC-5.10.3")).override_failure_message(
		"validator must reject block colors that differ only in hue, not luminance"
	).is_not_empty()

# ── Settings defaults + ranges (AC-5.10.1) ──────────────────────────────────
# Each negative breaks exactly one settings rule and asserts an AC-5.10.1 error fires, so the
# gate that backs the accessibility-settings defaults has teeth.

func _settings_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("AC-5.10.1"):
			out.append(e)
	return out

func test_validator_requires_settings_block() -> void:
	# AC-5.10.1: the settings defaults are /data — a missing block fails the gate.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("settings")
	assert_array(_settings_errors(t)).is_not_empty()

func test_validator_rejects_out_of_range_default_volume() -> void:
	# AC-5.10.1: a default volume outside [0,1] would start the slider off its track.
	var t := _load_real_tables()
	(t["balance"]["settings"])["default_sfx_volume"] = 1.7
	assert_array(_settings_errors(t)).is_not_empty()

func test_validator_rejects_default_text_scale_outside_band() -> void:
	# AC-5.10.1 / AC-5.8.6: the default text scale must sit inside the [min,max] slider band.
	var t := _load_real_tables()
	(t["balance"]["settings"])["default_text_scale"] = 9.0
	assert_array(_settings_errors(t)).is_not_empty()

func test_validator_rejects_inverted_text_scale_band() -> void:
	# AC-5.10.1: max < min is an incoherent slider range.
	var t := _load_real_tables()
	(t["balance"]["settings"])["text_scale_min"] = 2.0
	(t["balance"]["settings"])["text_scale_max"] = 1.0
	assert_array(_settings_errors(t)).is_not_empty()
