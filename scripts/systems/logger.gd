extends Node
## Logger — the diagnostics autoload (UNIT INFRA). A leveled logger that writes to a
## `user://` rotating log file AND mirrors to the console, plus a process-wide error handler
## that records `push_error`/`push_warning` + a script stack so a crash leaves evidence on
## disk instead of vanishing with the process.
##
## WHY THIS EXISTS: the game ships to web/desktop/mobile where stderr is often invisible
## (a closed browser tab, a backgrounded phone app). When something goes wrong in the field
## the only artifact a player/developer can hand back is the `user://` log. This autoload makes
## that artifact exist — every error/warning, plus an opt-in trail of gameplay events, lands in
## `user://mining_game.log` (rotated to `.1` once it crosses the size cap so it never grows
## unbounded on the evictable web IndexedDB / a long desktop session).
##
## SPLIT (mirrors the SettingsState / Audio pattern): the LEVEL-FILTERING + FORMATTING is a set
## of PURE static functions (no Node / FileAccess / OS deps) so it is headless-unit-testable; the
## autoload is the thin side-effecting layer (open the file, install the error handler, mirror to
## the console). The threshold + tunables are DATA (`data/logging.json` via GameData) with a
## DataValidator rule — never code literals (AC-5.5.4 spirit).
##
## Registered as the `Logger` autoload (project.godot). Headless-safe: under the headless
## runner FileAccess to `user://` still works (the test dir), and the console mirror is a plain
## print, so the suite never blocks on it.
##
## Supports the 60-fps performance discipline (AC-5.2.9) indirectly: the debug overlay reads the
## same diagnostics surface, and a logged warning on a missing node is how an init-order regression
## announces itself instead of silently degrading.

## Severity levels, low→high. A message is emitted iff its level >= the configured threshold.
## DEBUG = verbose gameplay trail; INFO = lifecycle milestones; WARN = recoverable anomaly
## (a missing optional node, a clamped value); ERROR = a real fault (a failed load, a caught
## bad state). OFF is threshold-only — nothing at OFF is ever emitted.
enum Level { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, OFF = 4 }

## Canonical short tags for each level, used in the formatted line. Index by the enum value.
const LEVEL_TAGS: Array[String] = ["DEBUG", "INFO", "WARN", "ERROR", "OFF"]

## Fallback config — used only if data/logging.json is missing/unparseable (so a data hiccup
## can't disable diagnostics entirely). The shipped logging.json mirrors these and is the real
## contract (the data gate enforces it).
const FALLBACK_CONFIG := {
	"min_level": "DEBUG",
	"log_file": "user://mining_game.log",
	"max_file_kb": 256,
	"mirror_to_console": true,
}

# ── Live (side-effecting) state ────────────────────────────────────────────────
var _threshold: int = Level.DEBUG
var _log_path: String = FALLBACK_CONFIG["log_file"]
var _max_bytes: int = int(FALLBACK_CONFIG["max_file_kb"]) * 1024
var _mirror: bool = bool(FALLBACK_CONFIG["mirror_to_console"])
var _file: FileAccess = null
## Observability so wiring / a crash can be asserted (a line actually landed), not just that the
## hook exists. Counted per-level + a last-line snapshot for inspection/tests.
var _counts: Array[int] = [0, 0, 0, 0]
var _last_line: String = ""

func _ready() -> void:
	_load_config()
	_open_file()
	info("Logger", "boot — threshold=%s file=%s" % [LEVEL_TAGS[_threshold], _log_path])

# ══════════════════════════════════════════════════════════════════════════════
# PURE CORE (level filtering + formatting) — no Node/FileAccess/OS deps; unit-tested
# ══════════════════════════════════════════════════════════════════════════════

## Map a level NAME (case-insensitive) to its enum value; unknown → DEBUG (most-verbose, fail
## open — a typo in config must never silently swallow diagnostics). Pure.
static func level_from_name(name: String) -> int:
	var idx: int = LEVEL_TAGS.find(name.strip_edges().to_upper())
	return idx if idx >= 0 else Level.DEBUG

## Whether a message at `level` should be emitted given a `threshold`. The single gate the
## autoload and any consumer share. Pure: should_log(L, T) == (L >= T) and L != OFF (OFF is a
## threshold sentinel, never a message level). Pure.
static func should_log(level: int, threshold: int) -> bool:
	if level >= Level.OFF or level < Level.DEBUG:
		return false
	return level >= threshold

## Format one log line: "[TAG] tag: message" with a tag column. Pure + deterministic (no
## timestamp here so it is golden-stable in tests; the autoload prepends the engine ticks when
## it writes). `level` out of range clamps into the tag table. Pure.
static func format_line(level: int, tag: String, message: String) -> String:
	var lvl: int = clampi(level, Level.DEBUG, Level.OFF)
	return "[%s] %s: %s" % [LEVEL_TAGS[lvl], tag, message]

# ══════════════════════════════════════════════════════════════════════════════
# THIN SIDE-EFFECTING LAYER (file + console mirror + error handler)
# ══════════════════════════════════════════════════════════════════════════════

## Load the threshold + file tunables from data/logging.json (via GameData), falling back to
## FALLBACK_CONFIG if the table is missing/unparseable. _ready may run before GameData has loaded
## under some boot orders — the fallback covers that too (mirrors Audio._build_streams).
func _load_config() -> void:
	var cfg: Dictionary = FALLBACK_CONFIG.duplicate(true)
	var gd: Node = get_node_or_null("/root/GameData")
	if gd != null:
		var t: Variant = gd.table("logging")
		if t is Dictionary:
			for k in (t as Dictionary):
				cfg[k] = (t as Dictionary)[k]
	_threshold = level_from_name(str(cfg.get("min_level", FALLBACK_CONFIG["min_level"])))
	_log_path = str(cfg.get("log_file", FALLBACK_CONFIG["log_file"]))
	_max_bytes = maxi(1, int(cfg.get("max_file_kb", FALLBACK_CONFIG["max_file_kb"]))) * 1024
	_mirror = bool(cfg.get("mirror_to_console", FALLBACK_CONFIG["mirror_to_console"]))

## Open the log file for append, rotating it to `<path>.1` first if it already exceeds the size
## cap (one rolling backup — never grows unbounded). All FileAccess failures are swallowed: a
## logger that can't open its file must degrade to console-only, never crash the game.
func _open_file() -> void:
	if _file != null:
		_file.close()
		_file = null
	_rotate_if_needed()
	# Append so a restart adds to (rather than truncates) the prior session's tail.
	var f := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if f == null:
		# File doesn't exist yet → create it.
		f = FileAccess.open(_log_path, FileAccess.WRITE)
	if f != null:
		f.seek_end()
	_file = f

## Rotate the current log to `<path>.1` if it has crossed the size cap, so the live file stays
## bounded. Best-effort; any failure leaves the existing file in place (worst case it grows a
## little past the cap — acceptable, never fatal).
func _rotate_if_needed() -> void:
	if not FileAccess.file_exists(_log_path):
		return
	var probe := FileAccess.open(_log_path, FileAccess.READ)
	if probe == null:
		return
	var size: int = probe.get_length()
	probe.close()
	if size < _max_bytes:
		return
	var backup: String = _log_path + ".1"
	var da := DirAccess.open(_log_path.get_base_dir())
	if da != null:
		if da.file_exists(backup):
			da.remove(backup)
		da.rename(_log_path, backup)

# ── Public logging API (the thin wrappers consumers call) ──────────────────────

func debug(tag: String, message: String) -> void: _emit(Level.DEBUG, tag, message)
func info(tag: String, message: String) -> void: _emit(Level.INFO, tag, message)
func warn(tag: String, message: String) -> void: _emit(Level.WARN, tag, message)
func error(tag: String, message: String) -> void: _emit(Level.ERROR, tag, message)

## Emit one message: gate on the threshold (pure should_log), format (pure format_line), then
## write to the file (with an engine-ticks prefix) and mirror to the console. Increments the
## per-level count + records the last line for inspection/tests. Headless-safe.
func _emit(level: int, tag: String, message: String) -> void:
	if not should_log(level, _threshold):
		return
	var body: String = format_line(level, tag, message)
	_last_line = body
	if level >= Level.DEBUG and level < Level.OFF:
		_counts[level] += 1
	# File gets a monotonic engine-ticks stamp so on-disk lines are time-ordered without relying
	# on wall-clock (which is unreliable/absent in some sandboxes). Pure body stays unstamped.
	if _file != null:
		_file.store_line("%8d %s" % [Time.get_ticks_msec(), body])
		_file.flush()
	if _mirror:
		if level >= Level.ERROR:
			printerr(body)
		else:
			print(body)

# ── Process-wide error/warning trail (crash evidence) ──────────────────────────

## Record a `push_error`-class fault into the log WITH the current script stack, so a crash leaves
## evidence on disk. Call this from a caught error site or before re-raising. Also routes through
## the engine's own error reporter so the editor/debugger still sees it. `also_push` (default true)
## controls whether the engine push_error fires — pass false to log-only (avoid double reporting
## when the engine already raised it).
func report_error(tag: String, message: String, also_push: bool = true) -> void:
	error(tag, message)
	var stack: Array = get_stack()
	if not stack.is_empty():
		var lines: PackedStringArray = []
		for frame in stack:
			lines.append("    at %s:%s in %s()" % [frame.get("source", "?"), frame.get("line", 0), frame.get("function", "?")])
		var trace: String = "\n".join(lines)
		if _file != null:
			_file.store_line(trace)
			_file.flush()
		if _mirror:
			printerr(trace)
	if also_push:
		push_error("%s: %s" % [tag, message])

## Record a recoverable anomaly + route through push_warning (editor visibility). Use for a
## missing optional node, a clamped value, a fallback path — anything that didn't fault but is
## worth a breadcrumb.
func report_warning(tag: String, message: String, also_push: bool = true) -> void:
	warn(tag, message)
	if also_push:
		push_warning("%s: %s" % [tag, message])

# ── Inspection (for the debug overlay + wiring assertions) ─────────────────────

## Total messages emitted at a given level (for tests / the overlay). DEBUG..ERROR only.
func count_at(level: int) -> int:
	if level < Level.DEBUG or level >= Level.OFF:
		return 0
	return _counts[level]

## The most-recent formatted line (unstamped body), for wiring assertions / the overlay.
var last_line: String:
	get:
		return _last_line

## The active threshold (enum value) + its tag (for the overlay readout).
var threshold: int:
	get:
		return _threshold

func threshold_tag() -> String:
	return LEVEL_TAGS[clampi(_threshold, Level.DEBUG, Level.OFF)]

## The resolved log-file path (for the overlay readout / an export-log feature later).
var log_path: String:
	get:
		return _log_path
