extends SceneTree
## One-shot golden generator for the MAPGEN unit. Emits the pinned gen regions to
## tests/golden/. Run manually after a DELIBERATE generation change:
##   godot --headless --path . -s tools/gen_golden.gd
## The TESTS never self-write goldens (AGENTS.md golden contract); this tool is the
## explicit, human-invoked pinning step, separate from the test harness.

const BlockGenC = preload("res://scripts/core/block_gen.gd")
const RegistryC = preload("res://scripts/core/registry.gd")


func _init() -> void:
	var tables: Dictionary = _load_tables()
	var seed_val: int = RegistryC.run_seed(tables)
	var width: int = RegistryC.mine_width_cells(tables)
	var cap: int = RegistryC.cap_depth_cells(tables)
	# Surface region (shallow, dirt/copper/silver dominated).
	_write("res://tests/golden/gen_surface.txt", BlockGenC.generate_region(tables, seed_val, 0, 0, width, 16))
	# Mid-cap region (smoothly richer, with mid/deep ores entering).
	_write("res://tests/golden/gen_mid.txt", BlockGenC.generate_region(tables, seed_val, 0, 5000, width, 16))
	# Deep region (below the cap; frozen cap_weights — proves deterministic far descent).
	_write("res://tests/golden/gen_deep.txt", BlockGenC.generate_region(tables, seed_val, 0, cap + 50, width, 16))
	# Cap-transition region straddling cap_depth_cells (locks the lerp→clamp boundary).
	_write("res://tests/golden/gen_cap_transition.txt", BlockGenC.generate_region(tables, seed_val, 0, cap - 8, width, 16))
	# Deep ore-rich window before the cap, proving the overlay layer participates.
	_write("res://tests/golden/gen_ore_deep.txt", BlockGenC.generate_region(tables, seed_val, 0, 8000, width, 16))
	var anchor: Vector2i = BlockGenC.relic_anchor(tables, seed_val)
	_write_text("res://tests/golden/relic_anchor.txt",
		"anchor:%d,%d\nfootprint:%s\n" % [anchor.x, anchor.y, _serialize_cells(BlockGenC.relic_footprint(tables, seed_val))]
	)
	print("golden regions written.")
	quit()


func _load_tables() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/")
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open("res://data/" + file_name, FileAccess.READ)
		var json := JSON.new()
		json.parse(f.get_as_text())
		out[file_name.get_basename()] = json.data
	return out


func _write(path: String, region: Array) -> void:
	var lines: PackedStringArray = PackedStringArray()
	for row in region:
		var cells: PackedStringArray = PackedStringArray()
		for cell in row:
			cells.append(str(cell))
		lines.append(",".join(cells))
	var text: String = "\n".join(lines) + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", path)


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", path)


func _serialize_cells(cells: Array) -> String:
	var parts := PackedStringArray()
	for c in cells:
		parts.append("%d,%d" % [c.x, c.y])
	return ";".join(parts)
