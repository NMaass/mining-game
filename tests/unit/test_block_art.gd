extends GdUnitTestSuite
## U23 — Block art (non-color identity). Proves the BlockArt helper produces REAL, distinct
## per-type identity without a render: distinct colors, luminance contrast (not hue alone),
## and distinct glyph SHAPES on the overlay. These are the headless-provable halves of
## AC-5.10.2 / AC-5.10.3 (the on-screen look is Verifier-E, sanity-checked by a live screenshot).
## Preloaded so the class is exercised even with a cold class cache.
##
## ACs: AC-5.10.2 (distinct shape/glyph per block type), AC-5.10.3 (colorblind-safe palette
##      with LUMINANCE — not just hue — contrast between block types).

const Art := preload("res://scripts/core/block_art.gd")

var _tables: Dictionary

func before() -> void:
	GameData.load_all()
	_tables = GameData.tables

# ── Palette / color (AC-5.10.3) ────────────────────────────────────────────────

func test_palette_resolves_and_flags_out_of_range() -> void:
	# Palette present; index resolves to a Color; out-of-range is a LOUD magenta sentinel,
	# never silent black (so an unmapped index is obvious in-game and in tests).
	assert_array(Art.palette_colors(_tables)).is_not_empty()
	var c0: Color = Art.palette_color(_tables, 0)
	assert_bool(c0 is Color).is_true()
	assert_object(Art.palette_color(_tables, 99999)).is_equal(Color(1, 0, 1, 1))
	assert_object(Art.palette_color(_tables, -1)).is_equal(Color(1, 0, 1, 1))

func test_block_colors_distinct_across_types() -> void:
	# AC-5.10.3: each rendered block type maps to a distinct color (no two share a swatch).
	var ids: Array = Art.rendered_block_ids(_tables)
	var seen: Array = []
	for id in ids:
		var c: Color = Art.block_color(_tables, str(id))
		for prev in seen:
			assert_bool(c.is_equal_approx(prev)).override_failure_message(
				"block '%s' shares a color with another type" % str(id)
			).is_false()
		seen.append(c)

func test_block_colors_have_luminance_contrast() -> void:
	# AC-5.10.3 (the real proof): every PAIR of rendered block colors differs in WCAG relative
	# luminance — identity reads by brightness, not hue alone (the colorblind-safety guarantee).
	var ids: Array = Art.rendered_block_ids(_tables)
	var lums: Array = []
	for id in ids:
		lums.append(Art.relative_luminance(Art.block_color(_tables, str(id))))
	for i in range(lums.size()):
		for j in range(i + 1, lums.size()):
			assert_float(absf(float(lums[i]) - float(lums[j]))).override_failure_message(
				"blocks '%s' and '%s' differ in luminance by < 0.06" % [str(ids[i]), str(ids[j])]
			).is_greater(0.06)

func test_relative_luminance_orders_black_below_white() -> void:
	# Sanity: the luminance helper is monotone (black < gray < white).
	assert_float(Art.relative_luminance(Color.BLACK)).is_less(Art.relative_luminance(Color(0.5, 0.5, 0.5)))
	assert_float(Art.relative_luminance(Color(0.5, 0.5, 0.5))).is_less(Art.relative_luminance(Color.WHITE))

# ── Glyph identity (AC-5.10.2) ─────────────────────────────────────────────────

func test_rendered_block_ids_excludes_air_and_is_stable() -> void:
	var ids: Array = Art.rendered_block_ids(_tables)
	assert_array(ids).not_contains(["air"])
	var sorted_copy: Array = ids.duplicate()
	sorted_copy.sort()
	assert_array(ids).is_equal(sorted_copy)  # deterministic column order

func test_each_block_maps_to_its_declared_glyph() -> void:
	# AC-5.10.2: every rendered (diggable) block has a glyph that indexes into the overlay atlas.
	var order: Array = Art.glyph_order(_tables)
	for id in Art.rendered_block_ids(_tables):
		var g: String = Art.block_glyph(_tables, str(id))
		assert_str(g).is_not_equal(Art.GLYPH_NONE)
		var gi: int = Art.glyph_index(_tables, str(id))
		assert_int(gi).is_between(0, order.size() - 1)
		assert_str(str(order[gi])).is_equal(g)  # the index round-trips to the declared glyph

func test_distinct_block_types_use_distinct_glyphs() -> void:
	# AC-5.10.2: no two rendered block types share a glyph (shape uniquely identifies a type).
	var seen: Array = []
	for id in Art.rendered_block_ids(_tables):
		var g: String = Art.block_glyph(_tables, str(id))
		assert_array(seen).not_contains([g])
		seen.append(g)

func test_air_has_no_glyph_index() -> void:
	assert_int(Art.glyph_index(_tables, "air")).is_equal(-1)

# ── Generated strip images (the actual swapped textures) ───────────────────────

func test_block_strip_has_distinct_per_column_colors() -> void:
	# The sourced block texture bakes one sampled tile per type column; each column must be
	# visually distinct (proves the runtime atlas uses the linked pack, not a flat placeholder).
	var ids: Array = Art.rendered_block_ids(_tables)
	var px := 64
	assert_bool(Art.has_sourced_terrain(_tables, ids)).is_true()
	var img: Image = Art.block_strip_image(_tables, ids, px)
	assert_int(img.get_width()).is_equal(ids.size() * px)
	assert_int(img.get_height()).is_equal(px)
	var hashes: Array = []
	for i in range(ids.size()):
		hashes.append(_column_hash(img, i, px))
	for i in range(hashes.size()):
		for j in range(i + 1, hashes.size()):
			assert_int(int(hashes[i])).override_failure_message(
				"block atlas columns for '%s' and '%s' are identical" % [str(ids[i]), str(ids[j])]
			).is_not_equal(int(hashes[j]))

func _column_hash(img: Image, col: int, px: int) -> int:
	var h: int = 17
	for y in range(px):
		for x in range(px):
			var c: Color = img.get_pixel(col * px + x, y)
			var r: int = int(round(c.r * 255.0))
			var g: int = int(round(c.g * 255.0))
			var b: int = int(round(c.b * 255.0))
			var a: int = int(round(c.a * 255.0))
			h = int((h * 31 + r * 3 + g * 5 + b * 7 + a) & 0x7FFFFFFF)
	return h

func test_glyph_strip_shapes_are_distinct_and_two_tone() -> void:
	# AC-5.10.2: each glyph cell has ink pixels, the shapes DIFFER pixel-for-pixel between
	# glyphs (not the same stamp), and every glyph carries BOTH dark ink AND a light halo so
	# it reads on any block background.
	var px := 64
	var img: Image = Art.glyph_strip_image(_tables, px)
	var order: Array = Art.glyph_order(_tables)
	assert_int(img.get_width()).is_equal(order.size() * px)
	var masks: Array = []
	for i in range(order.size()):
		var mask := PackedByteArray()
		var has_ink := false
		var has_halo := false
		var opaque := 0
		for y in range(px):
			for x in range(px):
				var c: Color = img.get_pixel(i * px + x, y)
				var on: int = 1 if c.a > 0.5 else 0
				mask.append(on)
				if on == 1:
					opaque += 1
					if c.r < 0.2 and c.g < 0.2:
						has_ink = true
					if c.r > 0.8 and c.g > 0.8:
						has_halo = true
		assert_int(opaque).override_failure_message("glyph '%s' drew no pixels" % str(order[i])).is_greater(0)
		assert_bool(has_ink).override_failure_message("glyph '%s' has no dark ink" % str(order[i])).is_true()
		assert_bool(has_halo).override_failure_message("glyph '%s' has no light halo" % str(order[i])).is_true()
		masks.append(mask)
	# Pairwise: the shapes must actually differ (a real shape vocabulary, not one repeated mark).
	for i in range(masks.size()):
		for j in range(i + 1, masks.size()):
			assert_bool((masks[i] as PackedByteArray) == (masks[j] as PackedByteArray)).override_failure_message(
				"glyphs '%s' and '%s' rasterize identically" % [str(order[i]), str(order[j])]
			).is_false()

func test_crack_strip_stages_increase_fractures() -> void:
	# Visible crack stages (1..stages-1); each stage cell has crack pixels and the later stage
	# has at least as many (more fractures = more damage read).
	var px := 64
	var stages: int = Registry.crack_stages(_tables)
	var img: Image = Art.crack_strip_image(stages, px)
	assert_int(img.get_width()).is_equal((stages - 1) * px)
	var counts: Array = []
	for s in range(stages - 1):
		var n := 0
		for y in range(px):
			for x in range(px):
				if img.get_pixel(s * px + x, y).a > 0.4:
					n += 1
		assert_int(n).override_failure_message("crack stage %d drew nothing" % (s + 1)).is_greater(0)
		counts.append(n)
	for s in range(1, counts.size()):
		assert_int(counts[s]).is_greater_equal(counts[s - 1])
