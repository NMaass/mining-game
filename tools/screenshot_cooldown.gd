extends SceneTree
## Visual-verification helper (dev-only, NOT part of the gates). Boots mine.tscn, FORCES a long
## mid-cooldown state on the throw button (arms ThrowControls with a long cooldown and advances it
## partway WITHOUT any detonation), then renders a PNG so the cooldown drain band + countdown + the
## desaturated button can be eyeballed as honest evidence.
##
## Run (NOT --headless; needs a real rendering context):
##   godot --path . -s res://tools/screenshot_cooldown.gd -- reports/cooldown.png

const OUT_DEFAULT := "res://reports/cooldown.png"
const SETTLE_FRAMES := 16
const COOLDOWN_TOTAL := 6.0   # long, so the band is large + the countdown is obviously > 1s
const COOLDOWN_ELAPSED := 2.4 # ~60% remaining → a clearly-visible partial drain band

var _n := 0
var _out := OUT_DEFAULT
var _mine: Node = null
var _armed := false

func _initialize() -> void:
	var argv: PackedStringArray = OS.get_cmdline_user_args()
	if argv.size() >= 1:
		_out = argv[0] if argv[0].begins_with("res://") or argv[0].begins_with("user://") else "res://" + argv[0]
	var packed: PackedScene = load("res://scenes/mine.tscn")
	if packed == null:
		push_error("screenshot_cooldown: could not load mine.tscn")
		quit(1)
		return
	_mine = packed.instantiate()
	root.add_child(_mine)

func _arm_cooldown() -> void:
	# Reach the wired ThrowControls + drive the cooldown straight from the timer (no charge, no
	# detonation) — proving the visual is a pure readout of the clock.
	var tc = _mine.get("_throw_controls")
	if tc == null:
		push_error("screenshot_cooldown: ThrowControls not wired")
		return
	tc.start_cooldown(COOLDOWN_TOTAL)
	tc.advance_cooldown(COOLDOWN_ELAPSED)
	# Same per-frame path the live game uses while cooling.
	_mine.call("_update_cooldown_visual")
	_armed = true

func _process(_delta: float) -> bool:
	_n += 1
	# Let the HUD lay out (the button gets its real size) before arming the cooldown band.
	if _n == SETTLE_FRAMES - 4 and not _armed:
		_arm_cooldown()
	if _n < SETTLE_FRAMES:
		return false
	# Re-assert the visual on the render frame in case a layout pass resized the button.
	if _mine != null:
		_mine.call("_update_cooldown_visual")
	var img := root.get_texture().get_image()
	var err := img.save_png(_out)
	print("screenshot_cooldown: saved '%s' err=%s size=%s" % [_out, err, img.get_size()])
	return true
