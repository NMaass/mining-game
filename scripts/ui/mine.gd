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
const MUZZLE_FLASH_SCENE := preload("res://scenes/muzzle_flash.tscn")
const VALUE_POPUP_SCENE := preload("res://scenes/value_popup.tscn")
const COIN_PICKUP_SCENE := preload("res://scenes/coin_pickup.tscn")
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
@onready var _crack_layer: TileMapLayer = get_node_or_null("BlockGrid/CrackLayer")
@onready var _shaft_guide: ShaftGuide = get_node_or_null("ShaftGuide")
@onready var _light_mask: ColorRect = get_node_or_null("LightMaskLayer/LightMask")
@onready var _platform: Platform = get_node_or_null("Platform")
@onready var _preview_line: Line2D = get_node_or_null("AimPreview")
@onready var _aim_reticle: Sprite2D = get_node_or_null("AimReticle")
@onready var _hud: Hud = get_node_or_null("Hud")
@onready var _tray: TrayUi = get_node_or_null("Hud/Bottom/TrayScroll/Tray")
@onready var _throw_button: Button = get_node_or_null("Hud/Bottom/ThrowButton")
@onready var _cooldown_fill: ColorRect = get_node_or_null("Hud/Bottom/ThrowButton/CooldownFill")
@onready var _cooldown_label: Label = get_node_or_null("Hud/Bottom/ThrowButton/CooldownLabel")
@onready var _buy_pack_button: Button = get_node_or_null("Hud/Bottom/BuyPackButton")
@onready var _elevator_up: Button = get_node_or_null("Hud/ElevatorControls/ElevatorUp")
@onready var _elevator_down: Button = get_node_or_null("Hud/ElevatorControls/ElevatorDown")
@onready var _dig_end_panel: DigEndPanel = get_node_or_null("Hud/DigEndPanel")
@onready var _overlay: SettingsOverlay = get_node_or_null("Overlay")
@onready var _prestige_offer: PrestigeOffer = get_node_or_null("PrestigeOffer")
@onready var _shop_modal: ShopModal = get_node_or_null("ShopModal")

# ── Systems (delegated logic; no Node deps) ───────────────────────────────────
var _tables: Dictionary
var _grid: BlockGrid
var _economy: Economy
var _run_state: RunState
var _aim: AimController
var _throw_controls: ThrowControls
var _save: SaveManager
var _settings: SettingsState

# ── Per-throw transient state ─────────────────────────────────────────────────
var _active_charge: Charge = null
var _last_banked: int = 0
## Live count of floating "+$N" value popups, so a wide ore vein can't spam labels past
## vfx.popup_max_active (decremented when each popup's ttl frees it).
var _active_popups: int = 0
## Live count of flying reward coins (v0.5 money juice), capped at coin_max_active so a wide ore
## vein can't spawn unbounded coin sprites on the single-threaded web budget; over-budget credits
## still land in the rolling count-up. Decremented when each coin's ttl frees it.
var _active_coins: int = 0

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

# ── TileSet view mapping (block id → atlas column). Resolved from the authored
# BlockLayer.tile_set so the controller stays a VIEW, not the asset author. With v0.5
# tile variation each type owns a CONTIGUOUS RANGE of columns (one per variant tile); the
# base column + variant count let _render_cell pick a stable per-cell variant. ───────
var _atlas_base_col: Dictionary = {}   # block_id → int (first BlockLayer atlas column)
var _atlas_variants: Dictionary = {}   # block_id → int (number of variant columns, >= 1)
var _source_id: int = 0
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
	_wire_throw_controls()
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

## Resolve block-id → atlas coordinate for the BlockLayer (color) from the authored TileSet.
## The scene authors the tiles + physics; the controller just learns which atlas coord each
## block id maps to. Block columns follow BlockArt's rendered-id order (so the generated
## color strip lines up). The debug-grid glyph overlay layer was removed (v0.5 arcade pass);
## non-color identity now rides the textured tile + the luminance-contrast gate.
func _build_atlas_mapping() -> void:
	_atlas_base_col.clear()
	_atlas_variants.clear()
	if _block_layer == null or _block_layer.tile_set == null:
		return
	var ts: TileSet = _block_layer.tile_set
	if ts.get_source_count() > 0:
		_source_id = ts.get_source_id(0)
	# Each type owns a contiguous block of columns (one per variant tile); the generated strip
	# (BlockArt.sourced_block_strip_image) uses the same per-type widths so the columns line up.
	var col: int = 0
	for id in BlockArt.rendered_block_ids(_tables):
		var vcount: int = BlockArt.variant_count(_tables, str(id))
		_atlas_base_col[id] = col
		_atlas_variants[id] = vcount
		col += vcount
	if _crack_layer != null and _crack_layer.tile_set != null and _crack_layer.tile_set.get_source_count() > 0:
		_crack_source_id = _crack_layer.tile_set.get_source_id(0)


## Swap procedurally-generated art (BlockArt) onto the authored atlas sources. The authored
## physics polygons survive a texture swap (verified), so the BlockLayer keeps its colliders
## (AC-5.1.6) while gaining real per-type COLOR / sourced pixel-art tiles (AC-5.10.3); the
## CrackLayer gets visible fracture stages. This is the same "synthesize the placeholder asset
## in code" approach as the audio autoload. (The debug-grid glyph overlay was removed in v0.5.)
func _apply_generated_art() -> void:
	var ordered: Array = BlockArt.rendered_block_ids(_tables)
	_swap_atlas_texture(_block_layer, BlockArt.build_block_strip(_tables, ordered, _bps))
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


func _wire_throw_controls() -> void:
	_throw_controls = ThrowControls.new()
	_throw_controls.name = "ThrowControls"
	add_child(_throw_controls)


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
		# Elevator arrows manually move the platform up/down.
		if not _hud.elevator_up_pressed.is_connected(_on_elevator_up):
			_hud.elevator_up_pressed.connect(_on_elevator_up)
		if not _hud.elevator_down_pressed.is_connected(_on_elevator_down):
			_hud.elevator_down_pressed.connect(_on_elevator_down)
	if _platform != null:
		if not _platform.descended.is_connected(_on_platform_descended):
			_platform.descended.connect(_on_platform_descended)
	if _tray != null:
		_tray.configure(_tables)
		if not _tray.slot_selected.is_connected(_on_tray_slot_selected):
			_tray.slot_selected.connect(_on_tray_slot_selected)
	if _throw_button != null and not _throw_button.pressed.is_connected(_on_throw_button):
		_throw_button.pressed.connect(_on_throw_button)
	if _buy_pack_button != null and not _buy_pack_button.pressed.is_connected(_on_buy_pack_button):
		_buy_pack_button.pressed.connect(_on_buy_pack_button)
	if _dig_end_panel != null:
		_dig_end_panel.configure(_tables)  # data-driven pop-in duration
		if not _dig_end_panel.buy_upgrade_pressed.is_connected(_on_panel_buy_upgrade):
			_dig_end_panel.buy_upgrade_pressed.connect(_on_panel_buy_upgrade)
		if not _dig_end_panel.next_dig_pressed.is_connected(_on_panel_next_dig):
			_dig_end_panel.next_dig_pressed.connect(_on_panel_next_dig)
	if _prestige_offer != null:
		_prestige_offer.configure(_tables)  # data-driven pop-in duration
		if not _prestige_offer.accepted.is_connected(_on_prestige_accepted):
			_prestige_offer.accepted.connect(_on_prestige_accepted)
		if not _prestige_offer.declined.is_connected(_on_prestige_declined):
			_prestige_offer.declined.connect(_on_prestige_declined)
	if _shop_modal != null:
		_shop_modal.configure(_tables, func() -> int: return _economy.money)
		if not _shop_modal.buy_pressed.is_connected(_on_shop_buy_pressed):
			_shop_modal.buy_pressed.connect(_on_shop_buy_pressed)


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
			mat.set_shader_parameter("radius_px", Registry.effective_light_radius(_tables, _run_state.prestige))
			mat.set_shader_parameter("softness_px", Registry.light_softness_px(_tables))
			mat.set_shader_parameter("dim_alpha", Registry.light_dim_alpha(_tables))
			# Warm/cool headlamp: the unlit mine fades toward a cool atmospheric tint, not
			# pure black (data-driven; AC-5.10.2 atmosphere). The mask alpha is the vignette.
			mat.set_shader_parameter("dark_tint", Registry.light_dark_tint(_tables))
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
			_prestige_offer.show_offer(_motion_intensity())
	else:
		# No relic yet: end the dig without prestige (soft abort).
		_run_state.end_dig()
		if _dig_end_panel != null:
			_dig_end_panel.show_dig_end(0, _run_state.total_prestige,
				_run_state.prestige.blast_intensity_mult(), _motion_intensity())
		if _aim != null:
			_aim.set_enabled(false)
	_refresh_all_ui()


## Elevator up arrow pressed: move the platform up one row (clamped to the mine top).
func _on_elevator_up() -> void:
	if _platform == null:
		return
	if _platform.move_up():
		_run_state.depth = _platform.target_row
		_refresh_all_ui()


## Elevator down arrow pressed: move the platform down one row (clamped to mine bottom).
func _on_elevator_down() -> void:
	if _platform == null:
		return
	if _platform.move_down():
		_run_state.depth = _platform.target_row
		_refresh_all_ui()


## Platform target row changed (auto-descent or manual elevator move): refresh UI so the
## elevator arrows gray at the top/bottom limits and the depth readout stays in sync.
func _on_platform_descended(_new_row: int) -> void:
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
	# A longer hit-stop on the relic break — the dig's climax lands with a deeper freeze.
	# Fire-and-forget (self-restores time_scale); gated on motion + paused inside _hit_stop.
	_hit_stop(Registry.vfx_f(_tables, "hitstop_relic_seconds", 0.16))
	var motion: float = _motion_intensity()
	if _hud != null:
		# Relic-found beat (v0.5 arcade pass): pulse the relic chip + a warm-gold screen wash. Both
		# motion-gated (the flash alpha is a11y-capped + scaled by motion → safe for AC-5.10.4).
		_hud.set_relic_progress(true, motion)
		_hud.flash(Color(1.0, 0.85, 0.4), Registry.ui_flash_alpha(_tables),
			Registry.ui_flash_seconds(_tables), motion)
		_hud.set_end_dig_visible(true, "PRESTIGE")
	if _prestige_offer != null:
		_prestige_offer.show_offer(motion)
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
	var motion: float = _motion_intensity()
	if _last_banked > 0:
		Audio.play_prestige_banked()
		# Prestige-banked beat (v0.5 arcade pass): a brighter wash than the relic-found one. Same
		# a11y-capped + motion-gated flash. Only fires when a point was actually banked.
		if _hud != null:
			_hud.flash(Color(1.0, 0.95, 0.7), Registry.ui_flash_alpha(_tables),
				Registry.ui_flash_seconds(_tables), motion)
	if _aim != null:
		_aim.set_enabled(false)
	if _hud != null:
		_hud.set_end_dig_visible(false)
	if _dig_end_panel != null:
		_dig_end_panel.show_dig_end(
			_last_banked, _run_state.total_prestige, _run_state.prestige.blast_intensity_mult(), motion
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
## as the surface test so the hint stops at the first solid cell it would enter. The PURE
## preview math (_aim.preview_path → Aim.initial_arc) is untouched (AC-5.3.x stays gate-free);
## only the cosmetic presentation — line width (feel.aim_line_width), full opacity, and a pulsing
## reticle parked on the predicted first-bounce cell — is layered on here.
func _update_preview() -> void:
	if _preview_line == null or _aim == null:
		return
	# A throw is committing — let _begin_aim_fade_out animate the line away; don't snap it back.
	if _aim_fading:
		return
	if _run_state.dig_ended or _active_charge != null:
		_clear_preview()
		return
	var params := ThrowParams.from_explosive(_tables, _run_state.selected_id)
	var is_solid := func(cell: Vector2i) -> bool:
		return _grid.is_solid(cell.x, cell.y)
	var path: PackedVector2Array = _aim.preview_path(
		params, _muzzle_position(), is_solid, 240, _bps
	)
	# Reset the cosmetic state the fade-out / a previous throw may have left dimmed.
	_preview_line.width = Registry.feel_f(_tables, "aim_line_width", 5.0)
	_preview_line.self_modulate = Color(1, 1, 1, 1)
	_preview_line.clear_points()
	for p in path:
		_preview_line.add_point(p)
	# Reticle: park it on the predicted first-bounce cell (the LAST preview point) while aiming,
	# so the player sees exactly where the throw lands. Hidden once there is no aimable path.
	if _aim_reticle != null:
		if path.size() > 0:
			_aim_reticle.position = path[path.size() - 1]
			_aim_reticle.visible = true
		else:
			_aim_reticle.visible = false


## Hide the aim line + reticle (no throw in progress). Snap-clears — used when the preview is
## simply invalid (dig ended / charge in flight). The animated fade lives in _begin_aim_fade_out.
func _clear_preview() -> void:
	if _preview_line != null:
		_preview_line.clear_points()
	if _aim_reticle != null:
		_aim_reticle.visible = false


# ── Animated aim line: marching-dash scroll + throw fade-out (v0.5 arcade pass) ──
## True WHILE a throw's fade-out tween is animating the line away — so _update_preview won't
## re-snap the freshly-thrown line back to full while it fades.
var _aim_fading: bool = false
## Accumulated time for the marching-dash texture scroll + reticle pulse (advanced in _process,
## ONLY while dragging). _process does not run while the tree is paused (the Settings overlay
## pauses it), so the dash naturally freezes during a pause; motion-intensity 0 also freezes it.
var _aim_dash_t: float = 0.0


## Per-frame cosmetic animation for the aim line + reticle, gated on `is_dragging` (so it costs
## nothing when not aiming) and on the motion-intensity accessibility setting (motion 0 → a still
## line, no scroll/pulse — the reduced-motion contract). Tolerates pause implicitly: _process is
## suspended while the tree is paused, so nothing here runs during the Settings overlay. Called from
## the single _process (which also drives the light mask).
func _animate_aim_line(delta: float) -> void:
	if _aim == null or not _aim.is_dragging:
		return
	if _preview_line == null:
		return
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0:
		# Reduced motion: hold a static, fully-opaque line + steady reticle (no march/pulse).
		_preview_line.self_modulate = Color(1, 1, 1, 1)
		if _aim_reticle != null:
			_aim_reticle.scale = Vector2(0.22, 0.22)
		return
	var scroll: float = Registry.feel_f(_tables, "aim_scroll_speed", 60.0)
	_aim_dash_t += delta * scroll
	# "Marching" aim feedback: a gentle opacity shimmer (driven by the data-tuned scroll speed) reads
	# as a live, active aim line crawling toward the impact — without shipping a dash-texture asset.
	# The gradient fade (muzzle → tip) is baked into the authored Line2D gradient.
	var shimmer: float = 0.78 + 0.22 * sin(_aim_dash_t * 0.12)
	_preview_line.self_modulate = Color(1, 1, 1, shimmer)
	# Reticle pulse: a small breathing scale so the impact marker feels alive while aiming.
	if _aim_reticle != null and _aim_reticle.visible:
		var pulse: float = 0.22 * (1.0 + 0.18 * sin(_aim_dash_t * 0.16))
		_aim_reticle.scale = Vector2(pulse, pulse)

# ══════════════════════════════════════════════════════════════════════════════
# THROW (button + headless-drivable)
# ══════════════════════════════════════════════════════════════════════════════

func _on_throw_button() -> void:
	# Button squash-then-pop BEFORE throw_at (which disables the button via _refresh_all_ui). The
	# tween is fire-and-forget on the button node itself — disabling it does not kill an in-flight
	# scale tween — so the squash plays even though the throw immediately greys the button out.
	_squash_throw_button()
	throw_at(_aim.angle if _aim != null else 0.0)


## Live THROW-button squash tween (kept so a rapid second press restarts cleanly without stacking).
var _throw_btn_tween: Tween = null

## Squash the THROW button on press, then pop it past 1.0 before settling (a tactile click).
## Runs BEFORE the throw disables the button. Gated on motion intensity (motion 0 → no squash —
## the button just greys out). All magnitudes are /data (feel.throw_button_squash / _pop_seconds).
func _squash_throw_button() -> void:
	if _throw_button == null:
		return
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0:
		return
	var squash: float = Registry.feel_f(_tables, "throw_button_squash", 0.86)
	var pop_s: float = Registry.feel_f(_tables, "throw_button_pop_seconds", 0.12)
	# Pivot at the button center so it scales in place (not from the top-left corner).
	_throw_button.pivot_offset = _throw_button.size * 0.5
	var down := Vector2(squash + 0.04, squash)  # compress mostly vertically (a "press")
	# Kill any prior squash so rapid throws don't stack tweens / strand the scale off 1.0.
	if _throw_btn_tween != null and _throw_btn_tween.is_valid():
		_throw_btn_tween.kill()
	_throw_button.scale = Vector2.ONE
	_throw_btn_tween = create_tween()
	_throw_btn_tween.tween_property(_throw_button, "scale", down, pop_s * 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_throw_btn_tween.tween_property(_throw_button, "scale", Vector2.ONE, pop_s * 0.6) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## Returns the effective throw cooldown for this dig, reduced by the Charge Holster prestige
## upgrade (AC-5.6.4). Centralized so the cooldown start and any UI readout use the same value.
func _throw_cooldown_seconds() -> float:
	return Registry.effective_throw_cooldown(_tables, _run_state.prestige)


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
	# Comet trail for a readable flight path + throw satisfaction (global-coords streak, web-safe COLOR).
	var trail: CPUParticles2D = CHARGE_TRAIL_SCENE.instantiate()
	charge.add_child(trail)
	charge.launch(angle)
	# Launch cue (v0.5 arcade audio): a short airy upward whoosh on release — this moment was silent
	# before. Co-located with the visual launch pop below.
	Audio.play_throw()  # AC-5.13.1
	_active_charge = charge
	if _throw_controls != null:
		_throw_controls.start_cooldown(_throw_cooldown_seconds())
	# LAUNCH POP: a muzzle flash at the launch point + a platform-deck recoil opposite the throw.
	# Both are cosmetic, capped/ttl-freed, and gated on motion intensity (motion 0 → no flash/kick).
	_spawn_muzzle_flash(angle)
	_recoil_platform(angle)
	# Fade the aim line out (don't snap it) so the throw reads as a release, not a hard cut.
	_begin_aim_fade_out()
	_refresh_all_ui()
	return charge


## Spawn a one-shot muzzle flash at the launch point (the platform muzzle). It is a GPUParticles2D
## whose spray COLOR rides a ParticleProcessMaterial color_ramp (+ an additive Flash sprite) — the
## web-safe pattern (no bare process shader), so it renders on the GL Compatibility / WebGL2 build.
## Cosmetic + ttl-freed → 0 orphans at exit. Gated on motion intensity (motion 0 → no flash). The
## burst size is /data (feel.muzzle_flash_particles), scaled by motion like the explosion spray.
func _spawn_muzzle_flash(angle: float) -> void:
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0:
		return
	var fx: GPUParticles2D = MUZZLE_FLASH_SCENE.instantiate()
	fx.position = _muzzle_position()
	# Point the flash along the launch direction (0 = straight down) so it reads as a barrel blast.
	fx.rotation = angle
	fx.z_index = 10
	var base: int = Registry.feel_i(_tables, "muzzle_flash_particles", fx.amount)
	fx.amount = explosion_particle_count(base, motion)
	add_child(fx)
	fx.emitting = true
	# Free after the one-shot's lifetime (honors the ttl-free pattern; survives a pause/time-scale).
	var ttl: float = fx.lifetime + 0.2
	get_tree().create_timer(ttl, true, false, true).timeout.connect(fx.queue_free)


## Kick the platform deck opposite the launch direction (a launch recoil). Delegates to the
## Platform (which writes ONLY the Body/Visual child — never the body/collider/muzzle/camera, so
## AC-5.7.x stays green). Gated + scaled by motion intensity (motion 0 → no kick). Distance /data.
func _recoil_platform(angle: float) -> void:
	if _platform == null:
		return
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0:
		return
	_platform.recoil(angle, Registry.feel_f(_tables, "recoil_px", 6.0) * motion)


## Fade the aim line + reticle out on throw (a soft release, not the old instant clear_points).
## Tweens the line width + opacity (and the reticle alpha) to 0, then snap-clears. Gated on motion:
## at motion 0 it just snap-clears (reduced motion). The `_aim_fading` flag stops _update_preview
## from re-snapping the line back to full mid-fade.
func _begin_aim_fade_out() -> void:
	if _preview_line == null:
		_clear_preview()
		return
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0 or _preview_line.get_point_count() == 0:
		_clear_preview()
		return
	_aim_fading = true
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_preview_line, "self_modulate:a", 0.0, 0.18).set_ease(Tween.EASE_OUT)
	t.tween_property(_preview_line, "width", 0.0, 0.18).set_ease(Tween.EASE_OUT)
	if _aim_reticle != null and _aim_reticle.visible:
		t.tween_property(_aim_reticle, "modulate:a", 0.0, 0.18).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(_finish_aim_fade_out)


## End the throw fade: snap the line + reticle clean and restore their cosmetic state so the NEXT
## aim draws bright again (_update_preview also resets width/opacity, but restore here too in case
## the next draw is gated off, e.g. dig ended).
func _finish_aim_fade_out() -> void:
	_aim_fading = false
	_clear_preview()
	if _preview_line != null:
		_preview_line.self_modulate = Color(1, 1, 1, 1)
		_preview_line.width = Registry.feel_f(_tables, "aim_line_width", 5.0)
	if _aim_reticle != null:
		_aim_reticle.modulate.a = 0.9


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
	if _shop_modal != null:
		_shop_modal.open(_motion_intensity())


## Buy a pack by id (AC-5.12.2). Delegates to RunState (debit + grant). Refreshes the UI.
func buy_pack(pack_id: String) -> bool:
	var ok: bool = _run_state.buy_pack(pack_id)
	if ok:
		Audio.play_pack_open()  # AC-5.13.1
		_refresh_all_ui()
	return ok


## A pack was bought from the shop modal: play the cue (already inside buy_pack), close
## the modal, and refresh the UI. If the buy is rejected (shouldn't happen when the button
## is disabled), leave the modal open so the player can pick something else.
func _on_shop_buy_pressed(pack_id: String) -> void:
	if buy_pack(pack_id) and _shop_modal != null:
		_shop_modal.close()

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

	# Credit cleared ore once per cell (AC-5.5.1), capturing the PER-CELL value so a credited
	# ore cell can throw a material-tinted "+$N" popup (the per-cell value was summed-and-discarded
	# before the v0.5 arcade pass).
	var credited: int = 0
	var cell_credit: Dictionary = {}  # Vector2i → int credited at that cell
	for cell in result["cleared"]:
		var got: int = _economy.credit(cell, pre_ids.get(cell, "air"))
		credited += got
		if got > 0:
			cell_credit[cell] = got
	# Money was credited this blast → the end-of-pipeline _refresh_all_ui rolls the readout (v0.5
	# money juice) instead of snapping; a $0 blast leaves it snapping. The roll/coins are gated on
	# motion intensity inside the HUD/coin path.
	if credited > 0:
		_animate_money_next_refresh = true

	var cleared_count: int = (result["cleared"] as Array).size()
	var blast_world_center := Vector2(
		float(center_cell.x * _bps) + float(_bps) * 0.5,
		float(center_cell.y * _bps) + float(_bps) * 0.5
	)

	_spawn_explosion(center_cell, radius)  # plays the detonate cue
	# Camera weight: trauma scaled by cleared-cell count (big breaks shake harder + longer),
	# kicked AWAY from the impact, plus a brief zoom punch. Both gated on motion intensity
	# (motion 0 → still frame). Writes camera.offset/zoom only, never position (AC-5.7.3).
	_shake_camera(cleared_count, blast_world_center, radius)

	# Per-cell debris for EVERY cleared solid cell (dirt/rock chunks now fly too, not just ore),
	# tinted by the cell's material (BlockArt.block_color). Capped at vfx.max_debris_emitters for
	# the web budget, preferring cells NEAREST the blast center over budget so the dust reads at
	# the impact even on a wide vein.
	var max_debris: int = Registry.vfx_i(_tables, "max_debris_emitters", 24)
	var cleared_solid: Array = []
	for cell in result["cleared"]:
		var cleared_id: String = pre_ids.get(cell, "air")
		if cleared_id != "air":
			cleared_solid.append(cell)
	# Nearest-center-first ordering (distance² is enough — avoids the sqrt).
	cleared_solid.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center_cell).length_squared() < (b - center_cell).length_squared()
	)
	var debris_count: int = 0
	for cell in cleared_solid:
		if debris_count >= max_debris:
			break
		_spawn_debris(cell, pre_ids.get(cell, "air"))
		debris_count += 1
	if debris_count == 0 and not (result["cleared"] as Array).is_empty():
		# All cleared cells were air (rare): emit a small dust puff at the blast center.
		_spawn_debris(center_cell, _grid.get_block_id(center_cell.x, center_cell.y))

	# Floating "+$N" value popups + flying reward coins at each credited ore cell (skip $0 dirt
	# breaks). Both capped (vfx.popup_max_active / coin_max_active) so a wide ore vein doesn't spam
	# the screen; caps are honored live via the _active_* counters (decremented on ttl free). Tinted
	# per-ore by the material color. The coins home to the wallet icon and pop the money HUD on arrival.
	for cell in cell_credit:
		_spawn_value_popup(cell, int(cell_credit[cell]), pre_ids.get(cell, "air"))
		_spawn_coin(cell, pre_ids.get(cell, "air"))

	# Placeholder SFX (AC-5.13.1): a rising-pitch break RATTLE scaled by the cleared-cell count (the
	# arcade arpeggio — a wide break sounds bigger than a single tap), else a crack if any cell was
	# only chipped; an ore ping when value was credited. Detonate is played (layered) by _spawn_explosion.
	if not (result["cleared"] as Array).is_empty():
		Audio.play_break_combo(cleared_count)
	elif not (result["damaged"] as Dictionary).is_empty():
		Audio.play_crack()
	if credited > 0:
		Audio.play_ore_credited()

	for cell in result["new_hp"]:
		_render_cell(cell.x, cell.y)

	_check_descent()
	_refresh_all_ui()
	_update_preview()

	# Hit-stop on a BIG break (>= vfx.hitstop_min_cells cleared) — a brief Engine.time_scale
	# freeze that lands the "crunch". Free 1-cell taps never freeze. Fire-and-forget (NOT
	# awaited) so resolve_blast returns the result synchronously for the smoke test; the
	# coroutine self-restores time_scale. Gated on motion intensity inside _hit_stop.
	if cleared_count >= Registry.vfx_i(_tables, "hitstop_min_cells", 6):
		_hit_stop(Registry.vfx_f(_tables, "hitstop_seconds", 0.05))
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
		# Depth-drop beat (v0.5 arcade pass): a quick squash on the depth chip. Presentation only;
		# bump_depth is a no-op headless and self-gates (a tween on a label, harmless if motion 0).
		if _hud != null:
			_hud.bump_depth()
		# Descent cue (v0.5 arcade audio): a low mechanical thud when the platform drops — this moment
		# was silent before. Fired once per descent regardless of step count.
		Audio.play_descend()  # AC-5.13.1


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
		if _crack_layer != null:
			_crack_layer.erase_cell(cell)
		return

	# Pick a stable per-cell tile variant inside this type's column range (v0.5 tile variation):
	# variant_for is a pure spatial hash of the cell, so a re-render after a descent never flickers
	# but adjacent same-type cells differ (no single repeating stamp). One variant → always col 0.
	var base_col: int = int(_atlas_base_col.get(block_id, 0))
	var vcount: int = int(_atlas_variants.get(block_id, 1))
	var variant: int = BlockArt.variant_for(block_id, cell, vcount)
	_block_layer.set_cell(cell, _source_id, Vector2i(base_col + variant, 0))

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

## Trauma-based screenshake + zoom punch, scaled by the cleared-cell count and the
## motion-intensity accessibility slider. Kept separate from blast logic so disabling/
## reducing motion never affects gameplay. ALL magnitudes are /data (Registry.vfx_*):
## trauma = (shake_base + shake_per_cell·cleared) · motion (so a megablast kicks far
## harder than a free tap), and the zoom punch scales with the blast radius. The kick is
## aimed AWAY from `blast_world_center`. The Platform writes camera.offset/zoom only —
## never position/target (AC-5.7.3). At motion 0 trauma/zoom are 0 → a still frame.
func _shake_camera(cleared_count: int, blast_world_center: Vector2, radius: int) -> void:
	if _platform == null:
		return
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0:
		return
	var base: float = Registry.vfx_f(_tables, "shake_base", 0.3)
	var per_cell: float = Registry.vfx_f(_tables, "shake_per_cell", 0.02)
	var trauma: float = (base + per_cell * float(cleared_count)) * motion
	_platform.add_trauma(trauma, blast_world_center)
	_platform.zoom_punch(float(radius) * motion)


# ══════════════════════════════════════════════════════════════════════════════
# HIT-STOP (a brief global Engine.time_scale freeze on big breaks — sells weight)
# ══════════════════════════════════════════════════════════════════════════════

## Current motion-intensity accessibility value [0,1] (AC-5.10.1/5.10.4), or 1.0 if no settings are
## bound (headless). The single read used to gate every cosmetic animation (flash/pop/bump/modal pop-in).
func _motion_intensity() -> float:
	return _settings.motion_intensity if _settings != null else 1.0


## Re-entrancy guard: true WHILE a hit-stop freeze is in flight, so two overlapping big
## blasts can't stack freezes (and so a second call can't stomp the restore of the first).
var _in_hitstop: bool = false

## Briefly freeze the game (Engine.time_scale → vfx.hitstop_scale) for `seconds` of REAL
## time, then restore time_scale to 1.0. The "crunch" lever for big breaks / the relic.
##
## Safety contract (a mis-restored or overlapping freeze would soft-lock the whole game):
##  - motion gate: reduced-motion players (motion <= EXPLOSION_MOTION_FLOOR) get no freeze.
##  - paused gate: the Settings overlay pauses the tree; never freeze while paused (the
##    restore timer wouldn't run and the overlay would be stuck slow on resume).
##  - re-entrancy guard (_in_hitstop): a freeze already running → no-op.
##  - the restore timer is created with ignore_time_scale=true (4th arg) so it counts REAL
##    seconds — otherwise it would wait seconds/scale real seconds (≈1s) and feel frozen.
##  - time_scale is ALWAYS restored to 1.0 in every exit path; a smoke test asserts ==1.0.
func _hit_stop(seconds: float) -> void:
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= EXPLOSION_MOTION_FLOOR:
		return
	if seconds <= 0.0:
		return
	if _in_hitstop:
		return
	if get_tree() == null or get_tree().paused:
		return
	_in_hitstop = true
	Engine.time_scale = Registry.vfx_f(_tables, "hitstop_scale", 0.05)
	# ignore_time_scale=true (4th arg) is MANDATORY: the timer must count REAL seconds, not
	# scaled seconds, or the freeze lasts seconds/time_scale and soft-locks.
	await get_tree().create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
	_in_hitstop = false


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
	# Data-driven burst size (vfx.debris_amount_per_cell) so the chunk count is a tunable, not a
	# scene literal. CPUParticles2D.color is the web-safe COLOR source (no process shader).
	fx.amount = Registry.vfx_i(_tables, "debris_amount_per_cell", fx.amount)
	var color: Color = BlockArt.block_color(_tables, block_id) if block_id != "air" else Color(0.7, 0.65, 0.6, 1.0)
	# Slightly vary the debris color so it doesn't look like a flat stamp.
	color = color.lightened(randf_range(0.0, 0.15))
	fx.color = color
	add_child(fx)
	fx.emitting = true
	var ttl: float = fx.lifetime + 0.2
	get_tree().create_timer(ttl).timeout.connect(fx.queue_free)


## Spawn one floating "+$N" value popup at a credited ore cell, tinted by the cell's material.
## Capped at vfx.popup_max_active (live count) so a wide ore vein can't spam labels; $0 dirt
## breaks never call this (caller-gated). The popup is cosmetic + ttl-freed → 0 orphans at exit.
func _spawn_value_popup(cell: Vector2i, amount: int, block_id: String) -> void:
	if amount <= 0:
		return
	var cap: int = Registry.vfx_i(_tables, "popup_max_active", 10)
	if _active_popups >= cap:
		return
	var fx: ValuePopup = VALUE_POPUP_SCENE.instantiate()
	fx.position = Vector2(
		float(cell.x * _bps) + float(_bps) * 0.5,
		float(cell.y * _bps) + float(_bps) * 0.5
	)
	var color: Color = BlockArt.block_color(_tables, block_id) if block_id != "air" else Color(1, 1, 1, 1)
	# Brighten the tint so the label reads on the dark mine even outside the headlamp bubble.
	color = color.lightened(0.35)
	color.a = 1.0
	add_child(fx)
	_active_popups += 1
	fx.play(_tables, amount, color)
	var ttl: float = Registry.vfx_f(_tables, "popup_seconds", 0.6) + 0.1
	get_tree().create_timer(ttl).timeout.connect(_on_popup_freed.bind(fx))


## Free a finished value popup and release its slot in the active-popup cap.
func _on_popup_freed(fx: ValuePopup) -> void:
	_active_popups = maxi(0, _active_popups - 1)
	if is_instance_valid(fx):
		fx.queue_free()


## Spawn one flying reward coin (v0.5 money juice) at a credited ore cell. It pops up then arcs to the
## HUD wallet icon and pops the money HUD on arrival. Capped at coin_max_active (live count) so a wide
## vein can't spawn unbounded sprites; over-budget credits still land in the rolling count-up. Gated
## OFF at motion intensity ~0 (reduced motion — the number still snaps). Cosmetic + ttl-freed → 0
## orphans at exit. The coin lives in WORLD space; the wallet's screen target is projected to world
## once (the camera barely moves over the sub-second flight).
func _spawn_coin(cell: Vector2i, block_id: String) -> void:
	if _hud == null:
		return
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.01:
		return
	if _active_coins >= Registry.coin_max_active(_tables):
		return
	var start_world := Vector2(
		float(cell.x * _bps) + float(_bps) * 0.5,
		float(cell.y * _bps) + float(_bps) * 0.5
	)
	# Project the wallet icon's screen (canvas) position back into world space so the coin homes to it.
	var screen_target: Vector2 = _hud.money_icon_screen_position()
	var ct := get_viewport().get_canvas_transform()
	var target_world: Vector2 = ct.affine_inverse() * screen_target
	var color: Color = BlockArt.block_color(_tables, block_id) if block_id != "air" else Color(1, 1, 1, 1)
	color = color.lightened(0.25)
	color.a = 1.0
	var coin: CoinPickup = COIN_PICKUP_SCENE.instantiate()
	coin.z_index = 11
	add_child(coin)
	_active_coins += 1
	coin.arrived.connect(_on_coin_arrived)
	coin.play(
		start_world, target_world, color,
		Registry.coin_pop_seconds(_tables), Registry.coin_fly_seconds(_tables),
		Registry.coin_arc_height_px(_tables)
	)
	# ttl just past the full pop+fly so a coin always frees even if a tween is interrupted. The timer
	# is process_always + ignore_time_scale so an in-flight coin still frees if the Settings overlay
	# pauses the tree or a hit-stop slows time mid-flight (no leaked coin). Honors the ttl-free pattern.
	var ttl: float = Registry.coin_pop_seconds(_tables) + Registry.coin_fly_seconds(_tables) + 0.2
	get_tree().create_timer(ttl, true, false, true).timeout.connect(_on_coin_freed.bind(coin))


## A coin reached the wallet → pop the money HUD (the count-up already rolls; this lands the kinetic
## reward where the player is looking).
func _on_coin_arrived() -> void:
	if _hud != null:
		_hud.pop_money()


## Free a finished coin and release its slot in the active-coin cap.
func _on_coin_freed(coin: CoinPickup) -> void:
	_active_coins = maxi(0, _active_coins - 1)
	if is_instance_valid(coin):
		coin.queue_free()


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


func _spawn_explosion(center_cell: Vector2i, radius: int = 1) -> void:
	# The explosion is now a LAYERED Node2D (ExplosionFx): a Spark GPUParticles2D child (the
	# web-safe color_ramp spray) plus an additive Flash + Ring scaled by the blast radius. The
	# root stays a DIRECT child of Mine (the smoke test finds the Spark via recursive search).
	var fx: ExplosionFx = EXPLOSION_SCENE.instantiate()
	fx.position = Vector2(
		float(center_cell.x * _bps) + float(_bps) * 0.5,
		float(center_cell.y * _bps) + float(_bps) * 0.5
	)
	fx.z_index = 10
	# Motion-intensity (AC-5.10.1 / AC-5.10.4): scale the cosmetic particle spray. The blast
	# GAMEPLAY already resolved (damage/credit) — only the visual intensity reduces, down to a
	# minimal readable puff at intensity 0 (reduced motion), never zero. The flash/ring are
	# disabled entirely at motion 0 (handled in ExplosionFx.play).
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	var spark: GPUParticles2D = fx.get_node_or_null("Spark")
	if spark != null:
		spark.amount = explosion_particle_count(spark.amount, motion)
	add_child(fx)
	if spark != null:
		spark.emitting = true
	fx.play(_tables, radius, motion)  # flash + ring (scaled by radius, gated on motion)
	Audio.play_detonate()  # AC-5.13.1: detonation cue, co-located with the visual fx
	# Free after the slowest layer's lifetime (the scene is one-shot).
	var spark_life: float = spark.lifetime if spark != null else 0.5
	var ttl: float = maxf(spark_life, Registry.vfx_f(_tables, "ring_seconds", 0.18)) + 0.2
	get_tree().create_timer(ttl).timeout.connect(fx.queue_free)

# ══════════════════════════════════════════════════════════════════════════════
# UI REFRESH
# ══════════════════════════════════════════════════════════════════════════════

## When true, the NEXT _refresh_all_ui rolls the money readout instead of snapping it (the live
## credit path sets this; everything else snaps). Consumed (reset) each refresh so a later non-credit
## refresh — boot, dig start, pack buy — keeps the canonical snap-exact behavior the tests read.
var _animate_money_next_refresh: bool = false


## Reflect the throw-cooldown state on the button fill + countdown label. The fill grows from the
## bottom (1 - progress at the top, full height when done) and is hidden when the cooldown ends.
func _update_cooldown_visual() -> void:
	if _throw_controls == null:
		return
	var cooling: bool = _throw_controls.is_cooling_down
	if _cooldown_fill != null:
		_cooldown_fill.visible = cooling
		# progress 0 → full grey overlay; progress 1 → no overlay (fill scaled to 0 from bottom).
		var p: float = _throw_controls.cooldown_progress
		_cooldown_fill.anchor_top = 1.0 - p
	if _cooldown_label != null:
		_cooldown_label.text = _throw_controls.cooldown_text
		_cooldown_label.visible = cooling


func _refresh_all_ui() -> void:
	if _hud != null:
		# Money: ROLL on the live credit path (v0.5 juice), SNAP everywhere else. set_money stays the
		# deterministic/test-read path (snap-exact); tick_money_to is the separate animated path and
		# snaps to the exact value on finish, so the final readout is identical either way.
		if _animate_money_next_refresh:
			var motion: float = _settings.motion_intensity if _settings != null else 1.0
			_hud.tick_money_to(_economy.money, motion)
		else:
			_hud.set_money(_economy.money)
		var depth: int = _platform.target_row if _platform != null else _run_state.depth
		_hud.set_depth(depth)
		_hud.set_relic_progress(_run_state.relic_collected)
		_hud.set_depth_odds(Registry.band_odds(_tables, depth))
	_rebuild_tray()
	if _throw_button != null:
		var can_throw: bool = _throw_controls.can_throw() if _throw_controls != null else (_active_charge == null)
		_throw_button.disabled = (_run_state.dig_ended or not can_throw)
	_update_cooldown_visual()
	if _buy_pack_button != null:
		# The bottom button now opens the shop modal, not a direct purchase, so it only
		# locks when the dig has ended.
		_buy_pack_button.disabled = _run_state.dig_ended
	if _elevator_up != null:
		_elevator_up.disabled = (_platform == null) or (not _platform.can_move_up())
	if _elevator_down != null:
		_elevator_down.disabled = (_platform == null) or (not _platform.can_move_down())
	# One-shot: consumed so a non-credit refresh always snaps the canonical money label.
	_animate_money_next_refresh = false


## Signature of the last-rendered tray SLOT SET ({id:count} per slot, in order). When only the
## selection changes (the common case — a tap), this is unchanged, so the tray POPS the new slot in
## place (set_selected) instead of a full queue_free/rebuild that would kill any animation + flicker
## the row. A slot-SET change (pack buy / dig start) differs → full rebuild (v0.5 arcade pass).
var _last_tray_signature: String = ""


## Rebuild the tray view from the RunState tray (collapsing duplicate finite charges
## into one slot with a count; the free charge is the first slot with ∞ — AC-5.8.1/2).
## Selection-only changes are routed through TrayUi.set_selected (a non-destructive pop) so the row
## never rebuilds on a tap; only a slot-SET change does a full rebuild.
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
	var signature: String = _tray_signature(slots)
	if signature == _last_tray_signature and _tray.get_child_count() == slots.size():
		# Slot set unchanged → selection-only: pop the tapped slot in place (no rebuild/flicker).
		_tray.set_selected(_run_state.selected_id, _motion_intensity())
		return
	_last_tray_signature = signature
	_tray.rebuild(slots, _run_state.selected_id)


## Stable string signature of the tray slot SET (id+count per slot, in order) — selection-independent
## so a re-select doesn't churn the signature. Used to decide rebuild-vs-pop.
func _tray_signature(slots: Array) -> String:
	var parts: Array = []
	for s in slots:
		parts.append("%s:%d" % [str((s as Dictionary).get("id", "")), int((s as Dictionary).get("count", 0))])
	return "|".join(parts)

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

func _process(delta: float) -> void:
	_update_light_mask()
	_animate_aim_line(delta)
	if _throw_controls != null and _throw_controls.advance_cooldown(delta):
		_update_cooldown_visual()
		_refresh_all_ui()

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
