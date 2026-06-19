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

# ── Depth-scaled weight curve (UNIT MAPGEN — infinite descent) ────────────────
## The mine is an INFINITE vertical shaft of finite width. Block-type weights are a
## CONTINUOUS interpolation between two anchor tables — `surface_weights` (at depth
## `surface_depth_cells`) and `cap_weights` (at depth `cap_depth_cells` and everywhere
## below) — so EV + gem-probability rise monotonically with depth toward a finite,
## bounded CAP, then freeze (the mine never becomes a free money printer). The curve
## descriptor lives in data/depth_bands.json (kept the filename; shape changed). The
## resulting {id: weight} dict feeds the EXISTING BlockGen noise→CDF pipeline unchanged.
##
## ACs: AC-5.1.3 (depth-scaled gen), AC-5.5.2 (depth reward, bounded + monotone),
##      AC-5.8.8 (HUD resource odds at the current depth).

## The whole depth_bands.json curve descriptor, or {} if absent/malformed.
static func depth_curve(tables: Dictionary) -> Dictionary:
	var c: Variant = tables.get("depth_bands")
	return c if c is Dictionary else {}

## The shallow anchor weight table (depth == surface_depth_cells). {} if absent.
static func surface_weights(tables: Dictionary) -> Dictionary:
	var w: Variant = depth_curve(tables).get("surface_weights")
	return w if w is Dictionary else {}

## The rich anchor weight table (depth >= cap_depth_cells). {} if absent.
static func cap_weights(tables: Dictionary) -> Dictionary:
	var w: Variant = depth_curve(tables).get("cap_weights")
	return w if w is Dictionary else {}

## Depth (cells) at/below which weights equal cap_weights exactly (the richness ceiling).
static func cap_depth_cells(tables: Dictionary) -> int:
	return int(depth_curve(tables).get("cap_depth_cells", 0))

## Depth (cells) of the shallow anchor (normally 0).
static func surface_depth_cells(tables: Dictionary) -> int:
	return int(depth_curve(tables).get("surface_depth_cells", 0))

## The interpolation shape ("smoothstep" or "linear"). Data-driven so the pacing of the
## EV ramp can be tuned without code.
static func gen_curve(tables: Dictionary) -> String:
	return str(depth_curve(tables).get("curve", "linear"))

## Bucket size (cells) the HUD odds readout snaps to, so the readout is stable as the
## player descends a few cells rather than flickering per row (AC-5.8.8). >= 1.
static func hud_sample_band_cells(tables: Dictionary) -> int:
	return maxi(1, int(depth_curve(tables).get("hud_sample_band_cells", 1)))

## Normalized, eased depth parameter s ∈ [0,1] for an absolute depth `y`. CLAMPED to 1
## at/below the cap (this is the bound that freezes EV/gem-prob below cap_depth_cells).
static func depth_curve_s(tables: Dictionary, depth_cells: int) -> float:
	var sd: int = surface_depth_cells(tables)
	var cap: int = cap_depth_cells(tables)
	if cap <= sd:
		return 1.0
	var t_raw: float = float(depth_cells - sd) / float(cap - sd)
	var t: float = clampf(t_raw, 0.0, 1.0)  # the CAP — t never exceeds 1
	if gen_curve(tables) == "smoothstep":
		return t * t * (3.0 - 2.0 * t)
	return t

## Continuous block-weight table at absolute depth `y`: weight(b,y) =
## lerp(surface_weights[b], cap_weights[b], s). A block absent from one anchor counts
## as weight 0 there (dirt fades out, hard_rock/gem fade in). Zero-weight ids are
## omitted from the returned dict (so the weighted pick never wastes a CDF slot on them).
## This REPLACES the old discrete band lookup; same {id: weight} contract for BlockGen.
static func depth_weights_at(tables: Dictionary, depth_cells: int) -> Dictionary:
	var sw: Dictionary = surface_weights(tables)
	var cw: Dictionary = cap_weights(tables)
	if sw.is_empty() and cw.is_empty():
		return {}
	var s: float = depth_curve_s(tables, depth_cells)
	var ids: Dictionary = {}
	for k in sw.keys():
		ids[k] = true
	for k in cw.keys():
		ids[k] = true
	var out: Dictionary = {}
	for id in ids.keys():
		var a: float = float(sw.get(id, 0.0))
		var b: float = float(cw.get(id, 0.0))
		var w: float = a + s * (b - a)
		if w > 0.0:
			out[id] = w
	return out

## Backwards-compatible alias retained for the many call sites that ask "what blocks
## generate at this depth". Now backed by the continuous curve (no discrete bands).
static func band_weights_at(tables: Dictionary, depth_cells: int) -> Dictionary:
	return depth_weights_at(tables, depth_cells)

## Returns the probability (0..1) for each block id at `depth_cells`, normalized by the
## total weight; {} if no curve. The depth is SNAPPED to `hud_sample_band_cells` buckets
## so the readout doesn't flicker per row as the platform descends (AC-5.8.8).
static func depth_odds_at(tables: Dictionary, depth_cells: int) -> Dictionary:
	var bucket: int = hud_sample_band_cells(tables)
	@warning_ignore("integer_division")
	var snapped: int = (maxi(0, depth_cells) / bucket) * bucket
	var weights: Dictionary = depth_weights_at(tables, snapped)
	var total: float = 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total <= 0.0:
		return {}
	var odds: Dictionary = {}
	for k in weights.keys():
		odds[k] = float(weights[k]) / total
	return odds

## Backwards-compatible alias for the HUD odds readout.
static func band_odds(tables: Dictionary, depth_cells: int) -> Dictionary:
	return full_odds_at(tables, depth_cells)

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

# ── Rarity colors ───────────────────────────────────────────────────────────

## Returns the configured Color for a rarity label (e.g. "common"), read from
## data/rarity.json. Falls back to neutral gray if the rarity is unknown or the
## table/colors entry is missing/invalid.
static func rarity_color(tables: Dictionary, rarity: String) -> Color:
	var colors: Variant = tables.get("rarity", {}).get("colors", {})
	if colors is Dictionary and (colors as Dictionary).has(rarity):
		var hex: String = str((colors as Dictionary)[rarity])
		if Color.html_is_valid(hex):
			return Color.html(hex)
	return Color(0.5, 0.5, 0.5, 1.0)

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

## Returns the id of the basic (safety-net) charge — the weakest explosive granted
## as a free 5-pack when the player has no money and no charges (AC-5.4.3 v0.7).
## Falls back to the "free_charge" id by name if no `free: true` flag exists (the
## v0.7 model sets `free: false` — the basic charge is finite, not unlimited).
static func free_charge_id(tables: Dictionary) -> String:
	var explosives: Dictionary = tables.get("explosives", {})
	for id in explosives.keys():
		var ex: Variant = explosives[id]
		if ex is Dictionary and bool(ex.get("free", false)):
			return id
	if explosives.has("free_charge"):
		return "free_charge"
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

static func platform_width_cells(tables: Dictionary) -> int:
	return int(balance(tables, "platform_width_cells", shaft_width(tables)))

static func mine_width_cells(tables: Dictionary) -> int:
	return int(balance(tables, "mine_width_cells", shaft_width(tables)))

## Mine height in cells. 0 (or negative) is the INFINITE-descent sentinel (UNIT MAPGEN):
## the vertical shaft has no bottom; the relic ends each dig at a finite depth instead.
static func mine_height_cells(tables: Dictionary) -> int:
	return int(balance(tables, "mine_height_cells", 0))

## True iff the mine is the infinite vertical shaft (no bottom row).
static func is_infinite_depth(tables: Dictionary) -> bool:
	return mine_height_cells(tables) <= 0

## The deepest valid row to clamp UI/platform descent against. For the infinite shaft
## (mine_height_cells <= 0) there is no bottom, so this returns a very large sentinel so
## that `mini(support_row, bottom)` always resolves to the real support-driven limit.
## For a bounded mine it is mine_height_cells - 1 (the last in-range row).
const INFINITE_BOTTOM_ROW := 1 << 30
static func mine_bottom_row(tables: Dictionary) -> int:
	var h: int = mine_height_cells(tables)
	if h <= 0:
		return INFINITE_BOTTOM_ROW
	return h - 1

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

# ── Elevator hold-to-move ramp (continuous row-by-row glide while held) ────────
## The `balance.elevator` sub-table: the ramp constants for holding an elevator button/key.
## Tunables are data, so these live in /data and the data gate enforces presence + ranges
## (_check_elevator). Reads {} if absent (invalid — the gate catches it before the game runs).
static func elevator(tables: Dictionary) -> Dictionary:
	var x: Variant = tables.get("balance", {}).get("elevator", {})
	return x if x is Dictionary else {}

## Initial hold speed (rows/sec) at the start of a fresh press — the slow start before the ramp.
static func elevator_start_rows_per_sec(tables: Dictionary) -> float:
	return float(elevator(tables).get("start_rows_per_sec", 2.0))

## Ramp acceleration (rows/sec²): how fast the held speed climbs from the slow start.
static func elevator_accel_rows_per_sec2(tables: Dictionary) -> float:
	return float(elevator(tables).get("accel_rows_per_sec2", 6.0))

## Capped maximum hold speed (rows/sec): the held glide never exceeds this.
static func elevator_max_rows_per_sec(tables: Dictionary) -> float:
	return float(elevator(tables).get("max_rows_per_sec", 14.0))

## Vertical lookahead, in cells, of the camera anchor BELOW the platform target.
## The camera follows the platform target offset by this much (still anchored to
## the platform target, smoothed — never hard-set per frame). Data-driven.
static func camera_lookahead_cells(tables: Dictionary) -> int:
	return int(balance(tables, "camera_lookahead_cells"))

## Slight horizontal camera look-ahead toward the aim direction (cells). The camera
## nudges toward where the charge is going so the player can see the target area.
## Small by design ("slight") — 0 disables. Data-driven.
static func camera_aim_lookahead_cells(tables: Dictionary) -> int:
	return maxi(0, int(balance(tables, "camera_aim_lookahead_cells", 0)))

static func camera_platform_screen_fraction(tables: Dictionary) -> float:
	return float(balance(tables, "camera_platform_screen_fraction", 0.5))

static func support_extend_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "support_extend_seconds", 0.25))

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

## The cool deep-terrain tint the headlamp light mask fades TOWARD (instead of pure black),
## so the unlit mine reads as an atmospheric blue-violet cast rather than muddy black. Reads
## the data-driven hex (balance.light_dark_tint); falls back to opaque black (the old look)
## if absent/invalid so an unconfigured mask is harmless. The data gate enforces a valid hex.
static func light_dark_tint(tables: Dictionary) -> Color:
	var hex: String = str(balance(tables, "light_dark_tint", "#000000"))
	if not Color.html_is_valid(hex):
		return Color(0, 0, 0, 1)
	return Color.html(hex)

static func throw_cooldown_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "throw_cooldown_seconds", 0.0))

## Effective throw cooldown after prestige Charge Holster upgrades.
static func effective_throw_cooldown(tables: Dictionary, prestige: Prestige) -> float:
	return prestige.dig_throw_cooldown(throw_cooldown_seconds(tables))

## Effective headlamp light radius after prestige Mining Torch upgrades.
static func effective_light_radius(tables: Dictionary, prestige: Prestige) -> float:
	return prestige.dig_light_radius(light_radius_px(tables))

## Effective required shaft clearance width after a `reduction` (in cells) from the
## per-dig Shaft Engineering money upgrade. Floored to the platform width so the corridor
## can never be narrower than the deck, and kept ODD (the corridor needs a center line —
## same invariant the data gate enforces on the base width). 9 → 7 with the shipped upgrade.
static func effective_shaft_width(tables: Dictionary, reduction: int) -> int:
	var min_w: int = platform_width_cells(tables)
	var w: int = shaft_width(tables) - maxi(0, reduction)
	if w < min_w:
		w = min_w
	if w % 2 == 0:
		w = maxi(min_w, w - 1)
	return w

## Left cell of a shaft of `eff_width`, centered in the bounded mine. The clearance band
## stays centered as Shaft Engineering narrows it (it shrinks inward from both edges).
static func effective_shaft_left_cell(tables: Dictionary, eff_width: int) -> int:
	return maxi(0, int(floor(float(mine_width_cells(tables) - eff_width) * 0.5)))

# ── Per-dig money upgrades (Shaft Engineering, etc.) ──────────────────────────

## All money-upgrade ids (insertion order), or [] if the optional table is absent.
static func upgrade_ids(tables: Dictionary) -> Array:
	var ups: Variant = tables.get("upgrades")
	if ups is Dictionary:
		return (ups as Dictionary).keys()
	return []

## Rank of a rarity name (0 = lowest/common, higher = rarer), from the ORDER of the keys in
## rarity.json's `colors` map (common, uncommon, rare, epic, legendary). Unknown rarities rank
## last so they never get auto-selected over a known low rarity. Used to pick the lowest-rarity
## charge to auto-select after a pack buy.
static func rarity_rank(tables: Dictionary, rarity: String) -> int:
	var rar: Variant = tables.get("rarity")
	if rar is Dictionary:
		var colors: Variant = (rar as Dictionary).get("colors")
		if colors is Dictionary:
			var keys: Array = (colors as Dictionary).keys()
			var idx: int = keys.find(rarity)
			return idx if idx >= 0 else keys.size()
	return 1 << 20

## A single money-upgrade definition by id, or {} if unknown.
static func upgrade(tables: Dictionary, upgrade_id: String) -> Dictionary:
	var ups: Variant = tables.get("upgrades")
	if ups is Dictionary and (ups as Dictionary).has(upgrade_id):
		return (ups as Dictionary)[upgrade_id]
	return {}

# ── Mines (surface + deeper, money-gated mines) ───────────────────────────────

## All mine ids (insertion order). The first free (access_cost 0) mine is the default.
static func mine_ids(tables: Dictionary) -> Array:
	var mines: Variant = tables.get("mines")
	if mines is Dictionary:
		return (mines as Dictionary).keys()
	return []

## A single mine definition by id, or {} if unknown.
static func mine(tables: Dictionary, mine_id: String) -> Dictionary:
	var mines: Variant = tables.get("mines")
	if mines is Dictionary and (mines as Dictionary).has(mine_id):
		return (mines as Dictionary)[mine_id]
	return {}

## The default (starting) mine id: the first mine with access_cost == 0, else the first id,
## else "" if there is no mines table.
static func default_mine_id(tables: Dictionary) -> String:
	var ids: Array = mine_ids(tables)
	for id in ids:
		if int(mine(tables, str(id)).get("access_cost", 0)) == 0:
			return str(id)
	return str(ids[0]) if not ids.is_empty() else ""

## Per-mine HP multiplier (harder rock deeper). Defaults to 1.0 for an absent mine.
static func mine_hardness_mult(tables: Dictionary, mine_id: String) -> float:
	return float(mine(tables, mine_id).get("hardness_mult", 1.0))

## Per-mine ore-value multiplier (richer ore deeper). Defaults to 1.0.
static func mine_ore_value_mult(tables: Dictionary, mine_id: String) -> float:
	return float(mine(tables, mine_id).get("ore_value_mult", 1.0))

## One-time money cost to unlock access to a mine. 0 = free (the starting mine).
static func mine_access_cost(tables: Dictionary, mine_id: String) -> int:
	return int(mine(tables, mine_id).get("access_cost", 0))

## Seed offset so each mine generates a distinct layout + relic placement. 0 = base layout.
static func mine_seed_offset(tables: Dictionary, mine_id: String) -> int:
	return int(mine(tables, mine_id).get("seed_offset", 0))

## The terrain tint (modulate) for a mine — a darker cut reads as "deeper". White = no tint.
static func mine_tile_tint(tables: Dictionary, mine_id: String) -> Color:
	var hex: String = str(mine(tables, mine_id).get("tile_tint", "#ffffff"))
	if not Color.html_is_valid(hex):
		return Color(1, 1, 1, 1)
	return Color.html(hex)

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

# ── Money juice (v0.5 arcade pass) ────────────────────────────────────────────
## Duration (seconds) of the rolling money count-up on the HUD. Data-driven; the data
## gate enforces presence + > 0 so the roll always has a non-zero ramp.
static func ui_money_roll_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "ui_money_roll_seconds"))

## Coin travel time (seconds) from the broken ore cell to the wallet icon.
static func coin_fly_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "coin_fly_seconds"))

## Initial coin pop/arc-up time (seconds) before it flies to the wallet.
static func coin_pop_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "coin_pop_seconds"))

## Cap on concurrent flying coins (web budget); extra credits merge into the count-up.
static func coin_max_active(tables: Dictionary) -> int:
	return int(balance(tables, "coin_max_active"))

## Coin arc apex height (logical px) on the initial pop.
static func coin_arc_height_px(tables: Dictionary) -> float:
	return float(balance(tables, "coin_arc_height_px"))

# ── UI/HUD animation (v0.5 arcade pass) ───────────────────────────────────────
## Scale-in duration (seconds) for a modal / the dig-end panel popping into view.
static func ui_panel_in_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "ui_panel_in_seconds"))

## Scale-out duration (seconds) for a modal closing.
static func ui_panel_out_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "ui_panel_out_seconds"))

## Peak alpha [0,1] of the relic/prestige screen flash. Capped (a11y) + motion-gated by the caller.
static func ui_flash_alpha(tables: Dictionary) -> float:
	return float(balance(tables, "ui_flash_alpha"))

## Fade duration (seconds) of the relic/prestige screen flash.
static func ui_flash_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "ui_flash_seconds"))

## Tray-select pop duration (seconds) — the scale/elevation bounce on the tapped slot.
static func ui_tray_pop_seconds(tables: Dictionary) -> float:
	return float(balance(tables, "ui_tray_pop_seconds"))

## Charge selector timing/motion tunables. These are presentation values, but still live in /data so
## UI feel can be tuned without script edits (AC-5.5.4 / AC-5.8.2 / AC-5.10.1).
static func ui_selector(tables: Dictionary) -> Dictionary:
	var x: Variant = tables.get("balance", {}).get("ui_selector", {})
	return x if x is Dictionary else {}

static func ui_selector_f(tables: Dictionary, key: String, default_value: float = 0.0) -> float:
	return float(ui_selector(tables).get(key, default_value))

static func ui_selector_i(tables: Dictionary, key: String, default_value: int = 0) -> int:
	return int(ui_selector(tables).get(key, default_value))

## Crate-reveal timing/motion tunables. Used by CrateReveal only; pack rolls remain in RunState.
static func ui_crate(tables: Dictionary) -> Dictionary:
	var x: Variant = tables.get("balance", {}).get("ui_crate", {})
	return x if x is Dictionary else {}

static func ui_crate_f(tables: Dictionary, key: String, default_value: float = 0.0) -> float:
	return float(ui_crate(tables).get(key, default_value))

static func ui_crate_i(tables: Dictionary, key: String, default_value: int = 0) -> int:
	return int(ui_crate(tables).get(key, default_value))

# ── Settings defaults + ranges (AC-5.10.1) ────────────────────────────────────
## The `balance.settings` sub-table: the data-driven default values + ranges the
## Settings UI seeds from (SFX/Music volume, motion intensity, UI text scale). Empty
## if absent (invalid — the data gate enforces presence). Settings are tunables, so
## their DEFAULTS live in /data, never as code literals.
static func settings_defaults(tables: Dictionary) -> Dictionary:
	var s: Variant = tables.get("balance", {}).get("settings", {})
	return s if s is Dictionary else {}

# ── VFX feel table (v0.5 arcade pass) ─────────────────────────────────────────
## The `balance.vfx` sub-table: every arcade-juice magnitude (camera shake, zoom punch,
## hit-stop, explosion flash/ring, debris cap, value popups). Tunables are data, so these
## live in /data and the data gate enforces presence + ranges (_check_vfx). Reads {} if
## absent (invalid — the gate catches it before the game runs).
static func vfx(tables: Dictionary) -> Dictionary:
	var x: Variant = tables.get("balance", {}).get("vfx", {})
	return x if x is Dictionary else {}

## A vfx tunable as a float. No code-side balance fallback: a missing key reads as
## `default_value` only for callers that explicitly tolerate it; the data gate is the
## real contract (missing keys fail the gate).
static func vfx_f(tables: Dictionary, key: String, default_value: float = 0.0) -> float:
	return float(vfx(tables).get(key, default_value))

## A vfx tunable as an int (e.g. debris cap, hit-stop min cells, popup cap).
static func vfx_i(tables: Dictionary, key: String, default_value: int = 0) -> int:
	return int(vfx(tables).get(key, default_value))

# ── Launch & control-feel table (v0.5 arcade pass) ────────────────────────────
## The `balance.feel` sub-table: every launch/control-feel magnitude (throw-button squash/pop,
## animated aim line width + dash scroll, platform recoil, muzzle-flash count). Tunables are data,
## so these live in /data and the data gate enforces presence + ranges (_check_feel). Reads {} if
## absent (invalid — the gate catches it before the game runs).
static func feel(tables: Dictionary) -> Dictionary:
	var x: Variant = tables.get("balance", {}).get("feel", {})
	return x if x is Dictionary else {}

## A feel tunable as a float (e.g. squash factor, aim line width, recoil px).
static func feel_f(tables: Dictionary, key: String, default_value: float = 0.0) -> float:
	return float(feel(tables).get(key, default_value))

## A feel tunable as an int (e.g. muzzle-flash particle count).
static func feel_i(tables: Dictionary, key: String, default_value: int = 0) -> int:
	return int(feel(tables).get(key, default_value))

static func keyboard_aim_start_deg_per_sec(tables: Dictionary) -> float:
	return feel_f(tables, "keyboard_aim_start_deg_per_sec", 35.0)

static func keyboard_aim_accel_deg_per_sec2(tables: Dictionary) -> float:
	return feel_f(tables, "keyboard_aim_accel_deg_per_sec2", 60.0)

static func keyboard_aim_max_deg_per_sec(tables: Dictionary) -> float:
	return feel_f(tables, "keyboard_aim_max_deg_per_sec", 140.0)

# ── HP-scaling multipliers (AC-5.2.1) ─────────────────────────────────────────
## Per-cell depth multiplier coefficient: depth_mult = 1 + depth_cells * this.
## Reads 0 if absent (invalid — the data gate enforces presence).
static func depth_hp_mult_per_cell(tables: Dictionary) -> float:
	return float(balance(tables, "depth_hp_mult_per_cell"))

## Upper bound on the depth HP multiplier (1 + depth*k). In an INFINITE shaft this clamp
## is REQUIRED (else HP grows without bound and even the best charge stalls past some
## depth). Mirrors the EV cap: HP stops scaling once depth_mult hits this ceiling. Reads 0
## if absent (invalid — the data gate enforces presence > 0 and >= 1).
static func max_depth_hp_mult(tables: Dictionary) -> float:
	return float(balance(tables, "max_depth_hp_mult"))

## The hardest mine's HP multiplier (worst case for no-stall checks). Per-mine
## multipliers land with the mine-select unit; this is the data-gate's upper bound.
static func mine_hardness_mult_max(tables: Dictionary) -> float:
	return float(balance(tables, "mine_hardness_mult_max"))

## Scaled HP for a block at a given absolute depth + per-mine hardness multiplier:
## base_hp(type) * min(1 + depth_cells * depth_hp_mult_per_cell, max_depth_hp_mult) *
## mine_hardness_mult. The depth multiplier is CLAMPED to max_depth_hp_mult so HP stays
## bounded in the infinite shaft (mirrors the EV cap; UNIT MAPGEN). Pure derivation
## (AC-5.2.1); U3 applies it once at chunk init and stores per-cell.
static func scaled_block_hp(tables: Dictionary, id: String, depth_cells: int, mine_hardness_mult: float = 1.0) -> int:
	var base_hp: int = block_max_hp(tables, id)
	var depth_mult: float = 1.0 + float(depth_cells) * depth_hp_mult_per_cell(tables)
	var cap: float = max_depth_hp_mult(tables)
	if cap > 0.0:
		depth_mult = minf(depth_mult, cap)
	return int(round(float(base_hp) * depth_mult * mine_hardness_mult))

# ── Relics (AC-5.6.1, AC-5.6.2, AC-5.6.6) ─────────────────────────────────────
## Prestige points awarded for collecting a relic. Reads 0 if absent (invalid —
## the data gate enforces presence > 0). This is the dig-end prestige bank value.
static func relic_prestige_value(tables: Dictionary) -> int:
	var relics: Variant = tables.get("relics")
	if relics is Dictionary:
		return int((relics as Dictionary).get("prestige_value", 0))
	return 0

## Half-width (cells) of the center band the relic column is confined to: the relic
## column satisfies |relic_col - center_col| <= relic_band_half_cells (an 11-wide band at
## 5). Keeps the relic on the descent corridor in the infinite shaft (AC-5.6.1). Reads 5
## if absent so an un-migrated relics.json still confines the column reasonably; the data
## gate enforces presence + that the band fits the configured width.
static func relic_band_half_cells(tables: Dictionary) -> int:
	var relics: Variant = tables.get("relics")
	if relics is Dictionary:
		return int((relics as Dictionary).get("relic_band_half_cells", 5))
	return 5

## The depth by which the relic is GUARANTEED to have appeared (the power-CDF max; the
## mine is completable because descending to here always crosses the relic). Reads 9000
## if absent; the data gate enforces min_depth < guaranteed <= cap_depth_cells.
static func relic_guaranteed_depth_cells(tables: Dictionary) -> int:
	var relics: Variant = tables.get("relics")
	if relics is Dictionary:
		return int((relics as Dictionary).get("relic_guaranteed_depth_cells", 9000))
	return 9000

## Back-load exponent k for the relic depth power-CDF (higher = rarer shallow). Reads 4
## if absent; the data gate enforces > 1.
static func relic_back_load_k(tables: Dictionary) -> int:
	var relics: Variant = tables.get("relics")
	if relics is Dictionary:
		return maxi(2, int((relics as Dictionary).get("relic_back_load_k", 4)))
	return 4

## The relic's in-world glow color (the purple objective beacon). White if absent/invalid.
static func relic_glow_color(tables: Dictionary) -> Color:
	var relics: Variant = tables.get("relics")
	if relics is Dictionary:
		var hex: String = str((relics as Dictionary).get("glow_color", "#a64bff"))
		if Color.html_is_valid(hex):
			return Color.html(hex)
	return Color(0.65, 0.29, 1.0, 1.0)

## The relic glow pulse period (seconds). Reads 1.6 if absent; the data gate enforces > 0.
static func relic_glow_pulse_seconds(tables: Dictionary) -> float:
	var relics: Variant = tables.get("relics")
	if relics is Dictionary:
		return float((relics as Dictionary).get("glow_pulse_seconds", 1.6))
	return 1.6

## The 2×2 relic top-left anchor for a mine seed (delegates to BlockGen). Pure fn of seed.
static func relic_anchor(tables: Dictionary, mine_seed: int) -> Vector2i:
	return BlockGen.relic_anchor(tables, mine_seed)

# ── Ore overlay layer (continuous gen, v0.7) ──────────────────────────────────
## The per-ore noise-overlay table (data/ore_overlays.json): the richness layer stamped
## over the base depth-curve filler. {} if absent (invalid — the data gate enforces it).
static func ore_overlays(tables: Dictionary) -> Dictionary:
	var o: Variant = tables.get("ore_overlays")
	return o if o is Dictionary else {}

## The ore-overlay definitions sorted RAREST-FIRST (ascending `priority`, index 0 = rarest,
## evaluated first → first hit wins). Each entry is the ore's dict from ore_overlays.ores.
## The walk order is deterministic (sorted by the unique, validated `priority`).
static func ore_priority(tables: Dictionary) -> Array:
	var ov: Dictionary = ore_overlays(tables)
	var ores: Variant = ov.get("ores")
	if not (ores is Dictionary):
		return []
	var rows: Array = []
	for id in (ores as Dictionary).keys():
		var o: Variant = (ores as Dictionary)[id]
		if o is Dictionary:
			rows.append(o)
	rows.sort_custom(func(a, b): return int(a.get("priority", 0)) < int(b.get("priority", 0)))
	return rows

## The analytic ore-odds proxy at depth `y` for one ore id: clamp(1 - threshold(s(y)), 0, 1),
## 0 below the ore's depth_min. Monotone in depth (threshold falls with depth). Used by the
## HUD odds chip + the validator reward check (the same 1-threshold formula). NOT the field-
## integrated truth — an upper bound — but monotone, which is what the reward invariant needs.
static func ore_odds_at(tables: Dictionary, ore_id: String, y: int) -> float:
	var ov: Dictionary = ore_overlays(tables)
	var ores: Variant = ov.get("ores")
	if not (ores is Dictionary) or not (ores as Dictionary).has(ore_id):
		return 0.0
	var o: Dictionary = (ores as Dictionary)[ore_id]
	if y < int(o.get("depth_min", 0)):
		return 0.0
	var s: float = depth_curve_s(tables, y)
	var shallow: float = float(o.get("threshold_shallow", 1.0))
	var deep: float = float(o.get("threshold_deep", 1.0))
	var thr: float = shallow + s * (deep - shallow)
	return clampf(1.0 - thr, 0.0, 1.0)

## The combined per-block odds at depth `y` for the HUD: folds the ore-overlay odds into the
## base filler odds with the SAME priority-reduction budget the generator uses (rarest eats
## first). Returns {block_id: probability} summing to ~1. Snapped to hud_sample_band_cells so
## the readout doesn't flicker per row. This is what the odds chip must show (real ore chances,
## not just filler) — AC-5.8.8 over the continuous-gen layers.
static func full_odds_at(tables: Dictionary, depth_cells: int) -> Dictionary:
	var bucket: int = hud_sample_band_cells(tables)
	@warning_ignore("integer_division")
	var snapped: int = (maxi(0, depth_cells) / bucket) * bucket
	var out: Dictionary = {}
	var remaining: float = 1.0
	for o in ore_priority(tables):  # rarest-first, matching the generator
		var bid: String = str(o.get("block_id", ""))
		if bid.is_empty():
			continue
		var odds: float = ore_odds_at(tables, bid, snapped) * remaining
		if odds > 0.0:
			out[bid] = out.get(bid, 0.0) + odds
			remaining -= odds
	if remaining < 0.0:
		remaining = 0.0
	# The base filler fills the remaining cell-coverage budget, split by its weight table.
	var weights: Dictionary = depth_weights_at(tables, snapped)
	var total: float = 0.0
	for k in weights.keys():
		total += float(weights[k])
	if total > 0.0:
		for k in weights.keys():
			out[k] = out.get(k, 0.0) + remaining * (float(weights[k]) / total)
	return out

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
