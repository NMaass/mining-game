class_name BlockArt
extends RefCounted
## Pure, headless-testable block-art derivation (AC-5.10.2, AC-5.10.3). Turns the
## data-driven block identity (palette_index in block_types.json, colors in palette.json) into:
##   - color accessors (palette_index → Color) with a WCAG relative-luminance helper, so
##     identity reads by LUMINANCE, not hue alone (AC-5.10.3);
##   - procedurally-generated tile-strip Images (block fills, crack stages), the same
##     "synthesize a placeholder asset in code" approach already used for audio (audio.gd) —
##     and the SOURCED pixel-art tile path that bakes the linked tileset per type column.
##
## The v0.5 arcade pass REMOVED the debug-grid glyph overlay (the +/cross/circle stamped on
## every cell read as a debug grid and fought the pixel-art tileset). Non-color identity is
## now carried by the textured tile PLUS the luminance-contrast guarantee (the data gate's
## MIN_BLOCK_LUMINANCE_DELTA loop), proven in tests/unit/test_block_art.gd without a render.
##
## This is pure logic: it returns Images/Colors/Arrays and never touches a Node, scene, or
## TileMapLayer. mine.gd swaps the generated textures onto the AUTHORED atlas sources (which
## keep their authored physics — verified).
##
## ACs: AC-5.10.2 / AC-5.10.3 (colorblind-safe block identity — distinct hue AND luminance).

# ── Palette / color ───────────────────────────────────────────────────────────

## The raw palette color list (hex strings) from palette.json, or [] if absent/malformed.
static func palette_colors(tables: Dictionary) -> Array:
	var pal: Variant = tables.get("palette")
	if pal is Dictionary and (pal as Dictionary).get("colors") is Array:
		return (pal as Dictionary)["colors"]
	return []

## Resolve a palette index to a Color. Out-of-range / malformed → opaque magenta (a loud
## "unmapped" tell, never silently black).
static func palette_color(tables: Dictionary, index: int) -> Color:
	var colors: Array = palette_colors(tables)
	if index < 0 or index >= colors.size():
		return Color(1, 0, 1, 1)
	var hex: String = str(colors[index])
	if not Color.html_is_valid(hex):
		return Color(1, 0, 1, 1)
	return Color.html(hex)

## The render color for a block id (its palette_index → Color).
static func block_color(tables: Dictionary, block_id: String) -> Color:
	var blk: Dictionary = Registry.block(tables, block_id)
	return palette_color(tables, int(blk.get("palette_index", 0)))

## WCAG relative luminance (0..1) of a color — the perceptual brightness used to prove
## that two block colors differ by more than hue (AC-5.10.3).
static func relative_luminance(c: Color) -> float:
	return 0.2126 * _linearize(c.r) + 0.7152 * _linearize(c.g) + 0.0722 * _linearize(c.b)

static func _linearize(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)

# ── Glyph identity ──────────────────────────────────────────────────────────────

## The block ids that are actually rendered (every non-"air" block), in a stable sorted
## order. This is the SINGLE source of the atlas-column order so the generated block strip
## and mine.gd's atlas mapping always agree.
static func rendered_block_ids(tables: Dictionary) -> Array:
	var ids: Array = Registry.block_ids(tables).duplicate()
	ids.sort()
	ids.erase("air")
	return ids

# ── Per-cell tile variation (v0.5 arcade pass) ──────────────────────────────────
## With the debug-grid glyph overlay gone, the textured tile carries the terrain read. A flat
## repeating stamp reads as a wall of one tile; sampling N variant tiles per type (from the
## unused tileset columns) breaks that monotony while each type still reads as one material.
## The strip lays the variants out contiguously per type; mine.gd maps id → (base_col, width)
## and `variant_for` picks a stable per-cell column so a re-render after descent never flickers.

## The list of variant tile coords (Vector2i) for a block id, from art_sources.terrain.block_tiles.
## Accepts the single-coord form [x, y] (→ one variant) OR a list [[x, y], ...]. Returns [] if
## the block has no sourced tile entry (the non-sourced color path then uses a single column).
static func tile_variants(tables: Dictionary, block_id: String) -> Array:
	var cfg: Dictionary = terrain_source(tables)
	var tiles: Variant = cfg.get("block_tiles")
	if not (tiles is Dictionary) or not (tiles as Dictionary).has(block_id):
		return []
	return _normalize_variants((tiles as Dictionary)[block_id])

## Normalize a block_tiles entry to a list of Vector2i. Accepts [x, y] or [[x, y], ...]; returns
## [] for any malformed shape (mirrors DataValidator._block_tile_variants, which gate-rejects it).
static func _normalize_variants(entry: Variant) -> Array:
	if not (entry is Array):
		return []
	var arr: Array = entry
	if arr.is_empty():
		return []
	if arr.size() == 2 and not (arr[0] is Array) and not (arr[1] is Array):
		return [Vector2i(int(arr[0]), int(arr[1]))]
	var out: Array = []
	for coord in arr:
		if not (coord is Array) or (coord as Array).size() != 2:
			return []
		out.append(Vector2i(int((coord as Array)[0]), int((coord as Array)[1])))
	return out

## The number of tile variants for a block id (>= 1). 1 when the block has no sourced entry or a
## single-coord form, so callers can always treat it as a column count.
static func variant_count(tables: Dictionary, block_id: String) -> int:
	return maxi(1, tile_variants(tables, block_id).size())

## PURE, deterministic per-cell variant index for a block id in [0, vcount). A stable spatial hash
## of the cell coordinate — same cell always picks the same variant (golden-safe; a re-render after
## a descent does NOT flicker), but adjacent cells differ so a dug-out area shows tile variety. No
## RNG, no per-frame state. (Classic 73856093 / 19349663 spatial-hash primes.)
static func variant_for(_block_id: String, cell: Vector2i, vcount: int) -> int:
	if vcount <= 1:
		return 0
	var h: int = (cell.x * 73856093) ^ (cell.y * 19349663)
	return absi(h) % vcount

# ── Procedural tile-strip images (returned as Image for headless pixel tests) ─────

## A horizontal strip Image: per id in `ordered_ids`, one `cell_px`-wide cell PER VARIANT, laid
## out contiguously per type (strip width = sum of variant counts). The non-sourced color path
## emits one bevelled color cell per type (single variant) so identity still reads by color.
static func block_strip_image(tables: Dictionary, ordered_ids: Array, cell_px: int) -> Image:
	if has_sourced_terrain(tables, ordered_ids):
		return sourced_block_strip_image(tables, ordered_ids, cell_px)
	var w: int = maxi(1, ordered_ids.size() * cell_px)
	var img := Image.create(w, cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(ordered_ids.size()):
		_fill_block_cell(img, i * cell_px, cell_px, block_color(tables, str(ordered_ids[i])))
	return img

## Total strip column count = sum of per-type variant counts (the sourced strip width / cell_px).
## mine.gd uses the same per-type widths to map id → base column; the authored atlas must expose
## at least this many tile slots (gate-guarded in test_level_smoke).
static func total_block_columns(tables: Dictionary, ordered_ids: Array) -> int:
	var n: int = 0
	for id in ordered_ids:
		n += variant_count(tables, str(id))
	return n

static func terrain_source(tables: Dictionary) -> Dictionary:
	var sources: Variant = tables.get("art_sources")
	if sources is Dictionary:
		var terrain: Variant = (sources as Dictionary).get("terrain")
		if terrain is Dictionary:
			return terrain
	return {}

static func has_sourced_terrain(tables: Dictionary, ordered_ids: Array = []) -> bool:
	var cfg: Dictionary = terrain_source(tables)
	if cfg.is_empty():
		return false
	var path: String = str(cfg.get("source_path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var tiles: Variant = cfg.get("block_tiles")
	if not (tiles is Dictionary):
		return false
	var ids: Array = ordered_ids if not ordered_ids.is_empty() else rendered_block_ids(tables)
	for id in ids:
		if not (tiles as Dictionary).has(str(id)):
			return false
	return true

static func sourced_block_strip_image(tables: Dictionary, ordered_ids: Array, cell_px: int) -> Image:
	var cfg: Dictionary = terrain_source(tables)
	var path: String = str(cfg.get("source_path", ""))
	var tile_px: int = int(cfg.get("tile_px", 8))
	# The packed tileset has a 1px transparent separator between tiles, so the per-tile
	# PITCH (tile_stride) exceeds the art size (tile_px) and the first tile starts at a
	# margin. Default stride=tile_px / margin=0 keeps a clean grid backward-compatible.
	var stride: int = int(cfg.get("tile_stride", tile_px))
	var margin: int = int(cfg.get("tile_margin", 0))
	var texture := load(path) as Texture2D
	if texture == null:
		return _fallback_magenta_strip(ordered_ids, cell_px)
	var src: Image = texture.get_image()
	if src == null:
		return _fallback_magenta_strip(ordered_ids, cell_px)
	src.convert(Image.FORMAT_RGBA8)

	# Strip width = sum of per-type variant columns (v0.5 tile variation). Each type lays its
	# variant tiles out contiguously; mine.gd maps id → base_col with the same per-type widths.
	var total_cols: int = total_block_columns(tables, ordered_ids)
	var w: int = maxi(1, total_cols * cell_px)
	var img := Image.create(w, cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col: int = 0
	for id in ordered_ids:
		var variants: Array = tile_variants(tables, str(id))
		if variants.is_empty():
			variants = [Vector2i.ZERO]
		for coord in variants:
			var tile: Image = _copy_source_tile(src, coord, tile_px, cell_px, stride, margin)
			img.blit_rect(tile, Rect2i(Vector2i.ZERO, Vector2i(cell_px, cell_px)), Vector2i(col * cell_px, 0))
			col += 1
	return img

static func _copy_source_tile(src: Image, coord: Vector2i, tile_px: int, cell_px: int, stride: int = -1, margin: int = 0) -> Image:
	var pitch: int = stride if stride > 0 else tile_px
	var rect := Rect2i(coord * pitch + Vector2i(margin, margin), Vector2i(tile_px, tile_px))
	if rect.position.x < 0 or rect.position.y < 0 \
			or rect.end.x > src.get_width() or rect.end.y > src.get_height():
		var fallback := Image.create(cell_px, cell_px, false, Image.FORMAT_RGBA8)
		fallback.fill(Color(1, 0, 1, 1))
		return fallback
	var tile := Image.create(tile_px, tile_px, false, Image.FORMAT_RGBA8)
	tile.blit_rect(src, rect, Vector2i.ZERO)
	if tile_px != cell_px:
		tile.resize(cell_px, cell_px, Image.INTERPOLATE_NEAREST)
	return tile

static func _fallback_magenta_strip(ordered_ids: Array, cell_px: int) -> Image:
	var img := Image.create(maxi(1, ordered_ids.size() * cell_px), cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1, 1))
	return img

static func _fill_block_cell(img: Image, ox: int, size: int, base: Color) -> void:
	var lighter := base.lightened(0.18)
	var darker := base.darkened(0.28)
	var frame := base.darkened(0.55)
	for y in range(size):
		for x in range(size):
			var c := base
			# Bevel: top/left lit, bottom/right shadowed (a cheap 3D block read).
			if x < 3 or y < 3:
				c = lighter
			elif x >= size - 3 or y >= size - 3:
				c = darker
			# 1px dark frame so adjacent same-type cells still separate visually.
			if x == 0 or y == 0 or x == size - 1 or y == size - 1:
				c = frame
			img.set_pixel(ox + x, y, c)

## A horizontal strip Image for the visible crack stages (1..stages-1); one cell each.
## v0.5 arcade pass: chunkier, clearly-readable fractures. Each stage draws a thicker, branching
## crack with escalating darkness PLUS a 1px light halo offset along one edge, so the fracture pops
## even on dark tiles (the old faint near-black diagonal vanished on hard_rock). PURE (returns an
## Image), data-driven over `stages`, and MONOTONIC: each later stage keeps the earlier fractures
## and adds more, so crack-pixel count never decreases (the test invariant).
static func crack_strip_image(stages: int, cell_px: int) -> Image:
	var visible: int = maxi(0, stages - 1)
	var w: int = maxi(1, visible * cell_px)
	var img := Image.create(w, cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Thicker pen + a brighter halo so the fracture reads on light AND dark tiles.
	var halo := Color(0.85, 0.85, 0.90, 0.55)
	# Each stage is a list of fracture segments {a:Vector2, b:Vector2} in 0..1 cell space. A stage
	# KEEPS the prior stage's segments (monotonic) and appends new branches; later stages also
	# darken so heavier damage reads darker. Authoring is independent of cell_px (scaled below).
	var stage_segs: Array = []
	var segs: Array = []
	# Stage 1: a primary diagonal fracture + a short branch off it (chunky single crack).
	segs.append([Vector2(0.18, 0.12), Vector2(0.74, 0.88)])
	segs.append([Vector2(0.46, 0.50), Vector2(0.72, 0.40)])
	stage_segs.append(segs.duplicate())
	# Stage 2: keep stage 1, add a crossing fracture + a second branch (a shattered look).
	segs = segs.duplicate()
	segs.append([Vector2(0.82, 0.16), Vector2(0.30, 0.92)])
	segs.append([Vector2(0.30, 0.30), Vector2(0.10, 0.62)])
	stage_segs.append(segs.duplicate())
	for s in range(visible):
		var ox: int = s * cell_px
		# Escalating darkness + alpha across stages (heavier damage = darker, denser crack).
		var t: float = float(s) / float(maxi(1, visible - 1))
		var ink := Color(0.05, 0.04, 0.06, lerpf(0.82, 0.95, t))
		var thickness: int = 2 if cell_px < 32 else 3
		var src: Array = stage_segs[mini(s, stage_segs.size() - 1)]
		for seg in src:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			var ax: int = ox + int(a.x * cell_px)
			var ay: int = int(a.y * cell_px)
			var bx: int = ox + int(b.x * cell_px)
			var by: int = int(b.y * cell_px)
			# Halo first (offset down-right by 1px), then the dark ink on top so it pops on dark tiles.
			_draw_line(img, ax + 1, ay + 1, bx + 1, by + 1, halo, maxi(1, thickness - 1))
			_draw_line(img, ax, ay, bx, by, ink, thickness)
	return img

static func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color, thickness: int = 2) -> void:
	# Bresenham with a square `thickness`x`thickness` pen, clamped to the image bounds.
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var x: int = x0
	var y: int = y0
	var t: int = maxi(1, thickness)
	while true:
		for ox in range(t):
			for oy in range(t):
				var px: int = x + ox
				var py: int = y + oy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					img.set_pixel(px, py, color)
		if x == x1 and y == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

# ── ImageTexture wrappers (what mine.gd swaps onto the authored atlas sources) ────

static func build_block_strip(tables: Dictionary, ordered_ids: Array, cell_px: int) -> ImageTexture:
	return ImageTexture.create_from_image(block_strip_image(tables, ordered_ids, cell_px))

static func build_crack_strip(stages: int, cell_px: int) -> ImageTexture:
	return ImageTexture.create_from_image(crack_strip_image(stages, cell_px))
