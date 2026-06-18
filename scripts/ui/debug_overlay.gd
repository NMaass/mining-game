class_name DebugOverlay
extends CanvasLayer
## DebugOverlay — a toggleable on-screen diagnostics HUD (UNIT INFRA). Bound to the `toggle_debug`
## action (F3 by default; see project.godot InputMap). Shows the live runtime facts a developer
## needs while reproducing a bug in the actual app: FPS + frame time (the 60-fps perf discipline,
## AC-5.2.9), the active RigidBody2D count (the pooled-collectible/charge cap — a leak shows up here),
## the run seed (so a bad dig is reproducible), the current depth, the selected charge, and the active
## mine id. Plus the Logger's error/warning counts so a crash trail is visible without opening the file.
##
## DESIGN: built in CODE (a Label inside a panel on a high-layer CanvasLayer) rather than an authored
## .tscn — it has no balance/layout tunables worth authoring and must attach to whatever scene is
## running. Hidden by default; `process_mode = ALWAYS` so it keeps updating while the Settings overlay
## pauses the tree (a paused-state bug is exactly when you want the readout). It NEVER mutates game
## state — read-only views only — so toggling it can't change behavior.
##
## SPLIT (mirrors Logger / SettingsState): the READOUT FORMATTING is a PURE static function
## (`format_readout`) taking a plain stats Dictionary, so it is headless-unit-testable without a
## viewport; the Node side just gathers the stats each frame and pushes them through it.
##
## ACs: supports AC-5.2.9 (the perf readout makes a frame-time regression visible). Otherwise pure
## developer infrastructure (no player-facing AC).

## How often (seconds, real time) to refresh the readout — cheap, but no need to rebuild the string
## every frame. Real-time so it keeps ticking under a hit-stop time_scale freeze.
const REFRESH_INTERVAL := 0.25

var _label: Label = null
var _panel: PanelContainer = null
## The Mine controller we read stats from (run seed / depth / selected charge / mine id). Optional —
## the overlay degrades to engine-only stats (FPS / bodies) if it isn't set, so it never hard-depends
## on a particular scene.
var _mine: Node = null
var _accum: float = 0.0

func _ready() -> void:
	layer = 128  # above the HUD + modals
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep updating while the tree is paused
	visible = false
	set_process(true)
	_build_ui()

## Build the panel + label in code (no authored scene). A translucent dark panel anchored top-left
## with a monospace-ish readout. Pure presentation; no tunables.
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DebugPanel"
	_panel.position = Vector2(8, 8)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # never eats gameplay input
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	style.set_content_margin_all(8.0)
	style.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.name = "DebugLabel"
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_label.add_theme_font_size_override("font_size", 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_label)
	add_child(_panel)

## Bind the Mine controller so the overlay can read run seed / depth / selected charge / mine id.
## Read-only — the overlay never calls a mutating method on it.
func bind_mine(mine: Node) -> void:
	_mine = mine

## F3 (toggle_debug) flips visibility. Uses _input (not _unhandled_input) so it works even when a
## focused Control would otherwise consume the key; accept it so it doesn't leak to gameplay. Input
## events don't fire headless — toggle() is the shared code path the test drives.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		toggle()
		get_viewport().set_input_as_handled()

## Show/hide the overlay. The single entry point (the F3 handler and any future button share it).
func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()  # immediate fill so it isn't blank for up to REFRESH_INTERVAL

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < REFRESH_INTERVAL:
		return
	_accum = 0.0
	_refresh()

## Gather the live stats and push them through the pure formatter into the label.
func _refresh() -> void:
	if _label != null:
		_label.text = format_readout(_collect_stats())

## Collect the runtime stats into a plain Dictionary (the input to the pure formatter). Every read is
## guarded — a missing Mine / Logger / tree just omits that line's data, never crashes the overlay.
func _collect_stats() -> Dictionary:
	var stats: Dictionary = {
		"fps": Engine.get_frames_per_second(),
		"frame_ms": 0.0,
		"bodies": _count_active_bodies(),
	}
	var fps: float = float(stats["fps"])
	stats["frame_ms"] = (1000.0 / fps) if fps > 0.0 else 0.0
	if _mine != null:
		# Read-only views; each behind a has_method/null guard so the overlay tolerates a partially
		# built or differently-shaped controller.
		if _mine.has_method("debug_run_seed"):
			stats["seed"] = _mine.call("debug_run_seed")
		if _mine.has_method("debug_depth"):
			stats["depth"] = _mine.call("debug_depth")
		if _mine.has_method("debug_selected_charge"):
			stats["charge"] = _mine.call("debug_selected_charge")
		if _mine.has_method("debug_mine_id"):
			stats["mine"] = _mine.call("debug_mine_id")
	var logger: Node = get_node_or_null("/root/GameLog")
	if logger != null and logger.has_method("count_at"):
		# Level.WARN = 2, Level.ERROR = 3 (see logger.gd Level enum).
		stats["warns"] = logger.call("count_at", 2)
		stats["errors"] = logger.call("count_at", 3)
	return stats

## Count active (non-sleeping) RigidBody2D nodes in the tree — the pooled-collectible / charge budget
## (balance.active_body_cap_*). A climbing count here is the signature of a body leak. Walks the tree
## from the root once per refresh (cheap at the 4 Hz refresh; only while the overlay is visible).
func _count_active_bodies() -> int:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return 0
	var n: int = 0
	var stack: Array = [tree.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is RigidBody2D and not (node as RigidBody2D).sleeping:
			n += 1
		for child in node.get_children():
			stack.append(child)
	return n

# ══════════════════════════════════════════════════════════════════════════════
# PURE FORMATTER — no Node/viewport deps; unit-tested directly
# ══════════════════════════════════════════════════════════════════════════════

## Format the multi-line readout from a plain stats Dictionary. Pure + deterministic: a key absent
## from `stats` renders as "—" so a partial gather (no Mine bound, no Logger) still produces a
## stable, well-formed block rather than crashing. The FPS/frame-time line is always present (engine
## stats are always available). Keys: fps:int, frame_ms:float, bodies:int, seed:int, depth:int,
## charge:String, mine:String, warns:int, errors:int.
static func format_readout(stats: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("DEBUG (F3)")
	lines.append("fps      %s  (%s ms)" % [_fmt(stats, "fps"), _fmt_ms(stats)])
	lines.append("bodies   %s" % _fmt(stats, "bodies"))
	lines.append("seed     %s" % _fmt(stats, "seed"))
	lines.append("depth    %s" % _fmt(stats, "depth"))
	lines.append("charge   %s" % _fmt(stats, "charge"))
	lines.append("mine     %s" % _fmt(stats, "mine"))
	lines.append("warn/err %s / %s" % [_fmt(stats, "warns"), _fmt(stats, "errors")])
	return "\n".join(lines)

## A stats value as a string, or "—" when absent (so the readout never shows a raw null / errors out).
static func _fmt(stats: Dictionary, key: String) -> String:
	if not stats.has(key) or stats[key] == null:
		return "—"
	return str(stats[key])

## The frame-time millisecond value to one decimal, or "—" when absent.
static func _fmt_ms(stats: Dictionary) -> String:
	if not stats.has("frame_ms") or stats["frame_ms"] == null:
		return "—"
	return "%.1f" % float(stats["frame_ms"])
