class_name BlockGen
extends RefCounted
## Pure, deterministic procedural block generation (v0.7 continuous gen).
##
## block_at(tables, mine_seed, x, y) -> block type id (String)
## relic_at(tables, mine_seed, cell)  -> bool (the dig's objective placement)
##
## Generation is a PURE, deterministic function of (mine_seed, absolute cell):
## identical output forever, every run, every fresh instance (AC-5.1.4). It is a
## THREE-LAYER resolve with a fixed priority (reports/continuous-gen-design.md §0):
##
##   relic stamp  (priority 0, wins everything)        — relic_at(seed, cell)
##      ↓ else
##   ore overlay  (priority 1..N, rarest-first wins)   — _ore_overlay_at(...)
##      ↓ else
##   base filler  (depth-weight lerp dirt/rock/hard_rock)
##
## No mutable state, no chunk accumulation, no neighbour reads → order-independent.
## The base filler keeps the proven coherent-noise → normal-CDF → weighted-pick pipeline
## (golden-pinned, untouched). The ore overlay is a per-ore FastNoiseLite field seeded
## `mine_seed ^ field_salt`, compared with an INTEGER-quantized threshold so a sub-LSB
## float wobble can only flip cells on a bucket edge (the goldens pin block-id grids,
## never floats — research source 3 cardinal rule, design §7). The relic is a single
## seed-derived 2×2 anchor (power-CDF depth selector, center column band).
##
## NOTE on physics determinism: only this *logical* generation is deterministic.
## Physics is NOT (v0.5, see SPEC). No physics enters this file.
##
## ACs: AC-5.1.3 (depth-banded gen), AC-5.1.4 (pure fn of seed+cell),
##      AC-5.1.7 (coherent veins), AC-5.6.1 (deterministic relic placement).

## Relic footprint (top-left anchor + this many cells in each axis).
const RELIC_W := 2
const RELIC_H := 2

## Quantization scale for the ore-overlay noise compare (design §2.1 / §7): both the
## noise sample and the threshold are floored to int(v * NOISE_QUANTIZE) before the
## >= compare, so the decision crosses an INTEGER boundary (golden-stable).
const NOISE_QUANTIZE := 1024.0

# ── Block selection ──────────────────────────────────────────────────────────

## Returns the block type id for absolute cell (x, y) under the given mine seed.
## x = column (0..mine_width-1), y = row (depth in cells, 0 = top). The 3-stage
## fall-through: relic stamp → ore overlay → base filler. Ore/relic never stamp on air.
static func block_at(tables: Dictionary, mine_seed: int, x: int, y: int) -> String:
	if relic_at(tables, mine_seed, Vector2i(x, y)):
		return "relic"
	var base: String = _base_block_at(tables, mine_seed, x, y)
	if base == "air":
		return "air"
	var ore: String = _ore_overlay_at(tables, mine_seed, x, y)
	if ore != "":
		return ore
	return base

## The base filler block id for absolute cell (x, y) — the proven depth-weight curve:
## depth_weights_at → coherent noise → normal-CDF roll → weighted pick. UNCHANGED from
## v0.4 except ores no longer appear in the weight tables (they moved to the overlay).
static func _base_block_at(tables: Dictionary, mine_seed: int, x: int, y: int) -> String:
	var weights: Dictionary = Registry.depth_weights_at(tables, y)
	if weights.is_empty():
		return "air"
	var noise: FastNoiseLite = _make_noise(tables, mine_seed)
	var roll: float = _roll_at(tables, noise, x, y)
	return _weighted_pick(weights, roll)

## Generates a rectangular region of block ids. Returns a 2D array [row][col].
## Calls block_at per cell (the full 3-stage resolve) — used by chunk init + the golden.
static func generate_region(tables: Dictionary, mine_seed: int,
		start_x: int, start_y: int, width: int, height: int) -> Array:
	var region: Array = []
	for row in range(height):
		var world_y: int = start_y + row
		var row_data: Array = []
		for col in range(width):
			var world_x: int = start_x + col
			row_data.append(block_at(tables, mine_seed, world_x, world_y))
		region.append(row_data)
	return region

# ── Ore overlay (per-ore noise field, rarest-first wins) ──────────────────────

## The ore id whose noise field is super-threshold at (x, y), evaluated in priority
## order (rarest/most-valuable first → first hit wins), or "" if none. Pure fn of
## (mine_seed, cell). Depth-gated (an ore is impossible above its depth_min) and the
## threshold falls with depth (richer deeper). The compare is integer-quantized so it
## is golden-stable (design §2.1).
static func _ore_overlay_at(tables: Dictionary, mine_seed: int, x: int, y: int) -> String:
	var ores: Array = Registry.ore_priority(tables)  # rarest-first, validated unique priority
	for o in ores:
		var depth_min: int = int(o.get("depth_min", 0))
		if y < depth_min:
			continue
		var raw: float = _ore_noise(tables, mine_seed, o).get_noise_2d(float(x), float(y))  # [-1,1]
		var n: float = clampf((raw + 1.0) * 0.5, 0.0, 1.0)
		var qn: int = int(floor(n * NOISE_QUANTIZE))
		var thr: float = _ore_threshold(tables, o, y)
		var qthr: int = int(floor(thr * NOISE_QUANTIZE))
		if qn >= qthr:
			return str(o.get("block_id", ""))
	return ""

## The depth-ramped rarity threshold for ore `o` at depth `y`: lerp(threshold_shallow,
## threshold_deep, depth_curve_s(y)) — falls with depth (deeper never rarer). Shared
## (analytic proxy 1-threshold) with Registry.ore_odds_at + the validator reward check.
static func _ore_threshold(tables: Dictionary, o: Dictionary, y: int) -> float:
	var s: float = Registry.depth_curve_s(tables, y)
	var shallow: float = float(o.get("threshold_shallow", 1.0))
	var deep: float = float(o.get("threshold_deep", 1.0))
	return shallow + s * (deep - shallow)

## The per-ore coherent noise field. Own seed `(mine_seed ^ field_salt) & 0x7FFFFFFF`
## (decorrelated from the base field + every other ore), own frequency (= cluster size:
## low → big veins, high → tiny specks). Pure: same inputs → same field on a fresh
## instance every time (FastNoiseLite is deterministic).
static func _ore_noise(tables: Dictionary, mine_seed: int, o: Dictionary) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = (mine_seed ^ int(o.get("field_salt", 0))) & 0x7FFFFFFF
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.frequency = float(o.get("frequency", 0.08))
	return n

# ── Relic placement (AC-5.6.1) — 2×2 anchor, power-CDF depth, center band ──────

## True iff this cell is one of the mine's relic's 4 cells. The relic is the dig's
## objective: a single seed-derived 2×2 structure. Existence + position are a pure
## function of (mine_seed, config) only — one anchor for the whole mine, re-derived
## independently by every cell, so a relic straddling a chunk seam renders identically
## from both sides regardless of stream order (design §3.2).
static func relic_at(tables: Dictionary, mine_seed: int, cell: Vector2i) -> bool:
	var a: Vector2i = relic_anchor(tables, mine_seed)
	if a.y < 0:
		return false
	return cell.x >= a.x and cell.x < a.x + RELIC_W and cell.y >= a.y and cell.y < a.y + RELIC_H

## The top-left anchor cell of this mine's 2×2 relic, or (-1,-1) if generation cannot
## place it. Pure fn of (mine_seed, config).
##   ROW   = power-CDF inverse-transform "first-success at increasing depth" (design §3.1):
##           depth = min + floor((max-min) * u^(1/k)), one hash draw → one depth, < max.
##           Exactly once + GUARANTEED by relic_guaranteed_depth_cells (the mine is
##           completable: descend to the guaranteed depth and the relic is on the corridor).
##           k back-loads the distribution (rare shallow → common deep).
##   COLUMN = center band |col - center| <= half, top-left clamped so the 2×2 stays in
##            [0, width) (never overflows the right wall).
static func relic_anchor(tables: Dictionary, mine_seed: int) -> Vector2i:
	var relics: Dictionary = tables.get("relics", {})
	if relics.is_empty():
		return Vector2i(-1, -1)
	var width: int = Registry.mine_width_cells(tables)
	if width < RELIC_W:
		return Vector2i(-1, -1)
	var min_d: int = int(relics.get("min_depth_cells", 0))
	var max_d: int = int(relics.get("relic_guaranteed_depth_cells", maxi(min_d + 1, 9000)))
	if max_d <= min_d:
		max_d = min_d + 1
	var k: int = maxi(2, int(relics.get("relic_back_load_k", 4)))
	# ROW: one hash draw → u in [0,1) → one trigger depth < max_d (exactly once, guaranteed).
	var u: float = float(_hash2(mine_seed, 0xC0FFEE) & 0xFFFFFF) / float(0x1000000)
	var depth: int = min_d + int(floor(float(max_d - min_d) * pow(u, 1.0 / float(k))))
	depth = clampi(depth, min_d, max_d - 1)
	# COLUMN: center band, top-left clamped so the 2×2 never overflows the right wall.
	var center: int = int(width / 2)
	var half: int = mini(maxi(0, Registry.relic_band_half_cells(tables)), 5)
	var hx: int = _hash2(mine_seed, 0x5EED)
	var col: int = center - half + (hx % (2 * half + 1))
	col = clampi(col, 0, width - RELIC_W)
	return Vector2i(col, depth)

## Backwards-compatible alias: the relic's top-left anchor cell (callers that ask "where
## is the relic" — block_grid resolves the 2×2 footprint from this). Pure fn of seed.
static func relic_cell(tables: Dictionary, mine_seed: int) -> Vector2i:
	return relic_anchor(tables, mine_seed)

## The 4 absolute cells of this mine's relic footprint, or [] if none. Pure fn of seed.
static func relic_footprint(tables: Dictionary, mine_seed: int) -> Array:
	var a: Vector2i = relic_anchor(tables, mine_seed)
	if a.y < 0:
		return []
	var out: Array = []
	for dy in range(RELIC_H):
		for dx in range(RELIC_W):
			out.append(Vector2i(a.x + dx, a.y + dy))
	return out

# ── Noise → uniform roll (base filler) ─────────────────────────────────────────

## Builds the coherent noise field for a mine seed. Pure: same seed -> same field on
## a fresh instance every time (FastNoiseLite is deterministic). Parameters come from
## generation.json (never hardcoded balance).
static func _make_noise(tables: Dictionary, mine_seed: int) -> FastNoiseLite:
	var gen: Dictionary = tables.get("generation", {})
	var n := FastNoiseLite.new()
	# FastNoiseLite.seed is a 32-bit int field; fold the mine seed into range.
	n.seed = mine_seed & 0x7FFFFFFF
	n.noise_type = FastNoiseLite.TYPE_PERLIN
	n.frequency = float(gen.get("noise_frequency", 0.08))
	var octaves: int = int(gen.get("noise_octaves", 1))
	if octaves <= 1:
		n.fractal_type = FastNoiseLite.FRACTAL_NONE
	else:
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = octaves
		n.fractal_lacunarity = float(gen.get("noise_lacunarity", 2.0))
		n.fractal_gain = float(gen.get("noise_gain", 0.5))
	return n

## Coherent noise at (x,y), normalized to an ~uniform roll in [0,1).
static func _roll_at(tables: Dictionary, noise: FastNoiseLite, x: int, y: int) -> float:
	var gen: Dictionary = tables.get("generation", {})
	var std: float = float(gen.get("noise_std", 0.188))
	if std <= 0.0:
		std = 0.188
	var v: float = noise.get_noise_2d(float(x), float(y))
	return clampf(_normal_cdf(v, std), 0.0, 0.99999999)

## Normal CDF: 0.5 * (1 + erf(v / (std * sqrt(2)))). Maps the bell-shaped noise
## output to a uniform [0,1] roll so the weighted pick honours the band weights.
static func _normal_cdf(v: float, std: float) -> float:
	return 0.5 * (1.0 + _erf(v / (std * 1.4142135623730951)))

## erf approximation (Abramowitz & Stegun 7.1.26, |error| < 1.5e-7). Pure, no
## platform-dependent ops beyond exp(), which is stable for our golden pin.
static func _erf(x: float) -> float:
	var sign: float = 1.0 if x >= 0.0 else -1.0
	var ax: float = absf(x)
	var t: float = 1.0 / (1.0 + 0.3275911 * ax)
	var y: float = 1.0 - (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t \
		- 0.284496736) * t + 0.254829592) * t * exp(-ax * ax)
	return sign * y

# ── Weighted pick ──────────────────────────────────────────────────────────────

## Maps a uniform roll in [0,1) to a key in a weighted dictionary. Keys are sorted
## for a stable, platform-independent walk order (dict iteration order is not a
## contract). The same roll always yields the same key (AC-5.1.4).
static func _weighted_pick(weights: Dictionary, roll: float) -> String:
	var keys: Array = weights.keys()
	keys.sort()
	if keys.is_empty():
		return "air"
	var total: float = 0.0
	for k in keys:
		total += float(weights[k])
	if total <= 0.0:
		return keys[0]
	var target: float = clampf(roll, 0.0, 0.99999999) * total
	var cumulative: float = 0.0
	for k in keys:
		cumulative += float(weights[k])
		if target < cumulative:
			return k
	return keys[keys.size() - 1]

# ── Hashing (relic placement only) ─────────────────────────────────────────────

## Deterministic 31-bit hash of (seed, salt). Used only for the relic's column/row;
## block selection uses coherent noise, not this. Platform-independent integer mix.
static func _hash2(seed_val: int, salt: int) -> int:
	var h: int = (seed_val ^ salt) & 0x7FFFFFFF
	h = (h ^ (h >> 13)) & 0x7FFFFFFF
	h = (h * 1274126177) & 0x7FFFFFFF
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return h
