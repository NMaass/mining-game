class_name BlockArt
extends RefCounted
## Pure, headless-testable block-art derivation (U23 / AC-5.10.2, AC-5.10.3). Turns the
## data-driven block identity (palette_index + glyph in block_types.json, colors in
## palette.json) into:
##   - color accessors (palette_index → Color) with a WCAG relative-luminance helper, so
##     identity reads by LUMINANCE, not hue alone (AC-5.10.3);
##   - a stable glyph ordering + per-block glyph name, for the shared overlay layer that
##     carries the NON-COLOR shape identity (AC-5.10.2);
##   - procedurally-generated tile-strip Images (block fills, glyph shapes, crack stages),
##     the same "synthesize a placeholder asset in code" approach already used for audio
##     (audio.gd) — no binary art assets, no deps.
##
## This is pure logic: it returns Images/Colors/Arrays and never touches a Node, scene, or
## TileMapLayer. mine.gd swaps the generated textures onto the AUTHORED atlas sources (which
## keep their authored physics — verified) and sets the glyph overlay per cell. Building the
## strips here (not in the controller) keeps the controller a thin view and makes the art
## unit-assertable: distinct colors, luminance contrast, and distinct glyph shapes are all
## proven in tests/unit/test_block_art.gd without a render.
##
## ACs: AC-5.10.2 (distinct shape/glyph per block type), AC-5.10.3 (colorblind-safe palette
##      with luminance — not just hue — contrast between block types).

## The glyph vocabulary the overlay layer can render. A diggable block's `glyph` MUST be one
## of these (the data gate enforces it); "none" means no overlay (air).
const ALLOWED_GLYPHS := ["dots", "cross", "bricks", "circle", "diamond"]
const GLYPH_NONE := "none"

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

## The distinct, stable-ordered glyph names used by diggable blocks (excludes "none").
## This defines the glyph atlas column order.
static func glyph_order(tables: Dictionary) -> Array:
	var seen: Array = []
	for id in rendered_block_ids(tables):
		var g: String = block_glyph(tables, id)
		if g != GLYPH_NONE and not seen.has(g):
			seen.append(g)
	seen.sort()
	return seen

## The glyph name declared for a block id ("none" for air / unmapped).
static func block_glyph(tables: Dictionary, block_id: String) -> String:
	return str(Registry.block(tables, block_id).get("glyph", GLYPH_NONE))

## The glyph atlas column for a block id, or -1 if it has no glyph ("none").
static func glyph_index(tables: Dictionary, block_id: String) -> int:
	var g: String = block_glyph(tables, block_id)
	if g == GLYPH_NONE:
		return -1
	return glyph_order(tables).find(g)

# ── Procedural tile-strip images (returned as Image for headless pixel tests) ─────

## A horizontal strip Image: one `cell_px`-wide cell per id in `ordered_ids`, filled with
## that block's color plus a bevel + dark frame so cells read as discrete blocks.
static func block_strip_image(tables: Dictionary, ordered_ids: Array, cell_px: int) -> Image:
	if has_sourced_terrain(tables, ordered_ids):
		return sourced_block_strip_image(tables, ordered_ids, cell_px)
	var w: int = maxi(1, ordered_ids.size() * cell_px)
	var img := Image.create(w, cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(ordered_ids.size()):
		_fill_block_cell(img, i * cell_px, cell_px, block_color(tables, str(ordered_ids[i])))
	return img

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
	var texture := load(path) as Texture2D
	if texture == null:
		return _fallback_magenta_strip(ordered_ids, cell_px)
	var src: Image = texture.get_image()
	if src == null:
		return _fallback_magenta_strip(ordered_ids, cell_px)
	src.convert(Image.FORMAT_RGBA8)

	var w: int = maxi(1, ordered_ids.size() * cell_px)
	var img := Image.create(w, cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tiles: Dictionary = cfg.get("block_tiles", {})
	for i in range(ordered_ids.size()):
		var coord_arr: Array = tiles.get(str(ordered_ids[i]), [0, 0])
		var coord := Vector2i(int(coord_arr[0]), int(coord_arr[1]))
		var tile: Image = _copy_source_tile(src, coord, tile_px, cell_px)
		img.blit_rect(tile, Rect2i(Vector2i.ZERO, Vector2i(cell_px, cell_px)), Vector2i(i * cell_px, 0))
	return img

static func _copy_source_tile(src: Image, coord: Vector2i, tile_px: int, cell_px: int) -> Image:
	var rect := Rect2i(coord * tile_px, Vector2i(tile_px, tile_px))
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

## A horizontal strip Image of the glyph shapes in `glyph_order` order; one cell per glyph.
## Each glyph is a dark ink shape with a light 1px halo, so it reads on any block color.
static func glyph_strip_image(tables: Dictionary, cell_px: int) -> Image:
	var order: Array = glyph_order(tables)
	var w: int = maxi(1, order.size() * cell_px)
	var img := Image.create(w, cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in range(order.size()):
		_draw_glyph(img, i * cell_px, cell_px, str(order[i]))
	return img

## Render a single glyph into the cell at column origin `ox` (ink + halo composite).
static func _draw_glyph(img: Image, ox: int, size: int, glyph: String) -> void:
	var mask := _glyph_mask(glyph, size)
	var ink := Color(0.06, 0.06, 0.09, 0.94)
	var halo := Color(0.96, 0.96, 0.96, 0.88)
	for y in range(size):
		for x in range(size):
			if mask[y * size + x] == 1:
				img.set_pixel(ox + x, y, ink)
			elif _has_ink_neighbor(mask, x, y, size):
				img.set_pixel(ox + x, y, halo)

static func _has_ink_neighbor(mask: PackedByteArray, x: int, y: int, size: int) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + d.x
		var ny: int = y + d.y
		if nx >= 0 and nx < size and ny >= 0 and ny < size and mask[ny * size + nx] == 1:
			return true
	return false

## Boolean ink mask (size*size, row-major) for a glyph shape. Distinct per glyph so the
## shapes are provably different (test_block_art asserts pairwise mask difference).
static func _glyph_mask(glyph: String, size: int) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(size * size)
	var s := float(size)
	var c := s * 0.5
	for y in range(size):
		for x in range(size):
			var fx := float(x)
			var fy := float(y)
			var on := false
			match glyph:
				"dots":
					for cx in [0.30, 0.70]:
						for cy in [0.30, 0.70]:
							if Vector2(fx, fy).distance_to(Vector2(cx * s, cy * s)) <= s * 0.11:
								on = true
				"cross":
					var v := absf(fx - c) <= s * 0.09 and fy >= s * 0.18 and fy <= s * 0.82
					var h := absf(fy - c) <= s * 0.09 and fx >= s * 0.18 and fx <= s * 0.82
					on = v or h
				"bricks":
					# Horizontal mortar at 1/3, 2/3 + offset vertical mortar per band.
					var mortar := absf(fy - s * 0.34) <= s * 0.05 or absf(fy - s * 0.66) <= s * 0.05
					var vtop := fy < s * 0.34 and absf(fx - s * 0.5) <= s * 0.05
					var vmid := fy >= s * 0.34 and fy < s * 0.66 and (absf(fx - s * 0.25) <= s * 0.05 or absf(fx - s * 0.75) <= s * 0.05)
					var vbot := fy >= s * 0.66 and absf(fx - s * 0.5) <= s * 0.05
					on = mortar or vtop or vmid or vbot
				"circle":
					var d := Vector2(fx, fy).distance_to(Vector2(c, c))
					on = absf(d - s * 0.30) <= s * 0.07
				"diamond":
					var dd := absf(fx - c) + absf(fy - c)
					on = absf(dd - s * 0.34) <= s * 0.06
				_:
					on = false
			if on:
				m[y * size + x] = 1
	return m

## A horizontal strip Image for the visible crack stages (1..stages-1); one cell each.
## Cracks are semi-transparent dark fractures; higher stages add more fractures.
static func crack_strip_image(stages: int, cell_px: int) -> Image:
	var visible: int = maxi(0, stages - 1)
	var w: int = maxi(1, visible * cell_px)
	var img := Image.create(w, cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var crack := Color(0.04, 0.04, 0.05, 0.80)
	for s in range(visible):
		var ox: int = s * cell_px
		# Stage 1: one diagonal fracture; each later stage adds another crossing one.
		_draw_line(img, ox + int(cell_px * 0.2), int(cell_px * 0.15), ox + int(cell_px * 0.7), int(cell_px * 0.85), crack)
		if s >= 1:
			_draw_line(img, ox + int(cell_px * 0.8), int(cell_px * 0.2), ox + int(cell_px * 0.35), int(cell_px * 0.9), crack)
			_draw_line(img, ox + int(cell_px * 0.45), int(cell_px * 0.45), ox + int(cell_px * 0.85), int(cell_px * 0.6), crack)
	return img

static func _draw_line(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	# Bresenham, 2px thick, clamped to the image bounds.
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var x: int = x0
	var y: int = y0
	while true:
		for ox in [0, 1]:
			for oy in [0, 1]:
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

static func build_glyph_strip(tables: Dictionary, cell_px: int) -> ImageTexture:
	return ImageTexture.create_from_image(glyph_strip_image(tables, cell_px))

static func build_crack_strip(stages: int, cell_px: int) -> ImageTexture:
	return ImageTexture.create_from_image(crack_strip_image(stages, cell_px))
