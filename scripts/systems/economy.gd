class_name Economy
extends RefCounted
## Economy system: ore crediting + money tracking. Stateful but no Node deps —
## can be tested headless.
##
## Loot PLACEMENT (AC-5.5.2) is NOT here: blocks are placed by BlockGen from the
## depth-scaled weight CURVE (Registry.depth_weights_at) and auto-credited on break via
## credit(). The depth-reward property (EV + gem probability rise with depth toward a
## bounded cap) is a hard data-gate invariant (DataValidator._check_depth_reward_monotone)
## and is tested over the real curve weights in test_economy.gd — there is no runtime loot
## *sampler* (the old draw_loot was dead code with no production callers, removed in v0.4.1).
##
## ACs: AC-5.5.1 (auto-credit on break), AC-5.5.3 (per-dig money), AC-5.5.4 (values from data).

var _tables: Dictionary
var _money: int = 0
var _credited_cells: Dictionary = {}  # Set of Vector2i → true (no double credit)
## Per-mine ore-value multiplier (richer ore in deeper mines). 1.0 = the surface mine.
var _ore_value_mult: float = 1.0

func _init(tables: Dictionary) -> void:
	_tables = tables
	_money = Registry.starting_money(tables)

## Set the active mine's ore-value multiplier (applied to every credit). Deeper mines pay
## more. Clamped to >= 0 so a misconfigured mine can never pay negative money.
func set_ore_value_mult(mult: float) -> void:
	_ore_value_mult = maxf(0.0, mult)

## Current money balance.
var money: int:
	get:
		return _money

## Credit ore value for a broken block at the given cell, scaled by the active mine's
## ore-value multiplier (AC-5.5.1: auto-credit on destruction). No double-credit per cell.
func credit(cell: Vector2i, block_id: String) -> int:
	if _credited_cells.has(cell):
		return 0  # Already credited this cell.
	_credited_cells[cell] = true
	var base: int = Registry.block_ore_value(_tables, block_id)
	var value: int = int(round(float(base) * _ore_value_mult))
	_money += value
	return value

## Credit multiple cleared blocks from a blast result.
## Returns total value credited.
func credit_blast(cleared: Array, block_ids: Dictionary) -> int:
	var total: int = 0
	for cell in cleared:
		var id: String = block_ids.get(cell, "air")
		total += credit(cell, id)
	return total

## Debit money for a purchase. Returns true if affordable, false otherwise.
func debit(amount: int) -> bool:
	if amount < 0:
		return false
	if _money < amount:
		return false
	_money -= amount
	return true

## Check if the player can afford a given amount.
func can_afford(amount: int) -> bool:
	return _money >= amount

## Reset for a new run.
## AC-5.5.3: money is per-run, reset at run-end.
func reset_run() -> void:
	_money = Registry.starting_money(_tables)
	_credited_cells.clear()
