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

## Amount of the most-recently-spawned explosion (GPUParticles2D direct child), or -1 if none.
func _latest_explosion_amount(mine: Mine) -> int:
	var found: Array = mine.find_children("*", "GPUParticles2D", false, false)
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
	# AC-5.9.1: explosions are GPUParticles2D (not ColorRect) AND carry NO collision (particles
	# never collide) AND have a process material (the COLOR source for the web ramp).
	var fx: Node = (preload("res://scenes/explosion.tscn") as PackedScene).instantiate()
	assert_bool(fx is GPUParticles2D).is_true()
	assert_bool(fx is CollisionObject2D).is_false()
	assert_int(fx.find_children("*", "CollisionShape2D").size()).is_equal(0)
	assert_object((fx as GPUParticles2D).process_material).is_not_null()
	fx.free()

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

# ── Non-color identity overlay + terrain physics (AC-5.10.2, AC-5.1.6) ─────────

func test_glyph_overlay_renders_block_identity() -> void:
	# AC-5.10.2: after boot, a solid cell's GlyphLayer carries that block type's glyph tile —
	# identity reads by SHAPE on the overlay, not color alone. Also asserts the generated art
	# texture actually replaced the placeholder (the runtime swap is live, not inert).
	var mine := _boot_mine()
	var grid: BlockGrid = mine.grid
	var glyph_layer := mine.get_node_or_null("BlockGrid/GlyphLayer") as TileMapLayer
	assert_object(glyph_layer).is_not_null()

	# Find any solid, glyph-bearing cell across the loaded chunks.
	var found := Vector2i(-1, -1)
	var found_id := ""
	var width: int = Registry.mine_width_cells(_tables)
	var height: int = Registry.chunk_height(_tables)
	for cy in grid.loaded_chunks():
		var base_y: int = cy * height
		for ly in range(height):
			for x in range(width):
				var y: int = base_y + ly
				if grid.is_solid(x, y) and Art.glyph_index(_tables, grid.get_block_id(x, y)) >= 0:
					found = Vector2i(x, y)
					found_id = grid.get_block_id(x, y)
					break
			if found.x >= 0:
				break
		if found.x >= 0:
			break
	assert_int(found.x).override_failure_message("no solid glyph-bearing cell found").is_greater_equal(0)

	# The overlay cell for that block maps to the block's declared glyph atlas column.
	var expected := Vector2i(Art.glyph_index(_tables, found_id), 0)
	assert_vector(glyph_layer.get_cell_atlas_coords(found)).is_equal(expected)
	assert_int(glyph_layer.get_cell_source_id(found)).is_greater_equal(0)

	# The generated art replaced the placeholder texture (per-type color is now live).
	var block_layer := mine.get_node("BlockGrid/BlockLayer") as TileMapLayer
	var src := block_layer.tile_set.get_source(block_layer.tile_set.get_source_id(0)) as TileSetAtlasSource
	assert_bool(src.texture is ImageTexture).override_failure_message(
		"BlockLayer still using the placeholder texture — generated art not applied"
	).is_true()

func test_authored_atlases_cover_all_rendered_types() -> void:
	# Guard the scene↔data coupling: the authored BlockLayer + GlyphLayer atlases must have at least as
	# many tiles as there are rendered block types / distinct glyphs (rendered_block_ids drives the atlas
	# columns). Else a future /data author adding a block type would silently get a missing tile/glyph.
	var mine := _boot_mine()
	var bl := mine.get_node("BlockGrid/BlockLayer") as TileMapLayer
	var gl := mine.get_node("BlockGrid/GlyphLayer") as TileMapLayer
	var bsrc := bl.tile_set.get_source(bl.tile_set.get_source_id(0)) as TileSetAtlasSource
	var gsrc := gl.tile_set.get_source(gl.tile_set.get_source_id(0)) as TileSetAtlasSource
	assert_int(bsrc.get_tiles_count()).override_failure_message(
		"BlockLayer atlas has fewer tiles than rendered block types — add a tile in block_grid.tscn"
	).is_greater_equal(Art.rendered_block_ids(_tables).size())
	assert_int(gsrc.get_tiles_count()).override_failure_message(
		"GlyphLayer atlas has fewer tiles than distinct glyphs — add a glyph tile in block_grid.tscn"
	).is_greater_equal(Art.glyph_order(_tables).size())

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
