class_name SettingsState
extends RefCounted
## Pure accessibility/settings model (AC-5.10.1). Holds the four player-adjustable settings —
## SFX volume, Music volume, motion/screen-shake intensity, and UI text scale — with clamping,
## linear→dB conversion for the audio buses, and serialize/restore for the save. No Node/scene/
## AudioServer deps, so it is headless-unit-testable; the Settings overlay (UI) and mine.gd
## (apply to Audio + HUD + explosion) are the thin layers that consume it.
##
## Volumes + motion are normalized sliders in [0,1]. The UI text scale is clamped to a
## data-driven [min,max] band (the slider's range). DEFAULTS + the text-scale band come from
## `/data` (balance.settings) — settings are tunables, never code literals (AC-5.5.4 spirit).
##
## ACs: AC-5.10.1 (motion + text-scale + SFX/music volume settings), AC-5.11.1 (settings persist).

## Volume below which a bus is treated as silent (linear 0 → -inf dB; floor it so the AudioServer
## gets a finite, mute-equivalent value rather than -INF).
const SILENCE_DB := -60.0

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
}

var _sfx_volume: float = FALLBACK["sfx_volume"]
var _music_volume: float = FALLBACK["music_volume"]
var _motion_intensity: float = FALLBACK["motion_intensity"]
var _text_scale: float = FALLBACK["text_scale"]
# The text-scale slider band (the clamp range). Volumes/motion are inherently [0,1].
var _ts_min: float = FALLBACK["text_scale_min"]
var _ts_max: float = FALLBACK["text_scale_max"]

# ── Construction ───────────────────────────────────────────────────────────────

## A fresh SettingsState seeded from the /data defaults (balance.settings). This is the
## source of the values a brand-new game starts with. Falls back to FALLBACK for any
## missing key so it never crashes on partial data (the data gate enforces completeness).
static func from_defaults(tables: Dictionary) -> SettingsState:
	var s := SettingsState.new()
	s._load_band(tables)
	var d: Dictionary = Registry.settings_defaults(tables)
	s._sfx_volume = clampf(float(d.get("default_sfx_volume", FALLBACK["sfx_volume"])), 0.0, 1.0)
	s._music_volume = clampf(float(d.get("default_music_volume", FALLBACK["music_volume"])), 0.0, 1.0)
	s._motion_intensity = clampf(float(d.get("default_motion_intensity", FALLBACK["motion_intensity"])), 0.0, 1.0)
	s._text_scale = s._clamp_text_scale(float(d.get("default_text_scale", FALLBACK["text_scale"])))
	return s

## A SettingsState restored from a saved snapshot, overlaying saved values on the /data
## defaults (so a save missing a key inherits the current default rather than 0). Every value
## is re-clamped/sanitized — a hand-edited or migrated save can't inject an out-of-range setting.
static func from_state(state: Dictionary, tables: Dictionary) -> SettingsState:
	var s := SettingsState.from_defaults(tables)
	if state.has("sfx_volume"):
		s._sfx_volume = clampf(float(state.get("sfx_volume", s._sfx_volume)), 0.0, 1.0)
	if state.has("music_volume"):
		s._music_volume = clampf(float(state.get("music_volume", s._music_volume)), 0.0, 1.0)
	if state.has("motion_intensity"):
		s._motion_intensity = clampf(float(state.get("motion_intensity", s._motion_intensity)), 0.0, 1.0)
	if state.has("text_scale"):
		s._text_scale = s._clamp_text_scale(float(state.get("text_scale", s._text_scale)))
	return s

func _load_band(tables: Dictionary) -> void:
	var d: Dictionary = Registry.settings_defaults(tables)
	_ts_min = float(d.get("text_scale_min", FALLBACK["text_scale_min"]))
	_ts_max = float(d.get("text_scale_max", FALLBACK["text_scale_max"]))
	if _ts_max < _ts_min:
		_ts_max = _ts_min

func _clamp_text_scale(v: float) -> float:
	return clampf(v, _ts_min, _ts_max)

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

# ── Clamped setters (the UI sliders call these) ──────────────────────────────────

func set_sfx_volume(v: float) -> void:
	_sfx_volume = clampf(v, 0.0, 1.0)

func set_music_volume(v: float) -> void:
	_music_volume = clampf(v, 0.0, 1.0)

func set_motion_intensity(v: float) -> void:
	_motion_intensity = clampf(v, 0.0, 1.0)

func set_text_scale(v: float) -> void:
	_text_scale = _clamp_text_scale(v)

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
## /data property, re-applied on load via from_state→from_defaults).
func to_state() -> Dictionary:
	return {
		"sfx_volume": _sfx_volume,
		"music_volume": _music_volume,
		"motion_intensity": _motion_intensity,
		"text_scale": _text_scale,
	}
