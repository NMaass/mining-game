extends SceneTree
## Visual-verification helper (dev-only, NOT a gate). Boots mine.tscn, opens the Settings overlay
## (AC-5.8.3 modal + AC-5.10.1 settings), renders a few frames, and saves a PNG so the new
## player-facing surface can be eyeballed as honest evidence (the headless suite proves the wiring;
## this proves the pixels — a settings dialog, not a placeholder mess).
##
## Run (NOT --headless; needs a real rendering context):
##   godot --path . -s res://tools/screenshot_settings.gd

const OUT := "res://reports/settings_overlay_0830.png"
const SETTLE_FRAMES := 16

var _n := 0
var _opened := false

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/mine.tscn")
	if packed == null:
		push_error("screenshot_settings: could not load mine.tscn")
		quit(1)
		return
	root.add_child(packed.instantiate())

func _process(_delta: float) -> bool:
	_n += 1
	if _n == SETTLE_FRAMES / 2 and not _opened:
		_opened = true
		var mine: Node = root.get_child(root.get_child_count() - 1)
		var overlay: Node = mine.get_node_or_null("Overlay")
		if overlay != null:
			overlay.call("open")
			paused = false  # keep the offline renderer running while the overlay stays visible
	if _n < SETTLE_FRAMES:
		return false
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT)
	print("screenshot_settings: saved '%s' err=%s size=%s" % [OUT, err, img.get_size()])
	return true
