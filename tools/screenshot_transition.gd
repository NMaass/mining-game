extends SceneTree
## Visual-verification helper for the UX-polish transition beats (dev-only, NOT a gate).
## Boots mine.tscn and captures two honest PNGs:
##   reports/transition_toast.png — the non-blocking "Relic recovered  +N Prestige" banner;
##   reports/transition_veil.png  — the dig-reveal veil mid-fade over the live mine.
## The headless suite proves the alpha math + wiring; this proves the pixels.
##
## Run (NOT --headless; needs a real rendering context):
##   godot --path . -s res://tools/screenshot_transition.gd

const TOAST_OUT := "res://reports/transition_toast.png"
const VEIL_OUT := "res://reports/transition_veil.png"

var _mine: Node = null
var _t := 0.0
var _toast_fired := false
var _toast_shot := false
var _veil_fired := false
var _veil_shot := false

func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/mine.tscn")
	if packed == null:
		push_error("screenshot_transition: could not load mine.tscn")
		quit(1)
		return
	_mine = packed.instantiate()
	root.add_child(_mine)

func _hud() -> Node:
	return _mine.get_node_or_null("Hud") if _mine != null else null

func _process(delta: float) -> bool:
	_t += delta
	var hud := _hud()
	if hud == null:
		return false
	# Let the boot reveal fade out first, then raise the relic toast (long hold so it sits still).
	if not _toast_fired and _t > 1.2:
		_toast_fired = true
		hud.call("show_toast", "Relic recovered   +1 Prestige", 0.2, 3.0, 0.5, 1.0)
	# Capture the toast ~0.5s in (past the fade-in, full alpha).
	if _toast_fired and not _toast_shot and _t > 1.75:
		_toast_shot = true
		_save(TOAST_OUT)
	# Then drive a reveal veil and capture it mid-fade (a wash over the live mine).
	if _toast_shot and not _veil_fired and _t > 2.2:
		_veil_fired = true
		hud.call("reveal", 0.1, 1.6, 1.0)
	if _veil_fired and not _veil_shot and _t > 2.85:
		_veil_shot = true
		_save(VEIL_OUT)
		return true  # done
	return false

func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	var err := img.save_png(path)
	print("screenshot_transition: saved '%s' err=%s size=%s" % [path, err, img.get_size()])
