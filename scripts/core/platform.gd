class_name PlatformLogic
extends RefCounted
## Pure platform descent logic. No Node/scene deps; headless-testable.
## Counts cleared cells beneath the platform and determines descent.
##
## ACs: AC-5.7.1 (platform anchor), AC-5.7.2 (tween descent, not snap),
##       AC-5.7.3 (camera follows platform).

## Count the number of cleared (empty / HP <= 0) cells directly beneath the platform.
## hp_grid: Dictionary of Vector2i → int (current HP; missing = air/cleared).
## platform_row: the row the platform sits on (cells directly below = platform_row + 1).
## width: shaft width in cells.
## A cell is "cleared" if it's not in hp_grid (was never solid) or has HP <= 0.
static func cleared_beneath(hp_grid: Dictionary, platform_row: int, width: int, start_x: int = 0) -> int:
	var count: int = 0
	var check_row: int = platform_row + 1
	for x in range(start_x, start_x + width):
		var cell := Vector2i(x, check_row)
		if not hp_grid.has(cell) or int(hp_grid[cell]) <= 0:
			count += 1
	return count

## Determine whether descent should trigger.
## Returns true if cleared cells >= threshold.
static func should_descend(hp_grid: Dictionary, platform_row: int,
		width: int, threshold: int, start_x: int = 0) -> bool:
	return cleared_beneath(hp_grid, platform_row, width, start_x) >= threshold

## Calculate how many rows the platform should descend.
## Scans downward from current position; for each consecutive row where
## enough cells are cleared, adds one descent step.
## Returns the number of rows to descend (0 if none).
static func descent_steps(hp_grid: Dictionary, platform_row: int,
		width: int, threshold: int, max_steps: int = 1, start_x: int = 0) -> int:
	var steps: int = 0
	var check_row: int = platform_row
	for _i in range(max_steps):
		if should_descend(hp_grid, check_row, width, threshold, start_x):
			steps += 1
			check_row += 1
		else:
			break
	return steps


## True if every cell in `row` from `start_x` to `start_x + width - 1` is cleared
## (missing from hp_grid or HP <= 0).
static func is_row_cleared(hp_grid: Dictionary, row: int, width: int, start_x: int = 0) -> bool:
	for x in range(start_x, start_x + width):
		var hp: int = int(hp_grid.get(Vector2i(x, row), 0))
		if hp > 0:
			return false
	return true


## Find the deepest consecutive cleared row starting at `support_row + 1`, capped
## at `max_row`. Returns the new support row (may equal the current one).
static func next_support_row(hp_grid: Dictionary, support_row: int,
		width: int, max_row: int, start_x: int = 0) -> int:
	var row: int = support_row
	while row < max_row:
		if is_row_cleared(hp_grid, row + 1, width, start_x):
			row += 1
		else:
			break
	return row
