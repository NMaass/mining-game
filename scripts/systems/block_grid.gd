class_name BlockGrid
extends RefCounted
## BlockGrid — per-chunk HP store + block-ID tracking (v0.4).
## Manages the grid's state using per-chunk PackedInt32Array for HP and
## Array[String] for block IDs. Headless-testable; no Node/scene deps.
## Per-cell HP lives HERE, NOT in TileMap cells (TileSet custom data is shared
## per type, not per cell — so mutable per-cell HP cannot live in the map).
##
## v0.4 HP scaling (AC-5.2.1): at chunk init each cell's HP is derived from its
## type via Registry.scaled_block_hp:
##   base_hp(type) * (1 + depth_cells * depth_hp_mult_per_cell) * mine_hardness_mult
## applied ONCE at chunk init and stored per-cell. Deeper / harder-mine cells get
## higher HP, so the player's charges underperform there (the optimization pressure).
##
## v0.4 relic (AC-5.6.2): the relic is the dig objective, placed as a pure fn of
## (mine_seed, cell) by BlockGen. When the relic's block breaks, BlockGrid emits
## `relic_collected(cell)` EXACTLY ONCE (it never recycles, never re-fires).
##
## ACs: AC-5.2.1 (depth/mine-scaled HP), AC-5.2.2 (damage/break lifecycle),
##       AC-5.2.7 (surviving block retains damage), AC-5.1.2 (chunk windowing),
##       AC-5.1.6 (collision via the side store — solidity is HP-driven),
##       AC-5.6.2 (relic break → signal, once).

## Emitted exactly once, when the relic cell's block reaches 0 HP and is removed.
signal relic_collected(cell: Vector2i)

var _tables: Dictionary
var _run_seed: int
var _mine_width: int
var _mine_height: int
var _shaft_width: int
var _chunk_height: int
var _mine_hardness_mult: float

## The top-left anchor cell of this mine's 2×2 relic, or (-1,-1) if none. Pure fn of
## (mine_seed, relic config); resolved once at construction.
var _relic_cell: Vector2i
## The 4 absolute cells of the relic's 2×2 footprint (the anchor + the 3 other cells),
## resolved once at construction from the SAME BlockGen.relic_anchor the gen uses (so the
## latch never targets cells gen didn't stamp `relic`). Empty if there is no relic.
var _relic_footprint: Array[Vector2i] = []
## Cells of the footprint still un-broken; the relic is collected when it reaches 0 (the
## 4th/last relic cell excavated). Counting to N preserves the idempotent latch.
var _relic_cells_remaining: int = 0
## Guards against re-emitting relic_collected (idempotent; never recycles).
var _relic_collected: bool = false

## Per-chunk data: chunk_y -> { "hp": PackedInt32Array, "ids": Array }
var _chunks: Dictionary = {}
var _newly_loaded: Array = []
var _just_unloaded: Array = []

func _init(tables: Dictionary, run_seed: int, mine_hardness_mult: float = 1.0) -> void:
	_tables = tables
	_run_seed = run_seed
	_mine_hardness_mult = mine_hardness_mult
	_mine_width = Registry.mine_width_cells(tables)
	_mine_height = Registry.mine_height_cells(tables)
	_shaft_width = Registry.shaft_width(tables)
	_chunk_height = Registry.chunk_height(tables)
	_relic_cell = BlockGen.relic_anchor(tables, run_seed)
	var fp: Array = BlockGen.relic_footprint(tables, run_seed)
	for c in fp:
		_relic_footprint.append(c)
	_relic_cells_remaining = _relic_footprint.size()

## Total bounded mine width in cells.
var mine_width: int:
	get:
		return _mine_width

## Total bounded mine height in cells.
var mine_height: int:
	get:
		return _mine_height

## Descent corridor width in cells.
var shaft_width: int:
	get:
		return _shaft_width

## Chunk height in cells.
var chunk_height: int:
	get:
		return _chunk_height

## Per-mine hardness HP multiplier in effect for this grid (AC-5.2.1).
var mine_hardness_mult: float:
	get:
		return _mine_hardness_mult

## The relic's top-left anchor cell for this mine, or (-1,-1) if none (2×2 footprint).
var relic_cell: Vector2i:
	get:
		return _relic_cell

## Whether the relic has already been collected (signal already fired).
var relic_collected_already: bool:
	get:
		return _relic_collected

# ── Chunk management ──────────────────────────────────────────────────────

## Ensure a chunk is loaded. Generates blocks via BlockGen + initializes HP
## from the SCALED formula (AC-5.2.1) applied once, here, at chunk init.
func ensure_chunk(chunk_y: int) -> void:
	if _chunks.has(chunk_y):
		return
	if chunk_y < 0:
		return
	var base_y: int = chunk_y * _chunk_height
	if _mine_height > 0 and base_y >= _mine_height:
		return
	var size: int = _mine_width * _chunk_height
	var hp := PackedInt32Array()
	hp.resize(size)
	var ids: Array = []
	ids.resize(size)

	# Build the whole chunk in one pass: one FastNoiseLite allocation + one weight-table
	# lookup per row instead of one per cell (PERF-01). generate_region is the same pure
	# fn as block_at — same seed + cell → same output (test_determinism_fresh_region_matches_cell_calls).
	var region: Array = BlockGen.generate_region(
		_tables, _run_seed, 0, base_y, _mine_width, _chunk_height
	)
	for ly in range(_chunk_height):
		var world_y: int = base_y + ly
		for lx in range(_mine_width):
			var idx: int = ly * _mine_width + lx
			var block_id: String = "air"
			if _mine_height <= 0 or world_y < _mine_height:
				block_id = region[ly][lx]
			ids[idx] = block_id
			# AC-5.2.1: HP scaled by depth + per-mine hardness, applied once here.
			hp[idx] = Registry.scaled_block_hp(_tables, block_id, world_y, _mine_hardness_mult)

	_chunks[chunk_y] = {"hp": hp, "ids": ids}

## Convert world cell_y to chunk index (floor division — correct for negatives).
func cell_to_chunk(cell_y: int) -> int:
	if cell_y >= 0:
		@warning_ignore("integer_division")
		return cell_y / _chunk_height
	# Floor division for negative y (shouldn't occur in normal play).
	@warning_ignore("integer_division")
	return (cell_y - _chunk_height + 1) / _chunk_height

## Unload a chunk, freeing its memory.
func unload_chunk(chunk_y: int) -> void:
	_chunks.erase(chunk_y)

## Number of currently loaded chunks.
func loaded_chunk_count() -> int:
	return _chunks.size()

## Array of currently loaded chunk indices.
func loaded_chunks() -> Array:
	return _chunks.keys()

## Chunks loaded by the most recent update_window call (for incremental rendering).
func newly_loaded_chunks() -> Array:
	return _newly_loaded

## Chunks unloaded by the most recent update_window call (for incremental erasure).
func just_unloaded_chunks() -> Array:
	return _just_unloaded

## Manage the chunk window: load chunks in [center - half, center + half],
## unload everything outside. AC-5.1.2: keeps resident count bounded.
func update_window(center_chunk_y: int, half_size: int) -> void:
	var lo: int = center_chunk_y - half_size
	var hi: int = center_chunk_y + half_size
	var max_chunk: int = cell_to_chunk(maxi(0, _mine_height - 1)) if _mine_height > 0 else hi
	var before: Array = _chunks.keys()
	# Load chunks in range.
	for cy in range(maxi(0, lo), mini(hi, max_chunk) + 1):
		ensure_chunk(cy)
	# Unload chunks outside range.
	var to_unload: Array = []
	for cy in _chunks.keys():
		if cy < lo or cy > hi:
			to_unload.append(cy)
	for cy in to_unload:
		unload_chunk(cy)
	# Track diff for incremental rendering (PERF-02).
	_newly_loaded = []
	_just_unloaded = to_unload
	for cy in _chunks.keys():
		if not before.has(cy):
			_newly_loaded.append(cy)

# ── Cell access ───────────────────────────────────────────────────────────

## Local index within a chunk's flat array.
func _local_index(cell_x: int, cell_y: int) -> int:
	var local_y: int = cell_y - cell_to_chunk(cell_y) * _chunk_height
	return local_y * _mine_width + cell_x

func in_bounds(cell_x: int, cell_y: int) -> bool:
	if cell_x < 0 or cell_x >= _mine_width:
		return false
	if cell_y < 0:
		return false
	if _mine_height > 0 and cell_y >= _mine_height:
		return false
	return true

## Get current HP of a cell. Returns 0 for unloaded/air/broken cells.
func get_hp(cell_x: int, cell_y: int) -> int:
	if not in_bounds(cell_x, cell_y):
		return 0
	var cy: int = cell_to_chunk(cell_y)
	if not _chunks.has(cy):
		return 0
	return _chunks[cy]["hp"][_local_index(cell_x, cell_y)]

## Build a {Vector2i: hp} window over a rectangular region of cells [left, left+width) ×
## [top_row, bottom_row]. Used by the support-descent scan (PlatformLogic.next_support_row) to
## look at the corridor cells below the platform without the UI controller hand-rolling the loop.
## Pure (only reads get_hp), so it's headless-testable on a BlockGrid directly. Unloaded cells
## read as 0 HP (air), matching get_hp.
func hp_window(left: int, width: int, top_row: int, bottom_row: int) -> Dictionary:
	var out: Dictionary = {}
	for ry in range(top_row, bottom_row + 1):
		for x in range(left, left + width):
			out[Vector2i(x, ry)] = get_hp(x, ry)
	return out

## Get the block id of a cell. Returns "air" for unloaded cells.
func get_block_id(cell_x: int, cell_y: int) -> String:
	if not in_bounds(cell_x, cell_y):
		return "air"
	var cy: int = cell_to_chunk(cell_y)
	if not _chunks.has(cy):
		return "air"
	return _chunks[cy]["ids"][_local_index(cell_x, cell_y)]

## Whether a cell is solid (HP > 0). Solidity is HP-driven so a broken cell stops
## providing collision (AC-5.1.6: blocks collide while solid, charges bounce off).
func is_solid(cell_x: int, cell_y: int) -> bool:
	return get_hp(cell_x, cell_y) > 0

## Set a cell's HP directly (testing / authored placement). Clamped to >= 0.
## Writes to the side array only; the TileMap cell id is untouched (the side-store
## contract — AC-5.2.2). Marks the cell air if HP hits 0 and fires the relic signal.
func set_hp(cell_x: int, cell_y: int, value: int) -> void:
	if not in_bounds(cell_x, cell_y):
		return
	var cy: int = cell_to_chunk(cell_y)
	if not _chunks.has(cy):
		return
	var idx: int = _local_index(cell_x, cell_y)
	var prev: int = _chunks[cy]["hp"][idx]
	var v: int = maxi(0, value)
	_chunks[cy]["hp"][idx] = v
	# Only a genuine solid→broken transition counts as a break (so set_hp(0) on an
	# already-air cell is a no-op and never fires the relic signal spuriously).
	if v == 0 and prev > 0:
		_break_cell(cy, idx, Vector2i(cell_x, cell_y))

## Damage a cell by amount. Returns remaining HP. 0 means broken.
## AC-5.2.7: surviving blocks retain accumulated damage between calls.
func damage(cell_x: int, cell_y: int, amount: int) -> int:
	if not in_bounds(cell_x, cell_y):
		return 0
	var cy: int = cell_to_chunk(cell_y)
	if not _chunks.has(cy):
		return 0
	var idx: int = _local_index(cell_x, cell_y)
	var hp_arr: PackedInt32Array = _chunks[cy]["hp"]
	var current: int = hp_arr[idx]
	if current <= 0:
		return 0
	var remaining: int = maxi(0, current - amount)
	hp_arr[idx] = remaining
	if remaining == 0:
		_break_cell(cy, idx, Vector2i(cell_x, cell_y))
	return remaining

## Internal: clear a cell to air and, if it was a relic footprint cell, count it down;
## when the LAST (4th) relic cell breaks, fire relic_collected EXACTLY ONCE (AC-5.6.2).
## Excavating the whole 2×2 reads as "dig out the relic" and leaves no orphan solid cells.
## The signal carries the anchor (top-left), matching the pre-2×2 contract callers expect.
func _break_cell(chunk_y: int, idx: int, cell: Vector2i) -> void:
	_chunks[chunk_y]["ids"][idx] = "air"
	if _relic_collected:
		return
	if _relic_footprint.has(cell):
		_relic_cells_remaining -= 1
		if _relic_cells_remaining <= 0:
			_relic_collected = true
			relic_collected.emit(_relic_cell)

# ── Blast integration ─────────────────────────────────────────────────────

## Build an HP snapshot {Vector2i: int} for cells in blast radius of center.
## Only includes cells with HP > 0 (skips air/broken). Used by Blast.resolve().
func hp_snapshot_blast(center: Vector2i, radius: int) -> Dictionary:
	var snapshot: Dictionary = {}
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var x: int = center.x + dx
			var y: int = center.y + dy
			if not in_bounds(x, y):
				continue
			var hp: int = get_hp(x, y)
			if hp > 0:
				snapshot[Vector2i(x, y)] = hp
	return snapshot

## Get block IDs for an array of Vector2i cells. Returns {Vector2i: String}.
func block_ids_for(cells: Array) -> Dictionary:
	var result: Dictionary = {}
	for cell in cells:
		result[cell] = get_block_id(cell.x, cell.y)
	return result

## Apply blast results to the grid: write new_hp values, mark broken cells as air.
## Broken relic cells fire relic_collected once (AC-5.6.2).
func apply_blast(blast_result: Dictionary) -> void:
	var new_hp: Dictionary = blast_result.get("new_hp", {})
	for cell in new_hp:
		var cy: int = cell_to_chunk(cell.y)
		if not _chunks.has(cy):
			continue
		var idx: int = _local_index(cell.x, cell.y)
		var val: int = int(new_hp[cell])
		_chunks[cy]["hp"][idx] = val
		if val <= 0:
			_break_cell(cy, idx, Vector2i(cell.x, cell.y))
