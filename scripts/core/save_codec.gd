class_name SaveCodec
extends RefCounted
## Pure save (de)serialization + migration (U20 / AC-5.11.1, AC-5.11.2). No Node/file deps —
## it transforms between a parsed-JSON `Variant` and a normalized save-state `Dictionary`, so all
## the version/migration/tolerance logic is headless-unit-testable without touching the disk. The
## file I/O (atomic write, backup, recovery) lives in `SaveManager` (a thin system) on top of this.
##
## Save shape (CURRENT_VERSION):
##   { "version": 3,
##     "prestige": { "points": int, "levels": { upgrade_id: int } },
##     "settings": { "sfx_volume": float, "music_volume": float,
##                   "motion_intensity": float, "text_scale": float,
##                   "elevator_side": "left"|"right",
##                   "keybinds": { action: physical-keycode int } } }
## `prestige` is the durable cross-dig progression (banked points + purchased upgrade levels —
## Prestige); `settings` is the durable accessibility config (AC-5.10.1 / AC-5.11.1). Per-dig state
## (tray, depth, money) is intentionally NOT saved (it resets each dig). Per-mine seeds / mine
## unlocks join the shape when those systems land (U21+).
##
## Migration is ordered + forward-only along a v0→v1→v2→v3 chain. The LOAD-BEARING step is v0→v1: a
## legacy flat save (`prestige_points` / `prestige_levels`, no `version`) is lifted into the nested
## shape — skip it and the prestige data is lost (proven by test_migrate_v0_flat_*). The v1→v2 step
## introduces the `settings` block; the v2→v3 step adds the `elevator_side` + `keybinds` controls
## sub-fields (D2). For both, normalization ALSO defaults the missing pieces, so the version steps
## are forward-declaration + belt-and-suspenders rather than the sole mechanism — an older settings
## block (no controls fields) still loads cleanly. Unknown fields are ignored; missing default (AC-5.11.2).

const CURRENT_VERSION := 3

## A fresh, valid default save state (used for a new game / unrecoverable load). Settings here are
## structural neutral fallbacks; a fresh GAME seeds settings from /data via SettingsState.from_defaults.
static func default_state() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"prestige": {"points": 0, "levels": {}},
		"settings": _default_settings(),
	}

## Structural-neutral settings fallback (independent of /data; the data-driven defaults live in
## SettingsState.from_defaults). Used to fill a missing/old settings block during normalization.
## `elevator_side` defaults to "right"; `keybinds` is left EMPTY here — the live InputMap is the
## true keybind-default source (SettingsState.from_defaults seeds it), and an empty map round-trips
## as "no override, inherit the live binding" rather than baking stale keycodes into the codec.
static func _default_settings() -> Dictionary:
	return {
		"sfx_volume": 0.8,
		"music_volume": 0.6,
		"motion_intensity": 0.3,
		"text_scale": 1.0,
		"elevator_side": "right",
		"keybinds": {},
	}

## Encode a save state to a JSON string, stamped with CURRENT_VERSION. Normalizes first so the
## written bytes are always a clean, current-shape save (never a half-built dict).
static func encode(state: Dictionary) -> String:
	return JSON.stringify(normalize(state), "\t")

## Decode JSON text to a normalized save state. Returns {} (empty) ONLY when the text fails to
## PARSE (corrupt bytes) — the caller (SaveManager) uses that to fall back to the backup. Any
## parseable-but-weird content normalizes to a valid state (best-effort, never throws).
static func decode(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	return normalize(json.data)

## Normalize parsed data (any Variant) to the current save shape: migrate older versions, ignore
## unknown fields, default missing ones, and sanitize types. Always returns a valid state dict.
static func normalize(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return default_state()
	var migrated: Dictionary = migrate(raw as Dictionary)
	return {
		"version": CURRENT_VERSION,
		"prestige": _normalize_prestige(migrated.get("prestige")),
		"settings": _normalize_settings(migrated.get("settings")),
	}

## Apply ordered migration steps to reach CURRENT_VERSION. A dict with no `version` key is treated
## as the legacy v0 (flat) format and lifted into the v1 nested shape.
static func migrate(raw: Dictionary) -> Dictionary:
	var data: Dictionary = raw.duplicate(true)
	var version: int = int(data.get("version", 0))
	# v0 → v1: the legacy flat format is detected by the PRESENCE of its flat keys
	# (`prestige_points` / `prestige_levels`), NOT by a missing `version` — a dict that already
	# carries a nested `prestige` object is v1-shaped even without the version stamp, and must not
	# be clobbered. (This is the bug the round-trip test caught: version-less current-shape input
	# was being misread as v0 and its data discarded.)
	if version < 1 and not data.has("prestige"):
		data = {
			"version": 1,
			"prestige": {
				"points": int(data.get("prestige_points", 0)),
				"levels": data.get("prestige_levels", {}),
			},
		}
	# v1 → v2: introduce the durable `settings` block (AC-5.10.1). An absent block defaults to the
	# structural-neutral settings; a present one is carried through (and re-sanitized by normalize).
	# Re-read the version from `data` (the v0→v1 step above may have rebuilt it) so the steps chain.
	if int(data.get("version", version)) < 2:
		if not data.has("settings"):
			data["settings"] = _default_settings()
		data["version"] = 2
	# v2 → v3 (D2): add the controls sub-fields (`elevator_side` + `keybinds`) to the settings block.
	# A v2 settings block has the four accessibility values but no controls; default them in here so a
	# v2 save loads cleanly. `_normalize_settings` re-defaults them anyway (belt-and-suspenders), so
	# this step is mainly the explicit, ordered forward declaration of the controls addition.
	if int(data.get("version", version)) < 3:
		var settings: Dictionary = data.get("settings") if data.get("settings") is Dictionary else {}
		if not settings.has("elevator_side"):
			settings["elevator_side"] = _default_settings()["elevator_side"]
		if not settings.has("keybinds"):
			settings["keybinds"] = {}
		data["settings"] = settings
		data["version"] = 3
	return data

## Sanitize the prestige sub-state: integer points >= 0, levels a {string: int>=0} map. Drops any
## malformed entries rather than trusting the file (a hand-edited / corrupt-but-parseable save).
static func _normalize_prestige(raw: Variant) -> Dictionary:
	var points: int = 0
	var levels: Dictionary = {}
	if raw is Dictionary:
		points = maxi(0, int((raw as Dictionary).get("points", 0)))
		var raw_levels: Variant = (raw as Dictionary).get("levels")
		if raw_levels is Dictionary:
			for k in (raw_levels as Dictionary).keys():
				var lv: int = int((raw_levels as Dictionary)[k])
				if lv > 0:
					levels[str(k)] = lv
	return {"points": points, "levels": levels}

## The five rebindable keyboard actions + the valid elevator sides. Inlined (not pulled from
## SettingsState) so the codec stays dependency-free — SettingsState re-validates against its own
## copy of these on load, so the two only need to agree, not share a symbol.
const _KEYBIND_ACTIONS: Array[String] = [
	"aim_left", "aim_right", "fire", "elevator_up", "elevator_down",
]
const _ELEVATOR_SIDES: Array[String] = ["left", "right"]

## Sanitize the settings sub-state (AC-5.10.1 / AC-5.11.1). Volumes + motion clamp to [0,1];
## text scale clamps to a broad structural safety band [0.1, 4.0] (the precise /data slider band is
## re-applied by SettingsState.from_state on load). `elevator_side` coerces to one of {left,right};
## `keybinds` keeps only the five known actions with a positive integer keycode. Missing keys fall
## back to the neutral default — so a hand-edited or partial save can't inject an out-of-range setting.
static func _normalize_settings(raw: Variant) -> Dictionary:
	var d: Dictionary = _default_settings()
	if raw is Dictionary:
		var r: Dictionary = raw
		d["sfx_volume"] = clampf(float(r.get("sfx_volume", d["sfx_volume"])), 0.0, 1.0)
		d["music_volume"] = clampf(float(r.get("music_volume", d["music_volume"])), 0.0, 1.0)
		d["motion_intensity"] = clampf(float(r.get("motion_intensity", d["motion_intensity"])), 0.0, 1.0)
		d["text_scale"] = clampf(float(r.get("text_scale", d["text_scale"])), 0.1, 4.0)
		var side: String = str(r.get("elevator_side", d["elevator_side"]))
		d["elevator_side"] = side if side in _ELEVATOR_SIDES else d["elevator_side"]
		d["keybinds"] = _normalize_keybinds(r.get("keybinds"))
	return d

## Sanitize the keybinds map: only the five known actions, each with a positive integer keycode.
## Drops unknown actions + non-positive / non-int values (a corrupt save can't inject a bogus bind).
static func _normalize_keybinds(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		var r: Dictionary = raw
		for action in _KEYBIND_ACTIONS:
			if r.has(action):
				var kc: int = int(r[action])
				if kc > 0:
					out[action] = kc
	return out
