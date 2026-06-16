class_name BlockGen
extends RefCounted
## Pure, deterministic procedural block generation (v0.4).
##
## block_at(tables, mine_seed, x, y) -> block type id (String)
## relic_at(tables, mine_seed, cell)  -> bool (the dig's objective placement)
##
## Generation is a PURE, deterministic function of (mine_seed, absolute cell):
## identical output forever, every run, every fresh instance (AC-5.1.4). The block
## type is chosen with COHERENT noise (FastNoiseLite) so ore forms veins/clusters
## rather than per-cell salt-and-pepper (AC-5.1.7), and the choice is depth-banded
## (AC-5.1.3) via the depth band's block_weights.
##
## Coherence + correct distribution at once: the coherent noise value is normalized
## to an (approximately) uniform roll in [0,1) by a normal-CDF transform calibrated
## with generation.noise_std, then mapped through the band's weighted CDF. Coherent
## input -> neighbouring cells get similar rolls -> they tend to land on the same
## block (veins); the uniform roll keeps the long-run frequencies matching the
## configured weights (within tolerance).
##
## NOTE on physics determinism: only this *logical* generation is deterministic.
## Physics is NOT (v0.4, see SPEC). No physics enters this file.
##
## ACs: AC-5.1.3 (depth-banded gen), AC-5.1.4 (pure fn of seed+cell),
##      AC-5.1.7 (coherent veins), AC-5.6.1 (deterministic relic placement).

# ── Block selection ──────────────────────────────────────────────────────────

## Returns the block type id for absolute cell (x, y) under the given mine seed.
## x = column (0..shaft_width-1), y = row (depth in cells, 0 = top).
static func block_at(tables: Dictionary, mine_seed: int, x: int, y: int) -> String:
	var weights: Dictionary = Registry.band_weights_at(tables, y)
	if weights.is_empty():
		return "air"
	var noise: FastNoiseLite = _make_noise(tables, mine_seed)
	var roll: float = _roll_at(tables, noise, x, y)
	return _weighted_pick(weights, roll)

## Generates a rectangular region of block ids. Returns a 2D array [row][col].
## Builds the noise field once and reuses it (still a pure fn of the inputs) — used
## by chunk init and the golden test.
static func generate_region(tables: Dictionary, mine_seed: int,
		start_x: int, start_y: int, width: int, height: int) -> Array:
	var noise: FastNoiseLite = _make_noise(tables, mine_seed)
	var region: Array = []
	for row in range(height):
		var world_y: int = start_y + row
		var weights: Dictionary = Registry.band_weights_at(tables, world_y)
		var row_data: Array = []
		for col in range(width):
			var world_x: int = start_x + col
			if weights.is_empty():
				row_data.append("air")
			else:
				row_data.append(_weighted_pick(weights, _roll_at(tables, noise, world_x, world_y)))
		region.append(row_data)
	return region

# ── Relic placement (AC-5.6.1) ────────────────────────────────────────────────

## True iff this cell holds the mine's relic. The relic is the dig's objective: a
## single cell placed as a PURE function of (mine_seed, config) and located at or
## below the configured minimum depth (relics.min_depth_cells). Deterministic so an
## unloaded chunk regenerates the relic in the same place. The relic rides on top of
## whatever block the band generated at that cell (it is an objective overlay, not a
## block type) — breaking that cell awards it (U3/AC-5.6.2).
static func relic_at(tables: Dictionary, mine_seed: int, cell: Vector2i) -> bool:
	var rc: Vector2i = relic_cell(tables, mine_seed)
	if rc.y < 0:
		return false
	return cell == rc

## The absolute cell where this mine's relic sits, or (-1,-1) if generation cannot
## place it (no shaft width / no relic config). Pure fn of (mine_seed, config).
static func relic_cell(tables: Dictionary, mine_seed: int) -> Vector2i:
	var relics: Dictionary = tables.get("relics", {})
	if relics.is_empty():
		return Vector2i(-1, -1)
	var width: int = Registry.mine_width_cells(tables)
	if width <= 0:
		return Vector2i(-1, -1)
	var min_depth: int = int(relics.get("min_depth_cells", 0))
	var span: int = maxi(1, int(relics.get("depth_span_cells", 1)))
	# Two decorrelated hashes off the mine seed: one for the column, one for the row.
	var hx: int = _hash2(mine_seed, 0x9E3779B1)
	var hy: int = _hash2(mine_seed, 0x85EBCA77)
	var col: int = hx % width
	var depth: int = min_depth + (hy % span)
	return Vector2i(col, depth)

# ── Noise → uniform roll ───────────────────────────────────────────────────────

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
