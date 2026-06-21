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

func test_validator_catches_unknown_block_in_curve() -> void:
	# UNIT MAPGEN: an unknown block id in a curve anchor table fails the gate.
	var t := _load_real_tables()
	(t["depth_bands"]["surface_weights"])["does_not_exist"] = 5
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_catches_zero_weight_in_curve() -> void:
	# UNIT MAPGEN: a zero (or negative) weight in a curve anchor fails the gate.
	var t := _load_real_tables()
	var first_block: String = (t["depth_bands"]["surface_weights"] as Dictionary).keys()[0]
	(t["depth_bands"]["surface_weights"])[first_block] = 0
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_catches_blast_radius_over_cap() -> void:
	var t := _load_real_tables()
	var first_ex: String = (t["explosives"] as Dictionary).keys()[0]
	(t["explosives"][first_ex])["blast_radius_cells"] = 999
	assert_array(Validator.validate(t)).is_not_empty()

# ── Depth reward: EV + gem probability rise with depth, then freeze (AC-5.5.2) ──
# UNIT MAPGEN: the depth_bands curve must keep EV + gem-prob STRICTLY rising from the surface
# anchor to the cap anchor, then FROZEN below the cap (bounded richness). Each negative test
# breaks exactly ONE branch (EV / gem / freeze) and asserts the AC-5.5.2 error fires — so the
# rule isn't passing for an unrelated reason. The validator samples the continuous curve.

func _ac552_errors(t: Dictionary) -> Array:
	# Subset of validator errors attributable to the depth-reward rule.
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("AC-5.5.2"):
			out.append(e)
	return out

func test_shipped_data_passes_depth_reward() -> void:
	# AC-5.5.2 (positive): the shipped curve DOES have strictly-rising EV + gem probability.
	assert_array(_ac552_errors(_load_real_tables())).override_failure_message(
		"shipped depth_bands curve must satisfy AC-5.5.2 depth reward"
	).is_empty()

func test_validator_rejects_non_rising_expected_value() -> void:
	# AC-5.5.2: if both filler and overlay odds are flattened, the combined EV no longer
	# strictly rises with depth. This mutates the real reward layer (ore_overlays), not the
	# old filler-only curve, so it verifies the continuous-gen invariant.
	var t := _load_real_tables()
	(t["depth_bands"])["cap_weights"] = (t["depth_bands"]["surface_weights"] as Dictionary).duplicate(true)
	for oid in (t["ore_overlays"]["ores"] as Dictionary).keys():
		var ore: Dictionary = t["ore_overlays"]["ores"][oid]
		ore["threshold_deep"] = ore["threshold_shallow"]
	var errs := _ac552_errors(t)
	assert_array(errs).override_failure_message(
		"validator must reject a non-rising combined expected value (AC-5.5.2)"
	).is_not_empty()
	# The EV branch specifically must be the one that fired.
	var ev_hit := false
	for e in errs:
		if str(e).contains("expected ore value"):
			ev_hit = true
	assert_bool(ev_hit).override_failure_message(str(errs)).is_true()

func test_validator_rejects_non_rising_gem_probability() -> void:
	# AC-5.5.2: flatten only the max-value ore (diamond) so rare-gem probability no
	# longer strictly rises, while the rest of the overlay can still make EV richer.
	var t := _load_real_tables()
	var diamond: Dictionary = t["ore_overlays"]["ores"]["diamond"]
	diamond["threshold_deep"] = diamond["threshold_shallow"]
	var errs := _ac552_errors(t)
	assert_array(errs).override_failure_message(
		"validator must reject non-rising rare-gem probability (AC-5.5.2)"
	).is_not_empty()
	var gem_hit := false
	for e in errs:
		if str(e).contains("rare-gem probability"):
			gem_hit = true
	assert_bool(gem_hit).override_failure_message(str(errs)).is_true()

# ── Free unlimited charge (AC-5.4.3, AC-5.12.1) ─────────────────────────────

func test_shipped_data_has_basic_charge() -> void:
	# AC-5.4.3 (v0.7): the basic safety-net charge ('free_charge') exists in the explosives table.
	var t := _load_real_tables()
	assert_bool((t["explosives"] as Dictionary).has("free_charge")).is_true()

func test_validator_requires_basic_charge() -> void:
	# AC-5.4.3 (v0.7): removing the basic charge from explosives fails the gate.
	var t := _load_real_tables()
	(t["explosives"] as Dictionary).erase("free_charge")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_unsolvable_basic_charge() -> void:
	# AC-5.5.5 / AC-5.4.6: the basic charge breaks the floor "eventually / slowly", so the
	# no-stall condition is per-throw damage >= 1. Zero the centre falloff → stall.
	var t := _load_real_tables()
	var f: Array = ((t["explosives"]["free_charge"] as Dictionary).get("blast_falloff") as Array).duplicate()
	f[0] = 0.0
	(t["explosives"]["free_charge"])["blast_falloff"] = f
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_accepts_slow_basic_charge_against_scaled_floor() -> void:
	# AC-5.4.6: a basic charge that does NOT one-hit the deepest *scaled* floor (it is
	# weak/slow) is still VALID — it breaks the floor eventually.
	var t := _load_real_tables()
	var free_id := "free_charge"
	assert_bool((t["explosives"] as Dictionary).has(free_id)).is_true()
	var ex: Dictionary = t["explosives"][free_id]
	var centre_damage: int = int(float(ex.get("blast_intensity", 0)) * float((ex.get("blast_falloff") as Array)[0]))
	var b: Dictionary = t["balance"]
	var cap_weights: Dictionary = t["depth_bands"]["cap_weights"]
	var min_base_hp := 1 << 30
	for bid in cap_weights.keys():
		var blk: Dictionary = t["block_types"][bid]
		if bool(blk.get("diggable", false)):
			min_base_hp = mini(min_base_hp, int(blk.get("max_hp", 0)))
	var depth_mult: float = float(b["max_depth_hp_mult"])
	var scaled_floor: int = int(round(float(min_base_hp) * depth_mult * float(b["mine_hardness_mult_max"])))
	assert_int(centre_damage).override_failure_message(
		"test premise broken: free charge already one-hits the scaled floor (%d >= %d)" % [centre_damage, scaled_floor]
	).is_less(scaled_floor)
	# The gate must still accept the shipped data: slow-but-solvable is valid.
	assert_array(Validator.validate(t)).is_empty()

func test_validator_rejects_basic_charge_in_paid_pack() -> void:
	# v0.7: the basic charge may appear in price-0 packs (starter/basic) but NOT in paid packs.
	var t := _load_real_tables()
	(t["packs"]["basic"]["weights"])["free_charge"] = 10  # 'basic' is a paid pack (price 50)
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_accepts_basic_charge_in_free_pack() -> void:
	# v0.7: the basic charge in a price-0 pack (basic_pack) is valid (the safety net).
	var t := _load_real_tables()
	(t["packs"]["basic_pack"]["weights"])["free_charge"] = 100  # already there, but assert it passes
	assert_array(Validator.validate(t)).is_empty()

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
	# AC-5.4.3: every paid charge SHALL be MORE efficient than the basic charge. Make the
	# basic charge the MOST efficient and the gate must reject it.
	var t := _load_real_tables()
	(t["explosives"]["free_charge"])["efficiency"] = 9.9  # basic now beats every paid charge
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a basic charge more efficient than the paid charges (AC-5.4.3)"
	).is_not_empty()

func test_validator_rejects_basic_charge_zero_worst_case_fuzz_damage() -> void:
	# AC-5.5.5: the no-stall check folds WORST-CASE fuzz. A free charge whose UNFUZZED centre
	# damage is >= 1 but whose worst fuzz roll floors to 0 would pass the old (unfuzzed) check
	# yet can deal 0 on a bad roll. With intensity 1, falloff[0] 1.0, fuzz 0.25 →
	# int(1*1*0.75)=0 → must be rejected now (was accepted before the fuzz fold).
	var t := _load_real_tables()
	(t["explosives"]["free_charge"])["blast_intensity"] = 1
	(t["explosives"]["free_charge"])["blast_falloff"] = [1.0, 0.3]  # keep length == radius+1
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

func test_validator_requires_ui_selector_tunables() -> void:
	# AC-5.8.5 / AC-5.10.1: selector dimensions and motion timings are /data and validated.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("ui_selector")
	assert_array(Validator.validate(t)).is_not_empty()
	var t2 := _load_real_tables()
	(t2["balance"]["ui_selector"])["slot_width_px"] = 32
	assert_array(Validator.validate(t2)).is_not_empty()

func test_validator_requires_ui_crate_tunables() -> void:
	# AC-5.10.1 / AC-5.13.1: crate reveal timing, hit-stop, and particle caps stay data-driven.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("ui_crate")
	assert_array(Validator.validate(t)).is_not_empty()
	var t2 := _load_real_tables()
	(t2["balance"]["ui_crate"])["rare_hitstop_seconds"] = 0.5
	assert_array(Validator.validate(t2)).is_not_empty()

# ── on_rest charge motion gate (the "sticky bomb explodes instantly" fix; AC-5.4.2) ──────────

func test_validator_requires_charge_motion_gate() -> void:
	# AC-5.4.2: the on_rest charge motion gate (charge_min_airtime_seconds / charge_min_travel_px)
	# is a /data tunable — removing it fails the gate (balance is data, never a code literal).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("charge_min_airtime_seconds")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_zero_charge_min_airtime() -> void:
	# AC-5.4.2: a 0 airtime gate re-opens the frame-0 instant-detonation bug; the gate must reject it.
	var t := _load_real_tables()
	(t["balance"])["charge_min_airtime_seconds"] = 0.0
	var errs: Array = Validator.validate(t)
	var hit := false
	for e in errs:
		if str(e).contains("charge_min_airtime_seconds") and str(e).contains("> 0"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

func test_validator_rejects_airtime_gate_above_smallest_sticky_fuse() -> void:
	# AC-5.4.2: the motion gate must sit BELOW the smallest sticky on_rest fuse_seconds so it can
	# never delay a real stick-fuse. An airtime >= every sticky fuse must fail the gate.
	var t := _load_real_tables()
	(t["balance"])["charge_min_airtime_seconds"] = 99.0
	var errs: Array = Validator.validate(t)
	var hit := false
	for e in errs:
		if str(e).contains("charge_min_airtime_seconds") and str(e).contains("stick-fuse"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

func test_validator_rejects_negative_charge_min_travel() -> void:
	# AC-5.4.2: the travel floor must be >= 0 (0 = airtime-only gating, valid; negative is meaningless).
	var t := _load_real_tables()
	(t["balance"])["charge_min_travel_px"] = -1.0
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

# ── Shaft Engineering money upgrade (Phase C, AC-5.12.x) ──────────────────────

func test_shipped_shaft_engineering_upgrade_is_valid() -> void:
	# The shipped data declares a Shaft Engineering money upgrade that the gate accepts.
	var t := _load_real_tables()
	assert_bool((t["upgrades"] as Dictionary).has("shaft_engineering")).is_true()
	assert_array(Validator.validate(t)).is_empty()

func test_validator_rejects_money_upgrade_without_price() -> void:
	# A money upgrade must declare a positive money price.
	var t := _load_real_tables()
	(t["upgrades"]["shaft_engineering"]).erase("price")
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_shaft_width_reduction_with_positive_magnitude() -> void:
	# shaft_width_reduction is a REDUCTION — a positive magnitude (a widening) is invalid.
	var t := _load_real_tables()
	(t["upgrades"]["shaft_engineering"])["magnitude"] = 2
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_shaft_reduction_below_platform_width() -> void:
	# The fully-bought reduction may not narrow the shaft below the platform deck.
	var t := _load_real_tables()
	(t["upgrades"]["shaft_engineering"])["magnitude"] = -100
	var errs: Array = Validator.validate(t)
	var hit := false
	for e in errs:
		if str(e).contains("shaft_engineering") and str(e).contains("platform width"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

# ── Mines: surface + deeper money-gated mines (Deep Mine, AC-5.12.x) ───────────
# _check_mines enforces the no-lose, money-per-dig model: at least one free starting mine, a valid
# tint hex, a hardness bounded by the same HP-scaling cap the formula honors, and required multipliers.
# The shipped data is asserted valid; each negative mutates a COPY of the real tables, breaks exactly
# ONE rule, and asserts the matching error fires (so the gate isn't passing for an unrelated reason).

func _mines_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).begins_with("mines"):
			out.append(e)
	return out

func test_shipped_mines_table_is_valid() -> void:
	# Positive: the shipped surface + deep mines satisfy _check_mines.
	var t := _load_real_tables()
	assert_bool((t["mines"] as Dictionary).has("surface")).is_true()
	assert_bool((t["mines"] as Dictionary).has("deep")).is_true()
	assert_array(_mines_errors(t)).override_failure_message(
		"shipped mines.json must satisfy _check_mines"
	).is_empty()

func test_validator_rejects_mines_with_no_free_mine() -> void:
	# (a) Every mine costing money to access leaves the player with no free starting mine — that
	# breaks the no-lose model (a broke player could never dig). Give the free 'surface' mine a cost.
	var t := _load_real_tables()
	(t["mines"]["surface"])["access_cost"] = 50
	var errs := _mines_errors(t)
	var hit := false
	for e in errs:
		if str(e).contains("at least one mine must be free"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

func test_validator_rejects_invalid_mine_tile_tint() -> void:
	# (b) tile_tint is the terrain modulate hex — a typo'd value would render magenta/disable the
	# tint silently. A non-hex string must fail the gate.
	var t := _load_real_tables()
	(t["mines"]["deep"])["tile_tint"] = "not-a-hex"
	var errs := _mines_errors(t)
	var hit := false
	for e in errs:
		if str(e).contains("tile_tint") and str(e).contains("valid hex"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

func test_validator_rejects_mine_hardness_above_scaling_cap() -> void:
	# (c) A mine's hardness_mult feeds the HP scaling formula; the data gate's worst-case no-stall
	# check is bounded by balance.mine_hardness_mult_max. A mine harder than that cap would let the
	# scaled floor HP exceed the bound the free-charge solvability proof relies on — reject it.
	var t := _load_real_tables()
	var cap: float = float((t["balance"] as Dictionary).get("mine_hardness_mult_max", 99.0))
	(t["mines"]["deep"])["hardness_mult"] = cap + 1.0
	var errs := _mines_errors(t)
	var hit := false
	for e in errs:
		if str(e).contains("hardness_mult") and str(e).contains("mine_hardness_mult_max"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

func test_validator_rejects_mine_missing_ore_value_mult() -> void:
	# (d) ore_value_mult is the per-mine credit multiplier — money the deeper mine pays. A missing
	# value would silently read 0 (no ore pays out) and is a required field; the gate must reject it.
	var t := _load_real_tables()
	(t["mines"]["deep"] as Dictionary).erase("ore_value_mult")
	var errs := _mines_errors(t)
	var hit := false
	for e in errs:
		if str(e).contains("ore_value_mult"):
			hit = true
	assert_bool(hit).override_failure_message(str(errs)).is_true()

# ── Mine geometry (AC-5.1.1; UNIT MAPGEN infinite descent) ────────────────────

func test_validator_requires_mine_geometry_keys() -> void:
	# The mine must declare a positive finite width and a present height key (0 = infinite).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("mine_width_cells")
	assert_array(Validator.validate(t)).is_not_empty()
	var t2 := _load_real_tables()
	(t2["balance"] as Dictionary).erase("mine_height_cells")
	assert_array(Validator.validate(t2)).is_not_empty()

func test_validator_accepts_infinite_mine_height_sentinel() -> void:
	# UNIT MAPGEN: mine_height_cells == 0 is the INFINITE-shaft sentinel and is VALID. The
	# shipped data uses it, so the gate must accept 0 (a negative value is invalid).
	var t := _load_real_tables()
	assert_int(int((t["balance"] as Dictionary).get("mine_height_cells"))).is_equal(0)
	assert_array(Validator.validate(t)).is_empty()
	# A negative height is invalid.
	var t2 := _load_real_tables()
	(t2["balance"] as Dictionary)["mine_height_cells"] = -5
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

# ── Money-juice tunables (v0.5 arcade pass) ──────────────────────────────────
# The rolling-count-up duration + flying-coin timings/cap/arc are /data, gate-enforced via
# _check_ui. Each negative breaks one branch — a typo'd key that silently read 0 would snap with no
# animation (or suppress all coins), so the gate must reject out-of-band/missing values.

func test_shipped_data_passes_money_juice_keys() -> void:
	# Positive: the shipped balance satisfies the money-juice rules (present + in band).
	var errors: Array = []
	for e in Validator.validate(_load_real_tables()):
		if str(e).contains("money juice"):
			errors.append(e)
	assert_array(errors).override_failure_message(
		"shipped balance must satisfy the v0.5 money-juice rules"
	).is_empty()

func test_validator_requires_ui_money_roll_seconds() -> void:
	# Mutation #1: a missing roll duration fails the gate (no code-side default for the count-up).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("ui_money_roll_seconds")
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a balance missing 'ui_money_roll_seconds'"
	).is_not_empty()

func test_validator_rejects_zero_money_roll_seconds() -> void:
	# Mutation #2: a 0-second roll is incoherent (it would snap with no animation) — strict-min > 0.
	var t := _load_real_tables()
	(t["balance"])["ui_money_roll_seconds"] = 0.0
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject ui_money_roll_seconds == 0"
	).is_not_empty()

func test_validator_rejects_zero_coin_fly_seconds() -> void:
	# Mutation #3: a 0-second coin flight is incoherent — the coin must travel to the wallet.
	var t := _load_real_tables()
	(t["balance"])["coin_fly_seconds"] = 0.0
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_zero_coin_cap() -> void:
	# Mutation #4: coin_max_active is a cap (>= 1); a 0 cap would suppress every flying coin. Reject.
	var t := _load_real_tables()
	(t["balance"])["coin_max_active"] = 0
	assert_array(Validator.validate(t)).is_not_empty()

func test_validator_rejects_negative_coin_arc_height() -> void:
	# Mutation #5: a negative arc apex is nonsensical (>= 0 — a flat arc is allowed, a negative isn't).
	var t := _load_real_tables()
	(t["balance"])["coin_arc_height_px"] = -10
	assert_array(Validator.validate(t)).is_not_empty()

# ── UI/HUD-animation tunables present & in-band (v0.5 arcade pass) ──────────────
# The modal pop-in/out durations, the relic/prestige screen-flash (alpha + fade), and the tray
# select-pop duration are validated by _check_ui. A typo'd key that silently read 0 would snap with
# no animation; an out-of-band flash alpha could blow out to a full-white strobe — the gate rejects
# both. (>= 2 keys mutation-verified per the cluster's gate_risk; positive + negatives below.)

func test_shipped_data_passes_ui_animation_keys() -> void:
	# Positive: the shipped balance satisfies the UI-animation rules (present + in band).
	var errors: Array = []
	for e in Validator.validate(_load_real_tables()):
		if str(e).contains("UI animation"):
			errors.append(e)
	assert_array(errors).override_failure_message(
		"shipped balance must satisfy the v0.5 UI-animation rules"
	).is_empty()

func test_validator_requires_ui_panel_in_seconds() -> void:
	# Mutation: a missing modal scale-in duration fails the gate (no code-side default for the pop-in).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("ui_panel_in_seconds")
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a balance missing 'ui_panel_in_seconds'"
	).is_not_empty()

func test_validator_rejects_zero_ui_tray_pop_seconds() -> void:
	# Mutation: a 0-second tray pop is incoherent (it would snap with no animation) — strict-min > 0.
	var t := _load_real_tables()
	(t["balance"])["ui_tray_pop_seconds"] = 0.0
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject ui_tray_pop_seconds == 0"
	).is_not_empty()

func test_validator_rejects_out_of_band_ui_flash_alpha() -> void:
	# Mutation: the flash peak alpha is a11y-capped to [0,1]; an alpha > 1 (an opaque full-screen
	# strobe — a photosensitivity hazard, AC-5.10.4) must be rejected at the gate, not the player.
	var t := _load_real_tables()
	(t["balance"])["ui_flash_alpha"] = 1.5
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject ui_flash_alpha out of [0,1]"
	).is_not_empty()

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

# ── Non-color block identity: palette + luminance (AC-5.10.2 / AC-5.10.3) ───────
# The v0.5 arcade pass REMOVED the debug-grid glyph overlay; the SOLE machine-checked
# enforcement of non-color identity is now the luminance-delta loop (every two diggable
# block colors must differ in brightness, not just hue). Each negative breaks exactly ONE
# thing and asserts the matching AC error fires (mirrors the depth-reward isolation pattern).

func _palette_errors(t: Dictionary, tag: String) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains(tag):
			out.append(e)
	return out

func test_shipped_data_passes_palette_rules() -> void:
	# AC-5.10.2/5.10.3 (positive): the shipped palette satisfies the gate (valid hex, indices
	# in range, every block pair luminance-contrasting).
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

func test_validator_rejects_equal_palette_index_luminance_collision() -> void:
	# AC-5.10.3 (the KEPT identity gate after glyph removal): two diggable block types pointed at
	# the SAME palette_index share one color → zero luminance delta → the gate must reject it.
	# This proves the luminance-delta loop is the live non-color-identity enforcement.
	var t := _load_real_tables()
	(t["block_types"]["ore_copper"])["palette_index"] = int((t["block_types"]["rock"])["palette_index"])
	assert_array(_palette_errors(t, "AC-5.10.3")).override_failure_message(
		"validator must reject two diggable blocks pointed at the same palette_index (no luminance contrast)"
	).is_not_empty()

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

func test_validator_rejects_missing_block_tiles_coord() -> void:
	# Scene↔data coupling: art_sources.terrain.block_tiles must carry a tile coordinate for
	# every diggable block (the BlockLayer samples the linked pixel-art tileset per type). A
	# missing coordinate would leave a block type unmapped — the gate must reject it.
	var t := _load_real_tables()
	(t["art_sources"]["terrain"]["block_tiles"] as Dictionary).erase("rock")
	assert_array(Validator.validate(t)).override_failure_message(
		"validator must reject a diggable block missing its block_tiles coordinate"
	).is_not_empty()

func _art_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("art_sources"):
			out.append(e)
	return out

func test_validator_accepts_block_tiles_variant_list() -> void:
	# v0.5 tile variation: block_tiles accepts EITHER a single coord [x, y] OR a non-empty list
	# of coords [[x, y], ...]. The shipped data uses the list form — it must pass cleanly, and the
	# backward-compatible single-coord form (set on rock here) must also be accepted.
	var t := _load_real_tables()
	(t["art_sources"]["terrain"]["block_tiles"] as Dictionary)["rock"] = [6, 1]
	assert_array(_art_errors(t)).override_failure_message(
		"validator must accept both the single [x,y] and the list [[x,y],...] block_tiles forms"
	).is_empty()

func test_validator_rejects_empty_block_tiles_variant_list() -> void:
	# An empty variant list leaves a type with no tile to sample — the gate must reject it (a
	# typo'd "[]" must not silently fall through to a magenta/zero tile).
	var t := _load_real_tables()
	(t["art_sources"]["terrain"]["block_tiles"] as Dictionary)["dirt"] = []
	assert_array(_art_errors(t)).override_failure_message(
		"validator must reject an empty block_tiles variant list"
	).is_not_empty()

func test_validator_rejects_malformed_block_tiles_variant() -> void:
	# A variant element that is not a 2-element [x,y] pair is malformed — reject (catches a list
	# of bare ints like [13, 12, 14] that an author might write expecting per-cell columns).
	var t := _load_real_tables()
	(t["art_sources"]["terrain"]["block_tiles"] as Dictionary)["dirt"] = [[13, 0], [12]]
	assert_array(_art_errors(t)).override_failure_message(
		"validator must reject a block_tiles variant that is not an [x,y] pair"
	).is_not_empty()

# ── Headlamp deep-terrain tint (v0.5 arcade pass) ───────────────────────────────
# The light mask fades toward a cool tint instead of pure black; the hex is /data, so a missing
# or invalid value must fail the gate (else the shader reads magenta / silently disables the cast).

func _light_tint_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("light_dark_tint"):
			out.append(e)
	return out

func test_shipped_data_passes_light_dark_tint() -> void:
	assert_array(_light_tint_errors(_load_real_tables())).override_failure_message(
		"shipped balance.light_dark_tint must satisfy the gate"
	).is_empty()

func test_validator_requires_light_dark_tint() -> void:
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("light_dark_tint")
	assert_array(_light_tint_errors(t)).override_failure_message(
		"validator must require light_dark_tint (no code-side headlamp tint default)"
	).is_not_empty()

func test_validator_rejects_invalid_light_dark_tint() -> void:
	var t := _load_real_tables()
	(t["balance"] as Dictionary)["light_dark_tint"] = "not-a-hex"
	assert_array(_light_tint_errors(t)).override_failure_message(
		"validator must reject an invalid light_dark_tint hex"
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

func test_validator_requires_elevator_side_default() -> void:
	# AC-5.10.1 (D2 controls): the elevator-side default is /data — a missing one fails the gate.
	var t := _load_real_tables()
	(t["balance"]["settings"] as Dictionary).erase("default_elevator_side")
	assert_array(_settings_errors(t)).is_not_empty()

func test_validator_rejects_invalid_elevator_side() -> void:
	# AC-5.10.1 (D2 controls): the side must be exactly "left" or "right".
	var t := _load_real_tables()
	(t["balance"]["settings"])["default_elevator_side"] = "middle"
	assert_array(_settings_errors(t)).is_not_empty()

# ── VFX feel table (v0.5 arcade pass) ────────────────────────────────────────
# The arcade-juice magnitudes are /data tunables; _check_vfx enumerates + range-checks every
# key so a typo'd key can't silently read 0 (disabling a cue or soft-locking the hit-stop).
# Each negative asserts a balance.vfx error fires.

func _vfx_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("balance.vfx") or str(e).contains("'vfx'"):
			out.append(e)
	return out

func test_shipped_data_passes_vfx_rules() -> void:
	# Positive: the shipped vfx table satisfies the gate.
	assert_array(_vfx_errors(_load_real_tables())).override_failure_message(
		"shipped balance.vfx must satisfy _check_vfx"
	).is_empty()

func test_validator_requires_vfx_table() -> void:
	# The vfx feel table is /data — a missing block fails the gate (no code-side feel defaults).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("vfx")
	assert_array(_vfx_errors(t)).is_not_empty()

func test_validator_requires_each_vfx_key() -> void:
	# Mutation-verified key #1: a MISSING required key fails the gate (catches a typo'd rename).
	var t := _load_real_tables()
	(t["balance"]["vfx"] as Dictionary).erase("hitstop_min_cells")
	assert_array(_vfx_errors(t)).override_failure_message(
		"validator must reject a vfx table missing 'hitstop_min_cells'"
	).is_not_empty()

func test_validator_rejects_zero_hitstop_seconds() -> void:
	# Mutation-verified key #2: a 0-second freeze is incoherent (a strict-min duration). The
	# hit-stop bounds are load-bearing — an out-of-band value here would mis-time/soft-lock the freeze.
	var t := _load_real_tables()
	(t["balance"]["vfx"])["hitstop_seconds"] = 0.0
	assert_array(_vfx_errors(t)).override_failure_message(
		"validator must reject vfx.hitstop_seconds == 0"
	).is_not_empty()

func test_validator_rejects_out_of_band_hitstop_scale() -> void:
	# Mutation-verified key #3: hitstop_scale must be in (0,1] — Engine.time_scale during the
	# freeze. A value > 1 would speed up time, not freeze; reject it.
	var t := _load_real_tables()
	(t["balance"]["vfx"])["hitstop_scale"] = 1.5
	assert_array(_vfx_errors(t)).override_failure_message(
		"validator must reject vfx.hitstop_scale > 1"
	).is_not_empty()

func test_validator_rejects_out_of_band_zoom_punch() -> void:
	# zoom_punch is clamped [0,0.3]; a larger kick would zoom too hard. Reject above the band.
	var t := _load_real_tables()
	(t["balance"]["vfx"])["zoom_punch"] = 0.9
	assert_array(_vfx_errors(t)).is_not_empty()

func test_validator_rejects_zero_debris_cap() -> void:
	# max_debris_emitters is a cap (>= 1); a 0 cap would suppress all debris. Reject.
	var t := _load_real_tables()
	(t["balance"]["vfx"])["max_debris_emitters"] = 0
	assert_array(_vfx_errors(t)).is_not_empty()

# ── Screen-transition table (reveal veil + relic toast timing) ───────────────
# Every transition duration is a /data tunable; the gate enforces presence + bounds so a
# typo can't strand the screen behind an opaque veil or pin the banner on-screen forever.

func _ui_transition_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("ui_transition"):
			out.append(e)
	return out

func test_shipped_data_passes_ui_transition_rules() -> void:
	# Positive: the shipped ui_transition block satisfies the gate.
	assert_array(_ui_transition_errors(_load_real_tables())).override_failure_message(
		"shipped balance.ui_transition must satisfy _check_ui_transition"
	).is_empty()

func test_validator_requires_ui_transition_block() -> void:
	# The transition timing is /data — a missing block fails the gate (no code-side defaults).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("ui_transition")
	assert_array(_ui_transition_errors(t)).is_not_empty()

func test_validator_requires_each_ui_transition_key() -> void:
	# Mutation-verified: a MISSING required key fails the gate (catches a typo'd rename).
	var t := _load_real_tables()
	(t["balance"]["ui_transition"] as Dictionary).erase("toast_hold_seconds")
	assert_array(_ui_transition_errors(t)).override_failure_message(
		"validator must reject a ui_transition table missing 'toast_hold_seconds'"
	).is_not_empty()

func test_validator_rejects_zero_reveal_duration() -> void:
	# A 0-second reveal is a strict-min duration (it would disable the fade / divide-by-zero). Reject.
	var t := _load_real_tables()
	(t["balance"]["ui_transition"])["dig_reveal_seconds"] = 0.0
	assert_array(_ui_transition_errors(t)).override_failure_message(
		"validator must reject ui_transition.dig_reveal_seconds == 0"
	).is_not_empty()

func test_validator_rejects_runaway_transition_duration() -> void:
	# Durations are capped (<= 4s) so a typo can't strand the screen behind black / a stuck banner.
	var t := _load_real_tables()
	(t["balance"]["ui_transition"])["boot_reveal_seconds"] = 99.0
	assert_array(_ui_transition_errors(t)).override_failure_message(
		"validator must reject an absurdly long ui_transition duration"
	).is_not_empty()

func test_validator_allows_zero_hold_beat() -> void:
	# The HOLD phases may be 0 (a beat-less fade is valid) — a 0 hold must NOT fail the gate. This
	# covers ALL three holds (dig/boot/toast); toast_hold in particular is the instant-flash banner case.
	for hold_key in ["dig_hold_seconds", "boot_hold_seconds", "toast_hold_seconds"]:
		var t := _load_real_tables()
		(t["balance"]["ui_transition"])[hold_key] = 0.0
		assert_array(_ui_transition_errors(t)).override_failure_message(
			"validator must accept a 0 '%s' beat (beat-less fade is valid)" % hold_key
		).is_empty()

# ── Launch & control-feel table (v0.5 arcade pass) ───────────────────────────
# The throw-feel magnitudes (button squash/pop, animated aim line, platform recoil, muzzle flash)
# are /data tunables; _check_feel enumerates + range-checks every key so a typo'd key can't silently
# read 0 (which would disable a cue). Each negative asserts a balance.feel error fires (mirrors the
# _vfx_errors isolation pattern). Covers >= 2 keys per the cluster's data-rule contract.

func _feel_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("balance.feel") or str(e).contains("'feel'"):
			out.append(e)
	return out

func test_shipped_data_passes_feel_rules() -> void:
	# Positive: the shipped feel table satisfies the gate.
	assert_array(_feel_errors(_load_real_tables())).override_failure_message(
		"shipped balance.feel must satisfy _check_feel"
	).is_empty()

func test_validator_requires_feel_table() -> void:
	# The feel table is /data — a missing block fails the gate (no code-side feel defaults).
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("feel")
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject a missing balance.feel table"
	).is_not_empty()

func test_validator_requires_each_feel_key() -> void:
	# Mutation-verified key #1: a MISSING required key fails the gate (catches a typo'd rename).
	var t := _load_real_tables()
	(t["balance"]["feel"] as Dictionary).erase("recoil_px")
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject a feel table missing 'recoil_px'"
	).is_not_empty()

func test_validator_rejects_out_of_band_throw_button_squash() -> void:
	# Mutation-verified key #2: throw_button_squash is a (0,1] compress fraction. A value > 1 would
	# INFLATE the button on press (not squash it); reject above the band.
	var t := _load_real_tables()
	(t["balance"]["feel"])["throw_button_squash"] = 1.4
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject feel.throw_button_squash > 1"
	).is_not_empty()

func test_validator_rejects_zero_throw_button_squash() -> void:
	# Mutation-verified key #3: a 0 squash would collapse the button to nothing on press. The band
	# is strictly > 0; reject zero.
	var t := _load_real_tables()
	(t["balance"]["feel"])["throw_button_squash"] = 0.0
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject feel.throw_button_squash == 0"
	).is_not_empty()

func test_validator_rejects_zero_pop_seconds() -> void:
	# Mutation-verified key #4: the squash+pop duration is strictly > 0 (a 0 would snap with no
	# animation). Reject zero.
	var t := _load_real_tables()
	(t["balance"]["feel"])["throw_button_pop_seconds"] = 0.0
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject feel.throw_button_pop_seconds == 0"
	).is_not_empty()

func test_validator_rejects_negative_recoil_px() -> void:
	# Mutation-verified key #5: recoil distance is >= 0 (0 = no kick is fine; negative is nonsensical).
	var t := _load_real_tables()
	(t["balance"]["feel"])["recoil_px"] = -3.0
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject a negative feel.recoil_px"
	).is_not_empty()

func test_validator_rejects_aim_march_aim_mult_below_one() -> void:
	# v0.5 aim-indicator pass: the march SPEEDS UP while aiming, so the multiplier must be >= 1.
	# A value < 1 would slow the march while turning — reject it.
	var t := _load_real_tables()
	(t["balance"]["feel"])["aim_march_aim_mult"] = 0.7
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject feel.aim_march_aim_mult < 1"
	).is_not_empty()

func test_validator_rejects_zero_aim_march_ease_rate() -> void:
	# v0.5 aim-indicator pass: the speed-up eases in/out at aim_march_ease_rate per second. A
	# 0/negative rate has no ease budget — reject it.
	var t := _load_real_tables()
	(t["balance"]["feel"])["aim_march_ease_rate"] = 0.0
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject feel.aim_march_ease_rate == 0"
	).is_not_empty()


# ── Elevator hold-to-move ramp (balance.elevator) ─────────────────────────────
# The continuous-hold ramp constants (slow start → capped max) are /data tunables; _check_elevator
# requires + range-checks all three so a typo'd key that silently reads 0 can't disable the hold or
# invert the cap. Each negative asserts a balance.elevator error fires (mirrors the _feel_errors pattern).

func _elevator_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("balance.elevator") or str(e).contains("'elevator'"):
			out.append(e)
	return out

func test_shipped_data_passes_elevator_rules() -> void:
	# Positive: the shipped elevator ramp table satisfies the gate.
	assert_array(_elevator_errors(_load_real_tables())).override_failure_message(
		"shipped balance.elevator must satisfy _check_elevator"
	).is_empty()

func test_validator_requires_elevator_table() -> void:
	# The elevator ramp table is /data — a missing block fails the gate.
	var t := _load_real_tables()
	(t["balance"] as Dictionary).erase("elevator")
	assert_array(_elevator_errors(t)).override_failure_message(
		"validator must reject a missing balance.elevator table"
	).is_not_empty()

func test_validator_rejects_zero_start_rows_per_sec() -> void:
	# Mutation-verified: a 0 start speed would never move on the first frame — strictly > 0.
	var t := _load_real_tables()
	(t["balance"]["elevator"])["start_rows_per_sec"] = 0.0
	assert_array(_elevator_errors(t)).override_failure_message(
		"validator must reject elevator.start_rows_per_sec == 0"
	).is_not_empty()

func test_validator_rejects_negative_accel() -> void:
	# Mutation-verified: the ramp accel is >= 0 (0 = a constant slow glide is fine; negative is nonsense).
	var t := _load_real_tables()
	(t["balance"]["elevator"])["accel_rows_per_sec2"] = -1.0
	assert_array(_elevator_errors(t)).override_failure_message(
		"validator must reject a negative elevator.accel_rows_per_sec2"
	).is_not_empty()

func test_validator_rejects_max_below_start() -> void:
	# Mutation-verified: the capped max must be >= the start (a cap below the start would clamp the
	# glide to BELOW its own starting speed — incoherent).
	var t := _load_real_tables()
	(t["balance"]["elevator"])["max_rows_per_sec"] = 0.5
	(t["balance"]["elevator"])["start_rows_per_sec"] = 2.0
	assert_array(_elevator_errors(t)).override_failure_message(
		"validator must reject elevator.max_rows_per_sec < start_rows_per_sec"
	).is_not_empty()

func test_validator_rejects_zero_muzzle_flash_particles() -> void:
	# Mutation-verified key #6: the muzzle flash needs >= 1 particle to read. A 0 burst is invisible.
	var t := _load_real_tables()
	(t["balance"]["feel"])["muzzle_flash_particles"] = 0
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject feel.muzzle_flash_particles == 0"
	).is_not_empty()

func test_validator_requires_aim_dash_tunables() -> void:
	# AC-5.3.1 (aim preview): the marching-dash aim shader (UNIT C) reads aim_dash_px / aim_gap_px /
	# aim_march_px from balance.feel. They are REQUIRED + range-checked so a typo'd key can't silently
	# read 0 (a missing dash key would collapse the dash period or freeze the march with no warning).
	for key in ["aim_dash_px", "aim_gap_px", "aim_march_px"]:
		var t := _load_real_tables()
		(t["balance"]["feel"] as Dictionary).erase(key)
		assert_array(_feel_errors(t)).override_failure_message(
			"validator must reject a feel table missing '%s'" % key
		).is_not_empty()

func test_validator_requires_keyboard_aim_rate() -> void:
	# D1 (AC-5.3.1/5.3.2): the held-arrow-key aim rate (feel.keyboard_aim_deg_per_sec) is /data so the
	# keyboard aim speed is a tunable, not a code literal. REQUIRED — a missing key fails the gate.
	var t := _load_real_tables()
	(t["balance"]["feel"] as Dictionary).erase("keyboard_aim_deg_per_sec")
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject a feel table missing 'keyboard_aim_deg_per_sec'"
	).is_not_empty()

func test_validator_rejects_nonpositive_keyboard_aim_rate() -> void:
	# D1: the rate is strictly > 0 — a 0/negative rate would make the arrow keys unable to aim
	# (Aim.keyboard_angle_step early-returns on rate <= 0). Reject zero.
	var t := _load_real_tables()
	(t["balance"]["feel"])["keyboard_aim_deg_per_sec"] = 0.0
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject feel.keyboard_aim_deg_per_sec == 0"
	).is_not_empty()

func test_validator_rejects_negative_aim_dash_tunables() -> void:
	# AC-5.3.1: each dash magnitude is >= 0 (0 march = a static dash, valid). A negative dash/gap/march
	# is nonsensical (a negative period flips the dash; a negative march scrolls backward).
	for key in ["aim_dash_px", "aim_gap_px", "aim_march_px"]:
		var t := _load_real_tables()
		(t["balance"]["feel"])[key] = -1.0
		assert_array(_feel_errors(t)).override_failure_message(
			"validator must reject a negative feel.%s" % key
		).is_not_empty()

func test_validator_rejects_zero_dash_period() -> void:
	# AC-5.3.1: dash_px + gap_px is the dash PERIOD; the marching-dash shader divides by it, so it MUST
	# be > 0 even though each term may individually be 0. Both zero (a zero period) must be rejected.
	var t := _load_real_tables()
	(t["balance"]["feel"])["aim_dash_px"] = 0.0
	(t["balance"]["feel"])["aim_gap_px"] = 0.0
	assert_array(_feel_errors(t)).override_failure_message(
		"validator must reject a zero dash period (aim_dash_px + aim_gap_px == 0)"
	).is_not_empty()

# ── Data-driven SFX table (v0.5 arcade audio pass) ───────────────────────────
# The placeholder-SFX synthesis params now live in data/audio.json (consumed by audio.gd via
# GameData), validated by _check_audio: one spec per Audio.EVENTS (freq>0, dur in (0,2], noise in
# [0,1], sweep>=0, pitch_jitter in [0,0.5]); a combo block (>=1 voices, > 0 step, >= 0 semitone
# climb); and a detonate.layers list of >= 3 valid voices. Each negative asserts an audio.* error
# fires so a typo'd key can't silently read 0 and silence/distort a cue. (>= 2 keys mutation-verified.)

func _audio_errors(t: Dictionary) -> Array:
	var out: Array = []
	for e in Validator.validate(t):
		if str(e).contains("audio."):
			out.append(e)
	return out

func test_shipped_data_passes_audio_rules() -> void:
	# Positive: the shipped audio.json satisfies the gate.
	assert_array(_audio_errors(_load_real_tables())).override_failure_message(
		"shipped audio.json must satisfy _check_audio"
	).is_empty()

func test_validator_requires_audio_table() -> void:
	# The SFX table is /data — a missing table fails the gate (audio.gd keeps a code fallback so the
	# game still sounds, but the SHIPPED table must validate).
	var t := _load_real_tables()
	t.erase("audio")
	assert_array(_audio_errors(t)).override_failure_message(
		"validator must reject a missing audio.json table"
	).is_not_empty()

func test_validator_requires_an_event_spec_per_core_event() -> void:
	# Mutation-verified key #1: every Audio.EVENTS entry needs a spec. Drop one → error.
	var t := _load_real_tables()
	(t["audio"]["events"] as Dictionary).erase("descend")
	assert_array(_audio_errors(t)).override_failure_message(
		"validator must reject an audio table missing the 'descend' event spec"
	).is_not_empty()

func test_validator_rejects_zero_event_freq() -> void:
	# Mutation-verified key #2: a 0 Hz tone is silence. freq is strictly > 0.
	var t := _load_real_tables()
	(t["audio"]["events"]["break"])["freq"] = 0.0
	assert_array(_audio_errors(t)).override_failure_message(
		"validator must reject audio.events.break.freq == 0"
	).is_not_empty()

func test_validator_rejects_out_of_band_pitch_jitter() -> void:
	# Mutation-verified key #3: pitch_jitter is in [0,0.5]; a value above the band would warble a cue
	# into a different note on every play.
	var t := _load_real_tables()
	(t["audio"]["events"]["break"])["pitch_jitter"] = 0.9
	assert_array(_audio_errors(t)).override_failure_message(
		"validator must reject audio.events.break.pitch_jitter > 0.5"
	).is_not_empty()

func test_validator_rejects_too_few_detonate_layers() -> void:
	# Mutation-verified key #4: the detonate boom needs >= 3 layered voices. Two → error.
	var t := _load_real_tables()
	var layers: Array = (t["audio"]["detonate"]["layers"] as Array)
	(t["audio"]["detonate"])["layers"] = [layers[0], layers[1]]
	assert_array(_audio_errors(t)).override_failure_message(
		"validator must reject a detonate boom with < 3 layers"
	).is_not_empty()

func test_validator_rejects_zero_combo_step_seconds() -> void:
	# Mutation-verified key #5: the rattle's inter-voice spacing is strictly > 0 (a 0 stacks every
	# voice on the same frame — not a rattle).
	var t := _load_real_tables()
	(t["audio"]["combo"])["step_seconds"] = 0.0
	assert_array(_audio_errors(t)).override_failure_message(
		"validator must reject audio.combo.step_seconds == 0"
	).is_not_empty()

func test_validator_requires_music_tracks() -> void:
	# AC-5.13.2: menu/mining/deep/relic/shop placeholder music specs are data-driven.
	var t := _load_real_tables()
	(t["audio"]["music"] as Dictionary).erase("music_shop")
	assert_array(_audio_errors(t)).override_failure_message(
		"validator must reject an audio table missing the music_shop placeholder loop"
	).is_not_empty()
