class_name DataValidator
extends RefCounted
## Pure, engine-light validation of the /data tables. No Node/scene deps so it runs
## identically under the headless tool (tools/validate_data.gd) and the unit test
## (tests/unit/test_data_integrity.gd). Returns a list of human-readable errors;
## an empty list means the data set is internally consistent.
##
## This encodes the cross-reference + range rules the game relies on (AGENTS.md
## "canonical block-type registry" + SPEC data-validation gate §7). Extend the rules
## here as the data model grows — every new table gets a rule, every join gets a check.

const DETONATION_MODES := ["fuse_seconds", "on_first_impact", "on_rest"]
## Glyph vocabulary for the non-color overlay (mirrors BlockArt.ALLOWED_GLYPHS; kept local so
## the data gate stays self-contained and never depends on a class_name resolving under `-s`).
const ALLOWED_GLYPHS := ["dots", "cross", "bricks", "circle", "diamond"]
## Minimum WCAG relative-luminance separation required between any two diggable block colors
## (AC-5.10.3: contrast by luminance, not hue alone).
const MIN_BLOCK_LUMINANCE_DELTA := 0.06

static func validate(tables: Dictionary) -> Array:
	var errors: Array = []
	var balance: Dictionary = _dict(tables, "balance", errors)
	var blocks: Dictionary = _dict(tables, "block_types", errors)
	var explosives: Dictionary = _dict(tables, "explosives", errors)
	var packs: Dictionary = _dict(tables, "packs", errors)
	var bands: Variant = tables.get("depth_bands")
	var art_sources: Dictionary = _dict(tables, "art_sources", errors)

	_check_balance(balance, errors)
	_check_ui(balance, errors)
	_check_settings(balance, errors)
	_check_mine_geometry(balance, errors)
	_check_blocks(blocks, errors)
	_check_palette(tables.get("palette"), blocks, errors)
	_check_art_sources(art_sources, blocks, errors)
	_check_bands(bands, blocks, errors)
	_check_band_depth_reward(bands, blocks, errors)
	_check_explosives(explosives, balance, errors)
	_check_packs(packs, explosives, errors)
	_check_free_charge(explosives, blocks, bands, balance, errors)
	_check_generation(tables.get("generation"), errors)
	_check_relics(tables.get("relics"), bands, balance, errors)
	_check_prestige(tables.get("prestige"), errors)
	return errors

static func _dict(tables: Dictionary, key: String, errors: Array) -> Dictionary:
	var v: Variant = tables.get(key)
	if v == null:
		errors.append("missing table: %s.json" % key)
		return {}
	if not (v is Dictionary):
		errors.append("%s.json must be a JSON object" % key)
		return {}
	return v

static func _check_balance(b: Dictionary, errors: Array) -> void:
	# Strictly-positive required keys. HP-scaling multipliers (AC-5.2.1) are
	# required here so the no-stall solvability check (AC-5.5.5) can verify the
	# free charge against the SCALED floor HP, not just the unscaled table value.
	for k in ["block_pixel_size", "shaft_width_cells", "chunk_height_cells", "crack_stages",
			"max_blast_radius_cells", "active_body_cap_desktop", "active_body_cap_web",
			"depth_hp_mult_per_cell", "mine_hardness_mult_max"]:
		if not b.has(k):
			errors.append("balance: missing '%s'" % k)
		elif float(b[k]) <= 0.0:
			errors.append("balance: '%s' must be > 0" % k)
	# run_seed must be present (logical-determinism seed); any int is acceptable.
	if not b.has("run_seed"):
		errors.append("balance: missing 'run_seed'")
	# starting_money must be present and non-negative (0 is valid).
	if not b.has("starting_money"):
		errors.append("balance: missing 'starting_money'")
	elif int(b.get("starting_money", -1)) < 0:
		errors.append("balance: 'starting_money' must be >= 0")
	if b.has("platform_clear_threshold") and int(b.get("platform_clear_threshold", 0)) <= 0:
		errors.append("balance: 'platform_clear_threshold' must be > 0")
	# Platform descent + camera tunables (U7 / AC-5.7.2, AC-5.7.3). All required so
	# the descent depth, tween duration, and camera anchor are data, never code literals.
	# descent_max_steps: rows the platform may drop per trigger (>= 1).
	if not b.has("descent_max_steps"):
		errors.append("balance: missing 'descent_max_steps'")
	elif int(b.get("descent_max_steps", 0)) < 1:
		errors.append("balance: 'descent_max_steps' must be >= 1")
	# descent_tween_seconds: tween duration (> 0 so descent animates, never snaps).
	if not b.has("descent_tween_seconds"):
		errors.append("balance: missing 'descent_tween_seconds'")
	elif float(b.get("descent_tween_seconds", 0.0)) <= 0.0:
		errors.append("balance: 'descent_tween_seconds' must be > 0")
	# camera_lookahead_cells: camera anchor offset below the platform target (>= 0).
	if not b.has("camera_lookahead_cells"):
		errors.append("balance: missing 'camera_lookahead_cells'")
	elif int(b.get("camera_lookahead_cells", -1)) < 0:
		errors.append("balance: 'camera_lookahead_cells' must be >= 0")
	# Web active-body cap should not exceed the desktop cap (web is the weaker target).
	if b.has("active_body_cap_web") and b.has("active_body_cap_desktop"):
		if int(b.get("active_body_cap_web", 0)) > int(b.get("active_body_cap_desktop", 0)):
			errors.append("balance: 'active_body_cap_web' must be <= 'active_body_cap_desktop'")
	# blast_fuzz_pct (AC-5.2.3): the injected-rng fuzz spread. Must be present and in
	# [0, 1): 0 disables fuzz; a spread of 1 would permit a 0x factor (zero damage),
	# which could stall the no-regen dig (AC-5.2.7/AC-5.5.5), so it is bounded < 1.
	if not b.has("blast_fuzz_pct"):
		errors.append("balance: missing 'blast_fuzz_pct'")
	else:
		var fp: float = float(b.get("blast_fuzz_pct", -1.0))
		if fp < 0.0 or fp >= 1.0:
			errors.append("balance: 'blast_fuzz_pct' must be in [0, 1)")

static func _check_mine_geometry(b: Dictionary, errors: Array) -> void:
	for k in ["mine_width_cells", "mine_height_cells"]:
		if not b.has(k):
			errors.append("balance: missing '%s'" % k)
		elif int(b.get(k, 0)) <= 0:
			errors.append("balance: '%s' must be > 0" % k)
	if b.has("mine_width_cells") and b.has("shaft_width_cells"):
		var mine_w: int = int(b.get("mine_width_cells", 0))
		var shaft_w: int = int(b.get("shaft_width_cells", 0))
		if shaft_w > mine_w:
			errors.append("balance: 'shaft_width_cells' (%d) must be <= 'mine_width_cells' (%d)" % [shaft_w, mine_w])
		if shaft_w % 2 == 0:
			errors.append("balance: 'shaft_width_cells' must be odd so the corridor has a center line")
	if b.has("mine_height_cells") and b.has("chunk_height_cells"):
		var mine_h: int = int(b.get("mine_height_cells", 0))
		var chunk_h: int = int(b.get("chunk_height_cells", 0))
		if mine_h > 0 and chunk_h > 0 and mine_h < chunk_h:
			errors.append("balance: 'mine_height_cells' must be >= 'chunk_height_cells'")
	if b.has("platform_clear_threshold") and b.has("shaft_width_cells"):
		var threshold: int = int(b.get("platform_clear_threshold", 0))
		var shaft_w2: int = int(b.get("shaft_width_cells", 0))
		if threshold > shaft_w2:
			errors.append("balance: 'platform_clear_threshold' (%d) must be <= shaft width (%d)" % [threshold, shaft_w2])
	for k in ["camera_zoom", "light_radius_px", "light_softness_px", "light_dim_alpha"]:
		if not b.has(k):
			errors.append("balance: missing '%s'" % k)
	if b.has("camera_zoom") and float(b.get("camera_zoom", 0.0)) <= 0.0:
		errors.append("balance: 'camera_zoom' must be > 0")
	if b.has("light_radius_px") and float(b.get("light_radius_px", 0.0)) <= 0.0:
		errors.append("balance: 'light_radius_px' must be > 0")
	if b.has("light_softness_px") and float(b.get("light_softness_px", -1.0)) < 0.0:
		errors.append("balance: 'light_softness_px' must be >= 0")
	if b.has("light_dim_alpha"):
		var alpha: float = float(b.get("light_dim_alpha", -1.0))
		if alpha < 0.0 or alpha > 1.0:
			errors.append("balance: 'light_dim_alpha' must be in [0,1]")

## AC-5.8.5 (portrait HUD layout). The thumb-safe touch-target minimum and the base HUD
## edge margin are tunables, not code literals. The touch-target floor must sit in the
## ~44–48px guideline band (Apple HIG 44 / Material 48); allow a small range [44,64] so a
## designer can go larger but never below the accessibility floor. The edge margin must be
## present and non-negative (0 = flush, allowed but discouraged; the safe-area inset extends
## it on real devices). A missing key fails the gate (balance is data, never a code default).
static func _check_ui(b: Dictionary, errors: Array) -> void:
	if not b.has("ui_min_touch_target_px"):
		errors.append("balance: missing 'ui_min_touch_target_px' (AC-5.8.5 touch target)")
	else:
		var t: float = float(b.get("ui_min_touch_target_px", 0.0))
		if t < 44.0 or t > 64.0:
			errors.append("balance: 'ui_min_touch_target_px' %s must be in [44,64] — the ~44–48px thumb-safe floor (AC-5.8.5)" % str(t))
	if not b.has("ui_edge_margin_px"):
		errors.append("balance: missing 'ui_edge_margin_px' (AC-5.8.5 HUD edge margin)")
	elif float(b.get("ui_edge_margin_px", -1.0)) < 0.0:
		errors.append("balance: 'ui_edge_margin_px' must be >= 0 (AC-5.8.5)")

## AC-5.10.1 (accessibility settings). The Settings UI seeds from data-driven defaults +
## ranges — volumes/motion are normalized [0,1] sliders; the UI text scale carries an
## explicit [min,max] band the slider clamps to. All required (balance is data) and each
## default must sit inside its own range, so a /data author can't ship a setting that
## starts outside the slider it drives.
static func _check_settings(b: Dictionary, errors: Array) -> void:
	if not b.has("settings"):
		errors.append("balance: missing 'settings' block (AC-5.10.1 volume/motion/text-scale)")
		return
	var s: Variant = b.get("settings")
	if not (s is Dictionary):
		errors.append("balance: 'settings' must be a JSON object (AC-5.10.1)")
		return
	var sd: Dictionary = s
	# Normalized [0,1] sliders: SFX/Music volume + motion intensity.
	for k in ["default_sfx_volume", "default_music_volume", "default_motion_intensity"]:
		if not sd.has(k):
			errors.append("balance.settings: missing '%s' (AC-5.10.1)" % k)
		else:
			var v: float = float(sd.get(k, -1.0))
			if v < 0.0 or v > 1.0:
				errors.append("balance.settings: '%s' %s must be in [0,1] (AC-5.10.1)" % [k, str(v)])
	# UI text-scale band: 0 < min <= max, and the default sits inside it (AC-5.8.6 reflow target).
	for k in ["text_scale_min", "text_scale_max", "default_text_scale"]:
		if not sd.has(k):
			errors.append("balance.settings: missing '%s' (AC-5.10.1 text scale)" % k)
	if sd.has("text_scale_min") and sd.has("text_scale_max"):
		var lo: float = float(sd.get("text_scale_min", 0.0))
		var hi: float = float(sd.get("text_scale_max", 0.0))
		if lo <= 0.0:
			errors.append("balance.settings: 'text_scale_min' must be > 0 (AC-5.10.1)")
		if hi < lo:
			errors.append("balance.settings: 'text_scale_max' (%s) must be >= 'text_scale_min' (%s)" % [str(hi), str(lo)])
		if sd.has("default_text_scale"):
			var d: float = float(sd.get("default_text_scale", 0.0))
			if d < lo or d > hi:
				errors.append("balance.settings: 'default_text_scale' %s must be within [%s,%s] (AC-5.10.1)" % [str(d), str(lo), str(hi)])

static func _check_blocks(blocks: Dictionary, errors: Array) -> void:
	if blocks.is_empty():
		errors.append("block_types: registry is empty")
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary):
			errors.append("block_types[%s]: must be an object" % id)
			continue
		for k in ["display_name", "hardness", "max_hp", "diggable", "glyph", "palette_index"]:
			if not blk.has(k):
				errors.append("block_types[%s]: missing '%s'" % [id, k])
		if blk.get("diggable", false) and int(blk.get("max_hp", 0)) <= 0:
			errors.append("block_types[%s]: diggable block must have max_hp > 0" % id)
		if int(blk.get("hardness", -1)) < 0:
			errors.append("block_types[%s]: hardness must be >= 0" % id)
		var ore: Variant = blk.get("ore")
		if ore != null:
			if not (ore is Dictionary) or not ore.has("value"):
				errors.append("block_types[%s]: ore must be null or {value}" % id)
			elif int(ore.get("value", -1)) < 0:
				errors.append("block_types[%s]: ore.value must be >= 0" % id)
	# `hardness` is load-bearing, not vestigial (AC-5.1.5 resolves it; AC-5.2.1 says
	# "HP derived from its type's hardness"). We wire it into the HP contract: among
	# diggable blocks, base max_hp SHALL be monotonic non-decreasing in hardness, so a
	# harder block never has less base HP than a softer one. (Equal hardness may differ —
	# e.g. an ore vs plain rock of the same hardness.) This binds the authored max_hp
	# table to the hardness ordinal so the field is meaningful, without re-deriving HP.
	_check_hardness_hp_monotonic(blocks, errors)

static func _check_art_sources(art_sources: Dictionary, blocks: Dictionary, errors: Array) -> void:
	if art_sources.is_empty():
		return
	var terrain: Variant = art_sources.get("terrain")
	if not (terrain is Dictionary):
		errors.append("art_sources: missing terrain object")
		return
	var t: Dictionary = terrain
	var path: String = str(t.get("source_path", ""))
	if path.is_empty():
		errors.append("art_sources.terrain: missing source_path")
	elif not FileAccess.file_exists(path):
		errors.append("art_sources.terrain: source_path does not exist: %s" % path)
	if int(t.get("tile_px", 0)) <= 0:
		errors.append("art_sources.terrain: tile_px must be > 0")
	var tiles: Variant = t.get("block_tiles")
	if not (tiles is Dictionary):
		errors.append("art_sources.terrain: block_tiles must be an object")
		return
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary) or not bool((blk as Dictionary).get("diggable", false)):
			continue
		if not (tiles as Dictionary).has(id):
			errors.append("art_sources.terrain.block_tiles: missing tile coordinate for diggable block '%s'" % id)
			continue
		var coord: Variant = (tiles as Dictionary)[id]
		if not (coord is Array) or (coord as Array).size() != 2:
			errors.append("art_sources.terrain.block_tiles[%s]: must be [x, y]" % id)
			continue
		if int((coord as Array)[0]) < 0 or int((coord as Array)[1]) < 0:
			errors.append("art_sources.terrain.block_tiles[%s]: coordinates must be >= 0" % id)

## AC-5.2.1 / AC-5.1.5: max_hp must not decrease as hardness increases (diggable blocks).
static func _check_hardness_hp_monotonic(blocks: Dictionary, errors: Array) -> void:
	# Collect (hardness, max_hp, id) for diggable blocks, sort by hardness, and check
	# that the max_hp seen so far never exceeds a lower-hardness block's max_hp.
	var rows: Array = []
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary) or not bool(blk.get("diggable", false)):
			continue
		rows.append({"h": int(blk.get("hardness", 0)), "hp": int(blk.get("max_hp", 0)), "id": str(id)})
	rows.sort_custom(func(a, b): return a["h"] < b["h"])
	# For each adjacent pair of DISTINCT hardness levels, the higher level's MIN hp must
	# be >= the lower level's MAX hp. Compute per-level min/max, then compare in order.
	var levels: Dictionary = {}  # hardness -> {min, max}
	for r in rows:
		var h: int = r["h"]
		if not levels.has(h):
			levels[h] = {"min": r["hp"], "max": r["hp"]}
		else:
			levels[h]["min"] = mini(levels[h]["min"], r["hp"])
			levels[h]["max"] = maxi(levels[h]["max"], r["hp"])
	var hkeys: Array = levels.keys()
	hkeys.sort()
	for i in range(1, hkeys.size()):
		var lo_h: int = hkeys[i - 1]
		var hi_h: int = hkeys[i]
		if levels[hi_h]["min"] < levels[lo_h]["max"]:
			errors.append("block_types: max_hp not monotonic with hardness — hardness %d (min hp %d) < hardness %d (max hp %d); harder rock must not have less base HP (AC-5.2.1)" % [hi_h, levels[hi_h]["min"], lo_h, levels[lo_h]["max"]])

## AC-5.10.2 / AC-5.10.3 (non-color block identity). palette.json backs the block COLOR
## (palette_index) and each diggable block carries a distinct GLYPH shape on the overlay
## layer. Enforce: palette present + valid hex; every palette_index in range; every diggable
## glyph is a known shape (never "none"); distinct diggable blocks use distinct glyphs; and
## every pair of diggable block colors differs in LUMINANCE (not just hue), so identity never
## rides color/hue alone — a colorblind player can split blocks by shape AND by brightness.
static func _check_palette(pal: Variant, blocks: Dictionary, errors: Array) -> void:
	if pal == null:
		errors.append("missing table: palette.json")
		return
	if not (pal is Dictionary) or not ((pal as Dictionary).get("colors") is Array):
		errors.append("palette.json must be an object with a 'colors' array")
		return
	var colors: Array = (pal as Dictionary)["colors"]
	if colors.is_empty():
		errors.append("palette: 'colors' must be a non-empty array")
		return
	for i in range(colors.size()):
		if not Color.html_is_valid(str(colors[i])):
			errors.append("palette: colors[%d] '%s' is not a valid hex color" % [i, str(colors[i])])
	var glyph_owner: Dictionary = {}  # glyph name -> first block id that claimed it
	var lum_rows: Array = []          # {id, lum} per diggable block (luminance-contrast check)
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary):
			continue
		var pidx: int = int((blk as Dictionary).get("palette_index", -1))
		if pidx < 0 or pidx >= colors.size():
			errors.append("block_types[%s]: palette_index %d out of palette range [0,%d)" % [id, pidx, colors.size()])
		if not bool((blk as Dictionary).get("diggable", false)):
			continue
		var g: String = str((blk as Dictionary).get("glyph", "none"))
		if not ALLOWED_GLYPHS.has(g):
			errors.append("block_types[%s]: diggable glyph '%s' must be one of %s (no color-only identity, AC-5.10.2)" % [id, g, str(ALLOWED_GLYPHS)])
		elif glyph_owner.has(g):
			errors.append("block_types[%s]: glyph '%s' already used by '%s' — distinct block types need distinct glyphs (AC-5.10.2)" % [id, g, glyph_owner[g]])
		else:
			glyph_owner[g] = id
		if pidx >= 0 and pidx < colors.size() and Color.html_is_valid(str(colors[pidx])):
			lum_rows.append({"id": str(id), "lum": _rel_luminance(Color.html(str(colors[pidx])))})
	for i in range(lum_rows.size()):
		for j in range(i + 1, lum_rows.size()):
			var d: float = absf(float(lum_rows[i]["lum"]) - float(lum_rows[j]["lum"]))
			if d < MIN_BLOCK_LUMINANCE_DELTA:
				errors.append("palette: block colors for '%s' and '%s' differ in luminance by only %.3f (< %.3f) — block types must contrast in luminance, not just hue (AC-5.10.3)" % [lum_rows[i]["id"], lum_rows[j]["id"], d, MIN_BLOCK_LUMINANCE_DELTA])

## WCAG relative luminance (0..1). Local copy so the data gate is self-contained.
static func _rel_luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)

static func _lin(ch: float) -> float:
	if ch <= 0.04045:
		return ch / 12.92
	return pow((ch + 0.055) / 1.055, 2.4)

static func _check_bands(bands: Variant, blocks: Dictionary, errors: Array) -> void:
	if bands == null:
		errors.append("missing table: depth_bands.json")
		return
	if not (bands is Array) or (bands as Array).is_empty():
		errors.append("depth_bands.json must be a non-empty array")
		return
	for band in bands:
		if not (band is Dictionary):
			errors.append("depth_bands: each band must be an object")
			continue
		var bid: String = str(band.get("id", "?"))
		if int(band.get("min_depth_cells", 0)) >= int(band.get("max_depth_cells", 0)):
			errors.append("depth_bands[%s]: min_depth_cells must be < max_depth_cells" % bid)
		var weights: Variant = band.get("block_weights")
		if not (weights is Dictionary) or (weights as Dictionary).is_empty():
			errors.append("depth_bands[%s]: block_weights must be a non-empty object" % bid)
			continue
		for block_id in (weights as Dictionary).keys():
			if not blocks.has(block_id):
				errors.append("depth_bands[%s]: references unknown block '%s'" % [bid, block_id])
			elif not blocks.get(block_id, {}).get("diggable", false):
				errors.append("depth_bands[%s]: block '%s' is not diggable" % [bid, block_id])
			if float(weights[block_id]) <= 0.0:
				errors.append("depth_bands[%s]: weight for '%s' must be > 0" % [bid, block_id])

## AC-5.5.2 (depth reward): with increasing depth, the EXPECTED ore value per cell and the
## RARE-GEM (highest-value block type) probability SHALL both strictly rise across adjacent
## depth bands. This is the machine-checked replacement for the old "floor (minimum value)
## rises" clause (v0.4.1): common value-0 filler rock is allowed at any depth, so the reward
## signal is expected value + gem chance, not a per-cell minimum. Enforcing it at the gate means
## a future /data edit that makes a deeper band no more rewarding fails the build, not the player.
static func _check_band_depth_reward(bands: Variant, blocks: Dictionary, errors: Array) -> void:
	if not (bands is Array) or (bands as Array).size() < 2:
		return  # 0/1 band → no adjacency to compare (band shape errors are reported elsewhere)
	# The "gem" is the single highest ore value present in the registry; gem probability in a
	# band is the summed weight of every block at that max value (handles ties), over total weight.
	var gem_value: int = -1
	for id in blocks.keys():
		if blocks[id] is Dictionary:
			gem_value = maxi(gem_value, _ore_value(blocks[id]))
	# Build a depth-sorted list of (min_depth, ev, gem_prob, id); skip malformed bands.
	var rows: Array = []
	for band in (bands as Array):
		if not (band is Dictionary):
			continue
		var weights: Variant = band.get("block_weights")
		if not (weights is Dictionary) or (weights as Dictionary).is_empty():
			continue  # band-shape errors already reported by _check_bands
		var total: float = 0.0
		var value_sum: float = 0.0
		var gem_weight: float = 0.0
		for bid in (weights as Dictionary).keys():
			if not blocks.has(bid) or not (blocks[bid] is Dictionary):
				continue  # unknown-block errors already reported by _check_bands
			var w: float = float((weights as Dictionary)[bid])
			if w <= 0.0:
				continue
			total += w
			var v: int = _ore_value(blocks[bid])
			value_sum += w * float(v)
			if gem_value > 0 and v == gem_value:
				gem_weight += w
		if total <= 0.0:
			continue
		rows.append({
			"id": str(band.get("id", "?")),
			"min": int(band.get("min_depth_cells", 0)),
			"ev": value_sum / total,
			"gem": gem_weight / total,
		})
	rows.sort_custom(func(a, b): return a["min"] < b["min"])
	for i in range(1, rows.size()):
		var lo: Dictionary = rows[i - 1]
		var hi: Dictionary = rows[i]
		if hi["ev"] <= lo["ev"]:
			errors.append("depth_bands: expected ore value per cell must strictly rise with depth — band '%s' EV %.3f <= shallower band '%s' EV %.3f (SPEC AC-5.5.2)" % [hi["id"], hi["ev"], lo["id"], lo["ev"]])
		if hi["gem"] <= lo["gem"]:
			errors.append("depth_bands: rare-gem probability must strictly rise with depth — band '%s' gem-prob %.3f <= shallower band '%s' gem-prob %.3f (SPEC AC-5.5.2)" % [hi["id"], hi["gem"], lo["id"], lo["gem"]])

## Ore value of a block dict (0 if no ore). Local helper so the depth-reward check does not
## need the full Registry-by-id indirection (blocks here is the raw block_types table).
static func _ore_value(blk: Variant) -> int:
	if not (blk is Dictionary):
		return 0
	var ore: Variant = (blk as Dictionary).get("ore")
	if ore is Dictionary:
		return int((ore as Dictionary).get("value", 0))
	return 0

static func _check_explosives(explosives: Dictionary, balance: Dictionary, errors: Array) -> void:
	if explosives.is_empty():
		errors.append("explosives: registry is empty")
	var max_radius: int = int(balance.get("max_blast_radius_cells", 9999))
	for id in explosives.keys():
		var ex: Variant = explosives[id]
		if not (ex is Dictionary):
			errors.append("explosives[%s]: must be an object" % id)
			continue
		# AC-5.4.1 names the FULL explosive-resource shape. ALL of these are required so a
		# /data author can't ship a physics-incomplete charge that silently falls back to
		# code-side defaults (throw_params.gd), violating "balance is data, never code".
		for k in ["mass", "bounce", "friction", "base_impulse", "detonation_mode",
				"blast_radius_cells", "blast_intensity", "blast_falloff",
				"sticky", "efficiency", "rarity", "tier"]:
			if not ex.has(k):
				errors.append("explosives[%s]: missing '%s'" % [id, k])
		if float(ex.get("mass", 0.0)) <= 0.0:
			errors.append("explosives[%s]: mass must be > 0" % id)
		if float(ex.get("base_impulse", 0.0)) <= 0.0:
			errors.append("explosives[%s]: base_impulse must be > 0" % id)
		if not DETONATION_MODES.has(ex.get("detonation_mode", "")):
			errors.append("explosives[%s]: detonation_mode must be one of %s" % [id, str(DETONATION_MODES)])
		var radius: int = int(ex.get("blast_radius_cells", 0))
		if radius < 1:
			errors.append("explosives[%s]: blast_radius_cells must be >= 1" % id)
		elif radius > max_radius:
			errors.append("explosives[%s]: blast_radius_cells %d exceeds balance.max_blast_radius_cells %d" % [id, radius, max_radius])
		if int(ex.get("blast_intensity", 0)) <= 0:
			errors.append("explosives[%s]: blast_intensity must be > 0" % id)
		# Single source of truth: the falloff array length is exactly radius+1
		# (index 0 = center cell, index r = the cell r away). AC-5.2.4.
		var falloff: Variant = ex.get("blast_falloff")
		if not (falloff is Array):
			errors.append("explosives[%s]: blast_falloff must be an array" % id)
		elif radius >= 1 and (falloff as Array).size() != radius + 1:
			errors.append("explosives[%s]: blast_falloff length %d must equal blast_radius_cells+1 (%d)" % [id, (falloff as Array).size(), radius + 1])
		# Fuse-mode explosives must declare a positive fuse (AC-5.4.1).
		if ex.get("detonation_mode", "") == "fuse_seconds":
			if not ex.has("fuse_seconds") or float(ex.get("fuse_seconds", 0.0)) <= 0.0:
				errors.append("explosives[%s]: detonation_mode 'fuse_seconds' requires fuse_seconds > 0" % id)
		# Physics fields consumed by the live charge (charge.gd:32-33) — non-negative data,
		# not silent code-side defaults.
		if ex.has("bounce") and float(ex.get("bounce", -1.0)) < 0.0:
			errors.append("explosives[%s]: bounce must be >= 0" % id)
		if ex.has("friction") and float(ex.get("friction", -1.0)) < 0.0:
			errors.append("explosives[%s]: friction must be >= 0" % id)
		# Efficiency/cost descriptor (AC-5.4.1/5.4.3): strictly positive (the free charge is
		# the 1.0 baseline; paid charges exceed it — enforced in _check_free_charge).
		if ex.has("efficiency") and float(ex.get("efficiency", 0.0)) <= 0.0:
			errors.append("explosives[%s]: efficiency must be > 0" % id)
		# tier is the gacha/progression ordinal (>= 1); rarity is a non-empty label.
		if ex.has("tier") and int(ex.get("tier", 0)) < 1:
			errors.append("explosives[%s]: tier must be >= 1" % id)
		if ex.has("rarity") and str(ex.get("rarity", "")).is_empty():
			errors.append("explosives[%s]: rarity must be a non-empty label" % id)

static func _check_packs(packs: Dictionary, explosives: Dictionary, errors: Array) -> void:
	if packs.is_empty():
		errors.append("packs: registry is empty")
	# v0.4: packs grant ONLY finite, efficient (paid) charges. The free unlimited
	# charge is a flagged explosive (see _check_free_charge), not a price-0 pack —
	# so the old "at least one free pack" rule is gone.
	for id in packs.keys():
		var p: Variant = packs[id]
		if not (p is Dictionary):
			errors.append("packs[%s]: must be an object" % id)
			continue
		if int(p.get("price", -1)) < 0:
			errors.append("packs[%s]: price must be >= 0" % id)
		if int(p.get("charge_count", 0)) < 1:
			errors.append("packs[%s]: charge_count must be >= 1" % id)
		# pity_every: implement-or-absent. When present it must be a non-negative
		# int; when > 0 it declares a pity floor, which the pack's table must be
		# able to satisfy (at least one tier-2+ explosive reachable).
		if p.has("pity_every"):
			var pity: int = int(p.get("pity_every", -1))
			if pity < 0:
				errors.append("packs[%s]: pity_every must be >= 0 when present" % id)
		var weights: Variant = p.get("weights")
		if not (weights is Dictionary) or (weights as Dictionary).is_empty():
			errors.append("packs[%s]: weights must be a non-empty object" % id)
			continue
		var has_high_tier := false
		for ex_id in (weights as Dictionary).keys():
			if not explosives.has(ex_id):
				errors.append("packs[%s]: references unknown explosive '%s'" % [id, ex_id])
			elif int((explosives[ex_id] as Dictionary).get("tier", 1)) >= 2:
				has_high_tier = true
			# Packs grant paid charges only: the free charge must never be in a pack table.
			elif bool((explosives[ex_id] as Dictionary).get("free", false)):
				errors.append("packs[%s]: free charge '%s' must not appear in a pack table" % [id, ex_id])
			if float(weights[ex_id]) <= 0.0:
				errors.append("packs[%s]: weight for '%s' must be > 0" % [id, ex_id])
		if int(p.get("pity_every", 0)) > 0 and not has_high_tier:
			errors.append("packs[%s]: pity_every > 0 but no tier>=2 explosive is reachable to guarantee" % id)

## v0.4: exactly one explosive is the flagged FREE unlimited charge, and it must be
## able to break the shallowest floor beneath the platform — no /data config may
## produce a stall (AC-5.4.3, AC-5.5.5, AC-5.4.6, AC-5.12.1).
static func _check_free_charge(explosives: Dictionary, blocks: Dictionary, bands: Variant, balance: Dictionary, errors: Array) -> void:
	if explosives.is_empty():
		return  # already reported by _check_explosives
	var free_ids: Array = []
	for id in explosives.keys():
		var ex: Variant = explosives[id]
		if ex is Dictionary and bool(ex.get("free", false)):
			free_ids.append(id)
	if free_ids.is_empty():
		errors.append("explosives: exactly one explosive must be flagged 'free: true' (the free unlimited charge); found none (SPEC AC-5.12.1)")
		return
	if free_ids.size() > 1:
		errors.append("explosives: exactly one explosive may be flagged 'free: true'; found %d: %s" % [free_ids.size(), str(free_ids)])
		return
	var free: Dictionary = explosives[free_ids[0]]
	# The free charge must not also be a paid pity guarantee — it should be tier 1.
	if int(free.get("tier", 1)) != 1:
		errors.append("explosives[%s]: the free charge must be tier 1 (the inefficient baseline)" % free_ids[0])

	# AC-5.4.3: ALL other (paid) explosives SHALL be MORE efficient than the free charge —
	# efficiency is the thing money buys. Enforce strict ordering so /data can't silently
	# make the free charge as good as (or better than) a paid one.
	var free_eff: float = float(free.get("efficiency", 1.0))
	for oid in explosives.keys():
		if oid == free_ids[0]:
			continue
		var oex: Variant = explosives[oid]
		if not (oex is Dictionary):
			continue
		if float((oex as Dictionary).get("efficiency", 0.0)) <= free_eff:
			errors.append("explosives[%s]: paid charge efficiency %s must exceed the free charge's %s (AC-5.4.3: money buys efficiency)" % [oid, str((oex as Dictionary).get("efficiency", 0.0)), str(free_eff)])

	# No-stall solvability (AC-5.5.5 / AC-5.4.6). The free charge need NOT one-hit
	# the floor — AC-5.4.6 says it breaks it "eventually / slowly". The real stall
	# condition is the free charge dealing ZERO integer damage to a cell: surviving
	# blocks retain damage (AC-5.2.7, no regen), so any per-throw damage >= 1
	# guarantees progress. We verify this against the WORST-CASE *scaled* floor HP
	# (AC-5.5.5: "against each mine's floor-HP scaling"), i.e. the deepest cell in the
	# hardest mine, where HP = base_hp x depth_mult x mine_hardness_mult is largest.
	var floor_hp: int = _max_scaled_floor_hp(bands, blocks, balance)
	if floor_hp < 0:
		return  # no diggable floor — reported by band checks
	# Per-cell centre damage the free charge deals (integer-floored, as the grid is).
	var intensity: float = float(free.get("blast_intensity", 0))
	var falloff: Variant = free.get("blast_falloff")
	var f0: float = 1.0
	if falloff is Array and (falloff as Array).size() > 0:
		f0 = float((falloff as Array)[0])
	# Fold WORST-CASE fuzz into the no-stall floor: the live blast multiplies damage by a
	# factor in [1 - blast_fuzz_pct, 1 + blast_fuzz_pct] (blast.gd:68,86). The worst roll must
	# still deal >= 1 integer damage, else a throw can do literally nothing on a bad fuzz draw
	# (AC-5.5.5 no-stall, robust form — the unfuzzed check alone missed low-intensity charges).
	var fuzz_pct: float = clampf(float(balance.get("blast_fuzz_pct", 0.0)), 0.0, 1.0)
	var centre_damage: int = int(intensity * f0 * (1.0 - fuzz_pct))
	if centre_damage <= 0:
		errors.append("explosives[%s]: free charge worst-case damage is 0 (intensity %s x falloff[0] %s x (1-fuzz %s)) — a throw can deal 0 against the scaled floor (worst-case HP %d); would stall (SPEC AC-5.5.5 / AC-5.4.6)" % [free_ids[0], str(intensity), str(f0), str(fuzz_pct), floor_hp])

## Worst-case scaled floor HP across the configured depth/mine range, or -1 if no
## diggable floor exists. The deepest diggable floor cell sits at the deepest band's
## max depth in the hardest mine; HP = base_hp x depth_mult x mine_hardness_mult
## (AC-5.2.1). We take the LOWEST-HP diggable block in that band (the easiest floor
## the player could be standing on) so the no-stall bound is the worst plausible case.
static func _max_scaled_floor_hp(bands: Variant, blocks: Dictionary, balance: Dictionary) -> int:
	var deepest: Dictionary = _deepest_band(bands)
	if deepest.is_empty():
		return -1
	var weights: Variant = deepest.get("block_weights")
	if not (weights is Dictionary):
		return -1
	var min_base_hp: int = -1
	for bid in (weights as Dictionary).keys():
		if not blocks.has(bid):
			continue
		var blk: Dictionary = blocks[bid]
		if not bool(blk.get("diggable", false)):
			continue
		var hp: int = int(blk.get("max_hp", 0))
		if hp > 0 and (min_base_hp < 0 or hp < min_base_hp):
			min_base_hp = hp
	if min_base_hp < 0:
		return -1
	# Deepest cell = max_depth_cells - 1 (the last in-range cell of the deepest band).
	var max_depth_cell: int = max(0, int(deepest.get("max_depth_cells", 1)) - 1)
	var depth_mult: float = 1.0 + float(max_depth_cell) * float(balance.get("depth_hp_mult_per_cell", 0.0))
	var mine_mult: float = float(balance.get("mine_hardness_mult_max", 1.0))
	return int(round(float(min_base_hp) * depth_mult * mine_mult))

## Returns the band with the greatest max_depth_cells (the deepest), or {}.
static func _deepest_band(bands: Variant) -> Dictionary:
	if not (bands is Array):
		return {}
	var best: Dictionary = {}
	var best_max: int = -1
	for band in bands:
		if not (band is Dictionary):
			continue
		var m: int = int(band.get("max_depth_cells", 0))
		if m > best_max:
			best_max = m
			best = band
	return best

## U2 (v0.4): FastNoiseLite generation parameters. Coherent gen needs a positive
## frequency, >=1 octave, and a positive normalization std (the normal-CDF transform
## that keeps the coherent noise distribution-correct). These are tunables in /data.
static func _check_generation(gen: Variant, errors: Array) -> void:
	if gen == null:
		errors.append("missing table: generation.json")
		return
	if not (gen is Dictionary):
		errors.append("generation.json must be a JSON object")
		return
	var g: Dictionary = gen
	if not g.has("noise_frequency") or float(g.get("noise_frequency", 0.0)) <= 0.0:
		errors.append("generation: 'noise_frequency' must be > 0")
	if not g.has("noise_octaves") or int(g.get("noise_octaves", 0)) < 1:
		errors.append("generation: 'noise_octaves' must be >= 1")
	if not g.has("noise_std") or float(g.get("noise_std", 0.0)) <= 0.0:
		errors.append("generation: 'noise_std' must be > 0 (normal-CDF normalization)")

## U2 (v0.4): relic placement config (AC-5.6.1). The relic is the dig objective,
## placed at/below a configured minimum depth as a pure fn of (mine_seed). The
## min depth + span must be sane and must fall WITHIN a diggable depth band so the
## relic cell is actually reachable/breakable.
static func _check_relics(relics: Variant, bands: Variant, balance: Dictionary, errors: Array) -> void:
	if relics == null:
		errors.append("missing table: relics.json")
		return
	if not (relics is Dictionary):
		errors.append("relics.json must be a JSON object")
		return
	var r: Dictionary = relics
	var min_depth: int = int(r.get("min_depth_cells", -1))
	if not r.has("min_depth_cells") or min_depth < 0:
		errors.append("relics: 'min_depth_cells' must be present and >= 0")
	var span: int = int(r.get("depth_span_cells", 0))
	if not r.has("depth_span_cells") or span < 1:
		errors.append("relics: 'depth_span_cells' must be present and >= 1")
	if not r.has("prestige_value") or int(r.get("prestige_value", 0)) != 1:
		errors.append("relics: 'prestige_value' must be exactly 1 (one prestige point per relic, SPEC v0.5 AC-5.6.6)")
	# The relic's possible depth range [min_depth, min_depth+span) must lie within the
	# generated shaft (a diggable band), else the relic could never be generated/broken.
	if min_depth >= 0 and span >= 1 and bands is Array:
		var deepest_max: int = int(_deepest_band(bands).get("max_depth_cells", 0))
		if min_depth + span > deepest_max:
			errors.append("relics: relic depth range [%d,%d) exceeds the deepest band max_depth_cells %d" % [min_depth, min_depth + span, deepest_max])

## U9 (v0.4): minimal prestige upgrades (AC-5.6.4 / power growth). Each upgrade must
## declare a positive prestige cost, a known effect, a positive magnitude, and a
## positive max_level — so a purchase debits a currency, is bounded, and measurably
## changes a dig stat (no declared-but-inert upgrade). The table must be non-empty so
## the minimal prestige purchase exists (VERTICAL_SLICE §1: "buy one permanent upgrade").
static func _check_prestige(prestige: Variant, errors: Array) -> void:
	if prestige == null:
		errors.append("missing table: prestige.json")
		return
	if not (prestige is Dictionary):
		errors.append("prestige.json must be a JSON object")
		return
	var ups: Dictionary = prestige
	if ups.is_empty():
		errors.append("prestige: registry is empty (need at least one power-growth upgrade)")
		return
	var known_effects := ["blast_intensity_mult"]
	for id in ups.keys():
		var up: Variant = ups[id]
		if not (up is Dictionary):
			errors.append("prestige[%s]: must be an object" % id)
			continue
		for k in ["display_name", "effect", "magnitude", "cost_prestige", "max_level"]:
			if not up.has(k):
				errors.append("prestige[%s]: missing '%s'" % [id, k])
		if int(up.get("cost_prestige", 0)) <= 0:
			errors.append("prestige[%s]: cost_prestige must be > 0" % id)
		if float(up.get("magnitude", 0.0)) <= 0.0:
			errors.append("prestige[%s]: magnitude must be > 0" % id)
		if int(up.get("max_level", 0)) <= 0:
			errors.append("prestige[%s]: max_level must be > 0" % id)
		if up.has("effect") and not known_effects.has(str(up.get("effect", ""))):
			errors.append("prestige[%s]: unknown effect '%s' (known: %s)" % [id, str(up.get("effect", "")), str(known_effects)])
