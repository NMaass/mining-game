extends GdUnitTestSuite
## U10 — Level assembly smoke test (v0.4). ACTUALLY instantiates the authored
## mine.tscn and drives it via direct API calls (input events do not fire headless),
## verifying the whole slice wires together end to end:
##   boot → free charge present → throw → fuzzy blast → block cleared + ore credited →
##   platform descends after enough clears → relic break ends the dig + banks prestige →
##   bought upgrade makes the next dig measurably stronger → no orphan nodes on free.
##
## This replaces the v0.3 smoke test that only exercised the systems in isolation. The
## v0.3 tray-exhaustion run-end tests are DELETED by design (the tray can never empty —
## the free unlimited charge is permanent; dig-end is relic-driven, AC-5.3.5 REMOVED).
##
## ACs: AC-5.8.1, AC-5.8.2, AC-5.8.4, AC-5.9.1, plus end-to-end of U1–U9.

const MINE_SCENE := preload("res://scenes/mine.tscn")
const Art := preload("res://scripts/core/block_art.gd")

var _tables: Dictionary

func before() -> void:
	# The controller reads GameData.tables; make sure the autoload has loaded /data.
	GameData.load_all()
	_tables = GameData.tables

func before_test() -> void:
	# mine.gd now auto-loads persisted prestige on boot. Clear the default save before each test so
	# every boot starts from a clean slate (no cross-test/cross-run prestige bleed).
	SaveManager.new().clear()

func after_test() -> void:
	# Defensive: the Settings-overlay tests pause the SceneTree (shared across the suite); never
	# leave it paused for the next test.
	if get_tree() != null:
		get_tree().paused = false
	# Defensive: the v0.5 hit-stop briefly sets the GLOBAL Engine.time_scale; a fire-and-forget
	# freeze from a prior test that wasn't awaited could bleed slow-mo into the next test. Reset it.
	Engine.time_scale = 1.0

func after() -> void:
	if get_tree() != null:
		get_tree().paused = false
	SaveManager.new().clear()  # don't leave a save file behind after the suite

# ── Helpers ───────────────────────────────────────────────────────────────────

## Instantiate + add mine.tscn to the test scene tree (auto-freed at test end) and
## let _ready/boot run.
func _boot_mine() -> Mine:
	var mine: Mine = MINE_SCENE.instantiate()
	add_child(mine)          # runs _ready → boot()
	auto_free(mine)
	return mine

## Find the lowest-HP solid cell across the loaded chunks (a floor the free charge can
## break in one hit — AC-5.4.6). Returns (-1,-1) if none.
func _softest_solid_cell(grid: BlockGrid) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_hp: int = 1 << 30
	var width: int = Registry.mine_width_cells(_tables)
	var height: int = Registry.chunk_height(_tables)
	for cy in grid.loaded_chunks():
		var base_y: int = cy * height
		for ly in range(height):
			for x in range(width):
				var y: int = base_y + ly
				if grid.is_solid(x, y):
					var hp: int = grid.get_hp(x, y)
					if hp > 0 and hp < best_hp:
						best_hp = hp
						best = Vector2i(x, y)
	return best

## Amount of the most-recently-spawned explosion's spark layer, or -1 if none. The explosion is
## now a LAYERED Node2D (ExplosionFx) with the GPUParticles2D spark as a CHILD, so the search is
## RECURSIVE (v0.5 arcade pass re-root; the non-recursive find_children would miss it).
func _latest_explosion_amount(mine: Mine) -> int:
	var found: Array = mine.find_children("*", "GPUParticles2D", true, false)
	if found.is_empty():
		return -1
	return (found[found.size() - 1] as GPUParticles2D).amount

# ── Boot + free charge present (AC-5.8.1, AC-5.3.8) ────────────────────────────

func test_boot_instantiates_with_free_charge() -> void:
	# AC-5.8.1: mine.tscn boots; AC-5.3.8/5.12.1: the free unlimited charge is present.
	var mine := _boot_mine()
	assert_object(mine.grid).is_not_null()
	assert_object(mine.economy).is_not_null()
	assert_object(mine.run_state).is_not_null()
	var free_id: String = Registry.free_charge_id(_tables)
	assert_str(free_id).is_not_empty()
	assert_array(mine.run_state.tray).contains([free_id])
	# AC-5.8.1: free charge is the first tray slot.
	assert_str(mine.run_state.tray[0] as String).is_equal(free_id)
	# Money starts at the data-defined starting money.
	assert_int(mine.economy.money).is_equal(Registry.starting_money(_tables))

func test_authored_scene_nodes_present() -> void:
	# The controller is a VIEW over an AUTHORED scene: the key nodes must exist in
	# mine.tscn (not be built imperatively). Assert the structural wiring is real.
	var mine := _boot_mine()
	assert_int(mine.mine_width_cells).is_equal(Registry.mine_width_cells(_tables))
	assert_object(mine.get_node_or_null("BlockGrid/BlockLayer")).is_not_null()
	assert_object(mine.get_node_or_null("BlockGrid/CrackLayer")).is_not_null()
	assert_object(mine.get_node_or_null("ShaftGuide")).is_not_null()
	assert_object(mine.get_node_or_null("LightMaskLayer/LightMask")).is_not_null()
	assert_object(mine.get_node_or_null("Platform")).is_not_null()
	assert_object(mine.get_node_or_null("AimPreview")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/Bottom/TrayScroll/Tray")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/Bottom/ThrowButton")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/DigEndPanel")).is_not_null()
	# AC-5.6.2: the prestige-offer overlay is authored with accept/decline buttons.
	assert_object(mine.get_node_or_null("PrestigeOffer")).is_not_null()
	assert_object(mine.get_node_or_null("PrestigeOffer/Panel/Box/AcceptButton")).is_not_null()
	assert_object(mine.get_node_or_null("PrestigeOffer/Panel/Box/DeclineButton")).is_not_null()
	# AC-5.8.1: the authored HUD has money + depth (top-left), a nav button (top-right), a
	# compact relic indicator, and the depth odds readout — assert each node is present.
	assert_object(mine.get_node_or_null("Hud/Top/MoneyBox/Money")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/Top/DepthBox/Depth")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/Top/RelicBox/Relic")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/Top/Odds")).is_not_null()
	assert_object(mine.get_node_or_null("Hud/TopRight/NavButton")).is_not_null()
	# AC-5.8.4: the dig-end panel is an EXPLAINED state — title + banked + power readouts + the
	# two actions (buy upgrade / next dig) are authored, not just a bare panel.
	for child in ["Title", "Banked", "Power", "BuyUpgrade", "NextDig"]:
		assert_object(mine.get_node_or_null("Hud/DigEndPanel/Box/" + child)).is_not_null()
	# AC-5.9.1 (strengthened, v0.5 arcade pass): the explosion is a LAYERED Node2D (ExplosionFx)
	# composing a GPUParticles2D spark spray + an additive Flash + Ring. It carries NO collision
	# (particles never collide). The WEB COLOR contract is the load-bearing assertion: the spark's
	# process_material is a ParticleProcessMaterial with a NON-NULL color_ramp (the engine writes
	# COLOR from the ramp → visible on WebGL2), and the flash uses an ADDITIVE CanvasItemMaterial
	# (BLEND_MODE_ADD also writes COLOR) — NEVER a bare custom process shader (invisible on web).
	var fx: Node = (preload("res://scenes/explosion.tscn") as PackedScene).instantiate()
	assert_bool(fx is GPUParticles2D).is_false()  # re-rooted: the root is a Node2D, not the particles
	assert_bool(fx is CollisionObject2D).is_false()
	assert_int(fx.find_children("*", "CollisionShape2D").size()).is_equal(0)
	# The spark layer is a GPUParticles2D child with a ParticleProcessMaterial color_ramp.
	var sparks: Array = fx.find_children("*", "GPUParticles2D", true, false)
	assert_int(sparks.size()).override_failure_message(
		"explosion has no GPUParticles2D spark child after the re-root"
	).is_greater(0)
	var spark := sparks[0] as GPUParticles2D
	var pm := spark.process_material as ParticleProcessMaterial
	assert_object(pm).override_failure_message(
		"spark process_material is not a ParticleProcessMaterial — web COLOR source broken (AC-5.9.1)"
	).is_not_null()
	assert_object(pm.color_ramp).override_failure_message(
		"spark color_ramp is null — GPUParticles2D would render invisible on WebGL2 (AC-5.9.1)"
	).is_not_null()
	# The flash is an additive Sprite2D (web-safe COLOR via BLEND_MODE_ADD), not a process shader.
	var flash := fx.find_child("Flash", true, false) as CanvasItem
	assert_object(flash).is_not_null()
	var fm := flash.material as CanvasItemMaterial
	assert_object(fm).override_failure_message(
		"flash has no CanvasItemMaterial — must be additive, not a custom process shader (AC-5.9.1)"
	).is_not_null()
	assert_int(fm.blend_mode).override_failure_message(
		"flash CanvasItemMaterial is not BLEND_MODE_ADD — additive flash is the web COLOR guarantee (AC-5.9.1)"
	).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)
	fx.free()

func test_launch_fx_write_color_for_web() -> void:
	# AC-5.9.1 (launch & control feel cluster): the NEW launch particle layers — the muzzle flash and
	# the in-flight charge comet trail — MUST write COLOR or they render BLANK on the shipped GL
	# Compatibility / WebGL2 build. The muzzle flash is a GPUParticles2D whose color comes from a
	# ParticleProcessMaterial color_ramp (engine writes COLOR) + an additive Flash sprite; the trail is
	# a CPUParticles2D whose color comes from its own color_ramp/.color (web-safe) on an additive
	# material — NEVER a bare custom process shader. Assert the web COLOR source on both.
	var flash_fx: GPUParticles2D = (preload("res://scenes/muzzle_flash.tscn") as PackedScene).instantiate()
	var fpm := flash_fx.process_material as ParticleProcessMaterial
	assert_object(fpm).override_failure_message(
		"muzzle flash process_material is not a ParticleProcessMaterial — web COLOR source broken (AC-5.9.1)"
	).is_not_null()
	assert_object(fpm.color_ramp).override_failure_message(
		"muzzle flash color_ramp is null — GPUParticles2D would render invisible on WebGL2 (AC-5.9.1)"
	).is_not_null()
	# Particles never collide.
	assert_int(flash_fx.find_children("*", "CollisionShape2D").size()).is_equal(0)
	var mflash := flash_fx.find_child("Flash", true, false) as CanvasItem
	assert_object(mflash).is_not_null()
	assert_int((mflash.material as CanvasItemMaterial).blend_mode).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)
	flash_fx.free()
	# Charge trail: CPUParticles2D with a non-null color_ramp (its web-safe COLOR source) + additive.
	var trail: CPUParticles2D = (preload("res://scenes/charge_trail.tscn") as PackedScene).instantiate()
	assert_object(trail.color_ramp).override_failure_message(
		"charge trail color_ramp is null — the comet streak would be a flat/invisible smear on web (AC-5.9.1)"
	).is_not_null()
	assert_int((trail.material as CanvasItemMaterial).blend_mode).is_equal(CanvasItemMaterial.BLEND_MODE_ADD)
	trail.free()

func test_hud_shows_money_and_depth_text() -> void:
	# AC-5.8.1: after boot the HUD labels render the live readouts (money as "$N", depth, relic).
	# This proves the controller actually pushes values into the authored labels (set_money etc.),
	# not just that the nodes exist.
	var mine := _boot_mine()
	var money := mine.get_node("Hud/Top/MoneyBox/Money") as Label
	var depth := mine.get_node("Hud/Top/DepthBox/Depth") as Label
	var relic := mine.get_node("Hud/Top/RelicBox/Relic") as Label
	var odds := mine.get_node("Hud/Top/Odds") as Label
	assert_str(money.text).contains("$")
	assert_str(depth.text).contains("Depth")
	assert_str(relic.text).contains("Relic")

func test_hud_shows_depth_resource_odds() -> void:
	# AC-5.8.8: the HUD displays the current depth band's resource probabilities.
	var mine := _boot_mine()
	var odds_label: Label = mine.get_node("Hud/Top/Odds")
	# Boot is at depth 0 (surface band), which has copper + gold odds.
	assert_str(odds_label.text).contains("Cu")
	# Descend to the deep band and verify gold odds are shown + copper odds changed.
	mine.hud.set_depth_odds(Registry.band_odds(_tables, 50))
	assert_str(odds_label.text).contains("Cu")
	assert_str(odds_label.text).contains("Au")

func test_hud_depth_odds_update_on_descent() -> void:
	# AC-5.8.8: the odds readout updates when the platform crosses into a deeper band.
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var platform: Platform = mine.platform
	var odds_label: Label = mine.get_node("Hud/Top/Odds")
	var text_before: String = odds_label.text

	# Clear enough cells to descend below the surface band (min depth 40 for deep band).
	var start_x: int = Registry.shaft_left_cell(_tables)
	var threshold: int = Registry.platform_clear_threshold(_tables)
	for y in range(1, 45):
		for x in range(start_x, start_x + threshold):
			var hp: int = grid.get_hp(x, y)
			if hp > 0:
				grid.damage(x, y, hp)

	# Drive descent repeatedly until the platform reaches the deep band or stops moving.
	for i in range(20):
		var row_before: int = platform.target_row
		mine._check_descent()
		mine._refresh_all_ui()
		if platform.target_row == row_before:
			break

	# The platform should have descended into the deep band and the odds text should change.
	assert_int(platform.target_row).is_greater_equal(40)
	assert_str(odds_label.text).is_not_equal(text_before)

# ── Portrait safe-area layout + touch targets (AC-5.8.5) ───────────────────────

func test_hud_lays_controls_inside_device_safe_area() -> void:
	# AC-5.8.5: on a notched phone (top notch + bottom home-indicator), the REAL HUD positions
	# the bottom control bar ABOVE the home-indicator/gesture zone and the top bar BELOW the
	# notch — driven through the same apply_layout path production uses, with synthetic device
	# metrics (DisplayServer reports no insets headless, so we inject a device profile).
	var mine := _boot_mine()
	var hud := mine.get_node("Hud") as Hud
	var logical := Vector2i(720, 1280)
	# iPhone-class portrait profile: 141px top notch, 135px bottom home indicator.
	hud.apply_layout_with(Vector2i(1170, 2532), Rect2i(0, 141, 1170, 2256), logical)

	var insets: Dictionary = hud.last_insets()
	# The notch is actually honored (insets exceed the base edge margin, not just the floor).
	assert_bool(insets["top"] > Registry.ui_edge_margin_px(_tables)).is_true()
	assert_bool(insets["bottom"] > Registry.ui_edge_margin_px(_tables)).is_true()

	var top := mine.get_node("Hud/Top") as Control
	var bottom := mine.get_node("Hud/Bottom") as Control
	var nav := mine.get_node("Hud/TopRight/NavButton") as Control

	# Bottom controls sit ABOVE the home-indicator zone (bottom edge <= safe bottom) and never
	# at the very screen edge — the exact defect the screenshot showed.
	assert_float(bottom.offset_bottom).is_less_equal(float(logical.y) - float(insets["bottom"]) + 0.5)
	assert_bool(bottom.offset_bottom < float(logical.y)).is_true()
	# Top controls sit BELOW the notch.
	assert_float(top.offset_top).is_greater_equal(float(insets["top"]) - 0.5)
	# Nav button stays clear of the right inset.
	assert_float(nav.offset_right).is_less_equal(float(logical.x) - float(insets["right"]) + 0.5)
	# Top and bottom bars do not overlap (no collision of hit areas — AC-5.8.5).
	assert_float(top.offset_bottom).is_less(bottom.offset_top)

func test_hud_reflows_when_viewport_shrinks() -> void:
	# AC-5.8.6: the HUD reflows to the viewport size, not a fixed 1280 — the bottom bar's bottom
	# edge tracks the logical height. A shorter portrait viewport moves the bar up accordingly.
	var mine := _boot_mine()
	var hud := mine.get_node("Hud") as Hud
	var bottom := mine.get_node("Hud/Bottom") as Control
	var window := Vector2i(720, 1280)
	var safe := Rect2i(0, 0, 720, 1280)  # no device inset → base margin only

	hud.apply_layout_with(window, safe, Vector2i(720, 1280))
	var tall_bottom: float = bottom.offset_bottom
	hud.apply_layout_with(window, safe, Vector2i(720, 800))
	var short_bottom: float = bottom.offset_bottom
	# The bar's bottom edge follows the logical height down (it is not pinned to 1280).
	assert_float(short_bottom).is_less(tall_bottom)
	assert_float(short_bottom).is_less_equal(800.0)

func test_interactive_controls_meet_touch_target() -> void:
	# AC-5.8.5: every tappable control meets the data-driven thumb-safe minimum on BOTH axes —
	# nav, throw, pack, and each tray slot. (Was claimed in code comments but never asserted.)
	var mine := _boot_mine()
	var min_touch: float = Registry.ui_min_touch_target_px(_tables)
	assert_float(min_touch).is_greater_equal(44.0)  # the data value is itself sane
	for path in ["Hud/TopRight/NavButton", "Hud/Bottom/ThrowButton", "Hud/Bottom/BuyPackButton"]:
		var b := mine.get_node(path) as Control
		assert_bool(UiLayout.meets_touch_target(b.custom_minimum_size, min_touch)).override_failure_message(
			"%s custom_minimum_size %s below touch target %s" % [path, str(b.custom_minimum_size), str(min_touch)]
		).is_true()
	# The tray rebuilt at boot with the free charge; its slot button meets the target too.
	var tray := mine.get_node("Hud/Bottom/TrayScroll/Tray") as Control
	assert_int(tray.get_child_count()).is_greater(0)
	var slot := tray.get_child(0) as Control
	assert_bool(UiLayout.meets_touch_target(slot.custom_minimum_size, min_touch)).is_true()

func test_tray_scrolls_instead_of_overflowing_bottom_bar() -> void:
	# AC-5.8.5: with more charges than fit, the tray SCROLLS rather than shrinking slots below the
	# touch target or pushing the throw button off-screen. The tray lives in a horizontal
	# ScrollContainer (h-scroll enabled, v-scroll disabled) — the mechanism that bounds its width.
	var mine := _boot_mine()
	var scroll := mine.get_node("Hud/Bottom/TrayScroll") as ScrollContainer
	assert_object(scroll).is_not_null()
	assert_int(scroll.horizontal_scroll_mode).is_not_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	# Fill the tray with more slots than fit; each keeps its full touch-target size (no shrink),
	# and the throw button — a sibling of the scroll, not the tray — is unaffected.
	var tray := mine.get_node("Hud/Bottom/TrayScroll/Tray") as TrayUi
	var many: Array = []
	for i in range(12):
		many.append({"id": "dynamite", "count": i + 1})
	tray.rebuild(many, "dynamite")
	var min_touch: float = Registry.ui_min_touch_target_px(_tables)
	for slot: Control in tray.get_children():
		assert_bool(UiLayout.meets_touch_target(slot.custom_minimum_size, min_touch)).is_true()

# ── Non-color identity (textured tile per type) + terrain physics (AC-5.10.2/3, AC-5.1.6) ──

func test_block_layer_renders_distinct_atlas_columns_per_type() -> void:
	# AC-5.10.2/5.10.3: the v0.5 arcade pass removed the debug-grid glyph overlay; non-color
	# identity now rides the textured BlockLayer tile. With v0.5 tile VARIATION each type owns a
	# CONTIGUOUS RANGE of atlas columns (one per variant tile), so the SAME type may render at
	# several columns inside its range — but distinct types must occupy DISJOINT column ranges.
	# Assert: (a) every rendered coord for a type lies in [base_col, base_col+vcount), with base/
	# vcount derived from the same BlockArt mapping mine.gd uses; (b) the ranges don't overlap.
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var block_layer := mine.get_node("BlockGrid/BlockLayer") as TileMapLayer
	# No glyph overlay layer exists anymore.
	assert_object(mine.get_node_or_null("BlockGrid/GlyphLayer")).is_null()

	# Reconstruct the per-type column ranges (base_col, vcount) exactly as _build_atlas_mapping does.
	var base_for: Dictionary = {}   # block_id -> base column
	var vcount_for: Dictionary = {} # block_id -> variant count
	var col: int = 0
	for id in Art.rendered_block_ids(_tables):
		base_for[id] = col
		vcount_for[id] = Art.variant_count(_tables, str(id))
		col += int(vcount_for[id])

	# Walk the loaded cells: collect the set of columns each type actually renders at.
	var cols_for_type: Dictionary = {}  # block_id -> Array[int] of distinct columns seen
	var width: int = Registry.mine_width_cells(_tables)
	var height: int = Registry.chunk_height(_tables)
	for cy in grid.loaded_chunks():
		var base_y: int = cy * height
		for ly in range(height):
			for x in range(width):
				var y: int = base_y + ly
				if not grid.is_solid(x, y):
					continue
				var bid: String = grid.get_block_id(x, y)
				var cell := Vector2i(x, y)
				if block_layer.get_cell_source_id(cell) < 0:
					continue  # only damaged/erased cells; skip
				var coord: Vector2i = block_layer.get_cell_atlas_coords(cell)
				assert_int(coord.y).override_failure_message(
					"block type '%s' rendered off row 0 of the atlas (%s)" % [bid, str(coord)]
				).is_equal(0)
				# The column must sit inside this type's authored range.
				var base: int = int(base_for.get(bid, -999))
				var vc: int = int(vcount_for.get(bid, 1))
				assert_bool(coord.x >= base and coord.x < base + vc).override_failure_message(
					"block type '%s' rendered at column %d, outside its range [%d,%d)" % [bid, coord.x, base, base + vc]
				).is_true()
				if not cols_for_type.has(bid):
					cols_for_type[bid] = []
				if not (cols_for_type[bid] as Array).has(coord.x):
					(cols_for_type[bid] as Array).append(coord.x)
	assert_int(cols_for_type.size()).override_failure_message(
		"no solid rendered cells found to verify per-type atlas mapping"
	).is_greater(0)
	# Distinct types occupy DISJOINT column ranges (identity reads by the textured tile, no overlay).
	var claimed: Dictionary = {}  # column -> block_id
	for bid in cols_for_type.keys():
		for cx in (cols_for_type[bid] as Array):
			assert_bool(claimed.has(cx)).override_failure_message(
				"column %d shared by block types '%s' and '%s'" % [cx, str(claimed.get(cx, "?")), bid]
			).is_false()
			claimed[cx] = bid

	# The generated/sourced art replaced the placeholder texture (per-type tile is now live).
	var src := block_layer.tile_set.get_source(block_layer.tile_set.get_source_id(0)) as TileSetAtlasSource
	assert_bool(src.texture is ImageTexture).override_failure_message(
		"BlockLayer still using the placeholder texture — generated art not applied"
	).is_true()

func test_authored_atlases_cover_all_rendered_types() -> void:
	# Guard the scene↔data coupling: the authored BlockLayer atlas must have at least as many tiles
	# as there are rendered atlas COLUMNS. With v0.5 tile variation each type owns one column per
	# variant tile, so the total is sum-of-variants (BlockArt.total_block_columns), not the type
	# count. Else a future /data author adding a block type or variant would silently get a missing
	# tile. (The glyph overlay layer was removed in v0.5, so only the BlockLayer guard remains.)
	var mine := _boot_mine()
	var bl := mine.get_node("BlockGrid/BlockLayer") as TileMapLayer
	var bsrc := bl.tile_set.get_source(bl.tile_set.get_source_id(0)) as TileSetAtlasSource
	var needed: int = Art.total_block_columns(_tables, Art.rendered_block_ids(_tables))
	assert_int(bsrc.get_tiles_count()).override_failure_message(
		"BlockLayer atlas has fewer tiles (%d) than rendered atlas columns (%d) — add tiles in block_grid.tscn" % [bsrc.get_tiles_count(), needed]
	).is_greater_equal(needed)

func test_terrain_tiles_carry_physics_collider() -> void:
	# AC-5.1.6: solid terrain provides collision via the TileMap physics layer (a dropped
	# charge bounces off it before detonating). Scene-level assertion: the BlockLayer TileSet
	# has the charge↔terrain physics layer and a tile keeps its collision polygon AFTER the
	# runtime art-texture swap (the swap must not strip authored colliders).
	var mine := _boot_mine()
	var block_layer := mine.get_node("BlockGrid/BlockLayer") as TileMapLayer
	var ts := block_layer.tile_set
	assert_int(ts.get_physics_layers_count()).is_greater_equal(1)
	assert_int(ts.get_physics_layer_collision_layer(0)).is_equal(1)  # terrain occupies layer 1
	assert_int(ts.get_physics_layer_collision_mask(0)).is_equal(2)   # and collides with the charge (layer 2)
	var src := ts.get_source(ts.get_source_id(0)) as TileSetAtlasSource
	var td := src.get_tile_data(Vector2i(0, 0), 0)
	assert_object(td).is_not_null()
	assert_int(td.get_collision_polygons_count(0)).override_failure_message(
		"terrain tile lost its collision polygon after the art-texture swap"
	).is_greater(0)

# ── Select → throw → blast → clear + credit (end-to-end of U2/U4/U5/U8) ─────────

func test_throw_clears_block_and_credits_money() -> void:
	# AC-5.8.2 end-to-end: select the free charge → resolve a blast at a solvable floor
	# → ≥1 block cleared, money increases by the cleared ore value (AC-5.5.1).
	var mine := _boot_mine()
	var free_id: String = Registry.free_charge_id(_tables)
	assert_bool(mine.select_charge(free_id)).is_true()

	var grid: BlockGrid = mine.grid
	var center := _softest_solid_cell(grid)
	assert_int(center.x).is_greater_equal(0)  # a solvable floor exists

	# Expected ore value of the target cell BEFORE the blast (credited iff it clears).
	var target_id: String = grid.get_block_id(center.x, center.y)
	var ore_value: int = Registry.block_ore_value(_tables, target_id)
	var money_before: int = mine.economy.money

	var params := ThrowParams.from_explosive(_tables, free_id)
	var audio_before: int = Audio.play_count
	var result: Dictionary = mine.resolve_blast(center, params)

	# At least one cell cleared (the free charge breaks the softest cell — AC-5.4.6).
	assert_int((result["cleared"] as Array).size()).is_greater(0)
	# AC-5.13.1: the blast actually fired placeholder SFX — proves the mine→Audio wiring is
	# LIVE, not just that the hooks exist (detonate always plays via _spawn_explosion).
	assert_int(Audio.play_count).override_failure_message(
		"resolve_blast triggered no audio cue — mine→Audio wiring dead?"
	).is_greater(audio_before)
	# The center cell itself cleared.
	assert_bool(grid.is_solid(center.x, center.y)).is_false()
	# Money increased by AT LEAST the center cell's ore value (other cleared ore adds more).
	assert_int(mine.economy.money).is_greater_equal(money_before + ore_value)
	# A throw does NOT end the dig (only the relic does — AC-5.6.2).
	assert_bool(mine.run_state.dig_ended).is_false()

func test_throw_spawns_and_resolves_charge() -> void:
	# AC-5.3.3: throw_at spawns a Rapier RigidBody2D charge; it resolves (detonates) and
	# clears the in-flight lock so another throw is possible. on_first_impact-mode free
	# charge detonates on its first terrain contact — drive that directly.
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	var charge: Charge = mine.throw_at(0.0)
	assert_object(charge).is_not_null()
	assert_bool(charge is RigidBody2D).is_true()
	# Launch & control feel (v0.5 arcade pass): the throw attaches a comet trail to the charge.
	assert_object(charge.find_child("ChargeTrail", true, false)).override_failure_message(
		"throw_at must attach the charge_trail (comet streak) to the live charge"
	).is_not_null()
	# CRITICAL gate_risk for this cluster: the charge's flight squash-stretch/spin scales the Sprite2D
	# child ONLY — the circle collider must stay the authored radius (otherwise charge/physics drift).
	# Capture the collider radius + the sprite scale, run the flight-visual step directly (it scales +
	# spins the Sprite2D by velocity), then assert the Sprite2D DID change while the CollisionShape2D
	# circle radius is byte-identical. (Driven directly, not via a physics frame, since the free charge
	# detonates + frees itself on first terrain contact.)
	var shape := charge.get_node("CollisionShape2D") as CollisionShape2D
	var circle := shape.shape as CircleShape2D
	assert_object(circle).is_not_null()
	var radius_before: float = circle.radius
	var sprite := charge.get_node("Sprite2D") as Sprite2D
	var sprite_scale_before: Vector2 = sprite.scale
	charge.linear_velocity = Vector2(0, 500)  # give it speed so the squash-stretch is non-trivial
	charge._update_flight_visual(0.1)          # the cosmetic flight step (scales/spins the Sprite2D)
	assert_vector(sprite.scale).override_failure_message(
		"the flight visual did not squash-stretch the Sprite2D"
	).is_not_equal(sprite_scale_before)
	assert_float((shape.shape as CircleShape2D).radius).override_failure_message(
		"the charge collider radius drifted — squash-stretch must scale the Sprite2D, never the collider"
	).is_equal(radius_before)
	# A second throw is blocked while one is in flight.
	assert_object(mine.throw_at(0.0)).is_null()
	# Simulate the charge hitting terrain → detonation → blast pipeline runs.
	charge.on_impact()
	# After detonation the in-flight lock is released (another throw becomes possible).
	await await_idle_frame()
	assert_object(mine.throw_at(0.0)).is_not_null()

func test_default_straight_down_throw_enters_open_shaft() -> void:
	# AC-5.3.9 (v0.4.2 platform-as-lid guardrail): with the shaft column clear of blocks,
	# a default straight-down throw must spawn below the platform body and fall into the
	# mine, detonating on terrain below the launcher/platform line — never resting on it.
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var shaft_left: int = Registry.shaft_left_cell(_tables)
	var shaft_w: int = Registry.shaft_width(_tables)
	var bps: int = Registry.block_pixel_size(_tables)

	# Carve an open shaft column deep enough for the charge to fall through.
	var clear_depth_cells: int = 8
	for y in range(1, clear_depth_cells + 1):
		for x in range(shaft_left, shaft_left + shaft_w):
			if grid.is_solid(x, y):
				grid.damage(x, y, grid.get_hp(x, y))
	# Re-render so the TileMap colliders reflect the cleared shaft.
	mine._render_all_loaded_chunks()

	mine.select_charge(Registry.free_charge_id(_tables))
	var charge: Charge = mine.throw_at(0.0)
	assert_object(charge).is_not_null()

	var detonation: Dictionary = {"fired": false, "cell": Vector2i.ZERO}
	charge.detonated.connect(func(cell: Vector2i, _params: ThrowParams) -> void:
		detonation["fired"] = true
		detonation["cell"] = cell
	)

	var passed: bool = false
	for i in range(120):  # up to 2 seconds of physics
		await get_tree().physics_frame
		if detonation["fired"]:
			# Detonation must occur below the platform row (row 0), i.e. inside the mine.
			passed = (detonation["cell"].y > 0)
			break
		# Also pass if the live charge has clearly passed the platform line.
		if is_instance_valid(charge) and not charge.has_detonated and charge.position.y > float(bps):
			passed = true
			break

	assert_bool(passed).override_failure_message(
		"AC-5.3.9: default straight-down throw did not enter the mine; it rested on or above the platform line"
	).is_true()

# ── Descent after enough clears (AC-5.7.x end-to-end) ──────────────────────────

func test_platform_descends_after_enough_clears() -> void:
	# AC-5.7.2 end-to-end: clearing the threshold row beneath the platform descends it.
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var platform: Platform = mine.platform
	var start_x: int = Registry.shaft_left_cell(_tables)
	var threshold: int = Registry.platform_clear_threshold(_tables)
	var start_row: int = platform.target_row

	# Clear `threshold` cells in the row directly beneath the platform target.
	var clear_row: int = start_row + 1
	for x in range(start_x, start_x + threshold):
		var hp: int = grid.get_hp(x, clear_row)
		if hp > 0:
			grid.damage(x, clear_row, hp)
	# Drive the controller's descent check via a real blast resolve nearby (or directly).
	mine._check_descent()
	assert_int(platform.target_row).is_greater(start_row)

# ── Relic → dig-end → prestige → stronger next dig (AC-5.6.x, AC-5.8.4) ─────────

func test_relic_break_offers_prestige_and_accept_ends_dig() -> void:
	# AC-5.6.2/5.6.3 end-to-end: breaking the relic cell OFFERS prestige; accepting banks +1
	# point, ends the dig, and shows the distinct dig-end panel (AC-5.8.4).
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var relic := grid.relic_cell
	assert_int(relic.y).is_greater_equal(0)  # the mine has a relic

	# Ensure the relic's chunk is loaded, then break the relic cell (fires the signal).
	grid.ensure_chunk(grid.cell_to_chunk(relic.y))
	var before_prestige: int = mine.run_state.total_prestige
	grid.damage(relic.x, relic.y, 1 << 30)  # overkill → break

	# The offer overlay is shown; the dig has NOT automatically ended.
	assert_bool(mine.run_state.relic_collected).is_true()
	assert_bool(mine.run_state.dig_ended).is_false()
	var offer: PrestigeOffer = mine.get_node_or_null("PrestigeOffer")
	assert_bool(offer.visible).is_true()

	# Accept the offer.
	var accept_btn: Button = offer.get_node("Panel/Box/AcceptButton")
	accept_btn.pressed.emit()

	assert_bool(mine.run_state.dig_ended).is_true()
	assert_int(mine.run_state.total_prestige).is_equal(
		before_prestige + Registry.relic_prestige_value(_tables)
	)
	# AC-5.8.4: the dig-end panel is a distinct, shown state.
	var panel: DigEndPanel = mine.get_node_or_null("Hud/DigEndPanel")
	assert_bool(panel.visible).is_true()

func test_relic_break_can_be_declined_to_keep_digging() -> void:
	# AC-5.6.2: declining the prestige offer resumes the current dig without banking prestige.
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var relic := grid.relic_cell
	grid.ensure_chunk(grid.cell_to_chunk(relic.y))
	var before_prestige: int = mine.run_state.total_prestige
	grid.damage(relic.x, relic.y, 1 << 30)

	var offer: PrestigeOffer = mine.get_node_or_null("PrestigeOffer")
	assert_bool(offer.visible).is_true()
	var decline_btn: Button = offer.get_node("Panel/Box/DeclineButton")
	decline_btn.pressed.emit()

	assert_bool(mine.run_state.dig_ended).is_false()
	assert_int(mine.run_state.total_prestige).is_equal(before_prestige)
	assert_bool(offer.visible).is_false()
	assert_bool(get_tree().paused).is_false()

func _accept_relic_offer(mine: Mine) -> void:
	var offer: PrestigeOffer = mine.get_node_or_null("PrestigeOffer")
	assert_object(offer).is_not_null()
	var accept_btn: Button = offer.get_node("Panel/Box/AcceptButton")
	accept_btn.pressed.emit()


func test_bought_upgrade_makes_next_dig_stronger() -> void:
	# AC-5.6.4 end-to-end: after accepting the relic's prestige offer and buying the upgrade,
	# the SAME charge deals more blast intensity on the next dig (measurable power growth).
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var free_params := ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables))
	var base_intensity: int = free_params.blast_intensity

	# Dig 1: no upgrades → effective intensity == base.
	assert_int(mine.run_state.dig_blast_intensity(base_intensity)).is_equal(base_intensity)

	# Collect the relic (offer → accept → banks prestige), buy the one upgrade, start the next dig.
	var relic := grid.relic_cell
	grid.ensure_chunk(grid.cell_to_chunk(relic.y))
	grid.damage(relic.x, relic.y, 1 << 30)
	_accept_relic_offer(mine)
	assert_bool(mine.buy_first_upgrade()).is_true()
	mine._on_panel_next_dig()  # start next dig from the panel

	# Dig 2: the same charge now deals MORE blast intensity (stronger).
	assert_int(mine.run_state.dig_blast_intensity(base_intensity)).is_greater(base_intensity)
	# New dig reset per-dig state but kept prestige purchases.
	assert_bool(mine.run_state.dig_ended).is_false()

# ── Progress persists across a boot (AC-5.11.1 / 5.11.4, end to end) ───────────

func test_progress_persists_across_boot() -> void:
	# AC-5.11.1/5.11.4: prestige banked in one boot is autosaved at the relic/dig boundary and LOADED
	# by the next boot — the power-growth hook survives an app restart. before_test() cleared the save,
	# so boot 1 starts fresh.
	var mine1 := _boot_mine()
	var grid: BlockGrid = mine1.grid
	var relic := grid.relic_cell
	grid.ensure_chunk(grid.cell_to_chunk(relic.y))
	grid.damage(relic.x, relic.y, 1 << 30)  # relic found → offer shown
	_accept_relic_offer(mine1)  # accept → banks prestige → autosaves
	var banked: int = mine1.run_state.total_prestige
	assert_int(banked).is_greater(0)

	# A FRESH boot must load the persisted prestige from disk (not start at 0).
	var mine2 := _boot_mine()
	assert_int(mine2.run_state.total_prestige).override_failure_message(
		"prestige did not persist across a fresh boot — autosave/load wiring dead?"
	).is_equal(banked)

# ── No orphans after free (AC: clean teardown) ─────────────────────────────────

func test_no_orphans_after_free() -> void:
	# Boot, do a little work, then free; gdUnit4's orphan monitor (suite summary) must
	# report 0 orphans. We additionally free explicitly here and assert validity flips.
	var mine: Mine = MINE_SCENE.instantiate()
	add_child(mine)
	mine.select_charge(Registry.free_charge_id(_tables))
	var center := _softest_solid_cell(mine.grid)
	if center.x >= 0:
		mine.resolve_blast(center, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	mine.queue_free()
	await await_idle_frame()
	assert_bool(is_instance_valid(mine)).is_false()

# ── Nav → modal Settings overlay (AC-5.8.3) + accessibility settings (AC-5.10.1) ──

func test_nav_button_opens_settings_overlay_and_pauses_mine() -> void:
	# AC-5.8.3: the nav button opens a modal overlay; while open the Mine is PAUSED (instanced +
	# frozen), and closing restores play. Drives the REAL HUD nav signal → mine connection (a Button's
	# `pressed` can't fire headless, so we emit the signal the button emits).
	var mine := _boot_mine()
	var ov: SettingsOverlay = mine.overlay
	assert_object(ov).is_not_null()
	assert_bool(ov.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()

	mine.hud.nav_pressed.emit()
	assert_bool(ov.is_open()).override_failure_message(
		"nav button did not open the Settings overlay — nav_pressed wiring dead? (AC-5.8.3)"
	).is_true()
	assert_bool(get_tree().paused).override_failure_message(
		"opening the Settings overlay must pause the Mine (AC-5.8.3)"
	).is_true()

	ov.close()
	assert_bool(ov.is_open()).is_false()
	assert_bool(get_tree().paused).is_false()

func test_overlay_preserves_in_progress_dig_state() -> void:
	# AC-5.8.3: opening + closing the overlay preserves all in-progress dig state (money, terrain HP,
	# tray). The Mine stays instanced — it is never rebuilt.
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	var grid: BlockGrid = mine.grid
	var center := _softest_solid_cell(grid)
	assert_int(center.x).is_greater_equal(0)
	mine.resolve_blast(center, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))

	var money_before: int = mine.economy.money
	var probe := _softest_solid_cell(grid)  # a surviving solid cell
	var hp_before: int = grid.get_hp(probe.x, probe.y) if probe.x >= 0 else -1
	var tray_before: int = mine.run_state.tray.size()

	mine.hud.nav_pressed.emit()  # open
	mine.overlay.close()         # close

	assert_int(mine.economy.money).is_equal(money_before)
	if probe.x >= 0:
		assert_int(grid.get_hp(probe.x, probe.y)).is_equal(hp_before)
	assert_int(mine.run_state.tray.size()).is_equal(tray_before)

func test_sfx_slider_drives_sfx_bus_volume() -> void:
	# AC-5.10.1 + AC-5.13.2: moving the SFX slider routes through to the SFX bus volume (the mine
	# applies the shared SettingsState live).
	var mine := _boot_mine()
	mine.hud.nav_pressed.emit()
	var ov: SettingsOverlay = mine.overlay
	var sfx_idx: int = AudioServer.get_bus_index("SFX")
	assert_int(sfx_idx).is_greater_equal(0)

	ov.sfx_slider().value = 0.0  # mute
	assert_float(mine.settings.sfx_volume).is_equal(0.0)
	assert_float(AudioServer.get_bus_volume_db(sfx_idx)).override_failure_message(
		"SFX slider did not reach the SFX bus volume — settings_changed→Audio wiring dead?"
	).is_equal_approx(mine.settings.sfx_volume_db(), 0.05)

	ov.sfx_slider().value = 1.0  # unity → 0 dB
	assert_float(AudioServer.get_bus_volume_db(sfx_idx)).is_equal_approx(0.0, 0.05)
	ov.close()

func test_music_slider_drives_music_bus_volume() -> void:
	# AC-5.10.1 + AC-5.13.2: the Music slider routes to the Music bus independently of SFX.
	var mine := _boot_mine()
	mine.hud.nav_pressed.emit()
	var music_idx: int = AudioServer.get_bus_index("Music")
	assert_int(music_idx).is_greater_equal(0)
	mine.overlay.music_slider().value = 0.0
	assert_float(AudioServer.get_bus_volume_db(music_idx)).is_equal_approx(
		mine.settings.music_volume_db(), 0.05
	)
	mine.overlay.close()

func test_settings_persist_across_boot() -> void:
	# AC-5.11.1: a changed setting is autosaved (on settings_changed) and restored by the next boot.
	# before_test() cleared the save, so boot 1 starts from the /data defaults.
	var mine1 := _boot_mine()
	mine1.hud.nav_pressed.emit()
	mine1.overlay.sfx_slider().value = 0.15  # change → autosave
	mine1.overlay.close()
	assert_float(mine1.settings.sfx_volume).is_equal_approx(0.15, 0.0001)

	var mine2 := _boot_mine()  # fresh boot reads the save written by boot 1
	assert_float(mine2.settings.sfx_volume).override_failure_message(
		"settings did not persist across a fresh boot — save/load wiring dead?"
	).is_equal_approx(0.15, 0.0001)

# ── Motion intensity (AC-5.10.1 / AC-5.10.4) + text-scale reflow (AC-5.8.6) ──────

func test_motion_intensity_scales_explosion_spray() -> void:
	# AC-5.10.1 / AC-5.10.4: the motion slider scales the cosmetic explosion spray (gameplay
	# unaffected). The pure knob is monotonic with a reduced-motion floor; the live blast honors it.
	assert_int(Mine.explosion_particle_count(28, 1.0)).is_equal(28)
	assert_int(Mine.explosion_particle_count(28, 1.0)).is_greater(Mine.explosion_particle_count(28, 0.0))
	assert_int(Mine.explosion_particle_count(28, 0.0)).is_greater_equal(Mine.EXPLOSION_MIN_PARTICLES)

	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	mine.settings.set_motion_intensity(1.0)
	var c1 := _softest_solid_cell(mine.grid)
	assert_int(c1.x).is_greater_equal(0)
	mine.resolve_blast(c1, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	var amount_high: int = _latest_explosion_amount(mine)

	mine.settings.set_motion_intensity(0.0)
	var c2 := _softest_solid_cell(mine.grid)
	assert_int(c2.x).is_greater_equal(0)
	mine.resolve_blast(c2, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	var amount_low: int = _latest_explosion_amount(mine)
	assert_int(amount_low).override_failure_message(
		"reduced motion did not reduce explosion spray (low=%d vs high=%d)" % [amount_low, amount_high]
	).is_less(amount_high)

# ── Explosion punch + per-cell debris + value popups (v0.5 arcade pass) ─────────

## Find a loaded solid cell of the given block id with positive HP, or (-1,-1).
func _find_cell_of_type(grid: BlockGrid, want_id: String) -> Vector2i:
	var width: int = Registry.mine_width_cells(_tables)
	var height: int = Registry.chunk_height(_tables)
	for cy in grid.loaded_chunks():
		var base_y: int = cy * height
		for ly in range(height):
			for x in range(width):
				var y: int = base_y + ly
				if grid.is_solid(x, y) and grid.get_hp(x, y) > 0 and grid.get_block_id(x, y) == want_id:
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func test_blast_spawns_per_cell_debris_for_non_ore_terrain() -> void:
	# v0.5 arcade pass: EVERY cleared solid cell throws material-colored chunks now, not just ore
	# (the ore-only filter was removed). A dirt/rock break spawns >=1 DebrisParticles emitter,
	# capped at vfx.max_debris_emitters and ttl-freed (0 orphans is gate-enforced at suite end).
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	# Target a non-ore solid cell (dirt is the surface filler) and overkill it so it clears.
	var cell := _find_cell_of_type(mine.grid, "dirt")
	assert_int(cell.x).override_failure_message("no dirt cell loaded to test per-cell debris").is_greater_equal(0)
	# Make sure it clears in one resolve: drop its HP to 1 first (gameplay-neutral for this VFX test).
	mine.grid.set_hp(cell.x, cell.y, 1)
	mine.resolve_blast(cell, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	var debris: Array = mine.find_children("*", "CPUParticles2D", true, false).filter(
		func(n: Node) -> bool: return n.name.begins_with("DebrisParticles")
	)
	assert_int(debris.size()).override_failure_message(
		"a terrain break spawned no debris emitter (per-cell debris broken)"
	).is_greater(0)
	# Cap honored: never more emitters than the data cap.
	assert_int(debris.size()).is_less_equal(Registry.vfx_i(_tables, "max_debris_emitters", 24))

func test_ore_clear_spawns_value_popup_skipped_for_dirt() -> void:
	# v0.5 arcade pass: clearing an ore cell for value spawns ONE "+$N" ValuePopup; a $0 dirt break
	# spawns none. The popup is cosmetic + capped + ttl-freed.
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	# Prefer copper (lower HP, easier to one-hit); fall back to gold.
	var ore_cell := _find_cell_of_type(mine.grid, "ore_copper")
	if ore_cell.x < 0:
		ore_cell = _find_cell_of_type(mine.grid, "ore_gold")
	assert_int(ore_cell.x).override_failure_message("no ore cell loaded to test value popups").is_greater_equal(0)
	# Make the ore cell breakable in one resolve.
	mine.grid.set_hp(ore_cell.x, ore_cell.y, 1)
	var money_before: int = mine.economy.money
	mine.resolve_blast(ore_cell, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	# The ore actually credited (so a popup should fire).
	assert_int(mine.economy.money).is_greater(money_before)
	var popups: Array = mine.find_children("*", "Node2D", true, false).filter(
		func(n: Node) -> bool: return n is ValuePopup
	)
	assert_int(popups.size()).override_failure_message(
		"clearing a credited ore cell spawned no value popup"
	).is_greater(0)
	assert_int(popups.size()).is_less_equal(Registry.vfx_i(_tables, "popup_max_active", 10))

# ── Money juice: rolling counter + flying coins + HUD pop (v0.5 arcade pass) ─────

func test_ore_clear_spawns_flying_coin_that_frees() -> void:
	# v0.5 money juice: clearing a CREDITED ore cell (motion on) spawns >= 1 flying CoinPickup that
	# arcs to the wallet icon, capped at coin_max_active, and FREES itself within its ttl (cosmetic +
	# capped + ttl-freed → 0 orphans is gate-enforced at suite end).
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	mine.settings.set_motion_intensity(1.0)  # coins are gated OFF at motion ~0
	var ore_cell := _find_cell_of_type(mine.grid, "ore_copper")
	if ore_cell.x < 0:
		ore_cell = _find_cell_of_type(mine.grid, "ore_gold")
	assert_int(ore_cell.x).override_failure_message("no ore cell loaded to test flying coins").is_greater_equal(0)
	mine.grid.set_hp(ore_cell.x, ore_cell.y, 1)
	var money_before: int = mine.economy.money
	mine.resolve_blast(ore_cell, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	assert_int(mine.economy.money).is_greater(money_before)
	var coins: Array = mine.find_children("*", "Sprite2D", true, false).filter(
		func(n: Node) -> bool: return n is CoinPickup
	)
	assert_int(coins.size()).override_failure_message(
		"clearing a credited ore cell spawned no flying coin"
	).is_greater(0)
	assert_int(coins.size()).is_less_equal(Registry.coin_max_active(_tables))
	# Wait out the full pop+fly+ttl with a generous margin on a real-time timer; every coin must be
	# freed (no orphans). The coin's own ttl timer is process_always+ignore_time_scale, so it fires
	# independently of pause/time-scale; the extra margin + idle frame flush the deferred queue_free.
	var ttl: float = Registry.coin_pop_seconds(_tables) + Registry.coin_fly_seconds(_tables) + 1.0
	await get_tree().create_timer(ttl, true, false, true).timeout
	await await_idle_frame()  # flush the deferred queue_free issued by the coin's ttl timer
	var still: Array = mine.find_children("*", "Sprite2D", true, false).filter(
		func(n: Node) -> bool: return n is CoinPickup
	)
	assert_int(still.size()).override_failure_message(
		"a flying coin did not free within its ttl (orphan-coin regression)"
	).is_equal(0)

func test_motion_zero_suppresses_flying_coins() -> void:
	# v0.5 money juice: at motion_intensity 0 (reduced motion) the number still credits + snaps but NO
	# coins fly (AC-5.10.4 reduced-motion seam — the same gate the explosion flash/ring honor).
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	mine.settings.set_motion_intensity(0.0)
	var ore_cell := _find_cell_of_type(mine.grid, "ore_copper")
	if ore_cell.x < 0:
		ore_cell = _find_cell_of_type(mine.grid, "ore_gold")
	assert_int(ore_cell.x).is_greater_equal(0)
	mine.grid.set_hp(ore_cell.x, ore_cell.y, 1)
	mine.resolve_blast(ore_cell, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	var coins: Array = mine.find_children("*", "Sprite2D", true, false).filter(
		func(n: Node) -> bool: return n is CoinPickup
	)
	assert_int(coins.size()).override_failure_message(
		"reduced motion (0) must suppress flying coins"
	).is_equal(0)

func test_set_money_stays_snap_exact_during_a_roll() -> void:
	# GATE-CRITICAL (v0.5 money juice): set_money is the deterministic/test-read path and MUST stay
	# snap-exact even while a tick_money_to roll is in flight — the abbreviated-text asserts read
	# money_label.text synchronously right after set_money. Start a roll, then set_money mid-roll and
	# read the label IMMEDIATELY: it is the exact snapped formatting, not an interpolated value.
	var mine := _boot_mine()
	var hud: Hud = mine.hud
	var money_label: Label = hud.get_node("Top/MoneyBox/Money")
	hud.set_money(0)
	hud.tick_money_to(1_000_000, 1.0)  # start an animated roll
	hud.set_money(12345)               # the deterministic path snaps mid-roll
	assert_str(money_label.text).override_failure_message(
		"set_money was not snap-exact during a roll (money-text contract broken)"
	).is_equal("$12.3K")

func test_tick_money_to_snaps_at_zero_motion() -> void:
	# v0.5 money juice: at motion ~0 the count-up is disabled — tick_money_to snaps to the exact final
	# formatting immediately (no await), so reduced-motion players get the canonical instant readout.
	var mine := _boot_mine()
	var hud: Hud = mine.hud
	var money_label: Label = hud.get_node("Top/MoneyBox/Money")
	hud.set_money(0)
	hud.tick_money_to(500, 0.0)
	assert_str(money_label.text).is_equal("$500")

## Soften an N×N block of solid cells around `center` to HP=1 so a single blast clears them.
func _soften_region(mine: Mine, center: Vector2i, half: int) -> void:
	var grid: BlockGrid = mine.grid
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var x: int = center.x + dx
			var y: int = center.y + dy
			if grid.is_solid(x, y) and grid.get_hp(x, y) > 0:
				grid.set_hp(x, y, 1)

## Find a cell whose full radius-1 (3×3 Chebyshev) neighborhood is ALL solid, so a softened
## blast there clears 9 cells (well past the hit-stop threshold). Returns (-1,-1) if none.
func _fully_enclosed_solid_cell(grid: BlockGrid) -> Vector2i:
	var width: int = Registry.mine_width_cells(_tables)
	var height: int = Registry.chunk_height(_tables)
	for cy in grid.loaded_chunks():
		var base_y: int = cy * height
		for ly in range(height):
			for x in range(1, width - 1):
				var y: int = base_y + ly
				var all_solid: bool = true
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if not grid.is_solid(x + dx, y + dy):
							all_solid = false
							break
					if not all_solid:
						break
				if all_solid:
					return Vector2i(x, y)
	return Vector2i(-1, -1)

func test_big_break_hit_stop_restores_time_scale() -> void:
	# v0.5 arcade pass (hit-stop): a BIG break (>= vfx.hitstop_min_cells cleared) briefly freezes
	# the game via Engine.time_scale, then MUST restore it to 1.0. A stranded slow-mo would soft-lock
	# the whole game — assert time_scale is back to 1.0 after awaiting the (real-time) freeze timer.
	# CRITICAL: the freeze timer uses ignore_time_scale=true so it counts REAL seconds.
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	mine.settings.set_motion_intensity(1.0)  # ensure the freeze is NOT motion-gated off
	# A fully-enclosed cell so its softened 3×3 footprint clears 9 cells (> the 6-cell threshold).
	var center := _fully_enclosed_solid_cell(mine.grid)
	assert_int(center.x).override_failure_message(
		"no fully-enclosed solid cell to force a big break"
	).is_greater_equal(0)
	# Soften the radius-1 footprint so the whole 3×3 clears in one resolve (a real "big break").
	_soften_region(mine, center, 1)
	var min_cells: int = Registry.vfx_i(_tables, "hitstop_min_cells", 6)
	var result: Dictionary = mine.resolve_blast(center, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	assert_int((result["cleared"] as Array).size()).override_failure_message(
		"region softening did not produce a big enough break to trigger hit-stop"
	).is_greater_equal(min_cells)
	# The freeze is in flight (fire-and-forget). Engine.time_scale is < 1 right now...
	# Wait out the freeze on a REAL-time timer (ignore_time_scale so it isn't itself slowed).
	var freeze_s: float = Registry.vfx_f(_tables, "hitstop_seconds", 0.05)
	await get_tree().create_timer(freeze_s + 0.1, true, false, true).timeout
	# ...and after it, time_scale is restored to EXACTLY 1.0 (no stranded slow-mo).
	assert_float(Engine.time_scale).override_failure_message(
		"hit-stop left Engine.time_scale stranded at %s (soft-lock regression)" % str(Engine.time_scale)
	).is_equal(1.0)

func test_small_break_does_not_hit_stop() -> void:
	# v0.5 arcade pass: a small break (< vfx.hitstop_min_cells) must NOT freeze — free taps stay
	# snappy. After a 1-cell clear, Engine.time_scale is unchanged (1.0) synchronously.
	var mine := _boot_mine()
	mine.select_charge(Registry.free_charge_id(_tables))
	mine.settings.set_motion_intensity(1.0)
	var center := _softest_solid_cell(mine.grid)
	assert_int(center.x).is_greater_equal(0)
	# A bare softest-cell blast clears few cells; assert it stays under the threshold OR (if a
	# vein clears many) skip — either way time_scale must be 1.0 right after a SMALL clear.
	var result: Dictionary = mine.resolve_blast(center, ThrowParams.from_explosive(_tables, Registry.free_charge_id(_tables)))
	if (result["cleared"] as Array).size() < Registry.vfx_i(_tables, "hitstop_min_cells", 6):
		# A small break never started a freeze → time_scale is the normal 1.0 immediately.
		assert_float(Engine.time_scale).is_equal(1.0)
	else:
		# Rare: the softest cell sat in a soft cluster → it WAS a big break; wait out the freeze.
		await get_tree().create_timer(Registry.vfx_f(_tables, "hitstop_seconds", 0.05) + 0.1, true, false, true).timeout
		assert_float(Engine.time_scale).is_equal(1.0)

func test_hud_money_abbreviates_large_values() -> void:
	# AC-5.8.6: large numbers abbreviate so the readout stays compact.
	var mine := _boot_mine()
	var money_label: Label = mine.hud.get_node("Top/MoneyBox/Money")
	mine.hud.set_money(500)
	assert_str(money_label.text).is_equal("$500")
	mine.hud.set_money(12345)
	assert_str(money_label.text).is_equal("$12.3K")
	mine.hud.set_money(45_000_000)
	assert_str(money_label.text).is_equal("$45.0M")

func test_hud_top_bar_fits_at_max_text_scale() -> void:
	# AC-5.8.6: at the maximum UI text scale with a large (abbreviated) balance, the top readout
	# fits within its allocated slot on the shipped portrait width — it does not overflow into the
	# nav button (no overlap) or past its slot (no clipping).
	var mine := _boot_mine()
	var hud: Hud = mine.hud
	hud.set_text_scale(mine.settings.text_scale_max)
	hud.set_money(99_999_999)
	hud.set_depth(999)
	var logical := Vector2i(720, 1280)
	hud.apply_layout_with(Vector2i(720, 1280), Rect2i(0, 0, 720, 1280), logical)
	await await_idle_frame()

	var money_label: Label = hud.get_node("Top/MoneyBox/Money")
	assert_int(money_label.text.length()).override_failure_message(
		"money '%s' is not abbreviated at max scale (AC-5.8.6)" % money_label.text
	).is_less_equal(8)

	var top: Control = hud.get_node("Top")
	var allocated: float = top.size.x
	var needed: float = top.get_combined_minimum_size().x
	# Non-vacuous: the labels have a real (font-metric-derived) min size at the scaled font.
	assert_float(needed).override_failure_message(
		"top readout min-size measured as 0 — font metrics unavailable, fit check is vacuous"
	).is_greater(0.0)
	assert_float(allocated).is_greater(0.0)
	assert_float(needed).override_failure_message(
		"top readout needs %.0f px but only %.0f px is allocated at %.1fx text scale — overflows the nav reserve (AC-5.8.6)"
		% [needed, allocated, mine.settings.text_scale_max]
	).is_less_equal(allocated)

# ── UI/HUD animation: modal pop-in, relic/prestige flash, tray/depth pops (v0.5) ─
# The delicate contract: the modal pop-in animates TRANSFORM/ALPHA only — is_open()/visible/paused
# stay synchronous at the instant the overlay-state tests read them. The flash is a11y-capped + HARD
# motion-gated. The tray select-pop is non-destructive (no rebuild/flicker).

func test_relic_break_pop_in_keeps_panel_visible_synchronously() -> void:
	# GATE-CRITICAL: the dig-end panel POPS IN (scale/alpha tween) but `visible` must be TRUE the
	# instant the relic-flow completes — the existing AC-5.8.4 assert reads panel.visible with no await.
	# Motion ON so the tween path (not the snap path) runs; visible is still synchronous.
	var mine := _boot_mine()
	mine.settings.set_motion_intensity(1.0)
	var grid: BlockGrid = mine.grid
	var relic := grid.relic_cell
	grid.ensure_chunk(grid.cell_to_chunk(relic.y))
	grid.damage(relic.x, relic.y, 1 << 30)  # relic found → offer shown
	_accept_relic_offer(mine)                # accept → dig-end panel shown (pop-in starts)
	var panel: DigEndPanel = mine.get_node_or_null("Hud/DigEndPanel")
	assert_bool(panel.visible).override_failure_message(
		"dig-end panel.visible was not TRUE synchronously after the pop-in started (animation timing leaked into the boolean)"
	).is_true()
	# The world-dim backdrop is shown alongside the panel.
	var backdrop: ColorRect = mine.get_node_or_null("Hud/DigEndBackdrop")
	assert_object(backdrop).is_not_null()
	assert_bool(backdrop.visible).is_true()

func test_overlay_pop_in_keeps_is_open_synchronous() -> void:
	# GATE-CRITICAL: opening the Settings overlay scales/fades the Dialog in, but is_open()/paused
	# must be synchronous (the overlay-state test reads them with no await). Motion ON → tween path.
	var mine := _boot_mine()
	mine.settings.set_motion_intensity(1.0)
	var ov: SettingsOverlay = mine.overlay
	mine.hud.nav_pressed.emit()
	assert_bool(ov.is_open()).override_failure_message(
		"is_open() was not TRUE synchronously after open() with motion on (pop-in leaked into the boolean)"
	).is_true()
	assert_bool(get_tree().paused).is_true()
	ov.close()
	assert_bool(ov.is_open()).override_failure_message(
		"is_open() was not FALSE synchronously after close() (out-tween leaked into the boolean)"
	).is_false()
	assert_bool(get_tree().paused).is_false()

func test_relic_break_flash_fires_with_motion_and_is_suppressed_at_zero() -> void:
	# v0.5 arcade pass: the relic break warms the screen via the Hud FlashRect (alpha > 0 right after,
	# before it fades). At motion 0 (reduced motion) the flash alpha stays 0 — the AC-5.10.4 guard.
	# Motion ON case:
	var mine := _boot_mine()
	mine.settings.set_motion_intensity(1.0)
	var flash: ColorRect = mine.get_node_or_null("Hud/FlashRect")
	assert_object(flash).override_failure_message("Hud has no authored FlashRect overlay").is_not_null()
	assert_bool(flash.mouse_filter == Control.MOUSE_FILTER_IGNORE).override_failure_message(
		"FlashRect must IGNORE input (a full-screen overlay must never eat taps)"
	).is_true()
	var grid: BlockGrid = mine.grid
	var relic := grid.relic_cell
	grid.ensure_chunk(grid.cell_to_chunk(relic.y))
	grid.damage(relic.x, relic.y, 1 << 30)
	# The flash peaks immediately (then fades over ui_flash_seconds) — read alpha synchronously.
	assert_float(flash.modulate.a).override_failure_message(
		"relic-break flash did not raise FlashRect alpha with motion on"
	).is_greater(0.0)
	# Capped: never exceeds the a11y-bounded peak alpha.
	assert_float(flash.modulate.a).is_less_equal(Registry.ui_flash_alpha(_tables) + 0.001)

	# Motion ZERO case (reduced motion): a fresh boot, flash suppressed entirely.
	var mine0 := _boot_mine()
	mine0.settings.set_motion_intensity(0.0)
	var flash0: ColorRect = mine0.get_node_or_null("Hud/FlashRect")
	var grid0: BlockGrid = mine0.grid
	var relic0 := grid0.relic_cell
	grid0.ensure_chunk(grid0.cell_to_chunk(relic0.y))
	grid0.damage(relic0.x, relic0.y, 1 << 30)
	assert_float(flash0.modulate.a).override_failure_message(
		"reduced motion (0) must suppress the relic-break flash (AC-5.10.4)"
	).is_equal(0.0)

func test_tray_select_pops_in_place_without_rebuilding_the_row() -> void:
	# v0.5 arcade pass: a selection-only change (a tap on another slot) POPS the slot IN PLACE — the
	# row is NOT queue_freed/rebuilt, so the SAME Button instances survive (no flicker). Buy a pack so
	# there are >= 2 slots, then re-select and assert the button identities are unchanged.
	var mine := _boot_mine()
	var tray := mine.get_node("Hud/Bottom/TrayScroll/Tray") as TrayUi
	# Ensure a second slot exists: the basic pack costs exactly the starting money, so a boot can
	# afford one buy. A pack buy is a slot-SET change → a rebuild happens; capture the new buttons.
	assert_bool(mine.buy_pack("basic")).override_failure_message(
		"could not buy a pack to set up a multi-slot tray (starting money/price changed?)"
	).is_true()
	var before: Array = tray.get_children().duplicate()
	assert_int(before.size()).override_failure_message("need >= 2 tray slots for the select-pop test").is_greater_equal(2)
	var free_id: String = Registry.free_charge_id(_tables)
	var other_id: String = ""
	for id: String in tray.slot_ids():
		if id != free_id:
			other_id = id
			break
	assert_str(other_id).is_not_empty()
	# Selection-only change: select the other slot, then back to free. Neither touches the slot SET.
	mine.select_charge(other_id)
	mine.select_charge(free_id)
	var after: Array = tray.get_children()
	assert_int(after.size()).is_equal(before.size())
	# SAME Button instances → the row was NOT rebuilt (a rebuild queue_frees + re-news every child).
	for i in range(before.size()):
		assert_bool(after[i] == before[i]).override_failure_message(
			"tray row was REBUILT on a selection-only change (slot %d instance changed) — flicker regression" % i
		).is_true()
	# And the cue moved: the now-selected free slot reads as selected (thicker border than an unselected one).
	var free_btn := after[0] as Button
	var free_sb := free_btn.get_theme_stylebox("normal") as StyleBoxFlat
	assert_int(free_sb.border_width_left).is_greater(1)

func test_depth_bump_callable_without_crash() -> void:
	# v0.5 arcade pass: a descent bumps the depth chip (presentation). bump_depth must be a safe no-op
	# wherever the label exists; assert it runs and leaves the label resting (scale settles to ~1 on the
	# next idle frames — here we just assert it doesn't crash and the depth text is still correct).
	var mine := _boot_mine()
	mine.hud.set_depth(7)
	mine.hud.bump_depth()
	var depth_label: Label = mine.hud.get_node("Top/DepthBox/Depth")
	assert_str(depth_label.text).is_equal("Depth 7")
