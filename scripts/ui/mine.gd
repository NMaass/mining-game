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
const DEBUG_OVERLAY_SCRIPT := preload("res://scripts/ui/debug_overlay.gd")
const PIXEL_UI_SCRIPT := preload("res://scripts/ui/pixel_ui.gd")
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
@onready var _shaft_supports: ShaftSupports = get_node_or_null("ShaftSupports")
@onready var _sky: Sprite2D = get_node_or_null("Sky")
@onready var _light_mask: ColorRect = get_node_or_null("LightMaskLayer/LightMask")
@onready var _platform: Platform = get_node_or_null("Platform")
@onready var _preview_line: AimLine = get_node_or_null("AimPreview")
@onready var _aim_reticle: Sprite2D = get_node_or_null("AimReticle")
@onready var _hud: Hud = get_node_or_null("Hud")
@onready var _tray: TrayUi = get_node_or_null("Hud/Bottom/SelectorBar/TrayScroll/Tray")
@onready var _throw_button: Button = get_node_or_null("Hud/Bottom/ActionRow/ThrowButton")
@onready var _cooldown_fill: ColorRect = get_node_or_null("Hud/Bottom/ActionRow/ThrowButton/CooldownFill")
@onready var _cooldown_label: Label = get_node_or_null("Hud/Bottom/ActionRow/ThrowButton/CooldownLabel")
@onready var _buy_pack_button: Button = get_node_or_null("Hud/Bottom/ActionRow/BuyPackButton")
@onready var _mine_select_button: Button = get_node_or_null("Hud/Bottom/ActionRow/MinesButton")
@onready var _elevator_up: Button = get_node_or_null("Hud/ElevatorControls/ElevatorUp")
@onready var _elevator_down: Button = get_node_or_null("Hud/ElevatorControls/ElevatorDown")
@onready var _dig_end_panel: DigEndPanel = get_node_or_null("Hud/DigEndPanel")
@onready var _overlay: SettingsOverlay = get_node_or_null("Overlay")
@onready var _prestige_offer: PrestigeOffer = get_node_or_null("PrestigeOffer")
@onready var _shop_modal: ShopModal = get_node_or_null("ShopModal")
@onready var _mine_select: MineSelect = get_node_or_null("MineSelect")

# ── Systems (delegated logic; no Node deps) ───────────────────────────────────
var _tables: Dictionary
var _grid: BlockGrid
var _economy: Economy
var _run_state: RunState
var _aim: AimController
var _throw_controls: ThrowControls
## The throw button's resting label ("THROW"), stashed while the cooldown countdown is shown so the
## two don't overlap. Restored the frame the cooldown readies.
var _throw_button_label: String = ""
var _save: SaveManager
var _settings: SettingsState
var _debug_overlay: DebugOverlay

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
## Persistent in-world beacon for the 2x2 relic footprint. The relic block itself is a
## normal generated tile (`relic`), while this additive sprite makes the objective read as
## purple/glowing when it enters the camera view. Purely visual; collection is still owned by
## BlockGrid's 4-cell footprint latch.
var _relic_glow: Sprite2D = null
var _relic_glow_time: float = 0.0

# ── Elevator hold-to-move ramp (continuous row-by-row glide while held) ────────
## Pure ramp integrators (one per direction) that turn held time into whole-row steps. Holding the
## up/down BUTTON or the up/down KEY moves the platform CONTINUOUSLY — row by row — ramping from a
## slow start to a capped max (constants in /data, balance.elevator). A tap moves exactly one row
## (the ramp's first-frame guarantee); a long hold glides faster and faster up to the cap. Both are
## reset on release / when the held direction flips, so the next press starts slow again. The actual
## per-row move still goes through the SAME _on_elevator_up()/_on_elevator_down() the tap path uses,
## so the can_move_up/can_move_down clamps and depth sync are shared (one code path).
var _ramp_up := ElevatorRamp.new()
var _ramp_down := ElevatorRamp.new()
## The direction held LAST frame (-1 up / +1 down / 0 none) — so a direction flip resets the ramp.
var _elevator_held_dir: int = 0
## On-screen elevator arrow HELD state (set by button_down/button_up signals from the
## HUD). The keyboard path is polled via Input.is_action_pressed; the on-screen button
## path uses these flags because `pressed` (release) is too late for a tap and polling
## `is_pressed()` alone was unreliable for quick taps. button_down sets the flag the
## instant the arrow is touched, so the hold-poll's first-frame guarantee yields one
## row for a tap and the flag drives the continuous glide for a hold.
var _btn_elevator_up: bool = false
var _btn_elevator_down: bool = false

# ── Layout (all from /data) ───────────────────────────────────────────────────
var _bps: int = 64
var _mine_w: int = 7
var _mine_h: int = 0
var _shaft_w: int = 7
var _shaft_left: int = 0
var _chunk_h: int = 16
var _fuzz_pct: float = 0.0

# ── Mines (session state; no disk persistence — resets on app restart) ────────
## Which mines the player has unlocked this session (id -> true). The starting mine is
## always unlocked; deeper mines are unlocked by paying their access cost in the mine-select.
var _unlocked_mines: Dictionary = {}
## The mine the NEXT _start_dig() will build. Reset to the home mine at each dig start so a
## Deep Mine run is one dig, then play returns to the home mine (re-enter via mine-select).
var _selected_mine_id: String = ""
## The mine the currently-built grid belongs to (so _start_dig only rebuilds on a change).
var _active_mine_id: String = ""

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
		var ok: bool = _save.save_state(state)
		if not ok:
			var logger: Node = get_node_or_null("/root/GameLog")
			if logger != null and logger.has_method("report_error"):
				logger.call("report_error", "Mine", "Save failed — durable state may not have persisted")


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
	# Init-order safety: if data STILL failed to load (a missing/corrupt /data dir), leave evidence
	# on disk before the downstream systems start reading defaults — otherwise a field failure
	# surfaces as a confusing null/zero far from the cause. Logger may not be wired yet under some
	# boot orders, so look it up defensively. Behavior is unchanged (we proceed on /data defaults).
	if _tables.is_empty():
		var logger: Node = get_node_or_null("/root/GameLog")
		if logger != null and logger.has_method("report_warning"):
			logger.call("report_warning", "Mine", "boot: GameData tables empty — running on /data defaults")

	_bps = Registry.block_pixel_size(_tables)
	_mine_w = Registry.mine_width_cells(_tables)
	_mine_h = Registry.mine_height_cells(_tables)
	_shaft_w = Registry.shaft_width(_tables)
	_shaft_left = Registry.shaft_left_cell(_tables)
	_chunk_h = Registry.chunk_height(_tables)
	_fuzz_pct = float(Registry.balance(_tables, "blast_fuzz_pct", 0.0))

	_economy = Economy.new(_tables)
	_run_state = RunState.new(_tables, _economy)
	# Mines (session state): the home mine is always unlocked + selected; deeper mines are
	# unlocked by paying their access cost in the mine-select. Build the home mine's grid.
	_selected_mine_id = Registry.default_mine_id(_tables)
	_unlocked_mines = {_selected_mine_id: true}
	_build_grid_for(_selected_mine_id)
	# Restore persisted progression (prestige points + purchases) so power growth survives an app
	# restart (AC-5.11.1). Per-dig state is not saved. A fresh game / corrupt save loads a clean default.
	_save = SaveManager.new()
	var loaded: Dictionary = _save.load_state()
	_run_state.prestige.from_state(loaded.get("prestige", {}))
	# Settings (AC-5.10.1 / AC-5.11.1): a returning player's saved settings overlay the /data
	# defaults; a fresh game seeds purely from the /data defaults (balance.settings). The keybind
	# DEFAULTS are read from the LIVE InputMap (the project bindings) — never code literals — so a
	# fresh game / an action absent from the save inherits the shipped key.
	var default_binds: Dictionary = _input_map_defaults()
	if _save.has_save():
		_settings = SettingsState.from_state(loaded.get("settings", {}), _tables, default_binds)
	else:
		_settings = SettingsState.from_defaults(_tables, default_binds)

	_build_atlas_mapping()
	_apply_generated_art()
	_wire_aim()
	_wire_throw_controls()
	_wire_ui()
	_wire_overlay()
	_wire_debug_overlay()
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
		# Elevator arrows: button_down starts a move (tap or hold), button_up stops it.
		# The hold poll in _process (_process_elevator_hold) reads the held flags and ramps
		# the speed — a tap moves one row (the ramp's first-frame guarantee), a hold glides.
		# `pressed` (release) is NOT wired to a move (it would double-fire with the poll).
		if not _hud.elevator_up_pressed.is_connected(_on_elevator_up_btn):
			_hud.elevator_up_pressed.connect(_on_elevator_up_btn)
		if not _hud.elevator_up_released.is_connected(_on_elevator_up_btn_released):
			_hud.elevator_up_released.connect(_on_elevator_up_btn_released)
		if not _hud.elevator_down_pressed.is_connected(_on_elevator_down_btn):
			_hud.elevator_down_pressed.connect(_on_elevator_down_btn)
		if not _hud.elevator_down_released.is_connected(_on_elevator_down_btn_released):
			_hud.elevator_down_released.connect(_on_elevator_down_btn_released)
	if _platform != null:
		if not _platform.descended.is_connected(_on_platform_descended):
			_platform.descended.connect(_on_platform_descended)
	if _tray != null:
		_tray.configure(_tables)
		if not _tray.slot_selected.is_connected(_on_tray_slot_selected):
			_tray.slot_selected.connect(_on_tray_slot_selected)
	if _throw_button != null and not _throw_button.pressed.is_connected(_on_throw_button):
		_throw_button.pressed.connect(_on_throw_button)
		PIXEL_UI_SCRIPT.apply_button(_throw_button, "primary", 24)
		PIXEL_UI_SCRIPT.bind_button_feel(_throw_button, Callable(self, "_motion_intensity"))
	if _buy_pack_button != null and not _buy_pack_button.pressed.is_connected(_on_buy_pack_button):
		_buy_pack_button.pressed.connect(_on_buy_pack_button)
		PIXEL_UI_SCRIPT.apply_button(_buy_pack_button, "secondary", 18)
		PIXEL_UI_SCRIPT.bind_button_feel(_buy_pack_button, Callable(self, "_motion_intensity"))
	if _mine_select_button != null and not _mine_select_button.pressed.is_connected(_on_mine_select_button):
		_mine_select_button.pressed.connect(_on_mine_select_button)
		PIXEL_UI_SCRIPT.apply_button(_mine_select_button, "secondary", 18)
		PIXEL_UI_SCRIPT.bind_button_feel(_mine_select_button, Callable(self, "_motion_intensity"))
	for button in [_elevator_up, _elevator_down]:
		if button != null:
			PIXEL_UI_SCRIPT.apply_button(button, "secondary", 22)
			PIXEL_UI_SCRIPT.bind_button_feel(button, Callable(self, "_motion_intensity"))
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
		_shop_modal.configure(
			_tables,
			func() -> int: return _economy.money,
			func(id: String) -> int: return _run_state.upgrade_level(id),
		)
		if not _shop_modal.buy_pressed.is_connected(_on_shop_buy_pressed):
			_shop_modal.buy_pressed.connect(_on_shop_buy_pressed)
		if not _shop_modal.buy_upgrade_pressed.is_connected(_on_shop_buy_upgrade):
			_shop_modal.buy_upgrade_pressed.connect(_on_shop_buy_upgrade)
		if not _shop_modal.closed.is_connected(_on_shop_closed):
			_shop_modal.closed.connect(_on_shop_closed)
	if _mine_select != null:
		_mine_select.configure(
			_tables,
			func() -> int: return _economy.money,
			func(id: String) -> bool: return _unlocked_mines.has(id),
		)
		if not _mine_select.unlock_pressed.is_connected(_on_mine_unlock_pressed):
			_mine_select.unlock_pressed.connect(_on_mine_unlock_pressed)
		if not _mine_select.enter_pressed.is_connected(_on_mine_enter_pressed):
			_mine_select.enter_pressed.connect(_on_mine_enter_pressed)
		if not _mine_select.closed.is_connected(_on_mine_select_closed):
			_mine_select.closed.connect(_on_mine_select_closed)


## Bind the modal Settings overlay (AC-5.8.3) to the shared SettingsState and listen for changes.
func _wire_overlay() -> void:
	if _overlay == null:
		return
	_overlay.configure(_tables, _settings)
	if _save != null:
		_overlay.set_save_persistence_warning(_save.persistence_warning())
	if not _overlay.settings_changed.is_connected(_on_settings_changed):
		_overlay.settings_changed.connect(_on_settings_changed)
	if not _overlay.keybind_rebound.is_connected(_on_keybind_rebound):
		_overlay.keybind_rebound.connect(_on_keybind_rebound)
	if not _overlay.save_export_requested.is_connected(_on_save_export_requested):
		_overlay.save_export_requested.connect(_on_save_export_requested)
	if not _overlay.save_import_requested.is_connected(_on_save_import_requested):
		_overlay.save_import_requested.connect(_on_save_import_requested)


## Attach the toggleable debug overlay in editor/debug exports only. It is intentionally absent from
## release exports so production builds do not ship a discoverable diagnostics HUD.
func _wire_debug_overlay() -> void:
	if not _debug_overlay_enabled():
		return
	if _debug_overlay == null:
		_debug_overlay = DEBUG_OVERLAY_SCRIPT.new()
		_debug_overlay.name = "DebugOverlay"
		add_child(_debug_overlay)
	_debug_overlay.bind_mine(self)


static func _debug_overlay_enabled() -> bool:
	return OS.has_feature("editor") or OS.has_feature("debug")

func _wire_world_guides() -> void:
	if _shaft_supports != null:
		_shaft_supports.configure(_tables, _shaft_left, _shaft_w)
		if not _shaft_supports.support_reached.is_connected(_on_support_reached):
			_shaft_supports.support_reached.connect(_on_support_reached)
	if _sky != null and _sky.texture != null:
		# Cover the sky band [-sky_px, 0] across the full mine width, centered on the mine, so
		# the surface reads as a horizon. Sprite2D is centered, so place the center at the band
		# midpoint and scale the texture to the target rectangle (derived from the real texture size).
		var sky_px: float = float(Registry.balance(_tables, "sky_band_cells", 40)) * float(_bps)
		var mine_w_px: float = float(_mine_w * _bps)
		var tex: Vector2 = _sky.texture.get_size()
		_sky.centered = true
		_sky.position = Vector2(mine_w_px * 0.5, -sky_px * 0.5)
		_sky.scale = Vector2(mine_w_px / maxf(1.0, tex.x), sky_px / maxf(1.0, tex.y))
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
		Audio.play_run_end_jingle()
		Audio.play_music("music_menu")
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


## On-screen elevator UP arrow pressed DOWN (button_down): mark it held so the hold poll
## (_process_elevator_hold) starts the ramped glide. The poll's first-frame guarantee
## moves one row immediately (a tap); a sustained hold glides row-by-row. No move here —
## the poll owns the per-row stepping so there's no double-fire with the release signal.
func _on_elevator_up_btn() -> void:
	_btn_elevator_up = true


## On-screen elevator UP arrow released (button_up): clear the held flag so the poll stops.
func _on_elevator_up_btn_released() -> void:
	_btn_elevator_up = false


## On-screen elevator DOWN arrow pressed DOWN (button_down): mark it held.
func _on_elevator_down_btn() -> void:
	_btn_elevator_down = true


## On-screen elevator DOWN arrow released (button_up): clear the held flag.
func _on_elevator_down_btn_released() -> void:
	_btn_elevator_down = false


## The elevator direction currently HELD via the on-screen buttons or the up/down KEY (-1 up,
## +1 down, 0 none/both). Polled each frame so HOLDING moves continuously. Buttons take precedence
## via is_pressed() (true while a normal button is held); the keyboard actions are also honored so
## the keyboard is the same continuous path. Pressing both directions cancels (0). Headless-safe:
## buttons may be null and the InputMap actions may be absent.
func _elevator_input_dir() -> int:
	var dir: int = 0
	# On-screen buttons (held via button_down/button_up flags — set the instant the arrow
	# is touched, cleared on release). Replaces is_pressed() polling, which was unreliable
	# for quick taps (the button could release before a _process frame caught it).
	if _btn_elevator_up:
		dir -= 1
	if _btn_elevator_down:
		dir += 1
	# Keyboard (held). Skipped in the editor; guarded on the actions existing.
	if not Engine.is_editor_hint():
		if InputMap.has_action("elevator_up") and Input.is_action_pressed("elevator_up"):
			dir -= 1
		if InputMap.has_action("elevator_down") and Input.is_action_pressed("elevator_down"):
			dir += 1
	return signi(dir)


## Continuous hold-to-move (called every frame from _process). Reads the held direction, ramps the
## speed (slow start → capped max, all /data), and steps that many WHOLE rows this frame through the
## SAME single-row _on_elevator_up()/_on_elevator_down() the tap path uses (so the can_move clamps +
## depth sync are shared). Respects can_move_up/can_move_down (a row that can't move just stops the
## glide). No-op while the tree is paused (a modal is open) or the dig has ended; releasing (or a
## direction flip) resets the ramp so the next press starts slow again.
func _process_elevator_hold(delta: float) -> void:
	if _platform == null:
		_reset_elevator_ramps()
		return
	if _tree_paused() or (_run_state != null and _run_state.dig_ended):
		_reset_elevator_ramps()
		return
	var dir: int = _elevator_input_dir()
	# A direction change (incl. release to 0, or a flip) resets BOTH ramps so the new hold starts slow.
	if dir != _elevator_held_dir:
		_reset_elevator_ramps()
		_elevator_held_dir = dir
	if dir == 0:
		return
	if not may_move_elevator(dir, _can_move_up(), _can_move_down(), _tree_paused()):
		# Can't move that way (at a limit) — hold the ramp reset so re-aiming starts fresh.
		_reset_elevator_ramps()
		return
	var ramp: ElevatorRamp = _ramp_up if dir < 0 else _ramp_down
	var rows: int = ramp.advance(
		delta,
		Registry.elevator_start_rows_per_sec(_tables),
		Registry.elevator_accel_rows_per_sec2(_tables),
		Registry.elevator_max_rows_per_sec(_tables),
	)
	for _i in range(rows):
		# Re-check the limit before EACH row so a glide stops cleanly at the top/support boundary.
		if not may_move_elevator(dir, _can_move_up(), _can_move_down(), _tree_paused()):
			break
		if dir < 0:
			_on_elevator_up()
		else:
			_on_elevator_down()


func _reset_elevator_ramps() -> void:
	_ramp_up.reset()
	_ramp_down.reset()
	_elevator_held_dir = 0


## Platform target row changed (auto-descent or manual elevator move): refresh UI so the
## elevator arrows gray at the top/bottom limits and the depth readout stays in sync.
func _on_platform_descended(_new_row: int) -> void:
	_refresh_all_ui()


## A setting changed in the overlay: apply it live (audio/HUD/InputMap) and persist it (AC-5.11.4).
func _on_settings_changed() -> void:
	_apply_settings()
	_save_progress()


func _on_save_export_requested() -> void:
	if _save == null or _overlay == null:
		return
	_save_progress()
	_overlay.set_save_export_text(_save.export_save_text())


func _on_save_import_requested(text: String) -> void:
	var ok := false
	if _save != null:
		ok = _save.import_save_text(text)
	if ok:
		_restore_durable_state_from_save()
	if _overlay != null:
		_overlay.set_save_import_result(ok)


## A keybind capture committed a new key for `action` (the overlay already wrote the SettingsState
## and fires settings_changed too). Mirror just that one action into the live InputMap right away so
## the rebind takes effect mid-dig without waiting for the full _apply_settings pass.
func _on_keybind_rebound(action: String, keycode: int) -> void:
	apply_keybinds_to_input_map({action: keycode})


## Push the current SettingsState into the systems it drives: SFX/Music bus volume now (AC-5.10.1 /
## AC-5.13.2); the HUD text scale; the keybinds into the live InputMap (so the keyboard path honors a
## rebind immediately); and the elevator-controls SIDE into the HUD (left/right layout). The explosion
## motion intensity is read at its spawn site. Safe to call repeatedly (idempotent).
func _apply_settings() -> void:
	if _settings == null:
		return
	Audio.set_sfx_volume_db(_settings.sfx_volume_db())
	Audio.set_music_volume_db(_settings.music_volume_db())
	apply_keybinds_to_input_map(_settings.keybinds())
	if _hud != null:
		_hud.set_text_scale(_settings.text_scale)
		_hud.set_elevator_side(_settings.elevator_side)
		_hud.set_button_motion(_settings.motion_intensity)
	if _tray != null:
		_tray.set_text_scale(_settings.text_scale)
	if _shop_modal != null:
		_shop_modal.set_text_scale(_settings.text_scale)
	if _mine_select != null:
		_mine_select.set_text_scale(_settings.text_scale)
	if _overlay != null:
		_overlay.set_text_scale(_settings.text_scale)


func _restore_durable_state_from_save() -> void:
	if _save == null or _run_state == null:
		return
	var loaded: Dictionary = _save.load_state()
	_run_state.prestige.from_state(loaded.get("prestige", {}))
	var default_binds: Dictionary = _input_map_defaults()
	_settings = SettingsState.from_state(loaded.get("settings", {}), _tables, default_binds)
	_apply_settings()
	_wire_overlay()
	_refresh_all_ui()


## Read the current default keycode for each rebindable action from the live InputMap (the project
## bindings). Returns {action: physical-keycode int}. Used to seed the SettingsState keybind defaults
## so they come from the project map, not code. Skips actions with no key event bound.
func _input_map_defaults() -> Dictionary:
	var out: Dictionary = {}
	for action in SettingsState.KEYBIND_ACTIONS:
		if not InputMap.has_action(action):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var key := ev as InputEventKey
				var kc: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
				if kc > 0:
					out[action] = kc
					break
	return out


## Apply a {action: physical-keycode int} keybind map to the live InputMap (AC-5.10.1 rebindable
## controls). For each known action present in the map, the action's key event(s) are replaced by a
## single InputEventKey on that physical keycode — so the held-aim / fire / elevator keyboard path
## (which checks these same actions) immediately uses the rebound key. Static + InputMap-only so the
## rebind→InputMap behavior is headless-testable (injected key EVENTS don't fire, but this rewrites
## the map directly). Unknown actions and non-positive keycodes are ignored.
static func apply_keybinds_to_input_map(binds: Dictionary) -> void:
	for action in SettingsState.KEYBIND_ACTIONS:
		if not binds.has(action):
			continue
		var keycode: int = int(binds[action])
		if keycode <= 0 or not InputMap.has_action(action):
			continue
		# Drop only this action's KEY events (leave any non-key events — none today — intact), then
		# add the single rebound physical key.
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				InputMap.action_erase_event(action, ev)
		var new_ev := InputEventKey.new()
		new_ev.physical_keycode = keycode
		InputMap.action_add_event(action, new_ev)

# ══════════════════════════════════════════════════════════════════════════════
# DIG LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

## Build (or rebuild) the terrain grid for `mine_id`: a per-mine seed offset gives each mine a
## distinct layout + relic placement, the mine's hardness scales block HP, its ore multiplier
## scales credits, and its tint darkens the terrain view. Reconnects the relic signal onto the
## fresh grid. Called at boot (home mine) and whenever _start_dig enters a different mine.
func _build_grid_for(mine_id: String) -> void:
	var grid_seed: int = Registry.run_seed(_tables) + Registry.mine_seed_offset(_tables, mine_id)
	_grid = BlockGrid.new(_tables, grid_seed, Registry.mine_hardness_mult(_tables, mine_id))
	_grid.relic_collected.connect(_on_relic_collected)
	_economy.set_ore_value_mult(Registry.mine_ore_value_mult(_tables, mine_id))
	if _block_layer != null:
		_block_layer.modulate = Registry.mine_tile_tint(_tables, mine_id)
	_active_mine_id = mine_id
	_refresh_relic_glow()


func _start_dig() -> void:
	_run_state.start_dig()
	# Enter the selected mine (rebuild the grid only when it differs from the active one). The
	# ore multiplier is re-applied here because start_dig → reset_run resets money; the mult and
	# tint persist for whichever mine this dig is in.
	if _selected_mine_id != _active_mine_id:
		_build_grid_for(_selected_mine_id)
	else:
		_economy.set_ore_value_mult(Registry.mine_ore_value_mult(_tables, _active_mine_id))
	# Per "back to the home mine after the relic": the next dig defaults home; re-enter a deeper
	# mine via the mine-select (its unlock persists for the session).
	_selected_mine_id = Registry.default_mine_id(_tables)
	# Reproducible fuzzy blasts: reseed the run-scoped blast RNG from the run seed each
	# dig so a dig is reproducible (AC-5.2.3/5.2.4 — fixed seed → fixed result).
	_blast_rng.seed = Registry.run_seed(_tables)
	# Per-dig money upgrades reset with the dig; reset the shaft clearance back to base width.
	_recompute_shaft()
	# UNIT INFRA (crash-triage #2): if a charge is somehow still alive when a dig (re)starts — e.g.
	# a rebuild raced an in-flight throw — free it FIRST. A stale Charge node still emits `detonated`
	# into _on_charge_detonated and would resolve a blast against the fresh grid at a stale cell.
	# queue_free + nulling the ref is idempotent and behavior-neutral on the normal path (no charge).
	if is_instance_valid(_active_charge):
		(_active_charge as Node).queue_free()
		var logger: Node = get_node_or_null("/root/GameLog")
		if logger != null and logger.has_method("report_warning"):
			logger.call("report_warning", "Mine", "start_dig freed a stale in-flight charge")
	_active_charge = null
	# UNIT INFRA (crash-triage #6): defensively restore time_scale. A hit-stop coroutine ALWAYS
	# restores it, but if its node was freed mid-await (a scene change during the freeze) the restore
	# line never ran and the next dig would boot frozen. Idempotent — a no-op on the normal path.
	Engine.time_scale = 1.0
	if _aim != null:
		_aim.reset_angle()
		_aim.set_enabled(true)
	_scaled_hp_cache.clear()
	_grid.update_window(0, CHUNK_WINDOW_HALF)
	_render_all_loaded_chunks()
	Audio.play_music("music_mining")
	if _dig_end_panel != null:
		_dig_end_panel.hide_panel()
	if _hud != null:
		_hud.set_end_dig_visible(false)
	_refresh_after_state_change()


## Called by BlockGrid when the relic cell breaks (AC-5.6.2). Marks the relic found,
## plays the relic-found cue, and offers prestige: accept banks +1 point and ends the
## dig; decline resumes play. The offer overlay pauses the tree.
func _on_relic_collected(cell: Vector2i) -> void:
	_run_state.relic_found()
	Audio.play_relic_found()
	Audio.play_music("music_relic", 0.12)
	_hide_relic_glow()
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
		Audio.play("prestige_bank")
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
		Audio.play_run_end_jingle()
		Audio.play_music("music_menu")
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
	# Single pure visibility gate (AimLine.preview_visible): the arc is drawn only when a real aim is
	# in play. Phase D — the launch_moving term HIDES the arc + reticle while the platform/elevator or
	# shaft-supports are MOVING (descending/extending), since the launch point is in motion and a drawn
	# arc would be a stale lie. It is redrawn with a freshly recomputed arc when they settle (the
	# _process Phase-D-settle edge re-calls _update_preview).
	if not AimLine.preview_visible(
			_run_state.dig_ended, _active_charge != null, _aim_fading, _aim_is_moving()):
		_clear_preview()
		return
	var params := ThrowParams.from_explosive(_tables, _run_state.selected_id)
	var is_solid := func(cell: Vector2i) -> bool:
		return _grid.is_solid(cell.x, cell.y)
	var path: PackedVector2Array = _aim.preview_path(
		params, _muzzle_position(), is_solid, 240, _bps
	)
	# Reset the cosmetic state the fade-out / a previous throw may have left dimmed, and push the
	# /data feel tunables onto the AimLine (it paints the dashes itself in _draw() — no shader/UV
	# fragility; see reports/aim-line-method.md). The dash PERIOD is in along-line pixels, so it is
	# stable as the arc's pixel length changes each frame.
	_preview_line.width = Registry.feel_f(_tables, "aim_line_width", 2.5)
	_preview_line.dash_px = Registry.feel_f(_tables, "aim_dash_px", 8.0)
	_preview_line.gap_px = Registry.feel_f(_tables, "aim_gap_px", 7.0)
	_preview_line.line_color = Color(1, 1, 0.6, 0.85)  # the old Gradient_aim head color
	_preview_line.alpha_mult = 1.0
	_preview_line.set_points(path)
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
		_preview_line.clear()
	if _aim_reticle != null:
		_aim_reticle.visible = false


## True while the launch point is in motion: the platform descent tween is animating OR the shaft
## supports are extending. The aim arc is hidden during this (Phase D) and redrawn when it settles.
func _aim_is_moving() -> bool:
	if _platform != null and _platform.is_descending:
		return true
	if _shaft_supports != null and _shaft_supports.is_extending:
		return true
	return false


## The effective dash march speed: the /data aim_march_px, but GATED to 0 (a still pattern) when
## motion intensity <= 0 (reduced motion) or while the tree is paused (a modal is open). Pure +
## headless-callable so the gate is unit-testable without sampling shader pixels.
func _aim_march_speed() -> float:
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0:
		return 0.0
	if get_tree() != null and get_tree().paused:
		return 0.0
	return Registry.feel_f(_tables, "aim_march_px", 60.0)


# ── Animated aim line: marching-dash scroll + throw fade-out (v0.5 arcade pass) ──
## True WHILE a throw's fade-out tween is animating the line away — so _update_preview won't
## re-snap the freshly-thrown line back to full while it fades.
var _aim_fading: bool = false
## Accumulated time for the reticle pulse (advanced in _process while the preview is shown). _process
## does not run while the tree is paused (the Settings overlay pauses it), so the pulse naturally
## freezes during a pause; motion-intensity 0 also freezes it.
var _aim_dash_t: float = 0.0
## Current eased march-speed multiplier (1.0 idle → feel.aim_march_aim_mult while actively turning the
## aim with ←/→). Eased toward its target each frame by AimLine.ease_march_mult so the speed-up ramps
## in/out instead of snapping. Resets to 1.0 whenever the preview isn't shown.
var _aim_march_mult: float = 1.0


## Per-frame cosmetic animation for the aim line + reticle. The MARCHING DASH now advances CONTINUOUSLY
## while the preview is on screen (not only while dragging) — gated only on the reduced-motion /
## paused contract via _aim_march_speed() (which zeroes the speed so the dashes hold still but stay
## visible — no shader TIME). It SPEEDS UP while the player is actively turning the aim (holding ←/→):
## the effective march speed is base × an eased multiplier (1.0 → feel.aim_march_aim_mult), easing
## back to base on release. _process is suspended while the tree is paused (the Settings overlay), so
## nothing here runs during a modal — and the gate also zeroes the march. Called from _process.
func _animate_aim_line(delta: float) -> void:
	if _preview_line == null:
		return
	# No arc on screen → nothing to crawl; reset the boost so the next aim starts at base speed.
	if not _preview_line.has_points():
		_aim_march_mult = 1.0
		return
	# Speed-up while actively aiming (←/→ held). Drag-aim doesn't trigger the boost (it's a discrete
	# pointer angle, not a continuous turn); the keyboard hold is the "actively turning" signal.
	var aiming: bool = _keyboard_aim_dir() != 0
	_aim_march_mult = AimLine.ease_march_mult(
		_aim_march_mult,
		aiming,
		Registry.feel_f(_tables, "aim_march_aim_mult", 2.6),
		Registry.feel_f(_tables, "aim_march_ease_rate", 8.0),
		delta,
	)
	# March the dashes toward the tip. _aim_march_speed() returns 0 for reduced motion / paused, and
	# advance_march(0) holds the pattern still (still drawn, just not crawling).
	_preview_line.advance_march(delta * _aim_march_speed() * _aim_march_mult)
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if motion <= 0.0:
		# Reduced motion: hold a steady reticle (the dash is already frozen by the march gate).
		if _aim_reticle != null:
			_aim_reticle.scale = Vector2(0.22, 0.22)
		return
	_aim_dash_t += delta * Registry.feel_f(_tables, "aim_scroll_speed", 60.0)
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


# ── Keyboard controls (D1) — a THIRD input path through the SAME logic (AC-5.3.7) ──
# Held aim_left/aim_right glide the launch angle in _process; fire / elevator_up / elevator_down
# are edge-triggered in _input. None of them introduce new game logic — fire routes through the
# very same _on_throw_button() the on-screen button does, and the elevator keys call the same
# _on_elevator_up()/_on_elevator_down() the arrows do. The guards below mirror the existing
# button-disabled rules so the keyboard can never do something the buttons couldn't, and nothing
# fires while the tree is paused (a modal/Settings overlay is open).

## Pure guard: may a throw be committed right now? Mirrors the throw-button enabled rule + the
## _on_throw_button → throw_at path (AC-5.3.3/5.3.8): not while the dig ended, not while a charge
## is already in flight, not during the throw cooldown, and not while a modal pauses the tree.
## Takes primitives so it is headless-testable (key events don't fire headless).
static func may_fire(dig_ended: bool, charge_in_flight: bool, can_throw: bool, paused: bool) -> bool:
	if paused:
		return false
	if dig_ended:
		return false
	if charge_in_flight:
		return false
	return can_throw

## Pure guard: may the elevator move in `dir` (-1 up, +1 down) right now? Mirrors the elevator-arrow
## disabled rule (AC-5.7.2): only when the platform reports it can move that way, and never while a
## modal pauses the tree. `can_up`/`can_down` are Platform.can_move_up()/can_move_down().
static func may_move_elevator(dir: int, can_up: bool, can_down: bool, paused: bool) -> bool:
	if paused:
		return false
	if dir < 0:
		return can_up
	if dir > 0:
		return can_down
	return false


## Edge-triggered keyboard actions (fire + elevator). Runs through the SAME handlers as the on-screen
## buttons after the pure guards pass. Held-aim is in _process (Input.is_action_pressed), per the
## "held in _process, edge in _input" split. Nothing here fires while the tree is paused (a modal is
## open) — the guards check it, and the actions themselves no-op when their button rule isn't met.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		if _may_fire_now():
			_on_throw_button()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("elevator_up") or event.is_action_pressed("elevator_down"):
		# Elevator keys are handled by the HOLD poll in _process (_process_elevator_hold) so HOLDING
		# the key glides the platform continuously (ramping to a capped speed), exactly like holding
		# the on-screen button — a single shared continuous path. We only consume the press edge here
		# so it doesn't fall through to another action; the poll does the actual row stepping.
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cycle_charge"):
		# Tab cycles the selected tray charge (free → each finite type → wrap). No-op while paused
		# or after the dig ended. Routes through the same selection state the tray taps use.
		if not _tree_paused() and not _run_state.dig_ended:
			_run_state.select_next()
			_refresh_after_state_change()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("select_next") or event.is_action_pressed("select_prev"):
		# Q/E (select_prev/select_next) step the hotbar selection by ±1 over the VISIBLE owned-only
		# slots, wrapping. Edge-triggered (a tap = one step). ←/→ are aim-only (aim_left/aim_right,
		# polled in _process) so no key does two things by press duration (AC-5.3.7: no timing-precision
		# inputs). Tab (cycle_charge) and the 1..9 number keys also select. No-op while paused or after
		# the dig ended. Routes through select_relative → select_charge (the shared path).
		if not _tree_paused() and not _run_state.dig_ended:
			select_relative(1 if event.is_action_pressed("select_next") else -1)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			var index := _slot_hotkey_index(key)
			if index >= 0:
				if not _tree_paused() and _run_state != null and not _run_state.dig_ended:
					select_tray_slot_index(index)
				get_viewport().set_input_as_handled()


## Held-aim direction this frame from the keyboard: -1 (aim_left), +1 (aim_right), 0 (none/both).
## Pressing both cancels (no net nudge). Read in _process so the angle glides smoothly while held.
func _keyboard_aim_dir() -> int:
	if Engine.is_editor_hint():
		return 0
	if not (InputMap.has_action("aim_left") and InputMap.has_action("aim_right")):
		return 0
	var dir: int = 0
	if Input.is_action_pressed("aim_left"):
		dir -= 1
	if Input.is_action_pressed("aim_right"):
		dir += 1
	return dir


## Apply one frame of held-keyboard aim: nudge the AimController angle by the data-driven rate.
## No-op while the tree is paused (a modal is open), the dig ended, a charge is in flight, or no key
## is held. Uses the SAME AimController angle API the drag path mutates, so the preview + platform
## look-ahead update through the existing angle_changed signal (one shared aim path, AC-5.3.1/5.3.7).
func _apply_keyboard_aim(delta: float) -> void:
	if _aim == null or _tree_paused():
		return
	if _run_state == null or _run_state.dig_ended or _active_charge != null:
		return
	var dir: int = _keyboard_aim_dir()
	if dir == 0:
		return
	var rate: float = Registry.feel_f(_tables, "keyboard_aim_deg_per_sec", 90.0)
	var next_angle: float = Aim.keyboard_angle_step(_aim.angle, dir, rate, delta)
	if next_angle != _aim.angle:
		_aim.set_angle(next_angle)


# ── Thin instance-side reads feeding the pure guards (so the guards stay primitive + testable) ──
func _tree_paused() -> bool:
	return get_tree() != null and get_tree().paused

func _can_move_up() -> bool:
	return _platform != null and _platform.can_move_up()

func _can_move_down() -> bool:
	return _platform != null and _platform.can_move_down()

func _may_fire_now() -> bool:
	var can_throw: bool = _throw_controls.can_throw() if _throw_controls != null else (_active_charge == null)
	return may_fire(_run_state.dig_ended, _active_charge != null, can_throw, _tree_paused())


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
	# The on_rest motion gate (data-driven): an on_rest charge may only resolve via the sleeping path
	# after it has actually moved, so a freshly-launched body that reports sleeping=true on frame 0
	# (before Rapier integrates the impulse) can't detonate in mid-air — the "sticky bomb explodes
	# instantly" fix. Code-side floors apply when these keys are absent.
	var min_airtime: float = float(Registry.balance(_tables, "charge_min_airtime_seconds", -1.0))
	var min_travel: float = float(Registry.balance(_tables, "charge_min_travel_px", -1.0))
	var sticky_delay: float = float(Registry.balance(_tables, "sticky_min_delay_seconds", -1.0))
	charge.setup(params, _muzzle_position(), _bps, min_airtime, min_travel, sticky_delay)
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
	# A finite charge was just consumed (count changed) — push the tray so the hotbar count / a
	# now-empty finite type updates. State-change path → tray pushed here, not in _refresh_all_ui.
	_push_tray()
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
	if motion <= 0.0 or _preview_line.point_count() == 0:
		_clear_preview()
		return
	_aim_fading = true
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(_preview_line, "alpha_mult", 0.0, 0.18).set_ease(Tween.EASE_OUT)
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
		_preview_line.alpha_mult = 1.0
		_preview_line.width = Registry.feel_f(_tables, "aim_line_width", 2.5)
	if _aim_reticle != null:
		_aim_reticle.modulate.a = 0.9


## Select a tray charge (AC-5.3.6). Free charge is always selectable.
func select_charge(charge_id: String) -> bool:
	var ok: bool = _run_state.select(charge_id)
	if ok:
		_refresh_after_state_change()
	return ok


## Select visible tray slot `index` (0-based) from keyboard hotkeys 1-9. Owned checks still live in
## RunState.select, so locked slots never bypass economy/tray rules.
func select_tray_slot_index(index: int) -> bool:
	if _tray == null or index < 0:
		return false
	var ids: Array = _tray.slot_ids()
	if index >= ids.size():
		Audio.play("button_disabled")
		return false
	var ok := select_charge(str(ids[index]))
	if not ok:
		Audio.play("button_disabled")
	return ok


## Step the selection ±1 within the VISIBLE hotbar slots (←/→ arrows + Q/E), wrapping at the ends.
## Pure index math over the tray's owned-only `slot_ids()` (which IS the selectable set, free first),
## so it stays truthful with the number badges. No-op headless if the tray is absent. Returns true if
## a (possibly same, when only one slot) selection landed. The selection itself routes through
## select_charge → RunState.select, the same path taps + number keys use.
func select_relative(step: int) -> bool:
	if _tray == null:
		return false
	var ids: Array = _tray.slot_ids()
	if ids.is_empty():
		return false
	var cur: int = ids.find(_run_state.selected_id)
	if cur < 0:
		cur = 0
	var n: int = ids.size()
	var nxt: int = ((cur + step) % n + n) % n  # wrap both directions
	return select_charge(str(ids[nxt]))


## Map a digit key (1..9) to a 0-based visible-slot index, or -1 if not a digit. Pure (no tree/state),
## so the number-key→index mapping is unit-testable without firing input events (which don't fire
## headless). Slots past 9 have no key (their badge is blank) — only 1..9 map.
static func slot_index_for_keycode(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	return -1


func _slot_hotkey_index(key: InputEventKey) -> int:
	var kc: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
	return slot_index_for_keycode(kc)


func _on_tray_slot_selected(charge_id: String) -> void:
	select_charge(charge_id)


func _on_buy_pack_button() -> void:
	if _shop_modal != null:
		Audio.play_music("music_shop")
		_shop_modal.open(_motion_intensity())


## Buy a pack by id (AC-5.12.2). Delegates to RunState (debit + grant). Refreshes the UI.
func buy_pack(pack_id: String) -> bool:
	var ok: bool = _run_state.buy_pack(pack_id)
	if ok:
		Audio.play_pack_open()  # AC-5.13.1
		_refresh_all_ui()
		# New charges granted (slot SET changed) — push the tray so the new types appear. State-change
		# path → tray pushed here, not in _refresh_all_ui.
		_push_tray()
	return ok


## A pack was bought from the shop modal: play the cue (already inside buy_pack), close
## the modal, and refresh the UI. If the buy is rejected (shouldn't happen when the button
## is disabled), leave the modal open so the player can pick something else.
func _on_shop_buy_pressed(pack_id: String) -> void:
	if buy_pack(pack_id) and _shop_modal != null:
		_shop_modal.play_pack_reveal(pack_id, _run_state.last_pack_result(), _motion_intensity())


func _on_shop_closed() -> void:
	if _run_state != null and not _run_state.dig_ended:
		Audio.play_music("music_mining")


## A per-dig MONEY upgrade (Shaft Engineering) was bought from the shop. Debit + record
## the level, apply it immediately (narrows the remaining descent), refresh the UI, and
## keep the modal open (so the player can buy more / see it flip to OWNED). Returns true on
## success. Resets next dig (per-dig, no persistence).
func buy_money_upgrade(upgrade_id: String) -> bool:
	if _run_state == null or not _run_state.buy_money_upgrade(upgrade_id):
		return false
	_recompute_shaft()
	_check_descent()  # the narrower requirement may already clear a layer (grid is loaded mid-dig)
	Audio.play_upgrade_purchase()
	_refresh_all_ui()
	if _shop_modal != null:
		_shop_modal.refresh()
	return true


func _on_shop_buy_upgrade(upgrade_id: String) -> void:
	buy_money_upgrade(upgrade_id)


# ── Mine select (dedicated screen; session unlock, money-gated) ───────────────

## Open the mine-select screen (HUD button). Pauses the tree like the other modals.
func _on_mine_select_button() -> void:
	if _mine_select != null:
		Audio.play_music("music_menu")
		_mine_select.open(_motion_intensity())


func _on_mine_select_closed() -> void:
	if _run_state != null and not _run_state.dig_ended:
		Audio.play_music("music_mining")


## Unlock access to `mine_id` by paying its one-time access cost from this dig's money. The
## unlock persists for the session (no disk save). Returns true on success. Keeps the modal open.
func unlock_mine(mine_id: String) -> bool:
	if _unlocked_mines.has(mine_id):
		return true
	var cost: int = Registry.mine_access_cost(_tables, mine_id)
	if not _economy.debit(cost):
		return false
	_unlocked_mines[mine_id] = true
	Audio.play_upgrade_purchase()
	_refresh_all_ui()
	if _mine_select != null:
		_mine_select.refresh()
	return true


func _on_mine_unlock_pressed(mine_id: String) -> void:
	unlock_mine(mine_id)


## Enter `mine_id`: it becomes the mine the next dig builds, then a fresh dig starts in it.
## Rejected if the mine is not unlocked (the UI should prevent this). Closes the modal.
func enter_mine(mine_id: String) -> bool:
	if not _unlocked_mines.has(mine_id):
		return false
	_selected_mine_id = mine_id
	if _mine_select != null:
		_mine_select.close()
	_start_dig()
	return true


func _on_mine_enter_pressed(mine_id: String) -> void:
	enter_mine(mine_id)

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
	_refresh_after_state_change()

	# Hit-stop on a BIG break (>= vfx.hitstop_min_cells cleared) — a brief Engine.time_scale
	# freeze that lands the "crunch". Free 1-cell taps never freeze. Fire-and-forget (NOT
	# awaited) so resolve_blast returns the result synchronously for the smoke test; the
	# coroutine self-restores time_scale. Gated on motion intensity inside _hit_stop.
	if cleared_count >= Registry.vfx_i(_tables, "hitstop_min_cells", 6):
		_hit_stop(Registry.vfx_f(_tables, "hitstop_seconds", 0.05))
	return result


## After a blast, check whether the full shaft-width layer(s) below the current
## support depth are cleared. If so, extend the supports down to the deepest
## consecutive cleared layer; the platform will follow when the support animation
## emits `support_reached`.
## Recompute the effective shaft clearance width from the current per-dig money upgrades
## (Shaft Engineering) and reconfigure the supports + re-check gating. Called at dig start
## (upgrades reset → base width) and immediately after a purchase (narrows the remaining
## descent). The current support depth is preserved so already-cleared layers stay supported.
func _recompute_shaft() -> void:
	var reduction: int = _run_state.shaft_width_reduction() if _run_state != null else 0
	_shaft_w = Registry.effective_shaft_width(_tables, reduction)
	_shaft_left = Registry.effective_shaft_left_cell(_tables, _shaft_w)
	if _shaft_supports != null:
		var keep_row: int = _platform.support_row if _platform != null else 0
		_shaft_supports.configure(_tables, _shaft_left, _shaft_w, keep_row)
	# NOTE: callers that run mid-dig (grid window loaded) follow this with _check_descent();
	# _start_dig deliberately does NOT, because the chunk window isn't loaded yet and a scan
	# would read unloaded cells as air and march the supports to the bottom.


func _check_descent() -> void:
	if _platform == null or _shaft_supports == null:
		return
	var support_row: int = _platform.support_row
	# UNIT MAPGEN (infinite shaft): there is no mine floor to scan to, so we walk a BOUNDED
	# window at a time and re-scan from the advanced row, looping until the supports stop
	# advancing. This finds the deepest contiguous cleared row (matching the old full-height
	# scan) WITHOUT an unbounded single scan — the loop terminates as soon as a solid row blocks.
	var bottom: int = Registry.mine_bottom_row(_tables)
	var window: int = _descent_scan_rows()
	var row: int = support_row
	while row < bottom:
		var max_row: int = mini(bottom, row + window)
		var hp_grid: Dictionary = _hp_grid_for_support_scan(row, max_row)
		var next_row: int = PlatformLogic.next_support_row(hp_grid, row, _shaft_w, max_row, _shaft_left)
		if next_row <= row:
			break  # a solid row blocks descent — stop (terminates the loop, bounded)
		row = next_row
	if row > support_row:
		_platform.support_row = row
		_shaft_supports.advance_to(row)


## How many rows below the current support the descent scan inspects per step. The platform
## can only advance through contiguous cleared rows; a window of descent_max_steps (+ one blast
## radius of slack) keeps each scan bounded in the infinite shaft (a full-height scan would be
## unbounded). _check_descent loops over these windows until the supports stop advancing.
func _descent_scan_rows() -> int:
	var steps: int = maxi(1, Registry.descent_max_steps(_tables))
	var slack: int = maxi(1, int(Registry.balance(_tables, "max_blast_radius_cells", 4)))
	return steps + slack


## Build the {Vector2i: hp} grid for the rows that could become supported next.
## Scans from just below the current support row down to `max_row` (the bounded window).
func _hp_grid_for_support_scan(support_row: int, max_row: int) -> Dictionary:
	var out: Dictionary = {}
	for ry in range(support_row + 1, max_row + 1):
		for x in range(_shaft_left, _shaft_left + _shaft_w):
			out[Vector2i(x, ry)] = _grid.get_hp(x, ry)
	return out


## The supports finished extending to `row`; lower the platform to that depth,
## re-window chunks, and refresh the HUD depth readout.
func _on_support_reached(row: int) -> void:
	if _platform == null:
		return
	if not _platform.descend_to(row):
		# Already there (e.g. player manually lowered) — still refresh depth readout.
		_run_state.depth = row
		_refresh_all_ui()
		return
	_run_state.depth = row
	var center_chunk: int = _grid.cell_to_chunk(row)
	_grid.update_window(center_chunk, CHUNK_WINDOW_HALF)
	_render_chunk_diff()
	if _hud != null:
		_hud.set_depth(row)
		_hud.bump_depth()
	Audio.play_descend()  # AC-5.13.1
	_refresh_all_ui()

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

## Cache for scaled_block_hp per (block_id, row) — avoids ~3 balance lookups per cell
## per re-render (PERF-02). Cleared at dig start; entries are stable within a dig.
var _scaled_hp_cache: Dictionary = {}

func _cached_scaled_block_hp(block_id: String, row: int) -> int:
	var key: String = "%s_%d" % [block_id, row]
	if _scaled_hp_cache.has(key):
		return int(_scaled_hp_cache[key])
	var v: int = Registry.scaled_block_hp(_tables, block_id, row, _grid.mine_hardness_mult)
	_scaled_hp_cache[key] = v
	return v

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

## Incremental render: erase unloaded chunks, render only newly-loaded ones (PERF-02).
## Avoids the full clear + re-render of all ~44,800 resident cells on every descent.
func _render_chunk_diff() -> void:
	if _block_layer == null:
		return
	for chunk_y in _grid.just_unloaded_chunks():
		var base_y_u: int = chunk_y * _chunk_h
		for ly in range(_chunk_h):
			var y_u: int = base_y_u + ly
			for lx in range(_mine_w):
				var cell_u := Vector2i(lx, y_u)
				_block_layer.erase_cell(cell_u)
				if _crack_layer != null:
					_crack_layer.erase_cell(cell_u)
	for chunk_y in _grid.newly_loaded_chunks():
		var base_y_n: int = chunk_y * _chunk_h
		for ly in range(_chunk_h):
			var y_n: int = base_y_n + ly
			if _mine_h > 0 and y_n >= _mine_h:
				continue
			for lx in range(_mine_w):
				_render_cell(lx, y_n)


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
	var max_hp: int = _cached_scaled_block_hp(block_id, cell_y)
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
##
## FX-timer policy under hit-stop: world fx (debris, explosion, relic pulse, value popups) use
## SCALED timers (no ignore_time_scale) so they freeze WITH the frame — the freeze-frame sells
## weight because the whole world stops. UI feedback fx (muzzle flash, coin fly) use REAL timers
## (ignore_time_scale=true) so they keep playing during the freeze — the player still sees feedback.
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


func _refresh_relic_glow() -> void:
	if _grid == null:
		return
	_ensure_relic_glow()
	if _relic_glow == null:
		return
	var anchor: Vector2i = _grid.relic_cell
	if anchor.y < 0 or _grid.relic_collected_already:
		_relic_glow.visible = false
		return
	_relic_glow.position = Vector2(
		float(anchor.x * _bps) + float(_bps),
		float(anchor.y * _bps) + float(_bps)
	)
	# Cover the 2x2 relic plus one block of falloff on every side.
	var desired_px: float = float(_bps) * 4.0
	var tex_size: Vector2 = _relic_glow.texture.get_size() if _relic_glow.texture != null else Vector2(128, 128)
	_relic_glow.scale = Vector2.ONE * (desired_px / maxf(1.0, tex_size.x))
	_relic_glow.visible = true


func _ensure_relic_glow() -> void:
	if _relic_glow != null and is_instance_valid(_relic_glow):
		return
	_relic_glow = Sprite2D.new()
	_relic_glow.name = "RelicGlow"
	_relic_glow.centered = true
	_relic_glow.z_index = 1
	_relic_glow.texture = _build_relic_glow_texture()
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_relic_glow.material = mat
	var color: Color = Registry.relic_glow_color(_tables)
	color.a = 0.55
	_relic_glow.modulate = color
	var parent: Node = get_node_or_null("BlockGrid")
	if parent == null:
		parent = self
	parent.add_child(_relic_glow)


func _build_relic_glow_texture() -> ImageTexture:
	var size: int = 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size) * 0.5, float(size) * 0.5)
	var radius: float = float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d: float = clampf(p.distance_to(center) / radius, 0.0, 1.0)
			var alpha: float = pow(1.0 - d, 2.2)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


func _hide_relic_glow() -> void:
	if _relic_glow != null and is_instance_valid(_relic_glow):
		_relic_glow.visible = false


func _update_relic_glow(delta: float) -> void:
	if _relic_glow == null or not is_instance_valid(_relic_glow) or not _relic_glow.visible:
		return
	_relic_glow_time += delta
	var pulse_seconds: float = maxf(0.1, Registry.relic_glow_pulse_seconds(_tables))
	var wave: float = 0.5 + 0.5 * sin((TAU * _relic_glow_time) / pulse_seconds)
	var color: Color = Registry.relic_glow_color(_tables)
	color.a = lerpf(0.35, 0.72, wave)
	_relic_glow.modulate = color


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


## Reflect the throw-cooldown on the button: a top-anchored dark overlay that DRAINS by HEIGHT
## (size-driven, immune to the old anchor/offset bug) + a numeric countdown + a desaturated button.
## Driven every frame from ThrowControls (the single clock) and never from the explosion/detonation —
## the timer is a pure readout, armed the instant throw_at() releases the charge.
func _update_cooldown_visual() -> void:
	if _throw_controls == null:
		return
	var cooling: bool = _throw_controls.is_cooling_down
	# remaining_frac: 1.0 = just thrown (full dark band), 0.0 = ready (band gone).
	var remaining_frac: float = clampf(1.0 - _throw_controls.cooldown_progress, 0.0, 1.0)
	if _cooldown_fill != null:
		_cooldown_fill.visible = cooling
		if cooling and _throw_button != null:
			# Top-anchored linear drain: a full-width band covering the TOP `remaining_frac` of the
			# button, shrinking to nothing as it readies. Absolute SIZE from the top edge — no anchor
			# vs. offset fight (the old "dead timer" bug), so it visibly drains every frame.
			var bw: float = _throw_button.size.x
			var bh: float = _throw_button.size.y
			_cooldown_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
			_cooldown_fill.position = Vector2.ZERO
			_cooldown_fill.size = Vector2(bw, bh * remaining_frac)
	if _cooldown_label != null:
		_cooldown_label.text = _throw_controls.cooldown_text  # "" when ready
		_cooldown_label.visible = cooling
	# Affordance: while cooling, desaturate the whole button AND blank its "THROW" label so the
	# countdown reads clearly (the two overlapped + muddied each other otherwise). Restore on ready.
	if _throw_button != null:
		_throw_button.modulate = Color(0.55, 0.55, 0.6, 1.0) if cooling else Color.WHITE
		if cooling:
			if _throw_button.text != "":
				_throw_button_label = _throw_button.text
				_throw_button.text = ""
		elif _throw_button_label != "":
			_throw_button.text = _throw_button_label
			_throw_button_label = ""


## Single entry point for "the dig state just changed, re-sync the view": refreshes the whole HUD
## then recomputes the aim preview. The two are almost always needed together after a state change
## (a throw resolved, a charge was selected, the dig started/ended), so callers route through here
## instead of remembering to call both. Pure mechanical pairing — no behavior change vs. calling
## `_refresh_all_ui()` then `_update_preview()` back-to-back at the call site.
func _refresh_after_state_change() -> void:
	_refresh_all_ui()
	_push_tray()
	_update_preview()


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
	# NOTE: the tray hotbar is INTENTIONALLY NOT pushed here. Geometry of the selector bar is a
	# function of the OWNED SLOT SET only, so a generic refresh — especially a per-frame platform
	# move (_on_elevator_*, _on_platform_descended) — must never touch it (requirement 4: the hotbar
	# must not rebuild/jump on platform movement). Tray pushes live ONLY in the state-change paths via
	# _push_tray() (select/cycle/throw/buy/dig-start/relic), wired through _refresh_after_state_change
	# and the explicit buy/throw/prestige sites. See _push_tray for the signature rebuild-vs-pop gate.
	if _throw_button != null:
		var can_throw: bool = _throw_controls.can_throw() if _throw_controls != null else (_active_charge == null)
		_throw_button.disabled = (_run_state.dig_ended or not can_throw)
	_update_cooldown_visual()
	if _buy_pack_button != null:
		# The bottom button now opens the shop modal, not a direct purchase, so it only
		# locks when the dig has ended.
		_buy_pack_button.disabled = _run_state.dig_ended
	if _mine_select_button != null:
		_mine_select_button.disabled = _run_state.dig_ended
	# Elevator buttons: HIDE (not just disable) the direction you can't go — up vanishes at the top
	# of the reachable area, down vanishes at the bottom (can_move_up/down already track the
	# supported, row-by-row reachable span). Also hidden entirely while the dig has ended. The two
	# buttons sit at FIXED slots in the HUD, so hiding one never moves the other (set_elevator_*_visible
	# is pure show/hide — the up slot stays upper, the down slot stays lower).
	if _hud != null:
		var can_up: bool = (not _run_state.dig_ended) and (_platform != null) and _platform.can_move_up()
		var can_down: bool = (not _run_state.dig_ended) and (_platform != null) and _platform.can_move_down()
		_hud.set_elevator_up_visible(can_up)
		_hud.set_elevator_down_visible(can_down)
	# One-shot: consumed so a non-credit refresh always snaps the canonical money label.
	_animate_money_next_refresh = false


## Signature of the last-rendered tray SLOT SET ({id:count} per slot, in order). When only the
## selection changes (the common case — a tap), this is unchanged, so the tray POPS the new slot in
## place (set_selected) instead of a full queue_free/rebuild that would kill any animation + flicker
## the row. A slot-SET change (pack buy / dig start) differs → full rebuild (v0.5 arcade pass).
var _last_tray_signature: String = ""


## Push the current tray state to the hotbar view (collapsing duplicate finite charges into one slot
## with a count; the free charge is the first slot with ∞ — AC-5.8.1/2). Called ONLY from the
## state-change paths (NOT from the generic _refresh_all_ui), so a platform move can never churn the
## row (requirement 4). Internally decides rebuild-vs-pop via the SLOT-SET signature: a slot-set
## change (pack buy / charge consumed / dig start) does a full rebuild; a selection-only change routes
## through TrayUi.set_selected (a non-destructive in-place pop, itself idempotent on a re-select).
func _push_tray() -> void:
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
	if signature == _last_tray_signature and _tray.get_child_count() > 0:
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
		_refresh_after_state_change()

## Tracks whether the launch point was MOVING last frame (platform/supports), so the aim arc can
## be redrawn the instant the motion settles (Phase D: the `descended` signal fires when the tween
## STARTS, not finishes, so a tween-finish hook alone wouldn't catch the settle).
var _aim_was_moving: bool = false

## Last light_uv pushed to the headlamp shader, so _update_light_mask can skip the
## set_shader_parameter on idle frames where the platform/camera (and thus the UV) hasn't moved.
## NAN sentinel forces the first computed value through.
var _last_light_uv: Vector2 = Vector2(NAN, NAN)


func _process(delta: float) -> void:
	_update_light_mask()
	_update_relic_glow(delta)
	# Held keyboard aim (D1): glide the launch angle while aim_left/aim_right is held. Done in
	# _process via Input.is_action_pressed (the "held → poll" half), so the angle moves smoothly
	# every frame, not once per key event. Gated (paused/dig-ended/in-flight) inside the helper.
	_apply_keyboard_aim(delta)
	# Phase D settle: redraw the aim arc the frame the platform/supports stop moving (they hid it
	# while in flight). _update_preview is itself gated, so re-calling when stopped is the redraw.
	var moving: bool = _aim_is_moving()
	if _aim_was_moving and not moving:
		_update_preview()
	_aim_was_moving = moving
	_animate_aim_line(delta)
	# Continuous elevator hold (button or key held → ramped row-by-row glide). Polled here so a HOLD
	# moves every frame, not once per click — a tap still moves exactly one row (the ramp's first-frame
	# guarantee). Gated (paused/dig-ended/limits) inside the helper.
	_process_elevator_hold(delta)
	# Throw cooldown: advance the clock and refresh the readout EVERY frame while cooling, fully
	# independent of the charge/explosion. The cooldown is a pure timer armed on release in throw_at();
	# nothing about the blast drives it. advance_cooldown() returns true only on the expiry tick — we
	# use that edge to re-sync the rest of the HUD (button re-enable) exactly once, but the fill/label
	# must update every frame in between (that was the "dead timer" bug — it only refreshed on expiry).
	if _throw_controls != null and _throw_controls.is_cooling_down:
		var just_expired: bool = _throw_controls.advance_cooldown(delta)
		_update_cooldown_visual()
		if just_expired:
			_refresh_all_ui()  # re-enable the button etc. exactly once, on the ready edge

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
	var light_uv := Vector2(screen_pos.x / viewport_size.x, screen_pos.y / viewport_size.y)
	# Dirty check: the platform/camera is settled most frames, so the UV is identical frame to frame.
	# Skip the shader write (and its uniform upload) when it hasn't changed since last frame.
	if light_uv.is_equal_approx(_last_light_uv):
		return
	_last_light_uv = light_uv
	mat.set_shader_parameter("light_uv", light_uv)

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

# ── DEBUG-OVERLAY READ-ONLY VIEWS (UNIT INFRA) ─────────────────────────────────
# Consumed by DebugOverlay via has_method/call so it never hard-depends on the controller's
# internals. All read-only — toggling the overlay can never change game state.

## The active run seed (the dig's reproducibility key). Pre-boot → 0.
func debug_run_seed() -> int:
	return Registry.run_seed(_tables) if not _tables.is_empty() else 0

## Current depth in cells, or 0 before the run state is built.
func debug_depth() -> int:
	return _run_state.depth if _run_state != null else 0

## The currently-selected charge id, or "" before the run state is built.
func debug_selected_charge() -> String:
	return _run_state.selected_id if _run_state != null else ""

## The id of the mine the live grid belongs to.
func debug_mine_id() -> String:
	return _active_mine_id
