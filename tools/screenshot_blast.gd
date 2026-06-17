extends SceneTree
## Dev-only visual check for the explosion-cluster VFX: boots mine.tscn, fires a blast at an ore
## cell, lets the flash/ring/sparks/debris/popups render a couple of frames, and saves a PNG.
## NOT part of the gates. Run (needs a real GL context, not --headless):
##   godot --path . -s res://tools/screenshot_blast.gd -- reports/explosion_blast.png

const Reg := preload("res://scripts/core/registry.gd")
const TP := preload("res://scripts/core/throw_params.gd")
const GD := preload("res://scripts/systems/game_data.gd")

var _n := 0
var _out := "res://reports/explosion_blast.png"
var _mine: Node = null
var _fired := false
var _tables: Dictionary = {}

func _initialize() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() >= 1:
		_out = argv[0] if argv[0].begins_with("res://") else "res://" + argv[0]
	var gd := GD.new()
	gd.load_all()
	_tables = gd.tables
	var packed: PackedScene = load("res://scenes/mine.tscn")
	_mine = packed.instantiate()
	root.add_child(_mine)

func _find_ore(grid) -> Vector2i:
	var width: int = Reg.mine_width_cells(_tables)
	var height: int = Reg.chunk_height(_tables)
	for cy in grid.loaded_chunks():
		var base_y: int = cy * height
		for ly in range(height):
			for x in range(width):
				var y: int = base_y + ly
				if grid.is_solid(x, y) and grid.get_block_id(x, y) in ["ore_copper", "ore_gold"]:
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func _process(_delta: float) -> bool:
	_n += 1
	if _n == 4 and not _fired:
		_fired = true
		var grid = _mine.grid
		var cell := _find_ore(grid)
		if cell.x < 0:
			cell = Vector2i(Reg.shaft_left_cell(_tables), 3)
		# Make a small cluster around the cell easy to clear so debris + popups fire.
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if grid.is_solid(cell.x + dx, cell.y + dy):
					grid.set_hp(cell.x + dx, cell.y + dy, 1)
		_mine.resolve_blast(cell, TP.from_explosive(_tables, Reg.free_charge_id(_tables)))
	if _n < 5:
		return false
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	print("screenshot_blast: saved '%s' err=%s size=%s" % [_out, err, img.get_size()])
	return true
