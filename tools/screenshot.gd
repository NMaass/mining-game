extends SceneTree
## Visual-verification helper (dev-only, NOT part of the gates). Boots a scene, renders a few
## frames, and saves a PNG so visual-only ACs (textured block identity AC-5.10.2/5.10.3,
## explosion look AC-5.9.1, HUD layout) can be eyeballed and attached as honest evidence — the
## headless test suite proves the data path, this proves the pixels.
##
## Run (NOT --headless; needs a real rendering context):
##   godot --path . -s res://tools/screenshot.gd
##   godot --path . -s res://tools/screenshot.gd -- res://scenes/mine.tscn reports/mine.png
##
## Args (optional, after `--`): <scene_path> <output_png_path>. Defaults boot mine.tscn →
## reports/block_art_render.png. Exits non-zero hint via the printed save error code.

const DEFAULT_SCENE := "res://scenes/mine.tscn"
const DEFAULT_OUT := "res://reports/block_art_render.png"
const SETTLE_FRAMES := 14

var _n := 0
var _out := DEFAULT_OUT

func _initialize() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = argv[0] if argv.size() >= 1 else DEFAULT_SCENE
	if argv.size() >= 2:
		_out = argv[1] if argv[1].begins_with("res://") or argv[1].begins_with("user://") else "res://" + argv[1]
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("screenshot: could not load scene %s" % scene_path)
		quit(1)
		return
	root.add_child(packed.instantiate())

func _process(_delta: float) -> bool:
	_n += 1
	if _n < SETTLE_FRAMES:
		return false  # keep the main loop running until the scene has rendered
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	print("screenshot: saved '%s' err=%s size=%s" % [_out, err, img.get_size()])
	return true  # done → quit
