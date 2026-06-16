class_name Registry
extends RefCounted
## Pure typed accessors over the raw /data JSON tables. Code outside this class
## never touches raw dictionaries — it goes through Registry for type-safe lookups.
## No Node/scene deps; headless-testable.
##
## ACs: AC-5.1.5 (block id → fields), AC-5.4.1 (explosive shape), AC-5.5.4.

# ── Block lookup ────────────────────────────────────────────────────────────

## Returns the block definition dict for the given id, or a safe default if unknown.
## The returned dict always has: display_name, hardness, max_hp, diggable, glyph, palette_index, ore.
static func block(tables: Dictionary, id: String) -> Dictionary:
	var blocks: Dictionary = tables.get("block_types", {})
	if blocks.has(id):
		return blocks[id]
	# Safe default for unknown block ids — non-diggable air-like.
	return {
		"display_name": "Unknown",
		"hardness": 0,
		"max_hp": 0,
		"diggable": false,
		"glyph": "none",
		"palette_index": 0,
		"ore": null,
	}

## Returns true if the block id exists in the registry.
static func has_block(tables: Dictionary, id: String) -> bool:
	return tables.get("block_types", {}).has(id)

## Returns the max_hp for a block id. 0 for unknown/air.
static func block_max_hp(tables: Dictionary, id: String) -> int:
	return int(block(tables, id).get("max_hp", 0))

## Returns the ore value for a block id. 0 if no ore or unknown.
static func block_ore_value(tables: Dictionary, id: String) -> int:
	var ore: Variant = block(tables, id).get("ore")
	if ore is Dictionary:
		return int(ore.get("value", 0))
	return 0

## Returns all block ids as an array.
static func block_ids(tables: Dictionary) -> Array:
	return tables.get("block_types", {}).keys()

## Returns all diggable block ids.
static func diggable_block_ids(tables: Dictionary) -> Array:
	var result: Array = []
	var blocks: Dictionary = tables.get("block_types", {})
	for id in blocks.keys():
		if blocks[id].get("diggable", false):
			result.append(id)
	return result

# ── Depth band lookup ───────────────────────────────────────────────────────

## Returns the depth band dict for a given depth in cells. Bands are checked
## in order; the first band whose range contains the depth wins.
## Returns {} if no band matches.
static func depth_band_for(tables: Dictionary, depth_cells: int) -> Dictionary:
	var bands: Variant = tables.get("depth_bands")
	if not (bands is Array):
		return {}
	for band in bands:
		if not (band is Dictionary):
			continue
		var min_d: int = int(band.get("min_depth_cells", 0))
		var max_d: int = int(band.get("max_depth_cells", 0))
		if depth_cells >= min_d and depth_cells < max_d:
			return band
	return {}

## Returns the block_weights dict for the band at a given depth. {} if no band.
static func band_weights_at(tables: Dictionary, depth_cells: int) -> Dictionary:
	var band: Dictionary = depth_band_for(tables, depth_cells)
	var w: Variant = band.get("block_weights")
	if w is Dictionary:
		return w
	return {}


## Returns the probability (0..1) for each block id in the band at `depth_cells`. Weights are
## normalized by their total; {} if no band. Used by the HUD depth resource-odds readout
## (AC-5.8.8).
static func band_odds(tables: Dictionary, depth_cells: int) -> Dictionary:
	var weights: Dictionary = band_weights_at(tables, depth_cells)
	var total: float = 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return {}
	var odds: Dictionary = {}
	for k in weights.keys():
		odds[k] = float(weights[k]) / total
	return odds

# ── Explosive lookup ────────────────────────────────────────────────────────

## Returns the explosive definition dict for the given id, or {} if unknown.
static func explosive(tables: Dictionary, id: String) -> Dictionary:
	var explosives: Dictionary = tables.get("explosives", {})
	if explosives.has(id):
		return explosives[id]
	return {}

## Returns true if the explosive id exists.
static func has_explosive(tables: Dictionary, id: String) -> bool:
	return tables.get("explosives", {}).has(id)

## Returns all explosive ids.
static func explosive_ids(tables: Dictionary) -> Array:
	return tables.get("explosives", {}).keys()

# ── Pack lookup ─────────────────────────────────────────────────────────────

## Returns the pack definition dict for the given id, or {} if unknown.
static func pack(tables: Dictionary, id: String) -> Dictionary:
	var packs: Dictionary = tables.get("packs", {})
	if packs.has(id):
		return packs[id]
	return {}

## Returns true if the pack id exists.
static func has_pack(tables: Dictionary, id: String) -> bool:
	return tables.get("packs", {}).has(id)

## Returns all pack ids.
static func pack_ids(tables: Dictionary) -> Array:
	return tables.get("packs", {}).keys()

# ── Free unlimited charge (v0.4) ──────────────────────────────────────────────

## Returns the id of the single flagged free unlimited charge, or "" if none.
## v0.4: exactly one explosive is flagged `free: true` and occupies a permanent,
## never-decremented tray slot (AC-5.4.3, AC-5.12.1).
static func free_charge_id(tables: Dictionary) -> String:
	var explosives: Dictionary = tables.get("explosives", {})
	for id in explosives.keys():
		var ex: Variant = explosives[id]
		if ex is Dictionary and bool(ex.get("free", false)):
			return id
	return ""

# ── Balance lookup ──────────────────────────────────────────────────────────

## Returns a balance value by key, with a default fallback. The default is a
## last-resort guard for callers that intentionally tolerate a missing key; the
## data gate (DataValidator) is the real contract — missing required balance keys
## fail the gate rather than silently resolving to a playable default.
static func balance(tables: Dictionary, key: String, default_value: Variant = 0) -> Variant:
	return tables.get("balance", {}).get(key, default_value)

## Convenience accessors. These intentionally have NO hardcoded balance fallback:
## a missing key reads as 0, which is invalid and surfaces immediately (the data
## gate enforces presence). Balance is data, never a code-side default.
static func crack_stages(tables: Dictionary) -> int:
	return int(balance(tables, "crack_stages"))

static func shaft_width(tables: Dictionary) -> int:
	return int(balance(tables, "shaft_width_cells"))

static func mine_width_cells(tables: Dictionary) -> int:
	return int(balance(tables, "mine_width_cells", shaft_width(tables)))

static func mine_height_cells(tables: Dictionary) -> int:
	return int(balance(tables, "mine_height_cells", 0))

static func shaft_left_cell(tables: Dictionary) -> int:
	var mine_w: int = mine_width_cells(tables)
	var shaft_w: int = shaft_width(tables)
	return maxi(0, int(floor(float(mine_w - shaft_w) * 0.5)))

static func shaft_right_cell(tables: Dictionary) -> int:
	return shaft_left_cell(tables) + shaft_width(tables)

static func chunk_height(tables: Dictionary) -> int:
	return int(balance(tables, "chunk_height_cells"))

static func block_pixel_size(tables: Dictionary) -> int:
	return int(balance(tables, "block_pixel_size"))

static func starting_money(tables: Dictionary) -> int:
	return int(balance(tables, "starting_money"))

static func run_seed(tables: Dictionary) -> int:
	return int(balance(tables, "run_seed"))

# ── Platform descent + camera (U7 / AC-5.7.2, AC-5.7.3) ───────────────────────
## Cleared-cells threshold that triggers a descent step. Reads 0 if absent
## (invalid — the data gate enforces presence > 0).
static func platform_clear_threshold(tables: Dictionary) -> int:
	return int(balance(tables, "platform_clear_threshold"))

## Max rows the platform may descend in a single trigger (caps the multi-row
## scan in PlatformLogic.descent_steps). Data-driven; no magic literal in callers.
static func descent_max_steps(tables: Dictionary) -> int:
	return int(balance(tables, "descent_max_steps"))

## Duration (seconds) of the platform-descent tween (AC-5.7.2: tween, not snap).
static func descent_tween_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "descent_tween_seconds"))

## Vertical lookahead, in cells, of the camera anchor BELOW the platform target.
## The camera follows the platform target offset by this much (still anchored to
## the platform target, smoothed — never hard-set per frame). Data-driven.
static func camera_lookahead_cells(tables: Dictionary) -> int:
	return int(balance(tables, "camera_lookahead_cells"))

## Camera zoom for the wide mine view. Values below 1.0 show more world and make the
## 16px sourced tiles read smaller on screen.
static func camera_zoom(tables: Dictionary) -> float:
	return float(balance(tables, "camera_zoom", 1.0))

static func light_radius_px(tables: Dictionary) -> float:
	return float(balance(tables, "light_radius_px", 0.0))

static func light_softness_px(tables: Dictionary) -> float:
	return float(balance(tables, "light_softness_px", 0.0))

static func light_dim_alpha(tables: Dictionary) -> float:
	return float(balance(tables, "light_dim_alpha", 0.0))

# ── Portrait HUD layout (U10 / AC-5.8.5) ──────────────────────────────────────
## Minimum interactive-control edge (pixels) for thumb-safe touch targets. The HUD
## sizes every tappable control to at least this, and the data gate enforces it sits
## in the ~44–48px range (AC-5.8.5). Data-driven; no magic literal in the UI code.
static func ui_min_touch_target_px(tables: Dictionary) -> float:
	return float(balance(tables, "ui_min_touch_target_px"))

## Base HUD edge margin (pixels, logical) always applied between a control and the
## viewport edge, BEFORE the device safe-area inset extends it further. Keeps the play
## space breathing on inset-free targets (desktop/web) and is the floor on mobile.
static func ui_edge_margin_px(tables: Dictionary) -> float:
	return float(balance(tables, "ui_edge_margin_px"))

# ── Settings defaults + ranges (AC-5.10.1) ────────────────────────────────────
## The `balance.settings` sub-table: the data-driven default values + ranges the
## Settings UI seeds from (SFX/Music volume, motion intensity, UI text scale). Empty
## if absent (invalid — the data gate enforces presence). Settings are tunables, so
## their DEFAULTS live in /data, never as code literals.
static func settings_defaults(tables: Dictionary) -> Dictionary:
	var s: Variant = tables.get("balance", {}).get("settings", {})
	return s if s is Dictionary else {}

# ── HP-scaling multipliers (AC-5.2.1) ─────────────────────────────────────────
## Per-cell depth multiplier coefficient: depth_mult = 1 + depth_cells * this.
## Reads 0 if absent (invalid — the data gate enforces presence).
static func depth_hp_mult_per_cell(tables: Dictionary) -> float:
	return float(balance(tables, "depth_hp_mult_per_cell"))

## The hardest mine's HP multiplier (worst case for no-stall checks). Per-mine
## multipliers land with the mine-select unit; this is the data-gate's upper bound.
static func mine_hardness_mult_max(tables: Dictionary) -> float:
	return float(balance(tables, "mine_hardness_mult_max"))

## Scaled HP for a block at a given absolute depth + per-mine hardness multiplier:
## base_hp(type) * (1 + depth_cells * depth_hp_mult_per_cell) * mine_hardness_mult.
## Pure derivation (AC-5.2.1); U3 applies it once at chunk init and stores per-cell.
static func scaled_block_hp(tables: Dictionary, id: String, depth_cells: int, mine_hardness_mult: float = 1.0) -> int:
	var base_hp: int = block_max_hp(tables, id)
	var depth_mult: float = 1.0 + float(depth_cells) * depth_hp_mult_per_cell(tables)
	return int(round(float(base_hp) * depth_mult * mine_hardness_mult))

# ── Relics (AC-5.6.1, AC-5.6.2, AC-5.6.6) ─────────────────────────────────────
## Prestige points awarded for collecting a relic. Reads 0 if absent (invalid —
## the data gate enforces presence > 0). This is the dig-end prestige bank value.
static func relic_prestige_value(tables: Dictionary) -> int:
	var relics: Variant = tables.get("relics")
	if relics is Dictionary:
		return int((relics as Dictionary).get("prestige_value", 0))
	return 0

# ── Prestige upgrades (AC-5.6.4, AC-5.12.x) ──────────────────────────────────
## Returns the prestige-upgrade definition dict for the given id, or {} if unknown.
static func prestige_upgrade(tables: Dictionary, id: String) -> Dictionary:
	var ups: Variant = tables.get("prestige")
	if ups is Dictionary and (ups as Dictionary).has(id):
		return (ups as Dictionary)[id]
	return {}

## True if the prestige-upgrade id exists.
static func has_prestige_upgrade(tables: Dictionary, id: String) -> bool:
	var ups: Variant = tables.get("prestige")
	return ups is Dictionary and (ups as Dictionary).has(id)

## All prestige-upgrade ids.
static func prestige_upgrade_ids(tables: Dictionary) -> Array:
	var ups: Variant = tables.get("prestige")
	if ups is Dictionary:
		return (ups as Dictionary).keys()
	return []
