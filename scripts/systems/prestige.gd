class_name Prestige
extends RefCounted
## Minimal prestige system: banks prestige points (persist across digs) and sells
## permanent power-growth upgrades that make subsequent digs measurably stronger.
## Stateful but no Node/scene deps — headless-testable.
##
## v0.4 power-growth loop (in miniature): collecting a relic banks prestige
## (RunState.end_dig); spending banked prestige here via buy_upgrade() raises a dig
## modifier (the blast-intensity multiplier) that the NEXT dig reads — closing the
## "prestige makes each dig stronger" loop (AC-5.6.4).
##
## ACs: AC-5.6.4 (purchases make subsequent digs measurably stronger),
##      AC-5.12.1/AC-5.12.2 (purchase debits a currency, unaffordable is rejected).

var _tables: Dictionary

## Banked prestige points available to spend on upgrades. Persists across digs.
var _points: int = 0

## Purchased upgrade levels: id -> level (count). Persists across digs (AC-5.6.4).
var _levels: Dictionary = {}

func _init(tables: Dictionary) -> void:
	_tables = tables

## Banked, spendable prestige points.
var points: int:
	get:
		return _points

## Bank prestige points (e.g. when a relic is collected and the dig ends).
func bank(amount: int) -> void:
	if amount > 0:
		_points += amount

## Current purchased level of an upgrade id (0 if never bought).
func level(upgrade_id: String) -> int:
	return int(_levels.get(upgrade_id, 0))

## Buy one level of a prestige upgrade. Returns true on success.
## Debits its prestige cost; rejects unknown ids, unaffordable buys, and buys past
## the upgrade's max_level (AC-5.6.4 / AC-5.12.2-style gating on the prestige currency).
func buy_upgrade(upgrade_id: String) -> bool:
	var up: Dictionary = Registry.prestige_upgrade(_tables, upgrade_id)
	if up.is_empty():
		return false
	var max_level: int = int(up.get("max_level", 0))
	if max_level > 0 and level(upgrade_id) >= max_level:
		return false
	var cost: int = int(up.get("cost_prestige", 0))
	if cost <= 0 or _points < cost:
		return false
	_points -= cost
	_levels[upgrade_id] = level(upgrade_id) + 1
	return true

## Multiplier applied to a charge's base blast intensity for a dig, derived from the
## purchased "blast_intensity_mult" upgrades. 1.0 with no upgrades; each purchased
## level adds the upgrade's magnitude (AC-5.6.4: measurably stronger next dig).
func blast_intensity_mult() -> float:
	return _effect_mult("blast_intensity_mult")

## Multiplier applied to the base light radius (Mining Torch upgrade).
## 1.0 with no upgrades; each level adds the upgrade's magnitude.
func light_radius_mult() -> float:
	return _effect_mult("light_radius_mult")

## Multiplier applied to the base throw cooldown (Charge Holster upgrade).
## Negative magnitudes reduce cooldown; result is clamped to a small positive floor
## so the cooldown can never reach zero.
func throw_cooldown_mult() -> float:
	return _effect_mult("throw_cooldown_mult")

## Sum the per-level magnitudes for a given prestige effect id.
func _effect_mult(effect_id: String) -> float:
	var mult: float = 1.0
	for id in Registry.prestige_upgrade_ids(_tables):
		var up: Dictionary = Registry.prestige_upgrade(_tables, id)
		if str(up.get("effect", "")) == effect_id:
			mult += float(up.get("magnitude", 0.0)) * float(level(id))
	return mult

## Apply the prestige blast-intensity multiplier to a base intensity, floored to an
## int (the grid HP/damage are integers). The dig reads this so the same charge does
## more damage after a prestige purchase (AC-5.6.4).
func dig_blast_intensity(base_intensity: int) -> int:
	return int(floor(float(base_intensity) * blast_intensity_mult()))

## Effective throw cooldown after Charge Holster. Clamped to a minimum of 0.2s
## so the UI never divides by zero and spam is still gated.
func dig_throw_cooldown(base_cooldown: float) -> float:
	return maxf(0.2, base_cooldown * throw_cooldown_mult())

## Effective light radius after Mining Torch.
func dig_light_radius(base_radius: float) -> float:
	return maxf(0.0, base_radius * light_radius_mult())

# ── Save/restore (U20 / AC-5.11.1) ─────────────────────────────────────────────

## Snapshot the DURABLE prestige state (banked points + purchased levels) for saving.
## This is the only cross-dig state the slice persists (per-dig state is not saved).
func to_state() -> Dictionary:
	return {"points": _points, "levels": _levels.duplicate()}

## Restore the durable prestige state from a saved snapshot (on boot/load). The save is the
## source of truth (it was validated when bought), but we still sanitize — points >= 0, levels
## a {id: int>0} map — so a corrupt/hand-edited file can't inject bad state (defense in depth
## with SaveCodec). Missing fields default to a fresh state.
func from_state(state: Dictionary) -> void:
	_points = maxi(0, int(state.get("points", 0)))
	_levels = {}
	var lv: Variant = state.get("levels")
	if lv is Dictionary:
		for k in (lv as Dictionary).keys():
			var n: int = int((lv as Dictionary)[k])
			if n > 0:
				_levels[str(k)] = n
