extends GdUnitTestSuite
## Block art (non-color identity). Proves the BlockArt helper produces REAL, distinct per-type
## identity without a render: distinct colors and luminance contrast (not hue alone). The v0.5
## arcade pass REMOVED the debug-grid glyph overlay; non-color identity is now carried by the
## textured tile PLUS the luminance-contrast guarantee, which these tests pin headlessly (the
## on-screen look is Verifier-E, sanity-checked by a live screenshot). Preloaded so the class is
## exercised even with a cold class cache.
##
## ACs: AC-5.10.2 / AC-5.10.3 (colorblind-safe block identity — distinct hue AND LUMINANCE,
##      not hue alone, between block types).

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

# ── Rendered id ordering (drives the atlas column order) ───────────────────────

func test_rendered_block_ids_excludes_air_and_is_stable() -> void:
	var ids: Array = Art.rendered_block_ids(_tables)
	assert_array(ids).not_contains(["air"])
	var sorted_copy: Array = ids.duplicate()
	sorted_copy.sort()
	assert_array(ids).is_equal(sorted_copy)  # deterministic column order

# ── Generated strip images (the actual swapped textures) ───────────────────────

func test_block_strip_has_distinct_per_type_base_columns() -> void:
	# The sourced block texture bakes per-type tile columns; the FIRST (base) column of each type
	# must be visually distinct across types (proves the runtime atlas uses the linked pack, not a
	# flat placeholder). v0.5 tile variation: each type now owns a CONTIGUOUS RANGE of columns
	# (one per variant), so the strip is sum-of-variants wide — walk to each type's base column.
	var ids: Array = Art.rendered_block_ids(_tables)
	var px := 64
	assert_bool(Art.has_sourced_terrain(_tables, ids)).is_true()
	var img: Image = Art.block_strip_image(_tables, ids, px)
	var total_cols: int = Art.total_block_columns(_tables, ids)
	assert_int(img.get_width()).is_equal(total_cols * px)
	assert_int(img.get_height()).is_equal(px)
	var base_col: int = 0
	var hashes: Array = []
	for id in ids:
		hashes.append(_column_hash(img, base_col, px))
		base_col += Art.variant_count(_tables, str(id))
	for i in range(hashes.size()):
		for j in range(i + 1, hashes.size()):
			assert_int(int(hashes[i])).override_failure_message(
				"block atlas base columns for '%s' and '%s' are identical" % [str(ids[i]), str(ids[j])]
			).is_not_equal(int(hashes[j]))

func test_block_strip_variants_within_a_type_differ() -> void:
	# v0.5 tile variation: a type with >1 variant must lay out VISUALLY DISTINCT columns inside its
	# range (else "variation" is a no-op flat stamp). At least one multi-variant type must exist in
	# the shipped data, and each of its variant columns must differ from the type's base column.
	var ids: Array = Art.rendered_block_ids(_tables)
	var px := 48
	var img: Image = Art.block_strip_image(_tables, ids, px)
	var base_col: int = 0
	var found_multi := false
	for id in ids:
		var vcount: int = Art.variant_count(_tables, str(id))
		if vcount > 1:
			found_multi = true
			var base_hash: int = _column_hash(img, base_col, px)
			for v in range(1, vcount):
				assert_int(_column_hash(img, base_col + v, px)).override_failure_message(
					"variant %d of '%s' is identical to its base tile (no real variation)" % [v, str(id)]
				).is_not_equal(base_hash)
		base_col += vcount
	assert_bool(found_multi).override_failure_message(
		"no block type has >1 tile variant — tile variation is not configured"
	).is_true()

# ── Per-cell tile variant selection (pure, deterministic) ──────────────────────

func test_variant_for_is_pure_and_in_range() -> void:
	# variant_for is a PURE function of the cell: the SAME cell always picks the SAME variant
	# (a re-render after a descent must NOT flicker), and the result is always in [0, vcount).
	for x in range(0, 40):
		for y in range(0, 40):
			var v: int = Art.variant_for("dirt", Vector2i(x, y), 3)
			assert_int(v).is_between(0, 2)
			# Idempotent: a second call with the same args returns the same variant.
			assert_int(Art.variant_for("dirt", Vector2i(x, y), 3)).is_equal(v)

func test_variant_for_single_variant_is_always_zero() -> void:
	# A block with one variant (or a degenerate vcount) always maps to column 0.
	assert_int(Art.variant_for("rock", Vector2i(5, 9), 1)).is_equal(0)
	assert_int(Art.variant_for("rock", Vector2i(5, 9), 0)).is_equal(0)

func test_variant_for_distributes_across_variants() -> void:
	# Across a block of cells, variant_for must actually USE more than one variant (a constant
	# would defeat the point). Over a 30x30 region with 3 variants, all 3 must appear.
	var seen := {}
	for x in range(0, 30):
		for y in range(0, 30):
			seen[Art.variant_for("dirt", Vector2i(x, y), 3)] = true
	assert_int(seen.size()).override_failure_message(
		"variant_for collapsed to a single variant — no spatial variety"
	).is_equal(3)

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
