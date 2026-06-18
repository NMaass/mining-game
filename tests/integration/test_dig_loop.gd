extends GdUnitTestSuite
## U9 — Dig loop (v0.4): free unlimited charge, reproducible packs, relic-ends-dig,
## idempotent end_dig, minimal prestige power growth. Drives RunState/Prestige via
## direct API calls (input events do not fire headless).
##
## ACs: AC-5.3.3, AC-5.3.8, AC-5.4.3, AC-5.4.4, AC-5.4.5, AC-5.6.2, AC-5.6.3,
##      AC-5.6.4, AC-5.12.1, AC-5.12.2.

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
	# Pack-affordability tests below assume a broke start ($0) and fund buys explicitly
	# via _give_money; pin the starting grant to 0 so they stay independent of it.
	(out["balance"] as Dictionary)["starting_money"] = 0
	return out

func _make_run() -> RunState:
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	return run

func _give_money(econ: Economy, amount: int) -> void:
	# Credit synthetic gold-ore cells to fund a pack buy (distinct cells = no dedupe).
	var per: int = Registry.block_ore_value(_tables, "ore_gold")
	var n: int = int(ceil(float(amount) / float(per)))
	for i in range(n):
		econ.credit(Vector2i(i, -1), "ore_gold")

# ── Free unlimited charge always present (AC-5.12.1, AC-5.4.3, AC-5.3.8) ───────

func test_free_charge_always_in_tray() -> void:
	# AC-5.12.1: the tray always contains the free unlimited charge from the start.
	var run := _make_run()
	var free_id: String = Registry.free_charge_id(_tables)
	assert_str(free_id).is_not_empty()
	assert_array(run.tray).contains([free_id])
	# AC-5.3.8: a throw is always possible — the tray is never empty.
	assert_int(run.tray.size()).is_greater(0)

func test_free_charge_is_first_slot() -> void:
	# AC-5.8.1: the free charge is the first tray slot.
	var run := _make_run()
	assert_str(run.tray[0] as String).is_equal(Registry.free_charge_id(_tables))

func test_free_charge_never_decrements() -> void:
	# AC-5.3.3 / AC-5.4.3: throwing the free charge NEVER decrements it (∞).
	var run := _make_run()
	var free_id: String = Registry.free_charge_id(_tables)
	run.select(free_id)
	for i in range(10):
		var thrown: String = run.throw()
		assert_str(thrown).is_equal(free_id)
		run.resolve_charge()
	# Still infinite, still present, finite tray untouched.
	assert_int(run.count_of(free_id)).is_equal(-1)
	assert_int(run.finite_count()).is_equal(0)
	assert_array(run.tray).contains([free_id])

func test_throw_always_returns_nonempty() -> void:
	# AC-5.3.8: no out-of-charges state — throw() always yields a charge id.
	var run := _make_run()
	for i in range(5):
		assert_str(run.throw()).is_not_empty()
		run.resolve_charge()

func test_tray_getter_returns_copy() -> void:
	# The tray getter must NOT leak the live backing array.
	var run := _make_run()
	var snapshot: Array = run.tray
	snapshot.append("tampered")
	# Mutating the returned array must not change RunState's tray.
	assert_array(run.tray).not_contains(["tampered"])

# ── Buy pack: debit, grant, reject, reproducible (AC-5.12.2, AC-5.4.5) ─────────

func test_buy_pack_debits_and_grants_finite_charges() -> void:
	# AC-5.12.2: a buyable pack debits its price and grants its finite charges.
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 50)
	var price: int = int(Registry.pack(_tables, "basic").get("price", 0))
	var before_money: int = econ.money
	var before_finite: int = run.finite_count()
	assert_bool(run.buy_pack("basic")).is_true()
	assert_int(econ.money).is_equal(before_money - price)
	var count: int = int(Registry.pack(_tables, "basic").get("charge_count", 0))
	assert_int(run.finite_count()).is_equal(before_finite + count)
	# Granted charges are paid/efficient (not the free charge).
	var free_id: String = Registry.free_charge_id(_tables)
	for id in run.tray:
		if id != free_id:
			assert_bool(Registry.explosive(_tables, id).get("free", false) as bool).is_false()

func test_buy_pack_unaffordable_rejected() -> void:
	# AC-5.12.2: an unaffordable purchase is prevented (no debit, no grant).
	var run := _make_run()  # starting_money is 0
	var before_finite: int = run.finite_count()
	assert_bool(run.buy_pack("basic")).is_false()
	assert_int(run.finite_count()).is_equal(before_finite)

func test_buy_unknown_pack_rejected() -> void:
	var run := _make_run()
	assert_bool(run.buy_pack("nonexistent")).is_false()

func test_pack_rolls_reproducible_from_run_seed() -> void:
	# AC-5.4.5: rolls are reproducible from the run seed (run-scoped RNG). Two fresh
	# runs with the same seed roll the same first pack.
	var rolls_a: Array = _roll_basic_pack()
	var rolls_b: Array = _roll_basic_pack()
	assert_array(rolls_a).is_equal(rolls_b)

func _roll_basic_pack() -> Array:
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 200)
	run.buy_pack("basic")
	var free_id: String = Registry.free_charge_id(_tables)
	var out: Array = []
	for id in run.tray:
		if id != free_id:
			out.append(id)
	return out

## Capture exactly the finite charges granted by ONE buy_pack call (the tray delta).
func _buy_and_capture(run: RunState, pack_id: String) -> Array:
	var before: Array = run.tray.duplicate()
	assert_bool(run.buy_pack(pack_id)).is_true()
	var after: Array = run.tray
	# The grant appends to the end of the finite tray, so the delta is the suffix.
	return after.slice(before.size())

func test_pack_rolls_advance_across_buys_not_reseeded() -> void:
	# AC-5.4.5: the run-scoped RNG is seeded ONCE and ADVANCED per draw — NOT re-seeded
	# from a constant per call. A reseed-per-_grant_pack mutant makes every pack roll the
	# identical sequence; an advancing RNG does not. Buying several packs in ONE run and
	# asserting they are not ALL identical kills that mutant (and is seed-robust: an
	# advancing RNG producing three identical 5-draw sequences by chance is negligible).
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 10000)
	var p1: Array = _buy_and_capture(run, "basic")
	var p2: Array = _buy_and_capture(run, "basic")
	var p3: Array = _buy_and_capture(run, "basic")
	assert_int(p1.size()).is_greater(0)
	# Not all three consecutive packs may be byte-identical (would prove a per-call reseed).
	var all_identical: bool = (p1 == p2 and p2 == p3)
	assert_bool(all_identical).is_false()

func test_finite_charge_decrements_on_throw() -> void:
	# AC-5.3.3: throwing a FINITE (paid) charge removes exactly one from the tray (the
	# free charge, covered by test_free_charge_never_decrements, never does). This is the
	# other half of AC-5.3.3 — previously only the free-charge half was asserted.
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 1000)
	assert_bool(run.buy_pack("basic")).is_true()
	var free_id: String = Registry.free_charge_id(_tables)
	var finite_id: String = ""
	for id in run.tray:
		if id != free_id:
			finite_id = id
			break
	assert_str(finite_id).is_not_empty()
	var before_total: int = run.finite_count()
	var before_of_id: int = run.count_of(finite_id)
	assert_bool(run.select(finite_id)).is_true()
	var thrown: String = run.throw()
	assert_str(thrown).is_equal(finite_id)                       # the selected finite charge flew
	assert_int(run.finite_count()).is_equal(before_total - 1)    # exactly one removed
	assert_int(run.count_of(finite_id)).is_equal(before_of_id - 1)

func test_pity_forces_high_tier_only_when_natural_rolls_would_not() -> void:
	# AC-5.4.4: pity is REAL, not incidental. The shipped "basic" pack rolls tier>=2 ~30%
	# of the time, so a naive "tier>=2 appears in the window" assertion passes even with
	# pity deleted (a tautology — flagged in the 2026-06-14 audit). This test isolates pity
	# with a tier-1-heavy table where natural tier>=2 rolls are effectively impossible:
	#   - pity OFF (control): the window has ZERO tier>=2 (proves the scenario needs pity).
	#   - pity ON: the window contains a tier>=2 EXACTLY at the pity boundary (only pity can
	#     produce it). A mutant deleting the pity force makes the ON case match the control
	#     and this assertion goes red.
	var pity_n: int = 5
	var t: Dictionary = _tables.duplicate(true)
	# heavy_bomb is tier 3; dynamite is tier 1. Weight tier-1 a million-to-one so a natural
	# tier>=2 draw never happens for any plausible seed — pity is the only path to one.
	var weights := {"dynamite": 1000000, "heavy_bomb": 1}
	t["packs"]["pity_off_probe"] = {
		"display_name": "Pity Off Probe", "price": 0, "charge_count": pity_n,
		"pity_every": 0, "weights": weights,
	}
	t["packs"]["pity_on_probe"] = {
		"display_name": "Pity On Probe", "price": 0, "charge_count": pity_n,
		"pity_every": pity_n, "weights": weights,
	}

	# Control: pity OFF → the window has no tier>=2 (natural rolls are all tier 1).
	var off_run := RunState.new(t, Economy.new(t))
	off_run.start_dig()
	var off_high: int = _count_high_tier(t, _buy_and_capture(off_run, "pity_off_probe"))
	assert_int(off_high).is_equal(0)

	# Pity ON → the window now contains a tier>=2 the natural rolls would never give.
	var on_run := RunState.new(t, Economy.new(t))
	on_run.start_dig()
	var on_high: int = _count_high_tier(t, _buy_and_capture(on_run, "pity_on_probe"))
	assert_int(on_high).is_greater(0)

func _count_high_tier(tables: Dictionary, ids: Array) -> int:
	var n: int = 0
	for id in ids:
		if int(Registry.explosive(tables, id).get("tier", 1)) >= 2:
			n += 1
	return n

# ── Relic ends dig, banks prestige, idempotent (AC-5.6.2, AC-5.6.3) ───────────

func test_collect_relic_ends_dig() -> void:
	# AC-5.6.2: the auto-accept path (collect_relic) ends the current dig.
	var run := _make_run()
	assert_bool(run.dig_ended).is_false()
	run.collect_relic()
	assert_bool(run.dig_ended).is_true()
	assert_bool(run.relic_collected).is_true()

func test_relic_found_does_not_end_dig_until_accepted() -> void:
	# AC-5.6.2 v0.5: relic_found marks the relic found but does NOT end the dig.
	# The dig ends only when end_dig() / collect_relic() is called (accept offer).
	var run := _make_run()
	assert_bool(run.relic_collected).is_false()
	run.relic_found()
	assert_bool(run.relic_collected).is_true()
	assert_bool(run.dig_ended).is_false()
	# A subsequent collect_relic (or end_dig) now ends the dig idempotently.
	run.collect_relic()
	assert_bool(run.dig_ended).is_true()

func test_collect_relic_banks_prestige_once() -> void:
	# AC-5.6.3: a dig-end banks the relic's prestige value exactly once (idempotent).
	var run := _make_run()
	var value: int = Registry.relic_prestige_value(_tables)
	assert_int(value).is_greater(0)
	run.collect_relic()
	assert_int(run.total_prestige).is_equal(value)
	# Collecting again banks nothing more (idempotent).
	run.collect_relic()
	assert_int(run.total_prestige).is_equal(value)
	# end_dig directly is also idempotent.
	run.end_dig()
	assert_int(run.total_prestige).is_equal(value)

func test_end_dig_idempotent() -> void:
	# AC-5.6.3: end_dig is idempotent — repeated calls bank prestige only once.
	var run := _make_run()
	var value: int = Registry.relic_prestige_value(_tables)
	run.end_dig()
	run.end_dig()
	run.end_dig()
	assert_int(run.total_prestige).is_equal(value)

func test_new_dig_resets_per_dig_state() -> void:
	# AC-5.6.3: starting a new dig resets per-dig state (money, finite charges, relic),
	# but prestige persists across digs.
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 200)
	run.buy_pack("basic")
	assert_int(run.finite_count()).is_greater(0)
	run.collect_relic()
	var banked: int = run.total_prestige
	# New dig.
	run.start_dig()
	assert_bool(run.dig_ended).is_false()
	assert_bool(run.relic_collected).is_false()
	assert_int(run.finite_count()).is_equal(0)  # finite charges reset
	assert_int(econ.money).is_equal(Registry.starting_money(_tables))  # money reset
	assert_int(run.total_prestige).is_equal(banked)  # prestige persists (AC-5.6.4)
	# The free charge is still present after reset.
	assert_array(run.tray).contains([Registry.free_charge_id(_tables)])

func test_prestige_accumulates_across_digs() -> void:
	# AC-5.6.3 / AC-5.6.4: banked prestige accumulates across multiple digs.
	var run := _make_run()
	var value: int = Registry.relic_prestige_value(_tables)
	run.collect_relic()
	run.start_dig()
	run.collect_relic()
	assert_int(run.total_prestige).is_equal(value * 2)

# ── Power growth: prestige upgrade makes the next dig stronger (AC-5.6.4) ──────

func test_buy_upgrade_requires_banked_prestige() -> void:
	# AC-5.12.2-style: an upgrade with no banked prestige is rejected.
	var run := _make_run()  # no prestige banked yet
	var up_id: String = Registry.prestige_upgrade_ids(_tables)[0]
	assert_bool(run.buy_upgrade(up_id)).is_false()

func test_buy_mining_torch_increases_effective_light_radius() -> void:
	# AC-5.6.4: buying Mining Torch raises the effective light radius used by the dig view.
	var run := _make_run()
	var base: float = Registry.effective_light_radius(_tables, run.prestige)
	run.collect_relic()  # bank prestige
	assert_bool(run.buy_upgrade("mining_torch")).is_true()
	run.start_dig()
	assert_float(Registry.effective_light_radius(_tables, run.prestige)).is_greater(base)

func test_buy_charge_holster_decreases_effective_throw_cooldown() -> void:
	# AC-5.6.4: buying Charge Holster lowers the effective throw cooldown used by the dig.
	var run := _make_run()
	var base: float = Registry.effective_throw_cooldown(_tables, run.prestige)
	run.collect_relic()  # bank prestige
	assert_bool(run.buy_upgrade("charge_holster")).is_true()
	run.start_dig()
	assert_float(Registry.effective_throw_cooldown(_tables, run.prestige)).is_less(base)

func test_buy_upgrade_makes_next_dig_stronger() -> void:
	# AC-5.6.4: after buying a prestige upgrade, a measurable dig stat improves.
	var run := _make_run()
	var free_params := ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables))
	var base_intensity: int = free_params.blast_intensity

	# Dig 1: no upgrades — the dig blast intensity equals the base.
	var before: int = run.dig_blast_intensity(base_intensity)
	assert_int(before).is_equal(base_intensity)

	# Earn prestige by collecting a relic, then buy the power upgrade.
	run.collect_relic()
	var up_id: String = Registry.prestige_upgrade_ids(_tables)[0]
	assert_bool(run.buy_upgrade(up_id)).is_true()

	# Dig 2: the SAME charge now deals MORE blast intensity (measurably stronger).
	run.start_dig()
	var after: int = run.dig_blast_intensity(base_intensity)
	assert_int(after).is_greater(before)

func test_buy_unknown_upgrade_rejected() -> void:
	var run := _make_run()
	run.collect_relic()  # bank some prestige
	assert_bool(run.buy_upgrade("nonexistent_upgrade")).is_false()

func test_upgrade_respects_max_level() -> void:
	# AC-5.6.4: an upgrade cannot be bought past its max_level.
	var run := _make_run()
	var up_id: String = Registry.prestige_upgrade_ids(_tables)[0]
	var up: Dictionary = Registry.prestige_upgrade(_tables, up_id)
	var max_level: int = int(up.get("max_level", 0))
	# Bank plenty of prestige.
	for i in range(max_level + 5):
		run.collect_relic()
		run.start_dig()
	var bought := 0
	for i in range(max_level + 5):
		if run.buy_upgrade(up_id):
			bought += 1
	assert_int(bought).is_equal(max_level)

# ── Per-dig MONEY upgrades: Shaft Engineering (Phase C, AC-5.12.x) ─────────────

func test_buy_money_upgrade_requires_money() -> void:
	# A money upgrade with insufficient money is rejected (no level, no reduction).
	var run := _make_run()  # broke (starting_money pinned to 0 here)
	assert_bool(run.buy_money_upgrade("shaft_engineering")).is_false()
	assert_int(run.upgrade_level("shaft_engineering")).is_equal(0)
	assert_int(run.shaft_width_reduction()).is_equal(0)

func test_buy_shaft_engineering_debits_money_and_reduces_clearance() -> void:
	# Buying Shaft Engineering debits its money price and applies a 2-cell clearance reduction.
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	var price: int = int(Registry.upgrade(_tables, "shaft_engineering").get("price", 0))
	_give_money(econ, price)
	var before: int = econ.money
	assert_bool(run.buy_money_upgrade("shaft_engineering")).is_true()
	assert_int(econ.money).is_equal(before - price)
	assert_int(run.upgrade_level("shaft_engineering")).is_equal(1)
	assert_int(run.shaft_width_reduction()).is_equal(2)
	# The effective clearance narrows 9 → 7 with this reduction.
	assert_int(Registry.effective_shaft_width(_tables, run.shaft_width_reduction())).is_equal(7)

func test_money_upgrade_respects_max_level() -> void:
	# Shaft Engineering is max_level 1 — a second buy is rejected even with money.
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 100000)
	assert_bool(run.buy_money_upgrade("shaft_engineering")).is_true()
	assert_bool(run.buy_money_upgrade("shaft_engineering")).is_false()
	assert_int(run.upgrade_level("shaft_engineering")).is_equal(1)

func test_select_next_noop_with_only_free_charge() -> void:
	# Tab cycle: with only the free charge in the tray, select_next is a no-op returning the free id.
	var run := _make_run()
	var free_id: String = Registry.free_charge_id(_tables)
	assert_str(run.select_next()).is_equal(free_id)
	assert_str(run.selected_id).is_equal(free_id)

func test_select_next_wraps_over_free_and_finite() -> void:
	# With finite charges present, select_next visits each distinct slot once and wraps to free.
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 100000)
	var pack_id: String = Registry.pack_ids(_tables)[0]
	assert_bool(run.buy_pack(pack_id)).is_true()
	var slots: int = run.tray.size()  # >= 2 (free + finite)
	# Cycling `distinct slot count` times returns to the starting selection.
	var distinct: Array = []
	for id in run.tray:
		if not distinct.has(id):
			distinct.append(id)
	var start: String = run.selected_id
	for i in range(distinct.size()):
		run.select_next()
	assert_str(run.selected_id).is_equal(start)

func test_buy_pack_auto_selects_lowest_rarity_granted() -> void:
	# Buying a pack readies the LOWEST-rarity charge it granted (not whatever was selected before).
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 100000)
	var pack_id: String = Registry.pack_ids(_tables)[0]
	assert_bool(run.buy_pack(pack_id)).is_true()
	var sel_rank: int = Registry.rarity_rank(_tables, str(Registry.explosive(_tables, run.selected_id).get("rarity", "")))
	# No granted finite charge has a strictly lower rarity than the selected one.
	for id in run.tray:
		if id == Registry.free_charge_id(_tables):
			continue
		var r: int = Registry.rarity_rank(_tables, str(Registry.explosive(_tables, str(id)).get("rarity", "")))
		assert_int(sel_rank).is_less_equal(r)

func test_money_upgrade_resets_each_dig() -> void:
	# Per-dig: the upgrade level (and its reduction) reset at the next start_dig.
	var econ := Economy.new(_tables)
	var run := RunState.new(_tables, econ)
	run.start_dig()
	_give_money(econ, 100000)
	assert_bool(run.buy_money_upgrade("shaft_engineering")).is_true()
	assert_int(run.shaft_width_reduction()).is_equal(2)
	run.start_dig()  # new dig
	assert_int(run.upgrade_level("shaft_engineering")).is_equal(0)
	assert_int(run.shaft_width_reduction()).is_equal(0)
