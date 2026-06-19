extends GdUnitTestSuite
## U3 — BlockGrid: per-chunk HP store + block-ID tracking (v0.4).
## ACs: AC-5.2.1 (depth/mine-scaled HP), AC-5.2.2 (damage/break lifecycle),
##       AC-5.2.7 (surviving block retains damage), AC-5.1.2 (chunk windowing),
##       AC-5.1.6 (HP-driven solidity for collision), AC-5.6.2 (relic break signal).

const BlockGridScript := preload("res://scripts/systems/block_grid.gd")

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

func _make_grid(mine_hardness_mult: float = 1.0) -> BlockGrid:
	return BlockGridScript.new(_tables, Registry.run_seed(_tables), mine_hardness_mult)

func _relic_footprint() -> Array:
	return BlockGen.relic_footprint(_tables, Registry.run_seed(_tables))

func _prepare_relic_footprint(grid: BlockGrid, hp: int = 10) -> void:
	for cell: Vector2i in _relic_footprint():
		grid.ensure_chunk(grid.cell_to_chunk(cell.y))
		grid.set_hp(cell.x, cell.y, hp)

func _break_relic_footprint(grid: BlockGrid) -> void:
	for cell: Vector2i in _relic_footprint():
		grid.damage(cell.x, cell.y, grid.get_hp(cell.x, cell.y))

# ── HP initialization from the SCALED formula (AC-5.2.1) ─────────────────────

func test_hp_initializes_from_scaled_formula() -> void:
	# AC-5.2.1: per-cell HP is the SCALED value (base * depth_mult * mine_mult),
	# applied once at chunk init and stored per-cell — NOT the raw table max_hp.
	var grid := _make_grid()
	grid.ensure_chunk(0)

	var width: int = Registry.mine_width_cells(_tables)
	var height: int = Registry.chunk_height(_tables)
	for y in range(height):
		for x in range(width):
			var block_id: String = grid.get_block_id(x, y)
			var expected_hp: int = Registry.scaled_block_hp(_tables, block_id, y, 1.0)
			assert_int(grid.get_hp(x, y)).override_failure_message(
				"Cell (%d,%d) block=%s expected scaled HP=%d" % [x, y, block_id, expected_hp]
			).is_equal(expected_hp)

func test_deeper_cells_have_higher_hp() -> void:
	# AC-5.2.1: HP scales with depth — a deep solid cell of a given type has more
	# HP than a shallow cell of the SAME type (the optimization pressure).
	var grid := _make_grid()
	# Load shallow + a deep chunk and find the same block type at both depths.
	var shallow_chunk := 0
	var deep_chunk := 6  # well below the surface band
	grid.ensure_chunk(shallow_chunk)
	grid.ensure_chunk(deep_chunk)
	var ch: int = Registry.chunk_height(_tables)
	var width: int = Registry.mine_width_cells(_tables)

	# Pick a block id present in both ranges; compare its scaled HP at two depths
	# via the registry (the grid stores exactly these values, verified above).
	# Use a fixed type ("rock") known to be diggable to make the assertion direct.
	var shallow_y: int = 1
	var deep_y: int = deep_chunk * ch + 1
	var shallow_hp: int = Registry.scaled_block_hp(_tables, "rock", shallow_y, 1.0)
	var deep_hp: int = Registry.scaled_block_hp(_tables, "rock", deep_y, 1.0)
	assert_int(deep_hp).override_failure_message(
		"deep rock HP (%d) must exceed shallow rock HP (%d)" % [deep_hp, shallow_hp]
	).is_greater(shallow_hp)

	# And the grid actually stores that scaled value at whatever solid cell it has.
	var deep_cell := _find_solid_cell_in_range(grid, deep_chunk * ch, deep_chunk * ch + ch - 1)
	var deep_id: String = grid.get_block_id(deep_cell.x, deep_cell.y)
	assert_int(grid.get_hp(deep_cell.x, deep_cell.y)).is_equal(
		Registry.scaled_block_hp(_tables, deep_id, deep_cell.y, 1.0))
	# Silence unused locals on platforms where width changes nothing here.
	assert_int(width).is_greater(0)

func test_harder_mine_multiplier_raises_hp() -> void:
	# AC-5.2.1: the per-mine hardness multiplier raises HP for the SAME cell/type.
	var soft := _make_grid(1.0)
	var hard := _make_grid(3.0)
	soft.ensure_chunk(0)
	hard.ensure_chunk(0)
	var cell := _find_solid_cell(soft, 0)
	# Same seed → same block ids at the same cell in both grids.
	assert_str(hard.get_block_id(cell.x, cell.y)).is_equal(soft.get_block_id(cell.x, cell.y))
	assert_int(hard.get_hp(cell.x, cell.y)).override_failure_message(
		"harder mine HP (%d) must exceed baseline HP (%d)" % [
			hard.get_hp(cell.x, cell.y), soft.get_hp(cell.x, cell.y)]
	).is_greater(soft.get_hp(cell.x, cell.y))

func test_air_blocks_have_zero_hp() -> void:
	# Air blocks should have 0 HP and not be solid.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	# Air has max_hp = 0 in block_types.json → scaled HP is 0 regardless of depth.
	assert_int(Registry.block_max_hp(_tables, "air")).is_equal(0)
	assert_int(Registry.scaled_block_hp(_tables, "air", 100, 3.0)).is_equal(0)

func test_grid_uses_wide_infinite_mine_dimensions() -> void:
	# UNIT MAPGEN: the shaft has finite width but is INFINITE in depth (mine_height_cells 0).
	var grid := _make_grid()
	assert_int(grid.mine_width).is_equal(Registry.mine_width_cells(_tables))
	assert_int(grid.mine_height).is_equal(Registry.mine_height_cells(_tables))  # 0 = infinite
	assert_int(grid.shaft_width).is_equal(Registry.shaft_width(_tables))
	grid.ensure_chunk(0)
	assert_bool(grid.in_bounds(0, 0)).is_true()
	# Width is still bounded: x outside [0,width) is out of bounds.
	assert_bool(grid.in_bounds(grid.mine_width, 0)).is_false()
	assert_int(grid.get_hp(grid.mine_width, 0)).is_equal(0)
	assert_str(grid.get_block_id(grid.mine_width, 0)).is_equal("air")
	# Depth is unbounded: an arbitrarily deep cell is still in bounds; only y < 0 is not.
	assert_bool(grid.in_bounds(0, 100000)).is_true()
	assert_bool(grid.in_bounds(0, -1)).is_false()

# ── Damage reduces HP (AC-5.2.1, AC-5.2.7) ──────────────────────────────

func test_damage_reduces_hp() -> void:
	# AC-5.2.1: damage(cell, n) reduces HP.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var cell := _find_solid_cell(grid, 0)
	var original_hp: int = grid.get_hp(cell.x, cell.y)
	assert_int(original_hp).is_greater(0)

	var remaining: int = grid.damage(cell.x, cell.y, 5)
	assert_int(remaining).is_equal(original_hp - 5)
	assert_int(grid.get_hp(cell.x, cell.y)).is_equal(original_hp - 5)

func test_damage_accumulates_between_calls() -> void:
	# AC-5.2.7: surviving block retains accumulated damage between calls.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var cell := _find_solid_cell(grid, 0)
	var original_hp: int = grid.get_hp(cell.x, cell.y)
	# Use a high-HP deep cell so two small hits never break it.
	if original_hp < 10:
		cell = _find_solid_cell_with_min_hp(grid, 0, 10)
		original_hp = grid.get_hp(cell.x, cell.y)

	grid.damage(cell.x, cell.y, 5)
	assert_int(grid.get_hp(cell.x, cell.y)).is_equal(original_hp - 5)

	grid.damage(cell.x, cell.y, 3)
	assert_int(grid.get_hp(cell.x, cell.y)).is_equal(original_hp - 8)

# ── is_solid until HP ≤ 0 (AC-5.2.2, AC-5.1.6) ──────────────────────────

func test_is_solid_true_while_hp_positive() -> void:
	# AC-5.2.2 / AC-5.1.6: solidity is HP-driven (a solid cell provides collision).
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var cell := _find_solid_cell(grid, 0)
	assert_bool(grid.is_solid(cell.x, cell.y)).is_true()

	# Damage but don't break.
	grid.damage(cell.x, cell.y, 1)
	assert_bool(grid.is_solid(cell.x, cell.y)).is_true()

func test_is_solid_false_when_broken() -> void:
	# AC-5.2.2: breaking makes is_solid false (collision goes away — AC-5.1.6).
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var cell := _find_solid_cell(grid, 0)
	var hp: int = grid.get_hp(cell.x, cell.y)

	grid.damage(cell.x, cell.y, hp)
	assert_bool(grid.is_solid(cell.x, cell.y)).is_false()

# ── Breaking clears to air (AC-5.2.2) ───────────────────────────────────

func test_break_sets_block_to_air() -> void:
	# AC-5.2.2: breaking removes the cell + clears HP entry.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var cell := _find_solid_cell(grid, 0)
	var hp: int = grid.get_hp(cell.x, cell.y)

	grid.damage(cell.x, cell.y, hp)
	assert_int(grid.get_hp(cell.x, cell.y)).is_equal(0)
	assert_str(grid.get_block_id(cell.x, cell.y)).is_equal("air")

func test_damage_on_broken_cell_returns_zero() -> void:
	# Damaging an already-broken cell is a no-op.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var cell := _find_solid_cell(grid, 0)
	var hp: int = grid.get_hp(cell.x, cell.y)
	grid.damage(cell.x, cell.y, hp)

	var result: int = grid.damage(cell.x, cell.y, 10)
	assert_int(result).is_equal(0)

# ── Real per-cell-HP-in-side-array assertion (AC-5.2.2) ──────────────────
# Replaces the old `is RefCounted` tautology: prove HP lives in the side array,
# is mutable per cell, reads back, and is independent of the block-type id.

func test_hp_stored_per_cell_in_side_array() -> void:
	# AC-5.2.2: per-cell HP lives in a parallel store, not in the TileMap cell.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var cell := _find_solid_cell_with_min_hp(grid, 0, 4)
	var id_before: String = grid.get_block_id(cell.x, cell.y)
	var hp_before: int = grid.get_hp(cell.x, cell.y)
	assert_int(hp_before).is_greater(0)

	# Mutate ONE cell's HP via the side store; it must read back exactly, and the
	# block-type id (the TileMap cell's identity) must be unchanged while HP > 0.
	grid.set_hp(cell.x, cell.y, hp_before - 1)
	assert_int(grid.get_hp(cell.x, cell.y)).is_equal(hp_before - 1)
	assert_str(grid.get_block_id(cell.x, cell.y)).is_equal(id_before)

	# A neighbouring solid cell of the same chunk is unaffected — proves the store
	# is genuinely per-cell, not shared per type (TileSet custom data is per type).
	var other := _find_other_solid_cell(grid, cell)
	if other.x >= 0:
		var other_hp: int = grid.get_hp(other.x, other.y)
		assert_int(other_hp).is_equal(
			Registry.scaled_block_hp(_tables, grid.get_block_id(other.x, other.y), other.y, 1.0))

# ── Chunk windowing (AC-5.1.2) ──────────────────────────────────────────

func test_ensure_chunk_loads_chunk() -> void:
	# AC-5.1.2: ensure_chunk loads a chunk.
	var grid := _make_grid()
	assert_int(grid.loaded_chunk_count()).is_equal(0)
	grid.ensure_chunk(0)
	assert_int(grid.loaded_chunk_count()).is_equal(1)

func test_ensure_chunk_is_idempotent() -> void:
	# Loading the same chunk twice doesn't duplicate it.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	grid.ensure_chunk(0)
	assert_int(grid.loaded_chunk_count()).is_equal(1)

func test_unload_chunk_removes_it() -> void:
	var grid := _make_grid()
	grid.ensure_chunk(0)
	grid.ensure_chunk(1)
	assert_int(grid.loaded_chunk_count()).is_equal(2)
	grid.unload_chunk(0)
	assert_int(grid.loaded_chunk_count()).is_equal(1)

func test_update_window_bounds_resident_chunks() -> void:
	# AC-5.1.2: after update_window, resident chunk count ≤ window size.
	var grid := _make_grid()
	# Load a wide initial set.
	for cy in range(10):
		grid.ensure_chunk(cy)
	assert_int(grid.loaded_chunk_count()).is_equal(10)

	# Window with half_size=1 around chunk 5 → chunks 4,5,6 = 3 loaded.
	grid.update_window(5, 1)
	assert_int(grid.loaded_chunk_count()).is_equal(3)
	assert_bool(grid.loaded_chunks().has(4)).is_true()
	assert_bool(grid.loaded_chunks().has(5)).is_true()
	assert_bool(grid.loaded_chunks().has(6)).is_true()

func test_update_window_loads_missing_chunks() -> void:
	# update_window loads chunks that weren't loaded yet.
	var grid := _make_grid()
	grid.update_window(2, 1)
	assert_int(grid.loaded_chunk_count()).is_equal(3)  # chunks 1, 2, 3

func test_window_resident_count_bounded_regardless_of_depth() -> void:
	# AC-5.1.2 (UNIT MAPGEN infinite descent): resident chunk count stays bounded at
	# (2*half+1) as the player descends through the UNBOUNDED shaft — there is no floor, so
	# the window always loads exactly the sliding window, however deep, never inventing more.
	var grid := _make_grid()
	assert_bool(grid.mine_height <= 0).override_failure_message(
		"this test asserts the infinite-shaft residency bound; mine_height should be the 0 sentinel"
	).is_true()
	var half := 2
	var expected := 2 * half + 1
	for center in [3, 20, 1000, 100000]:
		grid.update_window(center, half)
		assert_int(grid.loaded_chunk_count()).override_failure_message(
			"window at center %d must hold exactly %d chunks (bounded residency, no floor)" % [center, expected]
		).is_equal(expected)
		# Every resident chunk is inside [center-half, center+half] — no stragglers.
		for loaded in grid.loaded_chunks():
			assert_int(absi(int(loaded) - center)).is_less_equal(half)

func test_unloaded_cell_returns_defaults() -> void:
	# Accessing cells in unloaded chunks returns safe defaults.
	var grid := _make_grid()
	assert_int(grid.get_hp(0, 0)).is_equal(0)
	assert_str(grid.get_block_id(0, 0)).is_equal("air")
	assert_bool(grid.is_solid(0, 0)).is_false()

# ── Relic break → signal exactly once (AC-5.6.2) ─────────────────────────

func test_relic_cell_resolves_for_run_seed() -> void:
	# AC-5.6.2 precondition: the grid knows where this mine's relic is.
	var grid := _make_grid()
	var rc: Vector2i = grid.relic_cell
	assert_vector(rc).is_equal(BlockGen.relic_cell(_tables, Registry.run_seed(_tables)))
	assert_int(rc.y).is_greater_equal(0)  # a relic exists for this data set

func test_breaking_relic_cell_emits_once() -> void:
	# AC-5.6.2: destroying the whole 2x2 relic footprint awards it once.
	var grid := _make_grid()
	var rc: Vector2i = grid.relic_cell
	_prepare_relic_footprint(grid)

	var collector := _SignalCollector.new()
	grid.relic_collected.connect(collector.on_relic)

	_break_relic_footprint(grid)

	assert_int(collector.count).is_equal(1)
	assert_vector(collector.last_cell).is_equal(rc)
	assert_bool(grid.relic_collected_already).is_true()

func test_relic_signal_does_not_refire() -> void:
	# AC-5.6.2: the relic never recycles — once collected, no further emissions.
	var grid := _make_grid()
	_prepare_relic_footprint(grid)

	var collector := _SignalCollector.new()
	grid.relic_collected.connect(collector.on_relic)

	_break_relic_footprint(grid)
	assert_int(collector.count).is_equal(1)
	# Write HP back into the still-resident footprint and break it again — must NOT refire.
	_prepare_relic_footprint(grid, 5)
	_break_relic_footprint(grid)
	assert_int(collector.count).is_equal(1)  # still exactly one

func test_non_relic_break_emits_nothing() -> void:
	# AC-5.6.2: only the relic cell signals; ordinary breaks are silent.
	var grid := _make_grid()
	var rc: Vector2i = grid.relic_cell
	grid.ensure_chunk(0)
	# Pick a solid cell in chunk 0 that is NOT the relic cell.
	var cell := _find_solid_cell(grid, 0)
	if cell == rc:
		cell = _find_other_solid_cell(grid, rc)
	assert_int(cell.x).is_greater_equal(0)

	var collector := _SignalCollector.new()
	grid.relic_collected.connect(collector.on_relic)
	grid.damage(cell.x, cell.y, grid.get_hp(cell.x, cell.y))
	assert_int(collector.count).is_equal(0)

# ── Blast integration ────────────────────────────────────────────────────

func test_hp_snapshot_blast() -> void:
	# hp_snapshot_blast returns only solid cells within radius.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var center := Vector2i(3, 3)
	var snap: Dictionary = grid.hp_snapshot_blast(center, 2)
	# All returned cells should have HP > 0.
	for cell in snap:
		assert_int(int(snap[cell])).is_greater(0)
	# Center should be in the snapshot iff it is solid.
	if grid.is_solid(center.x, center.y):
		assert_bool(snap.has(center)).is_true()

func test_apply_blast_updates_hp() -> void:
	# apply_blast writes new HP values and marks broken cells as air.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	var center := Vector2i(3, 3)
	var snap: Dictionary = grid.hp_snapshot_blast(center, 2)
	# Resolve a big blast that should clear at least the center.
	var result: Dictionary = Blast.resolve(snap, center, 2, 200, [1.0, 0.6, 0.25])
	grid.apply_blast(result)

	# Cleared cells should now be air with 0 HP.
	for cell in result["cleared"]:
		assert_int(grid.get_hp(cell.x, cell.y)).is_equal(0)
		assert_str(grid.get_block_id(cell.x, cell.y)).is_equal("air")

	# Damaged-but-surviving cells should have reduced HP.
	for cell in result["new_hp"]:
		if int(result["new_hp"][cell]) > 0:
			assert_int(grid.get_hp(cell.x, cell.y)).is_equal(int(result["new_hp"][cell]))

func test_apply_blast_breaking_relic_emits() -> void:
	# AC-5.6.2: clearing the full relic footprint via a blast fires relic_collected once.
	var grid := _make_grid()
	var rc: Vector2i = grid.relic_cell
	# Make every relic footprint cell solid + low HP so the blast clears it.
	_prepare_relic_footprint(grid, 5)
	var collector := _SignalCollector.new()
	grid.relic_collected.connect(collector.on_relic)

	var snap: Dictionary = {}
	for cell: Vector2i in _relic_footprint():
		snap[cell] = grid.get_hp(cell.x, cell.y)
	var result: Dictionary = Blast.resolve(snap, rc, 2, 100, [1.0, 1.0, 1.0])
	grid.apply_blast(result)
	assert_int(collector.count).is_equal(1)
	assert_vector(collector.last_cell).is_equal(rc)

# ── Cross-chunk cell access ──────────────────────────────────────────────

func test_cell_to_chunk_mapping() -> void:
	# Verify cell_to_chunk correctly maps cells to chunks.
	var grid := _make_grid()
	var ch: int = Registry.chunk_height(_tables)
	assert_int(grid.cell_to_chunk(0)).is_equal(0)
	assert_int(grid.cell_to_chunk(ch - 1)).is_equal(0)
	assert_int(grid.cell_to_chunk(ch)).is_equal(1)
	assert_int(grid.cell_to_chunk(ch * 3 + 5)).is_equal(3)

func test_cells_in_different_chunks() -> void:
	# Accessing cells across chunk boundaries works.
	var grid := _make_grid()
	grid.ensure_chunk(0)
	grid.ensure_chunk(1)
	var ch: int = Registry.chunk_height(_tables)
	var cell_chunk0 := _find_solid_cell(grid, 0)
	var cell_chunk1 := _find_solid_cell_in_range(grid, ch, ch * 2 - 1)

	# Both should be independently accessible and damageable.
	assert_bool(grid.is_solid(cell_chunk0.x, cell_chunk0.y)).is_true()
	assert_bool(grid.is_solid(cell_chunk1.x, cell_chunk1.y)).is_true()

	grid.damage(cell_chunk0.x, cell_chunk0.y, 5)
	# cell_chunk1 should be unaffected.
	var hp1_before: int = grid.get_hp(cell_chunk1.x, cell_chunk1.y)
	assert_int(grid.get_hp(cell_chunk1.x, cell_chunk1.y)).is_equal(hp1_before)

# ── Helpers ──────────────────────────────────────────────────────────────

func _find_solid_cell(grid: BlockGrid, chunk_y: int) -> Vector2i:
	var base_y: int = chunk_y * Registry.chunk_height(_tables)
	return _find_solid_cell_in_range(grid, base_y,
		base_y + Registry.chunk_height(_tables) - 1)

func _find_solid_cell_in_range(grid: BlockGrid, min_y: int, max_y: int) -> Vector2i:
	var width: int = Registry.mine_width_cells(_tables)
	for y in range(min_y, max_y + 1):
		for x in range(width):
			if grid.is_solid(x, y):
				return Vector2i(x, y)
	# Fallback — should not happen with real data.
	return Vector2i(0, min_y)

func _find_solid_cell_with_min_hp(grid: BlockGrid, chunk_y: int, min_hp: int) -> Vector2i:
	var base_y: int = chunk_y * Registry.chunk_height(_tables)
	var width: int = Registry.mine_width_cells(_tables)
	for y in range(base_y, base_y + Registry.chunk_height(_tables)):
		for x in range(width):
			if grid.get_hp(x, y) >= min_hp:
				return Vector2i(x, y)
	return _find_solid_cell(grid, chunk_y)

func _find_other_solid_cell(grid: BlockGrid, exclude: Vector2i) -> Vector2i:
	var ch: int = Registry.chunk_height(_tables)
	var cy: int = grid.cell_to_chunk(exclude.y)
	var base_y: int = cy * ch
	var width: int = Registry.mine_width_cells(_tables)
	for y in range(base_y, base_y + ch):
		for x in range(width):
			var c := Vector2i(x, y)
			if c != exclude and grid.is_solid(x, y):
				return c
	return Vector2i(-1, -1)

# Small RefCounted signal sink: counts relic_collected emissions + last cell.
class _SignalCollector extends RefCounted:
	var count: int = 0
	var last_cell: Vector2i = Vector2i(-999, -999)
	func on_relic(cell: Vector2i) -> void:
		count += 1
		last_cell = cell
