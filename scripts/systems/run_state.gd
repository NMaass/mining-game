class_name RunState
extends RefCounted
## Dig-loop state (v0.4): the tray always holds the free unlimited charge (never
## decremented, never empty); paid packs grant finite efficient charges via a
## reproducible run-scoped RNG; collecting the relic ENDS the dig, banks prestige,
## and resets per-dig state. No lose state. Stateful but no Node deps — headless.
##
## v0.3 → v0.4 salvage (VERTICAL_SLICE §0 / U9):
##  - REMOVED the tray-exhaustion run-end model (AC-5.3.5 deleted): a throw is always
##    possible because the free charge is a permanent, never-decremented slot.
##  - Relic-ends-dig (AC-5.6.2/5.6.3) replaces out-of-charges run-end.
##  - Packs roll from ONE run-scoped seeded RNG, seeded from the run seed and advanced
##    per draw (reproducible), not re-seeded from mutable state per call (AC-5.4.5).
##  - end_dig() is idempotent (banks prestige once); tray getter returns a COPY.
##  - pity_every implemented (a tier>=2 charge guaranteed within N draws) (AC-5.4.4).
##
## ACs: AC-5.3.3, AC-5.3.8, AC-5.4.3, AC-5.4.4, AC-5.4.5, AC-5.6.2, AC-5.6.3,
##      AC-5.6.4, AC-5.12.1, AC-5.12.2.

var _tables: Dictionary
var _economy: Economy
var _prestige: Prestige

## The single flagged free unlimited charge id (permanent tray slot, AC-5.4.3/5.12.1).
var _free_charge_id: String = ""

## Finite (paid) charges granted into the tray this dig. Decremented on throw.
var _finite_tray: Array = []

## Currently selected charge id (the free charge or a finite charge). "" until set;
## defaults to the free charge.
var _selected_id: String = ""

## Whether a charge is currently in flight.
var _charge_in_flight: bool = false

## Depth in cells (dig state).
var _depth: int = 0

## Whether the relic has been collected this dig.
var _relic_collected: bool = false

## Whether the current dig has ended (relic collected). Idempotency guard.
var _dig_ended: bool = false

## One run-scoped RNG for pack rolls (AC-5.4.5): seeded once from the run seed,
## advanced per draw, NOT re-seeded per call.
var _pack_rng := RandomNumberGenerator.new()

## Draws since the last tier>=2 roll, for pity (AC-5.4.4). Per pack id.
var _pity_counter: Dictionary = {}

## Per-dig MONEY upgrade levels (id -> level), bought with in-dig money via the shop.
## RESET each dig (no persistence) — re-buyable next dig. Distinct from prestige (which
## persists). Drives, e.g., the Shaft Engineering clearance reduction this dig.
var _upgrade_levels: Dictionary = {}

func _init(tables: Dictionary, economy: Economy, prestige: Prestige = null) -> void:
	_tables = tables
	_economy = economy
	_prestige = prestige if prestige != null else Prestige.new(tables)
	_free_charge_id = Registry.free_charge_id(tables)

# ── Dig lifecycle ─────────────────────────────────────────────────────────────

## Start a new dig. The free charge is always present; per-dig state resets.
## AC-5.12.1: the tray always contains the free unlimited charge — no purchase needed.
func start_dig() -> void:
	_finite_tray.clear()
	_charge_in_flight = false
	_depth = 0
	_relic_collected = false
	_dig_ended = false
	_pity_counter.clear()
	_upgrade_levels.clear()  # per-dig money upgrades reset with the dig (no persistence)
	_selected_id = _free_charge_id
	_economy.reset_run()
	# Reproducible pack rolls: seed the run-scoped RNG from the run seed (AC-5.4.5).
	_pack_rng.seed = Registry.run_seed(_tables)

## Backward-compat alias for the v0.3 controller (mine.gd, rebuilt in U10).
func start_run() -> void:
	start_dig()

## The prestige system (banked points + purchased upgrades persist across digs).
var prestige: Prestige:
	get:
		return _prestige

# ── Tray & selection ──────────────────────────────────────────────────────────

## The current tray as a COPY (never the live backing array — AC: no leaky getter):
## the free charge is always the first slot, followed by the finite charges.
var tray: Array:
	get:
		var out: Array = []
		if _free_charge_id != "":
			out.append(_free_charge_id)
		out.append_array(_finite_tray)
		return out

## Count of FINITE charges remaining (the free charge is unlimited, not counted).
func finite_count() -> int:
	return _finite_tray.size()

## Remaining count for a specific charge id: -1 (infinite) for the free charge,
## else the number of that finite charge in the tray (AC-5.8.2: ∞ for free).
func count_of(charge_id: String) -> int:
	if charge_id == _free_charge_id:
		return -1
	return _finite_tray.count(charge_id)

## Total selectable slots (free + finite). Always >= 1 (the free charge) — there is
## never an empty tray (AC-5.3.8). Backward-compat name for the v0.3 controller;
## because it is always >= 1, the old `charges_remaining <= 0` lock can never fire.
var charges_remaining: int:
	get:
		return tray.size()

## The free unlimited charge id (permanent slot).
var free_charge_id: String:
	get:
		return _free_charge_id

## The currently selected charge id (defaults to the free charge).
var selected_id: String:
	get:
		return _selected_id if _selected_id != "" else _free_charge_id

## Select a tray charge (AC-5.3.6). The free charge is always selectable; a finite
## charge is selectable only while at least one remains. Returns true if selected.
func select(charge_id: String) -> bool:
	if charge_id == _free_charge_id:
		_selected_id = _free_charge_id
		return true
	if _finite_tray.has(charge_id):
		_selected_id = charge_id
		return true
	return false

## Cycle the selection to the NEXT distinct tray slot (free charge + one entry per finite type),
## wrapping around. Drives the Tab key. Returns the newly-selected id. The free charge is always
## the first slot; finite types follow in tray order (deduped). With only the free charge in the
## tray this is a no-op that returns the free charge.
func select_next() -> String:
	var slots: Array = _distinct_slots()
	if slots.size() <= 1:
		_selected_id = _free_charge_id
		return _selected_id
	var cur: int = slots.find(selected_id)
	var nxt: int = (cur + 1) % slots.size() if cur >= 0 else 0
	_selected_id = str(slots[nxt])
	return _selected_id

## The distinct selectable slots in tray order: the free charge first, then each finite type once.
func _distinct_slots() -> Array:
	var out: Array = []
	if _free_charge_id != "":
		out.append(_free_charge_id)
	for id in _finite_tray:
		if not out.has(id):
			out.append(id)
	return out

# ── Throw ─────────────────────────────────────────────────────────────────────

## Throw the selected charge. Returns the explosive id thrown (always non-empty —
## a throw is always possible, AC-5.3.8). The free charge is NEVER decremented
## (AC-5.3.3/5.4.3); a finite charge removes one from the tray. If the selected
## finite charge has run out, falls back to the free charge.
func throw() -> String:
	var id: String = selected_id
	if id != _free_charge_id:
		var idx: int = _finite_tray.find(id)
		if idx >= 0:
			_finite_tray.remove_at(idx)
			# If that was the last of this finite type, fall selection back to free.
			if not _finite_tray.has(id):
				_selected_id = _free_charge_id
		else:
			# Selected finite charge no longer available — use the free charge.
			id = _free_charge_id
			_selected_id = _free_charge_id
	_charge_in_flight = true
	return id

## Notify that the in-flight charge has resolved (landed/detonated). v0.4: this does
## NOT end the dig (only the relic does). Kept for the controller's flow tracking.
func resolve_charge() -> void:
	_charge_in_flight = false

## Whether a charge is currently in flight.
var charge_in_flight: bool:
	get:
		return _charge_in_flight
	set(value):
		_charge_in_flight = value

# ── Packs (AC-5.4.4, AC-5.4.5, AC-5.12.2) ─────────────────────────────────────

## Buy a pack by id. Debits its price and grants the rolled finite charges into the
## tray. Returns true on success; an unaffordable or unknown pack is rejected
## (AC-5.12.2). Rolls are driven by the run-scoped RNG (reproducible from the run
## seed, advanced per draw — AC-5.4.5).
func buy_pack(pack_id: String) -> bool:
	var pack_data: Dictionary = Registry.pack(_tables, pack_id)
	if pack_data.is_empty():
		return false
	var price: int = int(pack_data.get("price", 0))
	if not _economy.debit(price):
		return false
	var before: int = _finite_tray.size()
	_grant_pack(pack_id)
	# Auto-select the LOWEST-rarity charge just granted (so a pack buy readies its most basic
	# charge, not whatever was selected before). Ties resolve to the first granted in tray order.
	_select_lowest_rarity_granted(before)
	return true

## Select the lowest-rarity finite charge among those granted this buy (the slice of the finite
## tray added since `from_index`). No-op if nothing new was granted.
func _select_lowest_rarity_granted(from_index: int) -> void:
	var best_id: String = ""
	var best_rank: int = 1 << 30
	for i in range(from_index, _finite_tray.size()):
		var id: String = str(_finite_tray[i])
		var rank: int = Registry.rarity_rank(_tables, str(Registry.explosive(_tables, id).get("rarity", "")))
		if rank < best_rank:
			best_rank = rank
			best_id = id
	if best_id != "":
		_selected_id = best_id

## Roll a pack's charges into the finite tray using the run-scoped RNG.
func _grant_pack(pack_id: String) -> void:
	var pack_data: Dictionary = Registry.pack(_tables, pack_id)
	if pack_data.is_empty():
		return
	var count: int = int(pack_data.get("charge_count", 0))
	var weights: Dictionary = pack_data.get("weights", {})
	if weights.is_empty() or count <= 0:
		return

	var keys: Array = weights.keys()
	keys.sort()  # fixed walk order so a fixed seed yields a fixed result
	var total_weight: float = 0.0
	for k in keys:
		total_weight += float(weights[k])
	if total_weight <= 0.0:
		return

	var pity_every: int = int(pack_data.get("pity_every", 0))

	for i in range(count):
		var rolled: String = _weighted_roll(keys, weights, total_weight)
		# Pity (AC-5.4.4): if pity_every>0 and we've gone pity_every-1 draws without a
		# tier>=2 charge, force a tier>=2 roll on this draw.
		if pity_every > 0:
			var since: int = int(_pity_counter.get(pack_id, 0))
			if since >= pity_every - 1 and _explosive_tier(rolled) < 2:
				rolled = _force_high_tier(keys, weights)
			if _explosive_tier(rolled) >= 2:
				_pity_counter[pack_id] = 0
			else:
				_pity_counter[pack_id] = since + 1
		_finite_tray.append(rolled)

## Weighted selection over sorted keys using the run-scoped RNG.
func _weighted_roll(keys: Array, weights: Dictionary, total_weight: float) -> String:
	var roll: float = _pack_rng.randf() * total_weight
	var cumulative: float = 0.0
	for k in keys:
		cumulative += float(weights[k])
		if roll < cumulative:
			return k
	return keys[keys.size() - 1]

## The lowest-keyed tier>=2 explosive in the table (deterministic), or "" if none.
func _force_high_tier(keys: Array, _weights: Dictionary) -> String:
	for k in keys:
		if _explosive_tier(k) >= 2:
			return k
	return ""

func _explosive_tier(explosive_id: String) -> int:
	return int(Registry.explosive(_tables, explosive_id).get("tier", 1))

# ── Relic → dig end → prestige (AC-5.6.2, AC-5.6.3, AC-5.6.4) ──────────────────

## Mark the relic as found this dig, without ending the dig (AC-5.6.2). Called when the
## relic block breaks; the controller then shows the prestige offer UI.
func relic_found() -> void:
	_relic_collected = true


## Collect the dig's relic: banks prestige and ends the dig (AC-5.6.2). Idempotent —
## collecting again is a no-op (the dig has already ended, prestige already banked).
## This is the "auto-accept" path; the offer UI path calls relic_found(), then later end_dig().
func collect_relic() -> void:
	if _relic_collected:
		end_dig()
		return
	relic_found()
	end_dig()

## Whether the relic has been collected this dig.
var relic_collected: bool:
	get:
		return _relic_collected

## End the current dig: bank the relic's prestige (once) and reset per-dig state.
## IDEMPOTENT (AC-5.6.3): a second call banks nothing and changes nothing.
func end_dig() -> void:
	if _dig_ended:
		return
	_dig_ended = true
	_charge_in_flight = false
	_prestige.bank(Registry.relic_prestige_value(_tables))

## Backward-compat alias for the v0.3 controller (mine.gd, rebuilt in U10).
func end_run() -> void:
	end_dig()

## Whether the current dig has ended (relic collected). v0.4 dig-end state.
var dig_ended: bool:
	get:
		return _dig_ended

## Backward-compat alias for the v0.3 controller (mine.gd) + level smoke test.
var run_ended: bool:
	get:
		return _dig_ended

## Buy a permanent prestige upgrade (power growth). Delegates to the Prestige system;
## the bought upgrade makes subsequent digs measurably stronger (AC-5.6.4).
func buy_upgrade(upgrade_id: String) -> bool:
	return _prestige.buy_upgrade(upgrade_id)

# ── Per-dig MONEY upgrades (Shaft Engineering) ────────────────────────────────

## Current per-dig level of a money upgrade (0 if not bought this dig).
func upgrade_level(upgrade_id: String) -> int:
	return int(_upgrade_levels.get(upgrade_id, 0))

## Buy one level of a per-dig money upgrade. Debits its money price via Economy; rejects
## unknown ids, unaffordable buys, and buys past max_level. The level resets at the next
## start_dig (no persistence). Returns true on success.
func buy_money_upgrade(upgrade_id: String) -> bool:
	var up: Dictionary = Registry.upgrade(_tables, upgrade_id)
	if up.is_empty():
		return false
	var max_level: int = int(up.get("max_level", 0))
	if max_level > 0 and upgrade_level(upgrade_id) >= max_level:
		return false
	var price: int = int(up.get("price", 0))
	if price <= 0 or not _economy.debit(price):
		return false
	_upgrade_levels[upgrade_id] = upgrade_level(upgrade_id) + 1
	return true

## Total reduction (in whole cells) to the required shaft clearance width from purchased
## per-dig "shaft_width_reduction" upgrades. 0 with none; each level adds |magnitude| cells.
func shaft_width_reduction() -> int:
	var total: int = 0
	for id in Registry.upgrade_ids(_tables):
		var up: Dictionary = Registry.upgrade(_tables, str(id))
		if str(up.get("effect", "")) == "shaft_width_reduction":
			total += int(round(absf(float(up.get("magnitude", 0.0))))) * upgrade_level(str(id))
	return total

## The blast intensity a charge of `base_intensity` deals THIS dig, after applying
## banked prestige upgrades (AC-5.6.4: the next dig is measurably stronger). The dig
## reads this instead of the raw explosive intensity so prestige is felt in play.
func dig_blast_intensity(base_intensity: int) -> int:
	return _prestige.dig_blast_intensity(base_intensity)

# ── Misc dig state ────────────────────────────────────────────────────────────

## Total banked prestige points (across digs). Convenience over prestige.points.
var total_prestige: int:
	get:
		return _prestige.points

## Current depth in cells (dig state).
var depth: int:
	get:
		return _depth
	set(value):
		_depth = value
