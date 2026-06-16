class_name Mine
extends Node2D
## Mine — the thin level-assembly controller (U10, v0.4). It WIRES the authored
## scene (mine.tscn) to the core/systems; it does NOT build the node tree imperatively
## and holds NO balance literals (everything reads from /data via Registry). This is the
## v0.4 rebuild of the deleted v0.3 god-object: a controller that delegates, not a scene
## that constructs itself in _ready().
##
## Responsibilities (delegation only):
##  - aim: AimController (drag → angle), initial-arc preview to the FIRST bounce only,
##    drawn from the platform muzzle (AC-5.3.1, AC-5.3.7).
##  - throw: spawn the active charge as a Rapier RigidBody (Charge); the free unlimited
##    charge is always throwable and never decremented (RunState — AC-5.3.3/5.3.8/5.4.3).
##  - blast: a FUZZY, seeded blast (Blast.resolve with an injected run-scoped RNG +
##    balance.blast_fuzz_pct) against the pre-blast HP snapshot (AC-5.2.3).
##  - economy: auto-credit ore on break, once per cell (Economy — AC-5.5.1).
##  - terrain: BlockGrid owns per-cell HP; the TileMapLayers are a VIEW of it (AC-5.2.2).
##  - relic → dig-end → prestige → buy one upgrade → measurably stronger next dig
##    (RunState/Prestige/DigEndPanel — AC-5.6.2/5.6.3/5.6.4).
##  - descent + camera: the Platform node tweens its target down and the child Camera2D
##    follows the platform TARGET via smoothing — never hard-set per frame (AC-5.7.x).
##  - explosions: GPUParticles2D with COLOR set (web-safe) — no ColorRect (AC-5.9.1).
##  - audio: thin Audio.play_*() cues at the core event sites (detonate/break/crack/ore/
##    pack/relic/prestige) — placeholder SFX on the SFX bus (AC-5.13.1).
##
## Headless-drivable: the smoke test boots mine.tscn and drives select_charge/throw_at/
## step_physics directly (input events do not fire headless). The same methods back the
## button/drag handlers, so there is one shared code path (AC-5.3.7).
##
## ACs: AC-5.8.1, AC-5.8.2, AC-5.8.4, AC-5.9.1, plus end-to-end of U1–U9.

const CHARGE_SCENE := preload("res://scenes/charge.tscn")
const EXPLOSION_SCENE := preload("res://scenes/explosion.tscn")
const DEBRIS_SCENE := preload("res://scenes/debris_particles.tscn")
const RELIC_PULSE_SCENE := preload("res://scenes/relic_pulse.tscn")
const CHARGE_TRAIL_SCENE := preload("res://scenes/charge_trail.tscn")
const CHUNK_WINDOW_HALF := 3
## Floor on cosmetic explosion particles at the lowest motion-intensity setting — keeps the
## detonation readable (a minimal puff) for reduced-motion players without disabling the cue
## (AC-5.10.1 motion slider / AC-5.10.4 reduced-motion: a legible static-ish fallback, gameplay
## unaffected). Presentation detail, like hud.gd's _BAR_PAD — not game balance.
const EXPLOSION_MIN_PARTICLES := 4
## Particle multiplier at motion 0 (vs the authored count at motion 1) — the reduced-motion floor.
const EXPLOSION_MOTION_FLOOR := 0.12

# ── Authored node references (resolved in _ready from mine.tscn) ───────────────
@onready var _block_layer: TileMapLayer = get_node_or_null("BlockGrid/BlockLayer")
@onready var _glyph_layer: TileMapLayer = get_node_or_null("BlockGrid/GlyphLayer")
@onready var _crack_layer: TileMapLayer = get_node_or_null("BlockGrid/CrackLayer")
@onready var _shaft_guide: ShaftGuide = get_node_or_null("ShaftGuide")
@onready var _light_mask: ColorRect = get_node_or_null("LightMaskLayer/LightMask")
@onready var _platform: Platform = get_node_or_null("Platform")
@onready var _preview_line: Line2D = get_node_or_null("AimPreview")
@onready var _hud: Hud = get_node_or_null("Hud")
@onready var _tray: TrayUi = get_node_or_null("Hud/Bottom/TrayScroll/Tray")
@onready var _throw_button: Button = get_node_or_null("Hud/Bottom/ThrowButton")
@onready var _buy_pack_button: Button = get_node_or_null("Hud/Bottom/BuyPackButton")
@onready var _dig_end_panel: DigEndPanel = get_node_or_null("Hud/DigEndPanel")
@onready var _overlay: SettingsOverlay = get_node_or_null("Overlay")
@onready var _prestige_offer: PrestigeOffer = get_node_or_null("PrestigeOffer")

# ── Systems (delegated logic; no Node deps) ───────────────────────────────────
var _tables: Dictionary
var _grid: BlockGrid
var _economy: Economy
var _run_state: RunState
var _aim: AimController
var _save: SaveManager
var _settings: SettingsState

# ── Per-throw transient state ─────────────────────────────────────────────────
var _active_charge: Charge = null
var _last_banked: int = 0

# ── Layout (all from /data) ───────────────────────────────────────────────────
var _bps: int = 64
var _mine_w: int = 7
var _mine_h: int = 0
var _shaft_w: int = 7
var _shaft_left: int = 0
var _chunk_h: int = 16
var _fuzz_pct: float = 0.0

# ── Fuzzy-blast RNG (injected into Blast.resolve). Run-scoped + reseeded each dig
# so a dig's blasts are reproducible from the run seed (AC-5.2.3/5.2.4). ──────────
var _blast_rng := RandomNumberGenerator.new()

# ── TileSet view mapping (block id → atlas coord). Resolved from the authored
# BlockLayer.tile_set so the controller stays a VIEW, not the asset author. ───────
var _atlas_for: Dictionary = {}        # block_id → Vector2i (BlockLayer atlas coord)
var _glyph_atlas_for: Dictionary = {}  # block_id → Vector2i (GlyphLayer atlas coord)
var _source_id: int = 0
var _glyph_source_id: int = 0
var _crack_source_id: int = 0

# ══════════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	boot()


## Persist the durable state — prestige progression (points + purchases) + accessibility settings.
## Called at dig/prestige boundaries, on a settings change, and on focus-out (AC-5.11.4). No-op
## before boot wires the save+run_state.
func _save_progress() -> void:
	if _save != null and _run_state != null:
		var state: Dictionary = {"prestige": _run_state.prestige.to_state()}
		if _settings != null:
			state["settings"] = _settings.to_state()
		_save.save_state(state)


## Autosave on focus-out / app pause (AC-5.11.4: don't rely on PAUSED alone — also catch focus-out,
## which is more reliable on mobile/web). Cheap + idempotent, so firing on several is fine.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT \
			or what == NOTIFICATION_APPLICATION_PAUSED:
		_save_progress()

## Boot the level: build systems from /data, wire the authored nodes, start dig 1.
## Split out of _ready so the smoke test can boot a freshly instanced mine.tscn and
## then drive it deterministically.
func boot() -> void:
	_tables = GameData.tables
	if _tables.is_empty():
		# Headless callers that instanced the scene before GameData loaded: load now.
		GameData.load_all()
		_tables = GameData.tables

	_bps = Registry.block_pixel_size(_tables)
	_mine_w = Registry.mine_width_cells(_tables)
	_mine_h = Registry.mine_height_cells(_tables)
	_shaft_w = Registry.shaft_width(_tables)
	_shaft_left = Registry.shaft_left_cell(_tables)
	_chunk_h = Registry.chunk_height(_tables)
	_fuzz_pct = float(Registry.balance(_tables, "blast_fuzz_pct", 0.0))

	_economy = Economy.new(_tables)
	_grid = BlockGrid.new(_tables, Registry.run_seed(_tables))
	_run_state = RunState.new(_tables, _economy)
	# Restore persisted progression (prestige points + purchases) so power growth survives an app
	# restart (AC-5.11.1). Per-dig state is not saved. A fresh game / corrupt save loads a clean default.
	_save = SaveManager.new()
	var loaded: Dictionary = _save.load_state()
	_run_state.prestige.from_state(loaded.get("prestige", {}))
	# Settings (AC-5.10.1 / AC-5.11.1): a returning player's saved settings overlay the /data
	# defaults; a fresh game seeds purely from the /data defaults (balance.settings).
	if _save.has_save():
		_settings = SettingsState.from_state(loaded.get("settings", {}), _tables)
	else:
		_settings = SettingsState.from_defaults(_tables)
	_grid.relic_collected.connect(_on_relic_collected)

	_build_atlas_mapping()
	_apply_generated_art()
	_wire_aim()
	_wire_ui()
	_wire_overlay()
	_wire_world_guides()
	_apply_settings()

	if _platform != null:
		_platform.configure(_tables, 0)

	_start_dig()

# ══════════════════════════════════════════════════════════════════════════════
# WIRING (the authored nodes → the systems)
# ══════════════════════════════════════════════════════════════════════════════

## Resolve block-id → atlas coordinate for the BlockLayer (color) and GlyphLayer (shape)
## from the authored TileSets. The scene authors the tiles + physics; the controller just
## learns which atlas coord each block id maps to. Block columns follow BlockArt's single
## rendered-id order (so the generated color strip lines up); glyph columns follow the
## shared glyph order (so two block types could share a glyph — AC-5.10.2's overlay layer).
func _build_atlas_mapping() -> void:
	_atlas_for.clear()
	_glyph_atlas_for.clear()
	if _block_layer == null or _block_layer.tile_set == null:
		return
	var ts: TileSet = _block_layer.tile_set
	if ts.get_source_count() > 0:
		_source_id = ts.get_source_id(0)
	var col: int = 0
	for id in BlockArt.rendered_block_ids(_tables):
		_atlas_for[id] = Vector2i(col, 0)
		var gi: int = BlockArt.glyph_index(_tables, str(id))
		if gi >= 0:
			_glyph_atlas_for[id] = Vector2i(gi, 0)
		col += 1
	if _glyph_layer != null and _glyph_layer.tile_set != null and _glyph_layer.tile_set.get_source_count() > 0:
		_glyph_source_id = _glyph_layer.tile_set.get_source_id(0)
	if _crack_layer != null and _crack_layer.tile_set != null and _crack_layer.tile_set.get_source_count() > 0:
		_crack_source_id = _crack_layer.tile_set.get_source_id(0)


## Swap procedurally-generated art (BlockArt) onto the authored atlas sources. The authored
## physics polygons survive a texture swap (verified), so the BlockLayer keeps its colliders
## (AC-5.1.6) while gaining real per-type COLOR (AC-5.10.3); the GlyphLayer gains the shared
## non-color SHAPE overlay (AC-5.10.2); the CrackLayer gets visible fracture stages. This is
## the same "synthesize the placeholder asset in code" approach as the audio autoload.
func _apply_generated_art() -> void:
	var ordered: Array = BlockArt.rendered_block_ids(_tables)
	_swap_atlas_texture(_block_layer, BlockArt.build_block_strip(_tables, ordered, _bps))
	_swap_atlas_texture(_glyph_layer, BlockArt.build_glyph_strip(_tables, _bps))
	_swap_atlas_texture(_crack_layer, BlockArt.build_crack_strip(Registry.crack_stages(_tables), _bps))


## Replace the texture of a TileMapLayer's first atlas source (preserving its authored tiles
## + physics). No-op if the layer/tileset/source is missing.
func _swap_atlas_texture(layer: TileMapLayer, tex: Texture2D) -> void:
	if layer == null or layer.tile_set == null or layer.tile_set.get_source_count() == 0:
		return
	var src := layer.tile_set.get_source(layer.tile_set.get_source_id(0)) as TileSetAtlasSource
	if src != null:
		src.texture = tex


func _wire_aim() -> void:
	_aim = AimController.new()
	_aim.name = "AimController"
	add_child(_aim)
	if not _aim.angle_changed.is_connected(_on_aim_angle_changed):
		_aim.angle_changed.connect(_on_aim_angle_changed)


func _wire_ui() -> void:
	if _hud != null:
		# Data-driven safe-area + touch-target layout (AC-5.8.5); reflows on resize.
		_hud.configure(_tables)
		# Nav button (≡) opens the modal Settings overlay (AC-5.8.3).
		if not _hud.nav_pressed.is_connected(_on_nav_pressed):
			_hud.nav_pressed.connect(_on_nav_pressed)
		# Big "End Dig" button mirrors the prestige offer for mouse/touch parity.
		if not _hud.end_dig_pressed.is_connected(_on_end_dig_pressed):
			_hud.end_dig_pressed.connect(_on_end_dig_pressed)
	if _tray != null:
		_tray.configure(_tables)
		if not _tray.slot_selected.is_connected(_on_tray_slot_selected):
			_tray.slot_selected.connect(_on_tray_slot_selected)
	if _throw_button != null and not _throw_button.pressed.is_connected(_on_throw_button):
		_throw_button.pressed.connect(_on_throw_button)
	if _buy_pack_button != null and not _buy_pack_button.pressed.is_connected(_on_buy_pack_button):
		_buy_pack_button.pressed.connect(_on_buy_pack_button)
	if _dig_end_panel != null:
		if not _dig_end_panel.buy_upgrade_pressed.is_connected(_on_panel_buy_upgrade):
			_dig_end_panel.buy_upgrade_pressed.connect(_on_panel_buy_upgrade)
		if not _dig_end_panel.next_dig_pressed.is_connected(_on_panel_next_dig):
			_dig_end_panel.next_dig_pressed.connect(_on_panel_next_dig)
	if _prestige_offer != null:
		if not _prestige_offer.accepted.is_connected(_on_prestige_accepted):
			_prestige_offer.accepted.connect(_on_prestige_accepted)
		if not _prestige_offer.declined.is_connected(_on_prestige_declined):
			_prestige_offer.declined.connect(_on_prestige_declined)


## Bind the modal Settings overlay (AC-5.8.3) to the shared SettingsState and listen for changes.
func _wire_overlay() -> void:
	if _overlay == null:
		return
	_overlay.configure(_tables, _settings)
	if not _overlay.settings_changed.is_connected(_on_settings_changed):
		_overlay.settings_changed.connect(_on_settings_changed)

func _wire_world_guides() -> void:
	if _shaft_guide != null:
		_shaft_guide.configure(_tables)
	if _light_mask != null:
		var mat := _light_mask.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("radius_px", Registry.light_radius_px(_tables))
			mat.set_shader_parameter("softness_px", Registry.light_softness_px(_tables))
			mat.set_shader_parameter("dim_alpha", Registry.light_dim_alpha(_tables))
		_update_light_mask()


## Open the modal Settings overlay from the nav button (AC-5.8.3). Opening pauses the tree (the
## overlay owns the pause); the dig stays instanced + frozen and is restored on close.
func _on_nav_pressed() -> void:
	if _overlay != null:
		_overlay.open()


## Prominent "End Dig" / "Prestige" button pressed: show the prestige offer if the relic
## has been found, otherwise end the dig without banking prestige.
func _on_end_dig_pressed() -> void:
	if _run_state.relic_collected:
		if _prestige_offer != null:
			_prestige_offer.show_offer()
	else:
		# No relic yet: end the dig without prestige (soft abort).
		_run_state.end_dig()
		if _dig_end_panel != null:
			_dig_end_panel.show_dig_end(0, _run_state.total_prestige, _run_state.prestige.blast_intensity_mult())
		if _aim != null:
			_aim.set_enabled(false)
	_refresh_all_ui()


## A setting changed in the overlay: apply it live (audio/HUD/explosion) and persist it (AC-5.11.4).
func _on_settings_changed() -> void:
	_apply_settings()
	_save_progress()


## Push the current SettingsState into the systems it drives: SFX/Music bus volume now (AC-5.10.1 /
## AC-5.13.2); the HUD text scale + the explosion motion intensity are applied at their sites
## (_render/_spawn) and on the HUD directly. Safe to call repeatedly (idempotent).
func _apply_settings() -> void:
	if _settings == null:
		return
	Audio.set_sfx_volume_db(_settings.sfx_volume_db())
	Audio.set_music_volume_db(_settings.music_volume_db())
	if _hud != null:
		_hud.set_text_scale(_settings.text_scale)

# ══════════════════════════════════════════════════════════════════════════════
# DIG LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

func _start_dig() -> void:
	_run_state.start_dig()
	# Reproducible fuzzy blasts: reseed the run-scoped blast RNG from the run seed each
	# dig so a dig is reproducible (AC-5.2.3/5.2.4 — fixed seed → fixed result).
	_blast_rng.seed = Registry.run_seed(_tables)
	_active_charge = null
	if _aim != null:
		_aim.reset_angle()
		_aim.set_enabled(true)
	_grid.update_window(0, CHUNK_WINDOW_HALF)
	_render_all_loaded_chunks()
	if _dig_end_panel != null:
		_dig_end_panel.hide_panel()
	if _hud != null:
		_hud.set_end_dig_visible(false)
	_refresh_all_ui()
	_update_preview()


## Called by BlockGrid when the relic cell breaks (AC-5.6.2). Marks the relic found,
## plays the relic-found cue, and offers prestige: accept banks +1 point and ends the
## dig; decline resumes play. The offer overlay pauses the tree.
func _on_relic_collected(cell: Vector2i) -> void:
	_run_state.relic_found()
	Audio.play_relic_found()
	_spawn_relic_pulse(cell)
	if _hud != null:
		_hud.set_relic_progress(true)
		_hud.set_end_dig_visible(true, "PRESTIGE")
	if _prestige_offer != null:
		_prestige_offer.show_offer()
	else:
		# Headless / no-UI fallback: auto-accept the prestige offer.
		_accept_prestige()
	_refresh_all_ui()


## Player accepted the prestige offer: bank +1 point, end the dig, show the dig-end panel.
func _on_prestige_accepted() -> void:
	_accept_prestige()


func _accept_prestige() -> void:
	var before: int = _run_state.total_prestige
	_run_state.end_dig()
	_last_banked = _run_state.total_prestige - before
	_save_progress()  # autosave at the dig/prestige boundary (AC-5.11.4)
	if _last_banked > 0:
		Audio.play_prestige_banked()
	if _aim != null:
		_aim.set_enabled(false)
	if _hud != null:
		_hud.set_end_dig_visible(false)
	if _dig_end_panel != null:
		_dig_end_panel.show_dig_end(
			_last_banked, _run_state.total_prestige, _run_state.prestige.blast_intensity_mult()
		)
	_refresh_all_ui()


## Player declined the prestige offer: hide the offer and keep digging.
func _on_prestige_declined() -> void:
	_refresh_all_ui()

# ══════════════════════════════════════════════════════════════════════════════
# AIM + PREVIEW
# ══════════════════════════════════════════════════════════════════════════════

func _on_aim_angle_changed(angle: float) -> void:
	_update_preview()
	if _platform != null:
		_platform.set_look_ahead(angle)


## The fixed muzzle position — the authored `Body/Muzzle` marker on the platform. The arc
## originates here, never under the finger (AC-5.3.1, AC-5.7.1). Delegated to the Platform
## so the launch point is the authored scene marker, not a code constant.
func _muzzle_position() -> Vector2:
	if _platform != null:
		return _platform.muzzle_position()
	return Vector2(float(_mine_w * _bps) * 0.5, -float(_bps) * 0.5)


## Redraw the initial-arc preview (pre-first-bounce only, AC-5.3.1). Uses the live grid
## as the surface test so the hint stops at the first solid cell it would enter.
func _update_preview() -> void:
	if _preview_line == null or _aim == null:
		return
	if _run_state.dig_ended or _active_charge != null:
		_preview_line.clear_points()
		return
	var params := ThrowParams.from_explosive(_tables, _run_state.selected_id)
	var is_solid := func(cell: Vector2i) -> bool:
		return _grid.is_solid(cell.x, cell.y)
	var path: PackedVector2Array = _aim.preview_path(
		params, _muzzle_position(), is_solid, 240, _bps
	)
	_preview_line.clear_points()
	for p in path:
		_preview_line.add_point(p)

# ══════════════════════════════════════════════════════════════════════════════
# THROW (button + headless-drivable)
# ══════════════════════════════════════════════════════════════════════════════

func _on_throw_button() -> void:
	throw_at(_aim.angle if _aim != null else 0.0)


## Throw the selected charge at `angle`. Spawns it as a Rapier RigidBody at the muzzle
## (AC-5.3.3). The free charge is never decremented (RunState.throw — AC-5.4.3). Returns
## the spawned Charge, or null if a charge is already in flight / the dig ended.
func throw_at(angle: float) -> Charge:
	if _run_state.dig_ended or _active_charge != null:
		return null
	var explosive_id: String = _run_state.throw()
	if explosive_id == "":
		return null
	var params := ThrowParams.from_explosive(_tables, explosive_id)
	var charge: Charge = CHARGE_SCENE.instantiate()
	charge.setup(params, _muzzle_position(), _bps)
	charge.detonated.connect(_on_charge_detonated)
	add_child(charge)
	# Smoke trail for readable flight path and throw satisfaction.
	var trail: CPUParticles2D = CHARGE_TRAIL_SCENE.instantiate()
	charge.add_child(trail)
	charge.launch(angle)
	_active_charge = charge
	if _preview_line != null:
		_preview_line.clear_points()
	_refresh_all_ui()
	return charge


## Select a tray charge (AC-5.3.6). Free charge is always selectable.
func select_charge(charge_id: String) -> bool:
	var ok: bool = _run_state.select(charge_id)
	if ok:
		_refresh_all_ui()
		_update_preview()
	return ok


func _on_tray_slot_selected(charge_id: String) -> void:
	select_charge(charge_id)


func _on_buy_pack_button() -> void:
	buy_pack("basic")


## Buy a pack by id (AC-5.12.2). Delegates to RunState (debit + grant). Refreshes the UI.
func buy_pack(pack_id: String) -> bool:
	var ok: bool = _run_state.buy_pack(pack_id)
	if ok:
		Audio.play_pack_open()  # AC-5.13.1
		_refresh_all_ui()
	return ok

# ══════════════════════════════════════════════════════════════════════════════
# DETONATION → BLAST → CREDIT → DESCENT
# ══════════════════════════════════════════════════════════════════════════════

func _on_charge_detonated(center_cell: Vector2i, params: ThrowParams) -> void:
	_active_charge = null
	_run_state.resolve_charge()
	resolve_blast(center_cell, params)


## Resolve a blast at `center_cell` using `params`. Pure pipeline: snapshot → fuzzy
## seeded Blast.resolve → apply to grid → credit ore (pre-blast ids) → re-render. The
## blast intensity is run through the prestige power multiplier so a bought upgrade makes
## the SAME charge stronger this dig (AC-5.6.4). Returns the Blast result dict.
func resolve_blast(center_cell: Vector2i, params: ThrowParams) -> Dictionary:
	var radius: int = params.blast_radius_cells
	var snap: Dictionary = _grid.hp_snapshot_blast(center_cell, radius)

	# Pre-blast ids (for crediting cleared ore exactly once — AC-5.5.1).
	var pre_ids: Dictionary = {}
	for cell in snap:
		pre_ids[cell] = _grid.get_block_id(cell.x, cell.y)

	# Prestige power growth: the dig's effective intensity (AC-5.6.4).
	var intensity: int = _run_state.dig_blast_intensity(params.blast_intensity)

	# FUZZY, seeded blast (AC-5.2.3): inject the run-scoped RNG + data-driven spread.
	var result: Dictionary = Blast.resolve(
		snap, center_cell, radius, intensity, params.blast_falloff, _blast_rng, _fuzz_pct
	)

	_grid.apply_blast(result)

	var credited: int = 0
	for cell in result["cleared"]:
		credited += _economy.credit(cell, pre_ids.get(cell, "air"))

	_spawn_explosion(center_cell)  # plays the detonate cue
	_shake_camera()

	# Material-specific debris for ore blocks and a central dust puff.
	var debris_count: int = 0
	const MAX_DEBRIS: int = 16
	for cell in result["cleared"]:
		var cleared_id: String = pre_ids.get(cell, "air")
		if cleared_id == "ore_copper" or cleared_id == "ore_gold":
			if debris_count < MAX_DEBRIS:
				_spawn_debris(cell, cleared_id)
				debris_count += 1
	if debris_count == 0 and not (result["cleared"] as Array).is_empty():
		# Even if no ore broke, emit a small dust puff at the blast center.
		_spawn_debris(center_cell, _grid.get_block_id(center_cell.x, center_cell.y))

	# Placeholder SFX (AC-5.13.1): break if any cell broke, else crack if any was only
	# chipped; an ore ping when value was credited. Detonate is played by _spawn_explosion.
	if not (result["cleared"] as Array).is_empty():
		Audio.play_break()
	elif not (result["damaged"] as Dictionary).is_empty():
		Audio.play_crack()
	if credited > 0:
		Audio.play_ore_credited()

	for cell in result["new_hp"]:
		_render_cell(cell.x, cell.y)

	_check_descent()
	_refresh_all_ui()
	_update_preview()
	return result


## Count clears beneath the platform; if at threshold, descend (tweened) + re-window.
## The platform node owns the tween + camera re-anchor (AC-5.7.2/5.7.3); this just feeds
## it the HP grid and reacts to the descent.
func _check_descent() -> void:
	if _platform == null:
		return
	var hp_grid: Dictionary = _hp_grid_beneath(_platform.target_row)
	var steps: int = _platform.try_descend(hp_grid)
	if steps > 0:
		_run_state.depth = _platform.target_row
		var center_chunk: int = _grid.cell_to_chunk(_platform.target_row)
		_grid.update_window(center_chunk, CHUNK_WINDOW_HALF)
		_render_all_loaded_chunks()


## Build the {Vector2i: hp} grid for the rows just beneath `row` (descent lookahead).
func _hp_grid_beneath(row: int) -> Dictionary:
	var out: Dictionary = {}
	var max_steps: int = Registry.descent_max_steps(_tables)
	for dy in range(1, max_steps + 1):
		var ry: int = row + dy
		for x in range(_shaft_left, _shaft_left + _shaft_w):
			out[Vector2i(x, ry)] = _grid.get_hp(x, ry)
	return out

# ══════════════════════════════════════════════════════════════════════════════
# DIG-END PANEL ACTIONS (power growth)
# ══════════════════════════════════════════════════════════════════════════════

func _on_panel_buy_upgrade() -> void:
	buy_first_upgrade()


## Buy the first/only prestige upgrade (the minimal power-growth purchase, AC-5.6.4).
## Returns true on success. Refreshes the dig-end panel's power readout.
func buy_first_upgrade() -> bool:
	var ids: Array = Registry.prestige_upgrade_ids(_tables)
	if ids.is_empty():
		return false
	var ok: bool = _run_state.buy_upgrade(str(ids[0]))
	if ok:
		_save_progress()  # a purchase changes durable state — persist it (AC-5.11.4)
		if _dig_end_panel != null:
			_dig_end_panel.refresh_power(
				_run_state.total_prestige, _run_state.prestige.blast_intensity_mult()
			)
	return ok


func _on_panel_next_dig() -> void:
	_start_dig()

# ══════════════════════════════════════════════════════════════════════════════
# RENDERING (the TileMapLayers as a VIEW of the BlockGrid HP store)
# ══════════════════════════════════════════════════════════════════════════════

func _render_all_loaded_chunks() -> void:
	if _block_layer == null:
		return
	_block_layer.clear()
	if _glyph_layer != null:
		_glyph_layer.clear()
	if _crack_layer != null:
		_crack_layer.clear()
	for chunk_y in _grid.loaded_chunks():
		var base_y: int = chunk_y * _chunk_h
		for ly in range(_chunk_h):
			var y: int = base_y + ly
			if _mine_h > 0 and y >= _mine_h:
				continue
			for lx in range(_mine_w):
				_render_cell(lx, y)


func _render_cell(cell_x: int, cell_y: int) -> void:
	if _block_layer == null:
		return
	var cell := Vector2i(cell_x, cell_y)
	var block_id: String = _grid.get_block_id(cell_x, cell_y)
	var hp: int = _grid.get_hp(cell_x, cell_y)

	if block_id == "air" or hp <= 0:
		_block_layer.erase_cell(cell)
		if _glyph_layer != null:
			_glyph_layer.erase_cell(cell)
		if _crack_layer != null:
			_crack_layer.erase_cell(cell)
		return

	var atlas: Vector2i = _atlas_for.get(block_id, Vector2i(0, 0))
	_block_layer.set_cell(cell, _source_id, atlas)

	# Non-color identity overlay (AC-5.10.2): the block's glyph on the shared GlyphLayer.
	if _glyph_layer != null:
		if _glyph_atlas_for.has(block_id):
			_glyph_layer.set_cell(cell, _glyph_source_id, _glyph_atlas_for[block_id])
		else:
			_glyph_layer.erase_cell(cell)

	if _crack_layer == null:
		return
	var max_hp: int = Registry.scaled_block_hp(
		_tables, block_id, cell_y, _grid.mine_hardness_mult
	)
	var stages: int = Registry.crack_stages(_tables)
	var stage: int = Blast.crack_stage(hp, max_hp, stages)
	# Visible crack stages are 1..stages-1 (stage 0 = full, stages = broken sentinel).
	if stage >= 1 and stage < stages:
		_crack_layer.set_cell(cell, _crack_source_id, Vector2i(stage - 1, 0))
	else:
		_crack_layer.erase_cell(cell)

## Short screenshake scaled by the motion-intensity accessibility slider. Kept
## separate from blast logic so disabling/reducing motion never affects gameplay.
func _shake_camera() -> void:
	if _platform == null:
		return
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	var intensity: float = lerpf(0.0, 12.0, motion)
	if intensity > 0.1:
		_platform.shake(intensity)


# ══════════════════════════════════════════════════════════════════════════════
# EXPLOSION (GPUParticles2D — web-safe COLOR; no ColorRect — AC-5.9.1)
# ══════════════════════════════════════════════════════════════════════════════

## Scale an authored particle count by motion intensity [0,1]: full at 1, a reduced-motion floor
## at 0 (never below EXPLOSION_MIN_PARTICLES so the cue stays readable). Pure + monotonic so the
## motion-intensity accessibility knob is unit-testable without spawning a scene (AC-5.10.1).
func _spawn_debris(cell: Vector2i, block_id: String) -> void:
	var fx: CPUParticles2D = DEBRIS_SCENE.instantiate()
	fx.position = Vector2(
		float(cell.x * _bps) + float(_bps) * 0.5,
		float(cell.y * _bps) + float(_bps) * 0.5
	)
	fx.z_index = 9
	var color: Color = BlockArt.block_color(_tables, block_id) if block_id != "air" else Color(0.7, 0.65, 0.6, 1.0)
	# Slightly vary the debris color so it doesn't look like a flat stamp.
	color = color.lightened(randf_range(0.0, 0.15))
	fx.color = color
	add_child(fx)
	fx.emitting = true
	var ttl: float = fx.lifetime + 0.2
	get_tree().create_timer(ttl).timeout.connect(fx.queue_free)


func _spawn_relic_pulse(cell: Vector2i) -> void:
	var fx: CPUParticles2D = RELIC_PULSE_SCENE.instantiate()
	fx.position = Vector2(
		float(cell.x * _bps) + float(_bps) * 0.5,
		float(cell.y * _bps) + float(_bps) * 0.5
	)
	fx.z_index = 10
	add_child(fx)
	fx.emitting = true
	var ttl: float = fx.lifetime + 0.2
	get_tree().create_timer(ttl).timeout.connect(fx.queue_free)


static func explosion_particle_count(base_amount: int, motion: float) -> int:
	var m: float = clampf(motion, 0.0, 1.0)
	var factor: float = lerpf(EXPLOSION_MOTION_FLOOR, 1.0, m)
	return maxi(EXPLOSION_MIN_PARTICLES, int(round(float(base_amount) * factor)))


func _spawn_explosion(center_cell: Vector2i) -> void:
	var fx: GPUParticles2D = EXPLOSION_SCENE.instantiate()
	fx.position = Vector2(
		float(center_cell.x * _bps) + float(_bps) * 0.5,
		float(center_cell.y * _bps) + float(_bps) * 0.5
	)
	fx.z_index = 10
	# Motion-intensity (AC-5.10.1 / AC-5.10.4): scale the cosmetic particle spray. The blast
	# GAMEPLAY already resolved (damage/credit) — only the visual intensity reduces, down to a
	# minimal readable puff at intensity 0 (reduced motion), never zero.
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	fx.amount = explosion_particle_count(fx.amount, motion)
	add_child(fx)
	fx.emitting = true
	Audio.play_detonate()  # AC-5.13.1: detonation cue, co-located with the visual fx
	# Free after the particle lifetime (the scene is one-shot).
	var ttl: float = fx.lifetime + 0.2
	get_tree().create_timer(ttl).timeout.connect(fx.queue_free)

# ══════════════════════════════════════════════════════════════════════════════
# UI REFRESH
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_all_ui() -> void:
	if _hud != null:
		_hud.set_money(_economy.money)
		var depth: int = _platform.target_row if _platform != null else _run_state.depth
		_hud.set_depth(depth)
		_hud.set_relic_progress(_run_state.relic_collected)
		_hud.set_depth_odds(Registry.band_odds(_tables, depth))
	_rebuild_tray()
	if _throw_button != null:
		_throw_button.disabled = (_run_state.dig_ended or _active_charge != null)
	if _buy_pack_button != null:
		_buy_pack_button.disabled = (
			_run_state.dig_ended
			or not _economy.can_afford(int(Registry.pack(_tables, "basic").get("price", 0)))
		)


## Rebuild the tray view from the RunState tray (collapsing duplicate finite charges
## into one slot with a count; the free charge is the first slot with ∞ — AC-5.8.1/2).
func _rebuild_tray() -> void:
	if _tray == null:
		return
	var slots: Array = []
	var free_id: String = _run_state.free_charge_id
	slots.append({"id": free_id, "count": -1})
	var seen: Array = []
	for id in _run_state.tray:
		if id == free_id or seen.has(id):
			continue
		seen.append(id)
		slots.append({"id": id, "count": _run_state.count_of(id)})
	_tray.rebuild(slots, _run_state.selected_id)

# ══════════════════════════════════════════════════════════════════════════════
# CAMERA (followed by the Platform node; only stepped here for cleanup safety)
# ══════════════════════════════════════════════════════════════════════════════

func _physics_process(_delta: float) -> void:
	# Safety: a charge freed without emitting `detonated` (shouldn't happen) must not
	# leave the controller stuck "in flight" forever.
	if _active_charge != null and not is_instance_valid(_active_charge):
		_active_charge = null
		_run_state.resolve_charge()
		_refresh_all_ui()
		_update_preview()

func _process(_delta: float) -> void:
	_update_light_mask()

func _update_light_mask() -> void:
	if _light_mask == null:
		return
	var mat := _light_mask.material as ShaderMaterial
	if mat == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var world_pos: Vector2 = _platform.platform_target_position() if _platform != null else _muzzle_position()
	var screen_pos: Vector2 = get_viewport().get_canvas_transform() * world_pos
	mat.set_shader_parameter(
		"light_uv",
		Vector2(screen_pos.x / viewport_size.x, screen_pos.y / viewport_size.y)
	)

# ══════════════════════════════════════════════════════════════════════════════
# HEADLESS-TEST ACCESSORS (read-only views into the wired systems)
# ══════════════════════════════════════════════════════════════════════════════

var grid: BlockGrid:
	get:
		return _grid

var economy: Economy:
	get:
		return _economy

var run_state: RunState:
	get:
		return _run_state

var platform: Platform:
	get:
		return _platform

var block_pixel_size: int:
	get:
		return _bps

var mine_width_cells: int:
	get:
		return _mine_w

var settings: SettingsState:
	get:
		return _settings

var overlay: SettingsOverlay:
	get:
		return _overlay

var hud: Hud:
	get:
		return _hud
