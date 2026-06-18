class_name SettingsState
extends RefCounted
## Pure accessibility/settings model (AC-5.10.1). Holds the player-adjustable settings —
## SFX volume, Music volume, motion/screen-shake intensity, UI text scale, the elevator-controls
## SIDE (left/right), and a rebindable KEYBINDS map for the five keyboard actions — with clamping,
## linear→dB conversion for the audio buses, and serialize/restore for the save. No Node/scene/
## AudioServer/InputMap deps, so it is headless-unit-testable; the Settings overlay (UI) and mine.gd
## (apply to Audio + HUD + InputMap + explosion) are the thin layers that consume it.
##
## Volumes + motion are normalized sliders in [0,1]. The UI text scale is clamped to a
## data-driven [min,max] band (the slider's range). The elevator side is one of {"left","right"}.
## The keybinds map is {action: physical-keycode int} for the five D1 actions; its DEFAULTS are
## seeded from the project InputMap (the live binding) by the consumer, not hardcoded here.
## DEFAULTS + the text-scale band come from `/data` (balance.settings) — settings are tunables,
## never code literals (AC-5.5.4 spirit).
##
## ACs: AC-5.10.1 (motion + text-scale + SFX/music volume + controls), AC-5.11.1 (settings persist).

## Volume below which a bus is treated as silent (linear 0 → -inf dB; floor it so the AudioServer
## gets a finite, mute-equivalent value rather than -INF).
const SILENCE_DB := -60.0

## The five rebindable keyboard actions (D1). The map key set is FIXED to these; an unknown action
## in a save is ignored, a missing one inherits the default. Order is stable (UI row order).
const KEYBIND_ACTIONS: Array[String] = [
	"aim_left", "aim_right", "fire", "elevator_up", "elevator_down",
]

## Valid elevator-side values (which screen edge the up/down arrows are laid out against).
const ELEVATOR_SIDES: Array[String] = ["left", "right"]

## Fallback defaults + text-scale band, used only when /data is unavailable (the data gate
## guarantees `balance.settings` is present + valid in shipped data; these keep a bare
## `SettingsState.new()` sane for tests/tools).
const FALLBACK := {
	"sfx_volume": 0.8,
	"music_volume": 0.6,
	"motion_intensity": 0.3,
	"text_scale": 1.0,
	"text_scale_min": 0.8,
	"text_scale_max": 2.0,
	"elevator_side": "right",
}

var _sfx_volume: float = FALLBACK["sfx_volume"]
var _music_volume: float = FALLBACK["music_volume"]
var _motion_intensity: float = FALLBACK["motion_intensity"]
var _text_scale: float = FALLBACK["text_scale"]
# The text-scale slider band (the clamp range). Volumes/motion are inherently [0,1].
var _ts_min: float = FALLBACK["text_scale_min"]
var _ts_max: float = FALLBACK["text_scale_max"]
# Which edge the elevator up/down controls sit against (AC-5.10.1 controls layout).
var _elevator_side: String = FALLBACK["elevator_side"]
# action → physical-keycode int. Empty (no key bound) until seeded from /data default or InputMap.
var _keybinds: Dictionary = {}

# ── Construction ───────────────────────────────────────────────────────────────

## A fresh SettingsState seeded from the /data defaults (balance.settings). This is the
## source of the values a brand-new game starts with. Falls back to FALLBACK for any
## missing key so it never crashes on partial data (the data gate enforces completeness).
##
## `default_keybinds` is the InputMap-derived default {action: physical-keycode int} the consumer
## (mine.gd) passes in — SettingsState has no InputMap dep, so the LIVE project bindings are the
## source of the keybind defaults (never code literals). Omitted → no keys bound (empty map).
static func from_defaults(tables: Dictionary, default_keybinds: Dictionary = {}) -> SettingsState:
	var s := SettingsState.new()
	s._load_band(tables)
	var d: Dictionary = Registry.settings_defaults(tables)
	s._sfx_volume = clampf(float(d.get("default_sfx_volume", FALLBACK["sfx_volume"])), 0.0, 1.0)
	s._music_volume = clampf(float(d.get("default_music_volume", FALLBACK["music_volume"])), 0.0, 1.0)
	s._motion_intensity = clampf(float(d.get("default_motion_intensity", FALLBACK["motion_intensity"])), 0.0, 1.0)
	s._text_scale = s._clamp_text_scale(float(d.get("default_text_scale", FALLBACK["text_scale"])))
	s._elevator_side = _clamp_side(str(d.get("default_elevator_side", FALLBACK["elevator_side"])))
	s._keybinds = _sanitize_keybinds(default_keybinds)
	return s

## A SettingsState restored from a saved snapshot, overlaying saved values on the /data
## defaults (so a save missing a key inherits the current default rather than 0). Every value
## is re-clamped/sanitized — a hand-edited or migrated save can't inject an out-of-range setting.
## `default_keybinds` seeds the per-action default any action MISSING from the save inherits.
static func from_state(state: Dictionary, tables: Dictionary, default_keybinds: Dictionary = {}) -> SettingsState:
	var s := SettingsState.from_defaults(tables, default_keybinds)
	if state.has("sfx_volume"):
		s._sfx_volume = clampf(float(state.get("sfx_volume", s._sfx_volume)), 0.0, 1.0)
	if state.has("music_volume"):
		s._music_volume = clampf(float(state.get("music_volume", s._music_volume)), 0.0, 1.0)
	if state.has("motion_intensity"):
		s._motion_intensity = clampf(float(state.get("motion_intensity", s._motion_intensity)), 0.0, 1.0)
	if state.has("text_scale"):
		s._text_scale = s._clamp_text_scale(float(state.get("text_scale", s._text_scale)))
	if state.has("elevator_side"):
		s._elevator_side = _clamp_side(str(state.get("elevator_side", s._elevator_side)))
	# Keybinds: a saved per-action keycode overrides the default for that action; any action absent
	# from the save keeps its seeded default. Sanitized so only the known actions + valid ints survive.
	if state.get("keybinds") is Dictionary:
		var saved: Dictionary = state.get("keybinds")
		for action in KEYBIND_ACTIONS:
			if saved.has(action):
				var kc: int = int(saved[action])
				if kc > 0:
					s._keybinds[action] = kc
	return s

func _load_band(tables: Dictionary) -> void:
	var d: Dictionary = Registry.settings_defaults(tables)
	_ts_min = float(d.get("text_scale_min", FALLBACK["text_scale_min"]))
	_ts_max = float(d.get("text_scale_max", FALLBACK["text_scale_max"]))
	if _ts_max < _ts_min:
		_ts_max = _ts_min

func _clamp_text_scale(v: float) -> float:
	return clampf(v, _ts_min, _ts_max)

## Coerce an arbitrary string to a valid elevator side (defaults to the FALLBACK side on garbage).
static func _clamp_side(v: String) -> String:
	return v if v in ELEVATOR_SIDES else FALLBACK["elevator_side"]

## Keep only the five known actions with a positive integer keycode (drops unknown actions /
## non-int / non-positive values — a hand-edited or migrated save can't inject a bogus binding).
static func _sanitize_keybinds(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for action in KEYBIND_ACTIONS:
		if raw.has(action):
			var kc: int = int(raw[action])
			if kc > 0:
				out[action] = kc
	return out

# ── Accessors ───────────────────────────────────────────────────────────────────

var sfx_volume: float:
	get: return _sfx_volume
var music_volume: float:
	get: return _music_volume
var motion_intensity: float:
	get: return _motion_intensity
var text_scale: float:
	get: return _text_scale
var text_scale_min: float:
	get: return _ts_min
var text_scale_max: float:
	get: return _ts_max
var elevator_side: String:
	get: return _elevator_side

# ── Clamped setters (the UI sliders call these) ──────────────────────────────────

func set_sfx_volume(v: float) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)

func set_music_volume(v: float) -> void:
	_music_volume = clampf(v, 0.0, 1.0)

func set_motion_intensity(v: float) -> void:
	_motion_intensity = clampf(v, 0.0, 1.0)

func set_text_scale(v: float) -> void:
	_text_scale = _clamp_text_scale(v)

## Set which screen edge the elevator controls sit against ("left"|"right"); garbage coerces to
## the fallback side (so a bad call can never produce an invalid side).
func set_elevator_side(side: String) -> void:
	_elevator_side = _clamp_side(side)

## Toggle the elevator side (left↔right) — convenience for a two-state toggle button.
func toggle_elevator_side() -> void:
	_elevator_side = "left" if _elevator_side == "right" else "right"

# ── Keybinds (AC-5.10.1 rebindable controls) ─────────────────────────────────────

## Rebind one action to a physical keycode. Ignores an unknown action or a non-positive keycode
## (so the UI's capture path can't corrupt the map). The consumer (mine.gd) mirrors the change
## into the live InputMap; this is just the durable record.
##
## UNIT INFRA (crash-triage #1): REJECTS a keycode already bound to a DIFFERENT gameplay action.
## Two gameplay actions sharing one key (e.g. `fire` + `elevator_up` both on Space) makes a throw
## also move the elevator — a "the game did something weird" report whose worst case re-enters a
## dig. Rebinding an action to the key it already holds is a no-op (allowed). Returns true if the
## bind was applied, false if it was rejected — so the capture UI can keep its old binding/refuse.
func set_keybind(action: String, keycode: int) -> bool:
	if not (action in KEYBIND_ACTIONS) or keycode <= 0:
		return false
	for other in _keybinds:
		if other != action and int(_keybinds[other]) == keycode:
			return false  # collision: another action already owns this key
	_keybinds[action] = keycode
	return true

## The physical keycode currently bound to `action`, or 0 if unbound/unknown.
func keybind_for(action: String) -> int:
	return int(_keybinds.get(action, 0))

## A COPY of the full {action: keycode} map (defensive — callers can't mutate the internal store).
func keybinds() -> Dictionary:
	return _keybinds.duplicate()

# ── Derived ───────────────────────────────────────────────────────────────────

## SFX bus volume in dB (linear slider → dB for AudioServer.set_bus_volume_db). A slider of 0
## maps to SILENCE_DB (mute-equivalent) rather than -inf; 1.0 maps to 0 dB (unity).
func sfx_volume_db() -> float:
	return _to_db(_sfx_volume)

func music_volume_db() -> float:
	return _to_db(_music_volume)

func _to_db(linear: float) -> float:
	if linear <= 0.0:
		return SILENCE_DB
	return maxf(linear_to_db(linear), SILENCE_DB)

# ── Serialization (AC-5.11.1) ────────────────────────────────────────────────────

## Snapshot the durable settings for the save. The text-scale band is NOT saved (it is a
## /data property, re-applied on load via from_state→from_defaults). The keybinds map is saved as
## a fresh dict so the JSON encoder never sees the internal store.
func to_state() -> Dictionary:
	return {
		"sfx_volume": _sfx_volume,
		"music_volume": _music_volume,
		"motion_intensity": _motion_intensity,
		"text_scale": _text_scale,
		"elevator_side": _elevator_side,
		"keybinds": _keybinds.duplicate(),
	}
