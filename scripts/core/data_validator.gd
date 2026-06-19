class_name DataValidator
extends RefCounted
## Pure, engine-light validation of the /data tables. No Node/scene deps so it runs
## identically under the headless tool (tools/validate_data.gd) and the unit test
## (tests/unit/test_data_integrity.gd). Returns a list of human-readable errors;
## an empty list means the data set is internally consistent.
##
## This encodes the cross-reference + range rules the game relies on (AGENTS.md
## "canonical block-type registry" + SPEC data-validation gate §7). Extend the rules
## here as the data model grows — every new table gets a rule, every join gets a check.

const DETONATION_MODES := ["fuse_seconds", "on_first_impact", "on_rest"]
## Minimum WCAG relative-luminance separation required between any two diggable block colors
## (AC-5.10.3: contrast by luminance, not hue alone). With the debug-grid glyph overlay removed
## (v0.5 arcade pass), this luminance-delta gate is the SOLE machine-checked enforcement of
## non-color block identity — every two block types must read apart by brightness, not just hue.
const MIN_BLOCK_LUMINANCE_DELTA := 0.06

## Set at the top of validate() so the static _check_depth_curve (whose signature is shared
## with the existing tests) can see the ore-overlay layer to reject overlay-owned ids from the
## base filler curve. Per-call (validate is not re-entrant in practice).
static var _root_ore_overlays: Variant = null

static func validate(tables: Dictionary) -> Array:
	var errors: Array = []
	_root_ore_overlays = tables.get("ore_overlays")
	var balance: Dictionary = _dict(tables, "balance", errors)
	var blocks: Dictionary = _dict(tables, "block_types", errors)
	var explosives: Dictionary = _dict(tables, "explosives", errors)
	var packs: Dictionary = _dict(tables, "packs", errors)
	# depth_bands.json is now the CONTINUOUS depth CURVE descriptor (an object), not the
	# old discrete band array — see _check_depth_curve (UNIT MAPGEN infinite descent).
	var curve: Variant = tables.get("depth_bands")
	var art_sources: Dictionary = _dict(tables, "art_sources", errors)

	_check_balance(balance, errors)
	_check_ui(balance, errors)
	_check_ui_overhaul(balance, errors)
	_check_settings(balance, errors)
	_check_vfx(balance, errors)
	_check_feel(balance, errors)
	_check_elevator(balance, errors)
	_check_mine_geometry(balance, errors)
	_check_blocks(blocks, errors)
	_check_palette(tables.get("palette"), blocks, errors)
	_check_art_sources(art_sources, blocks, errors)
	_check_depth_curve(curve, blocks, errors)
	_check_ore_overlays(tables.get("ore_overlays"), blocks, errors)
	_check_ore_value_ladder(tables.get("ore_overlays"), blocks, errors)
	_check_depth_reward_monotone(curve, tables.get("ore_overlays"), blocks, errors)
	_check_explosives(explosives, balance, errors)
	_check_packs(packs, explosives, errors)
	_check_pack_affordability(packs, balance, errors)
	_check_free_charge(explosives, blocks, curve, balance, errors)
	_check_generation(tables.get("generation"), errors)
	_check_relics(tables.get("relics"), curve, balance, errors)
	_check_prestige(tables.get("prestige"), errors)
	_check_upgrades(tables.get("upgrades"), balance, errors)
	_check_mines(tables.get("mines"), balance, errors)
	_check_audio(tables.get("audio"), errors)
	_check_logging(tables.get("logging"), errors)
	return errors

static func _dict(tables: Dictionary, key: String, errors: Array) -> Dictionary:
	var v: Variant = tables.get(key)
	if v == null:
		errors.append("missing table: %s.json" % key)
		return {}
	if not (v is Dictionary):
		errors.append("%s.json must be a JSON object" % key)
		return {}
	return v

static func _check_balance(b: Dictionary, errors: Array) -> void:
	# Strictly-positive required keys. HP-scaling multipliers (AC-5.2.1) are
	# required here so the no-stall solvability check (AC-5.5.5) can verify the
	# free charge against the SCALED floor HP, not just the unscaled table value.
	for k in ["block_pixel_size", "shaft_width_cells", "platform_width_cells", "chunk_height_cells", "crack_stages",
			"max_blast_radius_cells", "active_body_cap_desktop", "active_body_cap_web",
			"depth_hp_mult_per_cell", "mine_hardness_mult_max", "max_depth_hp_mult"]:
		if not b.has(k):
			errors.append("balance: missing '%s'" % k)
		elif float(b[k]) <= 0.0:
			errors.append("balance: '%s' must be > 0" % k)
	# max_depth_hp_mult is the HP ceiling in the INFINITE shaft (UNIT MAPGEN). It must be
	# >= 1 (the surface multiplier) or it would make deep cells WEAKER than surface cells —
	# the bound has to cap growth, never invert it. Mirrors the EV cap.
	if b.has("max_depth_hp_mult") and float(b.get("max_depth_hp_mult", 0.0)) < 1.0:
		errors.append("balance: 'max_depth_hp_mult' must be >= 1.0 (the HP ceiling can't fall below the surface multiplier)")
	# run_seed must be present (logical-determinism seed); any int is acceptable.
	if not b.has("run_seed"):
		errors.append("balance: missing 'run_seed'")
	# starting_money must be present and non-negative (0 is valid).
	if not b.has("starting_money"):
		errors.append("balance: missing 'starting_money'")
	elif int(b.get("starting_money", -1)) < 0:
		errors.append("balance: 'starting_money' must be >= 0")
	if b.has("platform_clear_threshold") and int(b.get("platform_clear_threshold", 0)) <= 0:
		errors.append("balance: 'platform_clear_threshold' must be > 0")
	# Platform descent + camera tunables (U7 / AC-5.7.2, AC-5.7.3). All required so
	# the descent depth, tween duration, and camera anchor are data, never code literals.
	# descent_max_steps: rows the platform may drop per trigger (>= 1).
	if not b.has("descent_max_steps"):
		errors.append("balance: missing 'descent_max_steps'")
	elif int(b.get("descent_max_steps", 0)) < 1:
		errors.append("balance: 'descent_max_steps' must be >= 1")
	# descent_tween_seconds: tween duration (> 0 so descent animates, never snaps).
	if not b.has("descent_tween_seconds"):
		errors.append("balance: missing 'descent_tween_seconds'")
	elif float(b.get("descent_tween_seconds", 0.0)) <= 0.0:
		errors.append("balance: 'descent_tween_seconds' must be > 0")
	# camera_lookahead_cells: camera anchor offset below the platform target (>= 0).
	if not b.has("camera_lookahead_cells"):
		errors.append("balance: missing 'camera_lookahead_cells'")
	elif int(b.get("camera_lookahead_cells", -1)) < 0:
		errors.append("balance: 'camera_lookahead_cells' must be >= 0")
	# Web active-body cap should not exceed the desktop cap (web is the weaker target).
	if b.has("active_body_cap_web") and b.has("active_body_cap_desktop"):
		if int(b.get("active_body_cap_web", 0)) > int(b.get("active_body_cap_desktop", 0)):
			errors.append("balance: 'active_body_cap_web' must be <= 'active_body_cap_desktop'")
	# blast_fuzz_pct (AC-5.2.3): the injected-rng fuzz spread. Must be present and in
	# [0, 1): 0 disables fuzz; a spread of 1 would permit a 0x factor (zero damage),
	# which could stall the no-regen dig (AC-5.2.7/AC-5.5.5), so it is bounded < 1.
	if not b.has("blast_fuzz_pct"):
		errors.append("balance: missing 'blast_fuzz_pct'")
	else:
		var fp: float = float(b.get("blast_fuzz_pct", -1.0))
		if fp < 0.0 or fp >= 1.0:
			errors.append("balance: 'blast_fuzz_pct' must be in [0, 1)")
	if not b.has("throw_cooldown_seconds"):
		errors.append("balance: missing 'throw_cooldown_seconds'")
	elif float(b.get("throw_cooldown_seconds", 0.0)) <= 0.0:
		errors.append("balance: 'throw_cooldown_seconds' must be > 0")
	if not b.has("camera_platform_screen_fraction"):
		errors.append("balance: missing 'camera_platform_screen_fraction'")
	else:
		var frac: float = float(b.get("camera_platform_screen_fraction", -1.0))
		if frac < 0.0 or frac > 1.0:
			errors.append("balance: 'camera_platform_screen_fraction' must be in [0,1]")
	if not b.has("support_extend_seconds"):
		errors.append("balance: missing 'support_extend_seconds'")
	elif float(b.get("support_extend_seconds", 0.0)) <= 0.0:
		errors.append("balance: 'support_extend_seconds' must be > 0")

static func _check_mine_geometry(b: Dictionary, errors: Array) -> void:
	# mine_width_cells must be a positive finite width (the shaft has finite width).
	if not b.has("mine_width_cells"):
		errors.append("balance: missing 'mine_width_cells'")
	elif int(b.get("mine_width_cells", 0)) <= 0:
		errors.append("balance: 'mine_width_cells' must be > 0")
	# mine_height_cells: 0 (or negative) is the INFINITE-descent sentinel (UNIT MAPGEN) —
	# the shaft has no bottom and the relic ends the dig at a finite depth. A POSITIVE value
	# still means a bounded mine; a missing key fails the gate (geometry is data).
	if not b.has("mine_height_cells"):
		errors.append("balance: missing 'mine_height_cells'")
	elif int(b.get("mine_height_cells", 1)) < 0:
		errors.append("balance: 'mine_height_cells' must be >= 0 (0 = infinite shaft)")
	if b.has("mine_width_cells") and b.has("shaft_width_cells"):
		var mine_w: int = int(b.get("mine_width_cells", 0))
		var shaft_w: int = int(b.get("shaft_width_cells", 0))
		if shaft_w > mine_w:
			errors.append("balance: 'shaft_width_cells' (%d) must be <= 'mine_width_cells' (%d)" % [shaft_w, mine_w])
		if shaft_w % 2 == 0:
			errors.append("balance: 'shaft_width_cells' must be odd so the corridor has a center line")
	if b.has("shaft_width_cells") and b.has("platform_width_cells"):
		var shaft_w2: int = int(b.get("shaft_width_cells", 0))
		var plat_w: int = int(b.get("platform_width_cells", 0))
		if plat_w > shaft_w2:
			errors.append("balance: 'platform_width_cells' (%d) must be <= 'shaft_width_cells' (%d)" % [plat_w, shaft_w2])
		if plat_w % 2 == 0:
			errors.append("balance: 'platform_width_cells' must be odd so the platform has a center line")
	if b.has("mine_height_cells") and b.has("chunk_height_cells"):
		var mine_h: int = int(b.get("mine_height_cells", 0))
		var chunk_h: int = int(b.get("chunk_height_cells", 0))
		if mine_h > 0 and chunk_h > 0 and mine_h < chunk_h:
			errors.append("balance: 'mine_height_cells' must be >= 'chunk_height_cells'")
	if b.has("platform_clear_threshold") and b.has("shaft_width_cells"):
		var threshold: int = int(b.get("platform_clear_threshold", 0))
		var shaft_w2: int = int(b.get("shaft_width_cells", 0))
		if threshold > shaft_w2:
			errors.append("balance: 'platform_clear_threshold' (%d) must be <= shaft width (%d)" % [threshold, shaft_w2])
	for k in ["camera_zoom", "light_radius_px", "light_softness_px", "light_dim_alpha"]:
		if not b.has(k):
			errors.append("balance: missing '%s'" % k)
	if b.has("camera_zoom") and float(b.get("camera_zoom", 0.0)) <= 0.0:
		errors.append("balance: 'camera_zoom' must be > 0")
	if b.has("light_radius_px") and float(b.get("light_radius_px", 0.0)) <= 0.0:
		errors.append("balance: 'light_radius_px' must be > 0")
	if b.has("light_softness_px") and float(b.get("light_softness_px", -1.0)) < 0.0:
		errors.append("balance: 'light_softness_px' must be >= 0")
	if b.has("light_dim_alpha"):
		var alpha: float = float(b.get("light_dim_alpha", -1.0))
		if alpha < 0.0 or alpha > 1.0:
			errors.append("balance: 'light_dim_alpha' must be in [0,1]")
	# light_dark_tint (v0.5 arcade pass): the cool deep-terrain cast the headlamp mask fades
	# toward instead of pure black — must be present and a valid hex (it drives the shader's
	# `dark_tint` uniform; a typo'd/absent value would read magenta or silently disable the cast).
	if not b.has("light_dark_tint"):
		errors.append("balance: missing 'light_dark_tint' (v0.5 headlamp deep-terrain cast)")
	elif not Color.html_is_valid(str(b.get("light_dark_tint", ""))):
		errors.append("balance: 'light_dark_tint' %s must be a valid hex color" % str(b.get("light_dark_tint", "")))

## AC-5.8.5 (portrait HUD layout). The thumb-safe touch-target minimum and the base HUD
## edge margin are tunables, not code literals. The touch-target floor must sit in the
## ~44–48px guideline band (Apple HIG 44 / Material 48); allow a small range [44,64] so a
## designer can go larger but never below the accessibility floor. The edge margin must be
## present and non-negative (0 = flush, allowed but discouraged; the safe-area inset extends
## it on real devices). A missing key fails the gate (balance is data, never a code default).
static func _check_ui(b: Dictionary, errors: Array) -> void:
	if not b.has("ui_min_touch_target_px"):
		errors.append("balance: missing 'ui_min_touch_target_px' (AC-5.8.5 touch target)")
	else:
		var t: float = float(b.get("ui_min_touch_target_px", 0.0))
		if t < 44.0 or t > 64.0:
			errors.append("balance: 'ui_min_touch_target_px' %s must be in [44,64] — the ~44–48px thumb-safe floor (AC-5.8.5)" % str(t))
	if not b.has("ui_edge_margin_px"):
		errors.append("balance: missing 'ui_edge_margin_px' (AC-5.8.5 HUD edge margin)")
	elif float(b.get("ui_edge_margin_px", -1.0)) < 0.0:
		errors.append("balance: 'ui_edge_margin_px' must be >= 0 (AC-5.8.5)")
	# Money-juice tunables (v0.5 arcade pass): the rolling count-up duration + the flying-coin
	# timings/cap/arc. All /data (tunables-are-data), each present + range-checked so a typo'd key
	# can't silently read 0 (a 0 roll/fly would snap with no animation; a 0 cap would suppress coins).
	# (key, strict_min?) durations are > 0; the coin cap is >= 1; the arc apex is >= 0.
	for k in ["ui_money_roll_seconds", "coin_fly_seconds", "coin_pop_seconds"]:
		if not b.has(k):
			errors.append("balance: missing '%s' (v0.5 money juice)" % k)
		elif float(b.get(k, 0.0)) <= 0.0:
			errors.append("balance: '%s' %s must be > 0 (v0.5 money juice)" % [k, str(b.get(k))])
	if not b.has("coin_max_active"):
		errors.append("balance: missing 'coin_max_active' (v0.5 money juice)")
	elif int(b.get("coin_max_active", 0)) < 1:
		errors.append("balance: 'coin_max_active' %s must be >= 1 (v0.5 money juice)" % str(b.get("coin_max_active")))
	if not b.has("coin_arc_height_px"):
		errors.append("balance: missing 'coin_arc_height_px' (v0.5 money juice)")
	elif float(b.get("coin_arc_height_px", -1.0)) < 0.0:
		errors.append("balance: 'coin_arc_height_px' %s must be >= 0 (v0.5 money juice)" % str(b.get("coin_arc_height_px")))
	# UI/HUD-animation tunables (v0.5 arcade pass): the modal scale-in/out durations, the
	# relic/prestige screen-flash (peak alpha + fade), and the tray-select pop duration. All
	# /data (tunables-are-data) + range-checked so a typo'd key can't silently read 0 (a 0
	# duration would snap with no animation; an out-of-band flash alpha could either be invisible
	# or a full-white strobe — capped at 1.0 for the AC-5.10.4 photosensitivity guard).
	for k in ["ui_panel_in_seconds", "ui_panel_out_seconds", "ui_flash_seconds", "ui_tray_pop_seconds"]:
		if not b.has(k):
			errors.append("balance: missing '%s' (v0.5 UI animation)" % k)
		elif float(b.get(k, 0.0)) <= 0.0:
			errors.append("balance: '%s' %s must be > 0 (v0.5 UI animation)" % [k, str(b.get(k))])
	# Flash peak alpha is bounded to [0,1] — capped so a relic/prestige wash can never blow out to
	# an opaque full-screen strobe (AC-5.10.4 photosensitivity; the alpha is further motion-gated).
	if not b.has("ui_flash_alpha"):
		errors.append("balance: missing 'ui_flash_alpha' (v0.5 UI animation)")
	else:
		var fa: float = float(b.get("ui_flash_alpha", -1.0))
		if fa < 0.0 or fa > 1.0:
			errors.append("balance: 'ui_flash_alpha' %s must be in [0,1] (v0.5 UI animation, a11y-capped)" % str(fa))

## UI-overhaul tunables (selector + crate reveal). All timings/caps are authored in /data so the
## 8-bit UI pass remains balance/schema driven (AC-5.5.4, AC-5.8.5, AC-5.10.1).
static func _check_ui_overhaul(b: Dictionary, errors: Array) -> void:
	if not b.has("ui_selector"):
		errors.append("balance: missing 'ui_selector' block (charge selector UI)")
	else:
		var sel: Variant = b.get("ui_selector")
		if not (sel is Dictionary):
			errors.append("balance.ui_selector: must be a JSON object")
		else:
			var sd: Dictionary = sel
			for k in ["slot_width_px", "slot_height_px", "icon_px"]:
				if not sd.has(k):
					errors.append("balance.ui_selector: missing '%s'" % k)
				elif float(sd.get(k, 0.0)) < 44.0:
					errors.append("balance.ui_selector: '%s' %s must be >= 44px (AC-5.8.5)" % [k, str(sd.get(k))])
			# The selector occupies its OWN bar (a row distinct from the THROW/SHOP/MINES action row,
			# AC-5.8.1/5.8.5). The bar must be tall enough to hold a full slot so the hotbar never
			# clips a slot below the touch target — so the bar height is >= the slot height.
			if not sd.has("selector_bar_height_px"):
				errors.append("balance.ui_selector: missing 'selector_bar_height_px'")
			elif float(sd.get("selector_bar_height_px", 0.0)) < float(sd.get("slot_height_px", 0.0)):
				errors.append("balance.ui_selector: 'selector_bar_height_px' %s must be >= 'slot_height_px' %s (AC-5.8.5)" % [str(sd.get("selector_bar_height_px")), str(sd.get("slot_height_px"))])
			for k in ["selected_bob_px", "selected_bob_seconds", "long_press_seconds", "popover_seconds"]:
				if not sd.has(k):
					errors.append("balance.ui_selector: missing '%s'" % k)
				elif float(sd.get(k, 0.0)) <= 0.0:
					errors.append("balance.ui_selector: '%s' %s must be > 0" % [k, str(sd.get(k))])
	if not b.has("ui_crate"):
		errors.append("balance: missing 'ui_crate' block (pack reveal UI)")
	else:
		var crate: Variant = b.get("ui_crate")
		if not (crate is Dictionary):
			errors.append("balance.ui_crate: must be a JSON object")
		else:
			var cd: Dictionary = crate
			for k in ["drop_seconds", "open_seconds", "reveal_seconds", "settle_seconds", "hold_seconds", "reduced_hold_seconds", "card_stagger_seconds", "lid_lift_px"]:
				if not cd.has(k):
					errors.append("balance.ui_crate: missing '%s'" % k)
				elif float(cd.get(k, 0.0)) <= 0.0:
					errors.append("balance.ui_crate: '%s' %s must be > 0" % [k, str(cd.get(k))])
			if not cd.has("rare_hitstop_seconds"):
				errors.append("balance.ui_crate: missing 'rare_hitstop_seconds'")
			else:
				var hs: float = float(cd.get("rare_hitstop_seconds", -1.0))
				if hs < 0.0 or hs > 0.12:
					errors.append("balance.ui_crate: 'rare_hitstop_seconds' %s must be in [0,0.12]" % str(hs))
			if not cd.has("particle_count_rare"):
				errors.append("balance.ui_crate: missing 'particle_count_rare'")
			elif int(cd.get("particle_count_rare", 0)) < 0:
				errors.append("balance.ui_crate: 'particle_count_rare' must be >= 0")

## AC-5.10.1 (accessibility settings). The Settings UI seeds from data-driven defaults +
## ranges — volumes/motion are normalized [0,1] sliders; the UI text scale carries an
## explicit [min,max] band the slider clamps to. All required (balance is data) and each
## default must sit inside its own range, so a /data author can't ship a setting that
## starts outside the slider it drives.
static func _check_settings(b: Dictionary, errors: Array) -> void:
	if not b.has("settings"):
		errors.append("balance: missing 'settings' block (AC-5.10.1 volume/motion/text-scale)")
		return
	var s: Variant = b.get("settings")
	if not (s is Dictionary):
		errors.append("balance: 'settings' must be a JSON object (AC-5.10.1)")
		return
	var sd: Dictionary = s
	# Normalized [0,1] sliders: SFX/Music volume + motion intensity.
	for k in ["default_sfx_volume", "default_music_volume", "default_motion_intensity"]:
		if not sd.has(k):
			errors.append("balance.settings: missing '%s' (AC-5.10.1)" % k)
		else:
			var v: float = float(sd.get(k, -1.0))
			if v < 0.0 or v > 1.0:
				errors.append("balance.settings: '%s' %s must be in [0,1] (AC-5.10.1)" % [k, str(v)])
	# UI text-scale band: 0 < min <= max, and the default sits inside it (AC-5.8.6 reflow target).
	for k in ["text_scale_min", "text_scale_max", "default_text_scale"]:
		if not sd.has(k):
			errors.append("balance.settings: missing '%s' (AC-5.10.1 text scale)" % k)
	if sd.has("text_scale_min") and sd.has("text_scale_max"):
		var lo: float = float(sd.get("text_scale_min", 0.0))
		var hi: float = float(sd.get("text_scale_max", 0.0))
		if lo <= 0.0:
			errors.append("balance.settings: 'text_scale_min' must be > 0 (AC-5.10.1)")
		if hi < lo:
			errors.append("balance.settings: 'text_scale_max' (%s) must be >= 'text_scale_min' (%s)" % [str(hi), str(lo)])
		if sd.has("default_text_scale"):
			var d: float = float(sd.get("default_text_scale", 0.0))
			if d < lo or d > hi:
				errors.append("balance.settings: 'default_text_scale' %s must be within [%s,%s] (AC-5.10.1)" % [str(d), str(lo), str(hi)])
	# Elevator-side default (D2 controls): must be one of {"left","right"} — the on-screen elevator
	# arrows are laid out against that screen edge (AC-5.10.1 controls layout). Defaulting it in /data
	# keeps the value a tunable, not a code literal.
	if not sd.has("default_elevator_side"):
		errors.append("balance.settings: missing 'default_elevator_side' (AC-5.10.1 controls)")
	else:
		var side: String = str(sd.get("default_elevator_side", ""))
		if side != "left" and side != "right":
			errors.append("balance.settings: 'default_elevator_side' '%s' must be 'left' or 'right' (AC-5.10.1)" % side)

## VFX feel table (v0.5 arcade pass). Every magnitude that drives the juice — camera shake,
## zoom punch, hit-stop, explosion flash/ring, debris cap, value popups — is a /data tunable,
## not a code literal (mirrors the _check_settings / _check_ui rules). All keys are REQUIRED
## (a typo'd key that silently reads 0 would disable a cue or, worse, soft-lock the hit-stop),
## and each is range-checked to its documented safe band. The hit-stop bounds are the load-
## bearing ones: hitstop_scale in (0,1] and the durations capped small so a freeze can never
## strand (the freeze uses an ignore-time-scale restore timer; see mine.gd _hit_stop).
static func _check_vfx(b: Dictionary, errors: Array) -> void:
	if not b.has("vfx"):
		errors.append("balance: missing 'vfx' feel table (v0.5 arcade tunables)")
		return
	var v: Variant = b.get("vfx")
	if not (v is Dictionary):
		errors.append("balance: 'vfx' must be a JSON object")
		return
	var vd: Dictionary = v
	# (key, min_inclusive, max_inclusive) — every vfx key enumerated + range-checked.
	# A null upper bound means "unbounded above". Keys in `strict_min` use > min, not >= min.
	var rules: Array = [
		["shake_max_offset_px", 0.0, 200.0],
		["shake_kick_px", 0.0, 200.0],
		["shake_decay_per_sec", 0.0, null],
		["shake_base", 0.0, 1.0],
		["shake_per_cell", 0.0, 1.0],
		["shake_noise_freq", 0.0, null],
		["zoom_punch", 0.0, 0.3],
		["zoom_punch_seconds", 0.0, null],
		["hitstop_scale", 0.0, 1.0],
		["hitstop_seconds", 0.0, 0.12],
		["hitstop_min_cells", 1.0, null],
		["hitstop_relic_seconds", 0.0, 0.3],
		["flash_seconds", 0.0, null],
		["flash_scale_per_radius", 0.0, null],
		["ring_scale_per_radius", 0.0, null],
		["ring_seconds", 0.0, null],
		["max_debris_emitters", 1.0, null],
		["debris_amount_per_cell", 1.0, null],
		["popup_rise_px", 0.0, null],
		["popup_seconds", 0.0, null],
		["popup_max_active", 1.0, null],
	]
	var strict_min: Array = [
		"shake_decay_per_sec", "shake_noise_freq", "zoom_punch_seconds", "hitstop_scale",
		"hitstop_seconds", "hitstop_relic_seconds", "flash_seconds", "ring_seconds",
		"popup_seconds",
	]
	for rule in rules:
		var k: String = rule[0]
		if not vd.has(k):
			errors.append("balance.vfx: missing '%s'" % k)
			continue
		var val: float = float(vd.get(k, 0.0))
		var lo: float = float(rule[1])
		if strict_min.has(k):
			if val <= lo:
				errors.append("balance.vfx: '%s' %s must be > %s" % [k, str(val), str(lo)])
		elif val < lo:
			errors.append("balance.vfx: '%s' %s must be >= %s" % [k, str(val), str(lo)])
		if rule[2] != null and val > float(rule[2]):
			errors.append("balance.vfx: '%s' %s must be <= %s" % [k, str(val), str(rule[2])])

## Launch & control-feel table (v0.5 arcade pass). Every magnitude that drives the THROW
## tactility — the button squash/pop, the animated aim line width + dash scroll, the platform
## recoil, and the muzzle-flash particle count — is a /data tunable, not a code literal (mirrors
## the _check_vfx / _check_settings rules). All keys are REQUIRED + range-checked so a typo'd key
## that silently reads 0 can't disable a cue. `throw_button_squash` is a (0,1] compress fraction
## (1 = no squash, 0 = collapse to nothing — both excluded); the pop duration is strictly > 0;
## `aim_scroll_speed`/`recoil_px` are >= 0 (0 = a static line / no kick, still valid); the muzzle
## flash count is >= 1 (a one-shot burst needs at least one particle to read). `keyboard_aim_deg_per_sec`
## (D1) is the held-arrow-key aim rate in deg/sec and must be strictly > 0 (a 0 rate disables it).
static func _check_feel(b: Dictionary, errors: Array) -> void:
	if not b.has("feel"):
		errors.append("balance: missing 'feel' launch/control-feel table (v0.5 arcade tunables)")
		return
	var v: Variant = b.get("feel")
	if not (v is Dictionary):
		errors.append("balance: 'feel' must be a JSON object")
		return
	var fd: Dictionary = v
	# throw_button_squash: compress factor on press, in (0,1]. 1 = no squash; 0/negative collapses.
	if not fd.has("throw_button_squash"):
		errors.append("balance.feel: missing 'throw_button_squash'")
	else:
		var sq: float = float(fd.get("throw_button_squash", 0.0))
		if sq <= 0.0 or sq > 1.0:
			errors.append("balance.feel: 'throw_button_squash' %s must be in (0,1]" % str(sq))
	# Strictly-positive durations + widths (a 0 here would snap with no animation / an invisible line).
	# keyboard_aim_deg_per_sec (D1) is the held-key aim rate in deg/sec — a 0/negative rate would make
	# the arrow keys unable to aim (Aim.keyboard_angle_step early-returns on rate <= 0), so it is > 0.
	for k in ["throw_button_pop_seconds", "aim_line_width", "keyboard_aim_deg_per_sec"]:
		if not fd.has(k):
			errors.append("balance.feel: missing '%s'" % k)
		elif float(fd.get(k, 0.0)) <= 0.0:
			errors.append("balance.feel: '%s' %s must be > 0" % [k, str(fd.get(k))])
	# Non-negative magnitudes (0 = a still line / no recoil — valid, e.g. reduced motion authored low).
	# aim_march_px is the dash-shader march speed (0 = a static dash, valid); aim_dash_px/aim_gap_px
	# are the dash + gap lengths (each >= 0), but their SUM (the dash period) MUST be > 0 or the
	# marching-dash shader divides by a zero period.
	for k in ["aim_scroll_speed", "recoil_px", "aim_march_px", "aim_dash_px", "aim_gap_px"]:
		if not fd.has(k):
			errors.append("balance.feel: missing '%s'" % k)
		elif float(fd.get(k, -1.0)) < 0.0:
			errors.append("balance.feel: '%s' %s must be >= 0" % [k, str(fd.get(k))])
	if fd.has("aim_dash_px") and fd.has("aim_gap_px"):
		var period: float = float(fd.get("aim_dash_px", 0.0)) + float(fd.get("aim_gap_px", 0.0))
		if period <= 0.0:
			errors.append("balance.feel: 'aim_dash_px' + 'aim_gap_px' (dash period) %s must be > 0" % str(period))
	# aim_march_aim_mult: the dash crawls FASTER while the player is actively turning the aim
	# (holding ←/→). It MUST be >= 1 (1 = no speed-up; < 1 would perversely slow the march while
	# aiming). aim_march_ease_rate is how fast (per second) the multiplier eases in/out and must be
	# strictly > 0 (a 0/negative rate has no ease budget and would snap the speed-up on/off).
	if not fd.has("aim_march_aim_mult"):
		errors.append("balance.feel: missing 'aim_march_aim_mult'")
	elif float(fd.get("aim_march_aim_mult", 0.0)) < 1.0:
		errors.append("balance.feel: 'aim_march_aim_mult' %s must be >= 1" % str(fd.get("aim_march_aim_mult")))
	if not fd.has("aim_march_ease_rate"):
		errors.append("balance.feel: missing 'aim_march_ease_rate'")
	elif float(fd.get("aim_march_ease_rate", 0.0)) <= 0.0:
		errors.append("balance.feel: 'aim_march_ease_rate' %s must be > 0" % str(fd.get("aim_march_ease_rate")))
	# Muzzle flash burst: a one-shot needs at least one particle to read.
	if not fd.has("muzzle_flash_particles"):
		errors.append("balance.feel: missing 'muzzle_flash_particles'")
	elif int(fd.get("muzzle_flash_particles", 0)) < 1:
		errors.append("balance.feel: 'muzzle_flash_particles' %s must be >= 1" % str(fd.get("muzzle_flash_particles")))

## The data-driven elevator hold-to-move RAMP (balance.elevator). Holding an elevator button/key
## moves the platform CONTINUOUSLY, ramping from a slow start to a capped max (ElevatorRamp). All
## three constants are REQUIRED + range-checked so a typo'd key that silently reads 0 can't disable
## the hold (a 0 max/start would never move; a negative accel is meaningless): `start_rows_per_sec`
## > 0 (a fresh hold must move), `accel_rows_per_sec2` >= 0 (0 = a constant slow glide, still valid),
## `max_rows_per_sec` >= `start_rows_per_sec` (the cap can't sit below the start). Tunables are data.
static func _check_elevator(b: Dictionary, errors: Array) -> void:
	if not b.has("elevator"):
		errors.append("balance: missing 'elevator' hold-to-move ramp table")
		return
	var v: Variant = b.get("elevator")
	if not (v is Dictionary):
		errors.append("balance: 'elevator' must be a JSON object")
		return
	var ed: Dictionary = v
	# start_rows_per_sec: the slow initial hold speed — strictly > 0 so a fresh hold actually moves.
	if not ed.has("start_rows_per_sec"):
		errors.append("balance.elevator: missing 'start_rows_per_sec'")
	elif float(ed.get("start_rows_per_sec", 0.0)) <= 0.0:
		errors.append("balance.elevator: 'start_rows_per_sec' %s must be > 0" % str(ed.get("start_rows_per_sec")))
	# accel_rows_per_sec2: how fast the held speed ramps — >= 0 (0 = a constant slow glide, valid).
	if not ed.has("accel_rows_per_sec2"):
		errors.append("balance.elevator: missing 'accel_rows_per_sec2'")
	elif float(ed.get("accel_rows_per_sec2", -1.0)) < 0.0:
		errors.append("balance.elevator: 'accel_rows_per_sec2' %s must be >= 0" % str(ed.get("accel_rows_per_sec2")))
	# max_rows_per_sec: the capped top speed — must be >= the start (the cap can't be below the start).
	if not ed.has("max_rows_per_sec"):
		errors.append("balance.elevator: missing 'max_rows_per_sec'")
	else:
		var mx: float = float(ed.get("max_rows_per_sec", 0.0))
		var st: float = float(ed.get("start_rows_per_sec", 0.0))
		if mx < st:
			errors.append("balance.elevator: 'max_rows_per_sec' %s must be >= 'start_rows_per_sec' %s" % [str(mx), str(st)])

## The data-driven SFX table (audio.json, v0.5 arcade audio pass). Every placeholder cue's
## synthesis params (freq/dur/noise/sweep/pitch_jitter) are /data, not a code literal in audio.gd
## (mirrors the _check_settings / _check_vfx / _check_feel rules). The table is REQUIRED to carry an
## entry for EVERY core event Audio.EVENTS names, each range-checked so a typo'd key can't silence a
## cue or, via an out-of-band pitch_jitter, distort it. The `combo` block bounds the rising-pitch
## break rattle (>=1 voices, a > 0 step, a >= 0 semitone climb); `detonate.layers` must carry >= 3
## layered voices (low body + bright transient + noise tail) each itself a valid event spec.
## audio.gd keeps a hardcoded fallback so a missing table can't actually silence the game, but the
## SHIPPED table must satisfy this gate (tunables are data — AC-5.5.4).
const AUDIO_EVENTS := [
	"detonate", "crack", "break", "ore_credited",
	"pack_open", "relic_found", "prestige_banked",
	"descend", "throw",
	"crate_drop", "crate_creak", "crate_smash", "rare_reveal_sting",
	"charge_select", "button_hover", "button_press", "button_disabled",
	"modal_open", "modal_close", "insufficient_funds", "coin_fly",
	"prestige_bank", "run_end_jingle", "upgrade_purchase",
]

const AUDIO_MUSIC_TRACKS := [
	"music_menu", "music_mining", "music_deep", "music_relic", "music_shop",
]

static func _check_audio(audio: Variant, errors: Array) -> void:
	if audio == null:
		errors.append("missing table: audio.json (v0.5 data-driven SFX)")
		return
	if not (audio is Dictionary):
		errors.append("audio.json must be a JSON object")
		return
	var ad: Dictionary = audio
	var events: Variant = ad.get("events")
	if not (events is Dictionary):
		errors.append("audio.json: missing 'events' object (one spec per core event)")
	else:
		var ed: Dictionary = events
		for ev in AUDIO_EVENTS:
			if not ed.has(ev):
				errors.append("audio.events: missing '%s' (every Audio.EVENTS entry needs a spec)" % ev)
				continue
			_check_audio_event_spec("audio.events.%s" % ev, ed.get(ev), errors)
	# combo: the rising-pitch break rattle bounds.
	var combo: Variant = ad.get("combo")
	if not (combo is Dictionary):
		errors.append("audio.json: missing 'combo' object (break-rattle bounds)")
	else:
		var cd: Dictionary = combo
		if not cd.has("max_voices"):
			errors.append("audio.combo: missing 'max_voices'")
		elif int(cd.get("max_voices", 0)) < 1:
			errors.append("audio.combo: 'max_voices' %s must be >= 1" % str(cd.get("max_voices")))
		if not cd.has("step_seconds"):
			errors.append("audio.combo: missing 'step_seconds'")
		elif float(cd.get("step_seconds", 0.0)) <= 0.0:
			errors.append("audio.combo: 'step_seconds' %s must be > 0" % str(cd.get("step_seconds")))
		if not cd.has("semitone_step"):
			errors.append("audio.combo: missing 'semitone_step'")
		elif float(cd.get("semitone_step", -1.0)) < 0.0:
			errors.append("audio.combo: 'semitone_step' %s must be >= 0" % str(cd.get("semitone_step")))
	# detonate.layers: the layered boom (>= 3 voices, each a valid event spec).
	var det: Variant = ad.get("detonate")
	if not (det is Dictionary):
		errors.append("audio.json: missing 'detonate' object (layered-boom voices)")
	else:
		var layers: Variant = (det as Dictionary).get("layers")
		if not (layers is Array):
			errors.append("audio.detonate: missing 'layers' array (low body + transient + noise tail)")
		elif (layers as Array).size() < 3:
			errors.append("audio.detonate.layers: %d layer(s); need >= 3 for a layered boom" % (layers as Array).size())
		else:
			var li: int = 0
			for layer in (layers as Array):
				_check_audio_event_spec("audio.detonate.layers[%d]" % li, layer, errors)
				li += 1
	var music: Variant = ad.get("music")
	if not (music is Dictionary):
		errors.append("audio.json: missing 'music' object (placeholder chiptune loops)")
	else:
		var md: Dictionary = music
		for track in AUDIO_MUSIC_TRACKS:
			if not md.has(track):
				errors.append("audio.music: missing '%s'" % track)
				continue
			_check_music_spec("audio.music.%s" % track, md.get(track), errors)

static func _check_music_spec(label: String, spec: Variant, errors: Array) -> void:
	if not (spec is Dictionary):
		errors.append("%s: must be a JSON object" % label)
		return
	var sd: Dictionary = spec
	if not sd.has("bpm"):
		errors.append("%s: missing 'bpm'" % label)
	elif float(sd.get("bpm", 0.0)) <= 0.0:
		errors.append("%s: 'bpm' %s must be > 0" % [label, str(sd.get("bpm"))])
	if not sd.has("step_beats"):
		errors.append("%s: missing 'step_beats'" % label)
	elif float(sd.get("step_beats", 0.0)) <= 0.0:
		errors.append("%s: 'step_beats' %s must be > 0" % [label, str(sd.get("step_beats"))])
	if not sd.has("volume"):
		errors.append("%s: missing 'volume'" % label)
	else:
		var vol: float = float(sd.get("volume", -1.0))
		if vol < 0.0 or vol > 1.0:
			errors.append("%s: 'volume' %s must be in [0,1]" % [label, str(vol)])
	var notes: Variant = sd.get("notes")
	if not (notes is Array) or (notes as Array).is_empty():
		errors.append("%s: missing non-empty 'notes' array" % label)
	else:
		for i in range((notes as Array).size()):
			if float((notes as Array)[i]) < 0.0:
				errors.append("%s.notes[%d]: note frequency must be >= 0 (0 = rest)" % [label, i])

## A single synthesised-tone spec: freq>0, dur in (0,2], noise in [0,1], sweep>=0, pitch_jitter in
## [0,0.5]. Shared by both the per-event specs and the detonate.layers voices.
static func _check_audio_event_spec(label: String, spec: Variant, errors: Array) -> void:
	if not (spec is Dictionary):
		errors.append("%s: must be a JSON object" % label)
		return
	var sd: Dictionary = spec
	# freq: pitch, strictly positive (a 0 Hz tone is silence).
	if not sd.has("freq"):
		errors.append("%s: missing 'freq'" % label)
	elif float(sd.get("freq", 0.0)) <= 0.0:
		errors.append("%s: 'freq' %s must be > 0" % [label, str(sd.get("freq"))])
	# dur: in (0,2] seconds (a placeholder cue is short; > 2s is almost certainly a typo).
	if not sd.has("dur"):
		errors.append("%s: missing 'dur'" % label)
	else:
		var dur: float = float(sd.get("dur", 0.0))
		if dur <= 0.0 or dur > 2.0:
			errors.append("%s: 'dur' %s must be in (0,2]" % [label, str(dur)])
	# noise: white-noise mix in [0,1].
	if not sd.has("noise"):
		errors.append("%s: missing 'noise'" % label)
	else:
		var noise: float = float(sd.get("noise", -1.0))
		if noise < 0.0 or noise > 1.0:
			errors.append("%s: 'noise' %s must be in [0,1]" % [label, str(noise)])
	# sweep: end pitch in Hz, >= 0 (0 = no glide).
	if not sd.has("sweep"):
		errors.append("%s: missing 'sweep'" % label)
	elif float(sd.get("sweep", -1.0)) < 0.0:
		errors.append("%s: 'sweep' %s must be >= 0" % [label, str(sd.get("sweep"))])
	# pitch_jitter: per-play random pitch variance in [0,0.5] (0 = always tonal; 0.5 = a tritone of wobble).
	if not sd.has("pitch_jitter"):
		errors.append("%s: missing 'pitch_jitter'" % label)
	else:
		var pj: float = float(sd.get("pitch_jitter", -1.0))
		if pj < 0.0 or pj > 0.5:
			errors.append("%s: 'pitch_jitter' %s must be in [0,0.5]" % [label, str(pj)])

## Logging config (UNIT INFRA). The diagnostics threshold + file tunables are DATA (data/logging.json),
## consumed by the Logger autoload — never code literals (mirrors the _check_audio / _check_settings
## rules). Logger keeps a hardcoded FALLBACK_CONFIG so a missing table can't disable diagnostics, but
## the SHIPPED table must satisfy this gate. Rules: `min_level` is one of the level tags (DEBUG/INFO/
## WARN/ERROR/OFF); `log_file` is a non-empty user:// path (kept under user:// so it is sandbox-/web-
## safe and never escapes the writable dir); `max_file_kb` > 0 (the rotation cap); `mirror_to_console`
## is a bool.
const LOG_LEVELS := ["DEBUG", "INFO", "WARN", "ERROR", "OFF"]

static func _check_logging(logging: Variant, errors: Array) -> void:
	if logging == null:
		errors.append("missing table: logging.json (UNIT INFRA diagnostics config)")
		return
	if not (logging is Dictionary):
		errors.append("logging.json must be a JSON object")
		return
	var ld: Dictionary = logging
	# min_level: must be one of the canonical level tags (so the threshold maps to a real level).
	if not ld.has("min_level"):
		errors.append("logging: missing 'min_level'")
	else:
		var lvl: String = str(ld.get("min_level", "")).to_upper()
		if not LOG_LEVELS.has(lvl):
			errors.append("logging: 'min_level' '%s' must be one of %s" % [str(ld.get("min_level")), str(LOG_LEVELS)])
	# log_file: a non-empty user:// path (sandbox-/web-safe; never writes outside the writable dir).
	if not ld.has("log_file"):
		errors.append("logging: missing 'log_file'")
	else:
		var path: String = str(ld.get("log_file", ""))
		if path.is_empty():
			errors.append("logging: 'log_file' must be non-empty")
		elif not path.begins_with("user://"):
			errors.append("logging: 'log_file' '%s' must be a 'user://' path (sandbox-safe)" % path)
	# max_file_kb: the rotation cap, strictly positive (0 would rotate every write).
	if not ld.has("max_file_kb"):
		errors.append("logging: missing 'max_file_kb'")
	elif int(ld.get("max_file_kb", 0)) <= 0:
		errors.append("logging: 'max_file_kb' %s must be > 0" % str(ld.get("max_file_kb")))
	# mirror_to_console: a bool (typed so a stray string/int is caught).
	if not ld.has("mirror_to_console"):
		errors.append("logging: missing 'mirror_to_console'")
	elif not (ld.get("mirror_to_console") is bool):
		errors.append("logging: 'mirror_to_console' must be a boolean")

static func _check_blocks(blocks: Dictionary, errors: Array) -> void:
	if blocks.is_empty():
		errors.append("block_types: registry is empty")
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary):
			errors.append("block_types[%s]: must be an object" % id)
			continue
		for k in ["display_name", "hardness", "max_hp", "diggable", "palette_index"]:
			if not blk.has(k):
				errors.append("block_types[%s]: missing '%s'" % [id, k])
		if blk.get("diggable", false) and int(blk.get("max_hp", 0)) <= 0:
			errors.append("block_types[%s]: diggable block must have max_hp > 0" % id)
		if int(blk.get("hardness", -1)) < 0:
			errors.append("block_types[%s]: hardness must be >= 0" % id)
		var ore: Variant = blk.get("ore")
		if ore != null:
			if not (ore is Dictionary) or not ore.has("value"):
				errors.append("block_types[%s]: ore must be null or {value}" % id)
			elif int(ore.get("value", -1)) < 0:
				errors.append("block_types[%s]: ore.value must be >= 0" % id)
	# `hardness` is load-bearing, not vestigial (AC-5.1.5 resolves it; AC-5.2.1 says
	# "HP derived from its type's hardness"). We wire it into the HP contract: among
	# diggable blocks, base max_hp SHALL be monotonic non-decreasing in hardness, so a
	# harder block never has less base HP than a softer one. (Equal hardness may differ —
	# e.g. an ore vs plain rock of the same hardness.) This binds the authored max_hp
	# table to the hardness ordinal so the field is meaningful, without re-deriving HP.
	_check_hardness_hp_monotonic(blocks, errors)

static func _check_art_sources(art_sources: Dictionary, blocks: Dictionary, errors: Array) -> void:
	if art_sources.is_empty():
		return
	var terrain: Variant = art_sources.get("terrain")
	if not (terrain is Dictionary):
		errors.append("art_sources: missing terrain object")
		return
	var t: Dictionary = terrain
	var path: String = str(t.get("source_path", ""))
	if path.is_empty():
		errors.append("art_sources.terrain: missing source_path")
	elif not FileAccess.file_exists(path):
		errors.append("art_sources.terrain: source_path does not exist: %s" % path)
	if int(t.get("tile_px", 0)) <= 0:
		errors.append("art_sources.terrain: tile_px must be > 0")
	var tiles: Variant = t.get("block_tiles")
	if not (tiles is Dictionary):
		errors.append("art_sources.terrain: block_tiles must be an object")
		return
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary) or not bool((blk as Dictionary).get("diggable", false)):
			continue
		if not (tiles as Dictionary).has(id):
			errors.append("art_sources.terrain.block_tiles: missing tile coordinate for diggable block '%s'" % id)
			continue
		# block_tiles entries accept EITHER a single coord [x, y] (1 variant, the original
		# form — kept backward-compatible) OR a non-empty list of coords [[x, y], ...] (N
		# per-cell tile variants sampled from the unused tileset columns, v0.5 arcade pass).
		var entry: Variant = (tiles as Dictionary)[id]
		var variants: Array = _block_tile_variants(entry)
		if variants.is_empty():
			errors.append("art_sources.terrain.block_tiles[%s]: must be [x, y] or a non-empty list [[x, y], ...]" % id)
			continue
		for coord in variants:
			if int(coord[0]) < 0 or int(coord[1]) < 0:
				errors.append("art_sources.terrain.block_tiles[%s]: coordinates must be >= 0" % id)

## Normalize a block_tiles entry to a list of [x, y] int-pair Arrays. Accepts the single-coord
## form [x, y] (→ one variant) OR a list of coords [[x, y], ...]. Returns [] for any malformed
## shape (empty list, non-pair element, non-int coordinate), so the caller can reject it. Kept
## here (not BlockArt) so the data gate is self-contained; BlockArt has its own runtime mirror.
static func _block_tile_variants(entry: Variant) -> Array:
	if not (entry is Array):
		return []
	var arr: Array = entry
	if arr.is_empty():
		return []
	# Single-coord form: [x, y] where both elements are numbers (not Arrays).
	if arr.size() == 2 and not (arr[0] is Array) and not (arr[1] is Array):
		return [[int(arr[0]), int(arr[1])]]
	# List-of-coords form: every element must itself be a 2-element [x, y] pair.
	var out: Array = []
	for coord in arr:
		if not (coord is Array) or (coord as Array).size() != 2:
			return []
		out.append([int((coord as Array)[0]), int((coord as Array)[1])])
	return out

## AC-5.2.1 / AC-5.1.5: max_hp must not decrease as hardness increases (diggable blocks).
static func _check_hardness_hp_monotonic(blocks: Dictionary, errors: Array) -> void:
	# Collect (hardness, max_hp, id) for diggable blocks, sort by hardness, and check
	# that the max_hp seen so far never exceeds a lower-hardness block's max_hp.
	var rows: Array = []
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary) or not bool(blk.get("diggable", false)):
			continue
		rows.append({"h": int(blk.get("hardness", 0)), "hp": int(blk.get("max_hp", 0)), "id": str(id)})
	rows.sort_custom(func(a, b): return a["h"] < b["h"])
	# For each adjacent pair of DISTINCT hardness levels, the higher level's MIN hp must
	# be >= the lower level's MAX hp. Compute per-level min/max, then compare in order.
	var levels: Dictionary = {}  # hardness -> {min, max}
	for r in rows:
		var h: int = r["h"]
		if not levels.has(h):
			levels[h] = {"min": r["hp"], "max": r["hp"]}
		else:
			levels[h]["min"] = mini(levels[h]["min"], r["hp"])
			levels[h]["max"] = maxi(levels[h]["max"], r["hp"])
	var hkeys: Array = levels.keys()
	hkeys.sort()
	for i in range(1, hkeys.size()):
		var lo_h: int = hkeys[i - 1]
		var hi_h: int = hkeys[i]
		if levels[hi_h]["min"] < levels[lo_h]["max"]:
			errors.append("block_types: max_hp not monotonic with hardness — hardness %d (min hp %d) < hardness %d (max hp %d); harder rock must not have less base HP (AC-5.2.1)" % [hi_h, levels[hi_h]["min"], lo_h, levels[lo_h]["max"]])

## AC-5.10.2 / AC-5.10.3 (non-color block identity). palette.json backs the block COLOR
## (palette_index). With the debug-grid glyph overlay removed (v0.5 arcade pass), block
## identity is carried by the textured pixel-art tile PLUS a luminance contrast guarantee.
## Enforce: palette present + valid hex; every palette_index in range; and every pair of
## diggable block colors differs in LUMINANCE (not just hue), so identity never rides hue
## alone — a colorblind player can still split blocks by brightness (reframed AC-5.10.2/5.10.3).
static func _check_palette(pal: Variant, blocks: Dictionary, errors: Array) -> void:
	if pal == null:
		errors.append("missing table: palette.json")
		return
	if not (pal is Dictionary) or not ((pal as Dictionary).get("colors") is Array):
		errors.append("palette.json must be an object with a 'colors' array")
		return
	var colors: Array = (pal as Dictionary)["colors"]
	if colors.is_empty():
		errors.append("palette: 'colors' must be a non-empty array")
		return
	for i in range(colors.size()):
		if not Color.html_is_valid(str(colors[i])):
			errors.append("palette: colors[%d] '%s' is not a valid hex color" % [i, str(colors[i])])
	var lum_rows: Array = []          # {id, lum} per diggable block (luminance-contrast check)
	for id in blocks.keys():
		var blk: Variant = blocks[id]
		if not (blk is Dictionary):
			continue
		var pidx: int = int((blk as Dictionary).get("palette_index", -1))
		if pidx < 0 or pidx >= colors.size():
			errors.append("block_types[%s]: palette_index %d out of palette range [0,%d)" % [id, pidx, colors.size()])
		if not bool((blk as Dictionary).get("diggable", false)):
			continue
		if pidx >= 0 and pidx < colors.size() and Color.html_is_valid(str(colors[pidx])):
			lum_rows.append({"id": str(id), "lum": _rel_luminance(Color.html(str(colors[pidx])))})
	for i in range(lum_rows.size()):
		for j in range(i + 1, lum_rows.size()):
			var d: float = absf(float(lum_rows[i]["lum"]) - float(lum_rows[j]["lum"]))
			if d < MIN_BLOCK_LUMINANCE_DELTA:
				errors.append("palette: block colors for '%s' and '%s' differ in luminance by only %.3f (< %.3f) — block types must contrast in luminance, not just hue (AC-5.10.3)" % [lum_rows[i]["id"], lum_rows[j]["id"], d, MIN_BLOCK_LUMINANCE_DELTA])

## WCAG relative luminance (0..1). Local copy so the data gate is self-contained.
static func _rel_luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)

static func _lin(ch: float) -> float:
	if ch <= 0.04045:
		return ch / 12.92
	return pow((ch + 0.055) / 1.055, 2.4)

## UNIT MAPGEN (infinite descent): depth_bands.json is now the CONTINUOUS depth-weight CURVE
## descriptor — an OBJECT with two anchor weight tables (surface_weights, cap_weights), a
## cap_depth_cells, a curve shape, and the HUD sample bucket — NOT the old discrete band array.
## Enforce: both anchors non-empty objects; every weighted id is a known DIGGABLE block with a
## weight > 0; cap_depth_cells > surface_depth_cells; curve ∈ {linear, smoothstep};
## hud_sample_band_cells > 0. (Replaces _check_bands.)
const GEN_CURVES := ["linear", "smoothstep"]

static func _check_depth_curve(curve: Variant, blocks: Dictionary, errors: Array) -> void:
	if curve == null:
		errors.append("missing table: depth_bands.json")
		return
	if not (curve is Dictionary):
		errors.append("depth_bands.json must be a JSON object (the continuous depth-weight curve; UNIT MAPGEN)")
		return
	var c: Dictionary = curve
	var surface_depth: int = int(c.get("surface_depth_cells", 0))
	if not c.has("cap_depth_cells"):
		errors.append("depth_bands: missing 'cap_depth_cells'")
	elif int(c.get("cap_depth_cells", 0)) <= surface_depth:
		errors.append("depth_bands: 'cap_depth_cells' (%d) must be > 'surface_depth_cells' (%d)" % [int(c.get("cap_depth_cells", 0)), surface_depth])
	if not c.has("curve"):
		errors.append("depth_bands: missing 'curve'")
	elif not GEN_CURVES.has(str(c.get("curve", ""))):
		errors.append("depth_bands: 'curve' '%s' must be one of %s" % [str(c.get("curve")), str(GEN_CURVES)])
	if not c.has("hud_sample_band_cells"):
		errors.append("depth_bands: missing 'hud_sample_band_cells'")
	elif int(c.get("hud_sample_band_cells", 0)) <= 0:
		errors.append("depth_bands: 'hud_sample_band_cells' must be > 0")
	# The base filler curve is "how hard"; the ore overlay is "how rich". Ores live ONLY in
	# ore_overlays.json — an overlay-owned block id appearing in a base anchor would double-count
	# it (filler weight + overlay stamp). Reject any base-table id that the overlay claims (D2).
	var overlay_ids: Dictionary = {}
	var ov: Variant = _root_ore_overlays
	if ov is Dictionary:
		var ores: Variant = (ov as Dictionary).get("ores")
		if ores is Dictionary:
			for oid in (ores as Dictionary).keys():
				var o: Variant = (ores as Dictionary)[oid]
				if o is Dictionary:
					overlay_ids[str((o as Dictionary).get("block_id", oid))] = true
	_check_anchor_weights("surface_weights", c.get("surface_weights"), blocks, overlay_ids, errors)
	_check_anchor_weights("cap_weights", c.get("cap_weights"), blocks, overlay_ids, errors)

## One anchor weight table: a non-empty object whose keys are known diggable blocks, each
## with a weight > 0. (A block may be absent from one anchor — that means weight 0 there.)
## An overlay-owned id (in ore_overlays) must NOT appear here — that re-tangles the layers.
static func _check_anchor_weights(label: String, weights: Variant, blocks: Dictionary, overlay_ids: Dictionary, errors: Array) -> void:
	if not (weights is Dictionary) or (weights as Dictionary).is_empty():
		errors.append("depth_bands.%s: must be a non-empty object" % label)
		return
	for block_id in (weights as Dictionary).keys():
		if not blocks.has(block_id):
			errors.append("depth_bands.%s: references unknown block '%s'" % [label, block_id])
		elif not blocks.get(block_id, {}).get("diggable", false):
			errors.append("depth_bands.%s: block '%s' is not diggable" % [label, block_id])
		if overlay_ids.has(block_id):
			errors.append("depth_bands.%s: ore '%s' must not appear in the base filler curve — it belongs to ore_overlays.json (the overlay layer); base curve is filler-only (continuous-gen D2)" % [label, block_id])
		if float((weights as Dictionary)[block_id]) <= 0.0:
			errors.append("depth_bands.%s: weight for '%s' must be > 0" % [label, block_id])

## AC-5.5.2 (depth reward, now over the continuous curve): with increasing depth, the EXPECTED
## ore value per cell and the RARE-GEM (highest-value block type) probability SHALL both strictly
## rise toward the cap, then FREEZE at/below cap_depth_cells (bounded richness). We sample the
## continuous lerp at y ∈ {0, cap/4, cap/2, 3cap/4, cap} and assert strict increase across the
## samples, plus that a sample PAST the cap equals the cap sample (the boundedness guard). A /data
## edit that flattens or inverts the ramp — or makes cap_weights no richer than surface_weights —
## fails the build, not the player. This is the machine-checked AC-5.5.2 invariant over the curve.
## NEW (continuous-gen v0.7): the per-ore noise-overlay layer (data/ore_overlays.json).
## Enforces the join + range invariants the generator + reward proxy rely on (design §5.3):
## priority_order is a permutation of the ores keys; each ore's block_id exists + is diggable
## + has ore.value > 0; field_salt is a unique int; frequency > 0; depth_min >= 0;
## 0 < threshold_deep <= threshold_shallow < 1 (deeper never rarer); priority == the ore's
## index in priority_order (the deterministic walk order). Every rule is mutation-verified by
## a targeted negative in test_data_integrity.
static func _check_ore_overlays(overlays: Variant, blocks: Dictionary, errors: Array) -> void:
	if overlays == null:
		errors.append("missing table: ore_overlays.json (continuous-gen ore overlay layer)")
		return
	if not (overlays is Dictionary):
		errors.append("ore_overlays.json must be a JSON object")
		return
	var ov: Dictionary = overlays
	var order: Variant = ov.get("priority_order")
	var ores: Variant = ov.get("ores")
	if not (ores is Dictionary) or (ores as Dictionary).is_empty():
		errors.append("ore_overlays: 'ores' must be a non-empty object")
		return
	var ores_d: Dictionary = ores
	if not (order is Array):
		errors.append("ore_overlays: 'priority_order' must be an array")
		return
	var order_a: Array = order
	# priority_order must be a PERMUTATION of the ores keys (same set, same size, no dupes).
	if order_a.size() != ores_d.size():
		errors.append("ore_overlays: 'priority_order' length %d != number of ores %d (must be a permutation)" % [order_a.size(), ores_d.size()])
	var seen_order: Dictionary = {}
	for oid in order_a:
		if seen_order.has(oid):
			errors.append("ore_overlays: 'priority_order' has duplicate '%s'" % str(oid))
		seen_order[str(oid)] = true
		if not ores_d.has(str(oid)):
			errors.append("ore_overlays: 'priority_order' lists '%s' which is not in 'ores'" % str(oid))
	for oid in ores_d.keys():
		if not seen_order.has(str(oid)):
			errors.append("ore_overlays: ore '%s' is missing from 'priority_order'" % str(oid))
	# Per-ore field + join checks; field_salt uniqueness; priority == index in priority_order.
	var salts: Dictionary = {}
	for oid in ores_d.keys():
		var o: Variant = ores_d[oid]
		if not (o is Dictionary):
			errors.append("ore_overlays.ores[%s]: must be an object" % str(oid))
			continue
		var od: Dictionary = o
		for k in ["block_id", "field_salt", "frequency", "depth_min", "threshold_shallow", "threshold_deep", "priority"]:
			if not od.has(k):
				errors.append("ore_overlays.ores[%s]: missing '%s'" % [str(oid), k])
		var bid: String = str(od.get("block_id", ""))
		if not blocks.has(bid):
			errors.append("ore_overlays.ores[%s]: block_id '%s' is not a known block" % [str(oid), bid])
		else:
			var blk: Variant = blocks[bid]
			if not (blk is Dictionary) or not bool((blk as Dictionary).get("diggable", false)):
				errors.append("ore_overlays.ores[%s]: block_id '%s' must be diggable" % [str(oid), bid])
			elif _ore_value(blk) <= 0:
				errors.append("ore_overlays.ores[%s]: block_id '%s' must have ore.value > 0 (an overlay ore is a reward)" % [str(oid), bid])
		var salt: int = int(od.get("field_salt", 0))
		if salts.has(salt):
			errors.append("ore_overlays.ores[%s]: field_salt %d is not unique (collides with '%s') — fields would correlate" % [str(oid), salt, str(salts[salt])])
		salts[salt] = oid
		if float(od.get("frequency", 0.0)) <= 0.0:
			errors.append("ore_overlays.ores[%s]: frequency must be > 0 (it sets the cluster size)" % str(oid))
		if int(od.get("depth_min", -1)) < 0:
			errors.append("ore_overlays.ores[%s]: depth_min must be >= 0" % str(oid))
		var thr_sh: float = float(od.get("threshold_shallow", -1.0))
		var thr_dp: float = float(od.get("threshold_deep", -1.0))
		if thr_dp <= 0.0 or thr_dp >= 1.0:
			errors.append("ore_overlays.ores[%s]: threshold_deep %s must be in (0,1)" % [str(oid), str(thr_dp)])
		if thr_sh <= 0.0 or thr_sh >= 1.0:
			errors.append("ore_overlays.ores[%s]: threshold_shallow %s must be in (0,1)" % [str(oid), str(thr_sh)])
		if thr_dp > thr_sh:
			errors.append("ore_overlays.ores[%s]: threshold_deep %s must be <= threshold_shallow %s (deeper is never rarer)" % [str(oid), str(thr_dp), str(thr_sh)])
		# priority must equal the ore's index in priority_order (so the field + the walk agree).
		var idx: int = order_a.find(str(oid))
		if idx >= 0 and int(od.get("priority", -1)) != idx:
			errors.append("ore_overlays.ores[%s]: priority %d must equal its index %d in priority_order" % [str(oid), int(od.get("priority", -1)), idx])

## NEW (continuous-gen v0.7): the ore VALUE LADDER. Walking the ores rarest→common (the
## priority_order, index 0 = rarest), each ore's ore.value must be STRICTLY DECREASING
## (diamond > gem > gold > silver > copper > coal). Catches a value inversion (the live
## gold<silver bug) as a build failure (design §5.3, D11).
static func _check_ore_value_ladder(overlays: Variant, blocks: Dictionary, errors: Array) -> void:
	if not (overlays is Dictionary):
		return  # shape errors already reported by _check_ore_overlays
	var order: Variant = (overlays as Dictionary).get("priority_order")
	var ores: Variant = (overlays as Dictionary).get("ores")
	if not (order is Array) or not (ores is Dictionary):
		return
	var prev_value: int = -1
	var prev_id: String = ""
	for oid in (order as Array):
		var o: Variant = (ores as Dictionary).get(str(oid))
		if not (o is Dictionary):
			continue
		var bid: String = str((o as Dictionary).get("block_id", ""))
		if not blocks.has(bid) or not (blocks[bid] is Dictionary):
			continue
		var v: int = _ore_value(blocks[bid])
		if prev_value >= 0 and v >= prev_value:
			errors.append("ore_overlays: ore value ladder must strictly DECREASE rarest→common — '%s' value %d >= rarer '%s' value %d (a value inversion; rarer ore must be worth more)" % [str(oid), v, prev_id, prev_value])
		prev_value = v
		prev_id = str(oid)

static func _check_depth_reward_monotone(curve: Variant, overlays: Variant, blocks: Dictionary, errors: Array) -> void:
	if not (curve is Dictionary):
		return  # shape errors already reported by _check_depth_curve
	var c: Dictionary = curve
	var sw: Variant = c.get("surface_weights")
	var cw: Variant = c.get("cap_weights")
	if not (sw is Dictionary) or not (cw is Dictionary):
		return  # anchor-shape errors already reported
	var surface_depth: int = int(c.get("surface_depth_cells", 0))
	var cap: int = int(c.get("cap_depth_cells", 0))
	if cap <= surface_depth:
		return  # cap-depth error already reported
	if not (overlays is Dictionary):
		return  # overlay-shape errors already reported by _check_ore_overlays
	var smoothstep: bool = str(c.get("curve", "linear")) == "smoothstep"
	# The "gem" is the single highest ore value present in the registry (now diamond); gem
	# probability at a depth is the combined coverage of every ore at that max value (handles ties).
	var gem_value: int = -1
	for id in blocks.keys():
		if blocks[id] is Dictionary:
			gem_value = maxi(gem_value, _ore_value(blocks[id]))
	# Ore overlay entries sorted rarest-first (ascending priority) — the SAME walk order the
	# generator + Registry.full_odds_at use, so the priority-reduction budget matches generation.
	var ores: Array = _overlay_priority_rows(overlays)
	var span: int = cap - surface_depth
	var sample_depths: Array = [
		surface_depth,
		surface_depth + span / 4,
		surface_depth + span / 2,
		surface_depth + (3 * span) / 4,
		cap,
		cap + maxi(1, span),  # past the cap — must equal the cap sample (boundedness)
	]
	var rows: Array = []
	for y in sample_depths:
		rows.append(_combined_reward_at(sw, cw, ores, blocks, surface_depth, cap, smoothstep, gem_value, int(y)))
	# Strict rise up to and including the cap (indices 0..4); index 5 is the past-cap freeze check.
	for i in range(1, 5):
		var lo: Dictionary = rows[i - 1]
		var hi: Dictionary = rows[i]
		if hi["ev"] <= lo["ev"]:
			errors.append("depth_bands: expected ore value per cell must strictly rise with depth — at y=%d EV %.3f <= shallower y=%d EV %.3f (SPEC AC-5.5.2)" % [hi["y"], hi["ev"], lo["y"], lo["ev"]])
		if hi["gem"] <= lo["gem"]:
			errors.append("depth_bands: rare-gem probability must strictly rise with depth — at y=%d gem-prob %.4f <= shallower y=%d gem-prob %.4f (SPEC AC-5.5.2)" % [hi["y"], hi["gem"], lo["y"], lo["gem"]])
	# Boundedness: the past-cap sample must equal the cap sample (s is clamped at the cap).
	var at_cap: Dictionary = rows[4]
	var past_cap: Dictionary = rows[5]
	if absf(float(past_cap["ev"]) - float(at_cap["ev"])) > 0.0001 or absf(float(past_cap["gem"]) - float(at_cap["gem"])) > 0.0001:
		errors.append("depth_bands: reward must FREEZE at/below cap_depth_cells — past-cap EV/gem (%.3f/%.4f) differs from cap EV/gem (%.3f/%.4f); the curve is not clamped at the cap (SPEC AC-5.5.2)" % [past_cap["ev"], past_cap["gem"], at_cap["ev"], at_cap["gem"]])

## Ore-overlay rows sorted rarest-first (ascending `priority`). Local mirror of
## Registry.ore_priority so the data gate is self-contained.
static func _overlay_priority_rows(overlays: Variant) -> Array:
	if not (overlays is Dictionary):
		return []
	var ores: Variant = (overlays as Dictionary).get("ores")
	if not (ores is Dictionary):
		return []
	var rows: Array = []
	for id in (ores as Dictionary).keys():
		var o: Variant = (ores as Dictionary)[id]
		if o is Dictionary:
			rows.append(o)
	rows.sort_custom(func(a, b): return int(a.get("priority", 0)) < int(b.get("priority", 0)))
	return rows

## Combined base-filler + ore-overlay EV + gem-probability at depth `y`, with the priority-
## reduction budget (rarest ore eats the cell-coverage budget first → honest overlap). Mirrors
## the generation precedence + Registry.full_odds_at. The ore odds use the analytic proxy
## 1-threshold (monotone in depth), an upper bound — acceptable: the golden grids pin the real
## generated ids, and this proxy is exactly what the strict-rise invariant needs (design §1.3).
static func _combined_reward_at(sw: Variant, cw: Variant, ores: Array, blocks: Dictionary, surface_depth: int, cap: int, smoothstep: bool, gem_value: int, y: int) -> Dictionary:
	var t: float = clampf(float(y - surface_depth) / float(cap - surface_depth), 0.0, 1.0)
	var s: float = (t * t * (3.0 - 2.0 * t)) if smoothstep else t
	var remaining: float = 1.0
	var ev: float = 0.0
	var gem: float = 0.0
	for o in ores:
		var depth_min: int = int(o.get("depth_min", 0))
		var odds: float = 0.0
		if y >= depth_min:
			var shallow: float = float(o.get("threshold_shallow", 1.0))
			var deep: float = float(o.get("threshold_deep", 1.0))
			var thr: float = shallow + s * (deep - shallow)
			odds = clampf(1.0 - thr, 0.0, 1.0)
		odds = odds * remaining  # priority reduction (rarest eats the budget first)
		remaining -= odds
		var bid: String = str(o.get("block_id", ""))
		var v: int = 0
		if blocks.has(bid) and blocks[bid] is Dictionary:
			v = _ore_value(blocks[bid])
		ev += odds * float(v)
		if gem_value > 0 and v == gem_value:
			gem += odds
	if remaining < 0.0:
		remaining = 0.0
	# Base filler fills the remaining budget; add its EV-per-cell contribution.
	ev += remaining * _base_filler_ev(sw, cw, blocks, s)
	return { "y": y, "ev": ev, "gem": gem }

## Expected ore value per cell of JUST the base filler weight table at interpolation s. The
## filler is dirt/rock/hard_rock; rock carries a small $5 ore value so this is small but > 0.
static func _base_filler_ev(sw: Variant, cw: Variant, blocks: Dictionary, s: float) -> float:
	var ids: Dictionary = {}
	for k in (sw as Dictionary).keys():
		ids[k] = true
	for k in (cw as Dictionary).keys():
		ids[k] = true
	var total: float = 0.0
	var value_sum: float = 0.0
	for id in ids.keys():
		var a: float = float((sw as Dictionary).get(id, 0.0))
		var b: float = float((cw as Dictionary).get(id, 0.0))
		var w: float = a + s * (b - a)
		if w <= 0.0:
			continue
		if not blocks.has(id) or not (blocks[id] is Dictionary):
			continue
		total += w
		value_sum += w * float(_ore_value(blocks[id]))
	return value_sum / total if total > 0.0 else 0.0

## Ore value of a block dict (0 if no ore). Local helper so the depth-reward check does not
## need the full Registry-by-id indirection (blocks here is the raw block_types table).
static func _ore_value(blk: Variant) -> int:
	if not (blk is Dictionary):
		return 0
	var ore: Variant = (blk as Dictionary).get("ore")
	if ore is Dictionary:
		return int((ore as Dictionary).get("value", 0))
	return 0

static func _check_explosives(explosives: Dictionary, balance: Dictionary, errors: Array) -> void:
	if explosives.is_empty():
		errors.append("explosives: registry is empty")
	var max_radius: int = int(balance.get("max_blast_radius_cells", 9999))
	for id in explosives.keys():
		var ex: Variant = explosives[id]
		if not (ex is Dictionary):
			errors.append("explosives[%s]: must be an object" % id)
			continue
		# AC-5.4.1 names the FULL explosive-resource shape. ALL of these are required so a
		# /data author can't ship a physics-incomplete charge that silently falls back to
		# code-side defaults (throw_params.gd), violating "balance is data, never code".
		for k in ["mass", "bounce", "friction", "base_impulse", "detonation_mode",
				"blast_radius_cells", "blast_intensity", "blast_falloff",
				"sticky", "efficiency", "rarity", "tier"]:
			if not ex.has(k):
				errors.append("explosives[%s]: missing '%s'" % [id, k])
		if float(ex.get("mass", 0.0)) <= 0.0:
			errors.append("explosives[%s]: mass must be > 0" % id)
		if float(ex.get("base_impulse", 0.0)) <= 0.0:
			errors.append("explosives[%s]: base_impulse must be > 0" % id)
		if not DETONATION_MODES.has(ex.get("detonation_mode", "")):
			errors.append("explosives[%s]: detonation_mode must be one of %s" % [id, str(DETONATION_MODES)])
		var radius: int = int(ex.get("blast_radius_cells", 0))
		if radius < 1:
			errors.append("explosives[%s]: blast_radius_cells must be >= 1" % id)
		elif radius > max_radius:
			errors.append("explosives[%s]: blast_radius_cells %d exceeds balance.max_blast_radius_cells %d" % [id, radius, max_radius])
		if int(ex.get("blast_intensity", 0)) <= 0:
			errors.append("explosives[%s]: blast_intensity must be > 0" % id)
		# Single source of truth: the falloff array length is exactly radius+1
		# (index 0 = center cell, index r = the cell r away). AC-5.2.4.
		var falloff: Variant = ex.get("blast_falloff")
		if not (falloff is Array):
			errors.append("explosives[%s]: blast_falloff must be an array" % id)
		elif radius >= 1 and (falloff as Array).size() != radius + 1:
			errors.append("explosives[%s]: blast_falloff length %d must equal blast_radius_cells+1 (%d)" % [id, (falloff as Array).size(), radius + 1])
		# Each falloff entry must be in (0, 1] — a 0/negative creates a dead blast ring
		# (silently skipped at runtime in blast.gd) the gate should catch, not hide.
		if falloff is Array:
			for i in range((falloff as Array).size()):
				var fv: float = float((falloff as Array)[i])
				if fv <= 0.0 or fv > 1.0:
					errors.append("explosives[%s]: blast_falloff[%d] %s must be in (0, 1] (a 0 or negative value creates a dead blast ring)" % [id, i, str(fv)])
		# Fuse-mode explosives must declare a positive fuse (AC-5.4.1).
		if ex.get("detonation_mode", "") == "fuse_seconds":
			if not ex.has("fuse_seconds") or float(ex.get("fuse_seconds", 0.0)) <= 0.0:
				errors.append("explosives[%s]: detonation_mode 'fuse_seconds' requires fuse_seconds > 0" % id)
		# Physics fields consumed by the live charge (charge.gd:32-33) — non-negative data,
		# not silent code-side defaults.
		if ex.has("bounce") and float(ex.get("bounce", -1.0)) < 0.0:
			errors.append("explosives[%s]: bounce must be >= 0" % id)
		if ex.has("friction") and float(ex.get("friction", -1.0)) < 0.0:
			errors.append("explosives[%s]: friction must be >= 0" % id)
		# Efficiency/cost descriptor (AC-5.4.1/5.4.3): strictly positive (the free charge is
		# the 1.0 baseline; paid charges exceed it — enforced in _check_free_charge).
		if ex.has("efficiency") and float(ex.get("efficiency", 0.0)) <= 0.0:
			errors.append("explosives[%s]: efficiency must be > 0" % id)
		# tier is the gacha/progression ordinal (>= 1); rarity is a non-empty label.
		if ex.has("tier") and int(ex.get("tier", 0)) < 1:
			errors.append("explosives[%s]: tier must be >= 1" % id)
		if ex.has("rarity") and str(ex.get("rarity", "")).is_empty():
			errors.append("explosives[%s]: rarity must be a non-empty label" % id)
	_check_charge_motion_gate(explosives, balance, errors)

## The on_rest charge motion/airtime gate (charge.gd: the "sticky bomb explodes instantly" fix).
## An on_rest charge may only resolve via the sleeping/settled path AFTER it has actually moved —
## gated by charge_min_airtime_seconds + charge_min_travel_px (balance.json). Both are REQUIRED
## tunables (balance is data, never a code literal). The airtime must be strictly > 0 (a 0 gate
## re-opens the frame-0 instant-pop bug) AND strictly less than the smallest sticky fuse_seconds, so
## the gate can never delay a real STUCK sticky's stick-fuse (the freeze path arms its own fuse and
## the gate is irrelevant once frozen, but keeping the airtime below every stick fuse documents that
## the gate is a sub-frame motion guard, not a detonation delay). The travel floor is >= 0 (0 =
## airtime-only gating, valid).
static func _check_charge_motion_gate(explosives: Dictionary, balance: Dictionary, errors: Array) -> void:
	if not balance.has("charge_min_airtime_seconds"):
		errors.append("balance: missing 'charge_min_airtime_seconds' (on_rest charge motion gate)")
	else:
		var airtime: float = float(balance.get("charge_min_airtime_seconds", 0.0))
		if airtime <= 0.0:
			errors.append("balance: 'charge_min_airtime_seconds' %s must be > 0 (a 0 gate re-opens the frame-0 instant-detonation bug)" % str(airtime))
		else:
			# Must sit below the smallest sticky on_rest fuse so it never delays a real stick-fuse.
			var min_sticky_fuse: float = INF
			for id in explosives.keys():
				var ex: Variant = explosives[id]
				if not (ex is Dictionary):
					continue
				if bool((ex as Dictionary).get("sticky", false)) and str((ex as Dictionary).get("detonation_mode", "")) == "on_rest":
					min_sticky_fuse = minf(min_sticky_fuse, maxf(0.0, float((ex as Dictionary).get("fuse_seconds", 0.0))))
			if min_sticky_fuse != INF and airtime >= min_sticky_fuse:
				errors.append("balance: 'charge_min_airtime_seconds' %s must be < the smallest sticky fuse_seconds %s (the motion gate must never delay a real stick-fuse)" % [str(airtime), str(min_sticky_fuse)])
	if not balance.has("charge_min_travel_px"):
		errors.append("balance: missing 'charge_min_travel_px' (on_rest charge motion gate)")
	elif float(balance.get("charge_min_travel_px", -1.0)) < 0.0:
		errors.append("balance: 'charge_min_travel_px' %s must be >= 0 (on_rest charge motion gate)" % str(balance.get("charge_min_travel_px")))
	if not balance.has("sticky_min_delay_seconds"):
		errors.append("balance: missing 'sticky_min_delay_seconds' (sticky charge stick-fuse floor)")
	elif float(balance.get("sticky_min_delay_seconds", 0.0)) < 0.0:
		errors.append("balance: 'sticky_min_delay_seconds' must be >= 0 (sticky charge stick-fuse floor)")

static func _check_packs(packs: Dictionary, explosives: Dictionary, errors: Array) -> void:
	if packs.is_empty():
		errors.append("packs: registry is empty")
	# v0.4: packs grant ONLY finite, efficient (paid) charges. The free unlimited
	# charge is a flagged explosive (see _check_free_charge), not a price-0 pack —
	# so the old "at least one free pack" rule is gone.
	for id in packs.keys():
		var p: Variant = packs[id]
		if not (p is Dictionary):
			errors.append("packs[%s]: must be an object" % id)
			continue
		if int(p.get("price", -1)) < 0:
			errors.append("packs[%s]: price must be >= 0" % id)
		if int(p.get("charge_count", 0)) < 1:
			errors.append("packs[%s]: charge_count must be >= 1" % id)
		# pity_every: implement-or-absent. When present it must be a non-negative
		# int; when > 0 it declares a pity floor, which the pack's table must be
		# able to satisfy (at least one tier-2+ explosive reachable).
		if p.has("pity_every"):
			var pity: int = int(p.get("pity_every", -1))
			if pity < 0:
				errors.append("packs[%s]: pity_every must be >= 0 when present" % id)
		var weights: Variant = p.get("weights")
		if not (weights is Dictionary) or (weights as Dictionary).is_empty():
			errors.append("packs[%s]: weights must be a non-empty object" % id)
			continue
		var has_high_tier := false
		for ex_id in (weights as Dictionary).keys():
			if not explosives.has(ex_id):
				errors.append("packs[%s]: references unknown explosive '%s'" % [id, ex_id])
			elif int((explosives[ex_id] as Dictionary).get("tier", 1)) >= 2:
				has_high_tier = true
			# Packs grant paid charges only: the free charge must never be in a pack table.
			elif bool((explosives[ex_id] as Dictionary).get("free", false)):
				errors.append("packs[%s]: free charge '%s' must not appear in a pack table" % [id, ex_id])
			if float(weights[ex_id]) <= 0.0:
				errors.append("packs[%s]: weight for '%s' must be > 0" % [id, ex_id])
		if int(p.get("pity_every", 0)) > 0 and not has_high_tier:
			errors.append("packs[%s]: pity_every > 0 but no tier>=2 explosive is reachable to guarantee" % id)

## v0.4: exactly one explosive is the flagged FREE unlimited charge, and it must be
## able to break the shallowest floor beneath the platform — no /data config may
## produce a stall (AC-5.4.3, AC-5.5.5, AC-5.4.6, AC-5.12.1).
static func _check_free_charge(explosives: Dictionary, blocks: Dictionary, curve: Variant, balance: Dictionary, errors: Array) -> void:
	if explosives.is_empty():
		return  # already reported by _check_explosives
	var free_ids: Array = []
	for id in explosives.keys():
		var ex: Variant = explosives[id]
		if ex is Dictionary and bool(ex.get("free", false)):
			free_ids.append(id)
	if free_ids.is_empty():
		errors.append("explosives: exactly one explosive must be flagged 'free: true' (the free unlimited charge); found none (SPEC AC-5.12.1)")
		return
	if free_ids.size() > 1:
		errors.append("explosives: exactly one explosive may be flagged 'free: true'; found %d: %s" % [free_ids.size(), str(free_ids)])
		return
	var free: Dictionary = explosives[free_ids[0]]
	# The free charge must not also be a paid pity guarantee — it should be tier 1.
	if int(free.get("tier", 1)) != 1:
		errors.append("explosives[%s]: the free charge must be tier 1 (the inefficient baseline)" % free_ids[0])

	# AC-5.4.3: ALL other (paid) explosives SHALL be MORE efficient than the free charge —
	# efficiency is the thing money buys. Enforce strict ordering so /data can't silently
	# make the free charge as good as (or better than) a paid one.
	var free_eff: float = float(free.get("efficiency", 1.0))
	for oid in explosives.keys():
		if oid == free_ids[0]:
			continue
		var oex: Variant = explosives[oid]
		if not (oex is Dictionary):
			continue
		if float((oex as Dictionary).get("efficiency", 0.0)) <= free_eff:
			errors.append("explosives[%s]: paid charge efficiency %s must exceed the free charge's %s (AC-5.4.3: money buys efficiency)" % [oid, str((oex as Dictionary).get("efficiency", 0.0)), str(free_eff)])

	# No-stall solvability (AC-5.5.5 / AC-5.4.6). The free charge need NOT one-hit
	# the floor — AC-5.4.6 says it breaks it "eventually / slowly". The real stall
	# condition is the free charge dealing ZERO integer damage to a cell: surviving
	# blocks retain damage (AC-5.2.7, no regen), so any per-throw damage >= 1
	# guarantees progress. We verify this against the WORST-CASE *scaled* floor HP
	# (AC-5.5.5: "against each mine's floor-HP scaling"), i.e. the deepest cell in the
	# hardest mine, where HP = base_hp x depth_mult x mine_hardness_mult is largest.
	var floor_hp: int = _max_scaled_floor_hp(curve, blocks, balance)
	if floor_hp < 0:
		return  # no diggable floor — reported by curve checks
	# Per-cell centre damage the free charge deals (integer-floored, as the grid is).
	var intensity: float = float(free.get("blast_intensity", 0))
	var falloff: Variant = free.get("blast_falloff")
	var f0: float = 1.0
	if falloff is Array and (falloff as Array).size() > 0:
		f0 = float((falloff as Array)[0])
	# Fold WORST-CASE fuzz into the no-stall floor: the live blast multiplies damage by a
	# factor in [1 - blast_fuzz_pct, 1 + blast_fuzz_pct] (blast.gd:68,86). The worst roll must
	# still deal >= 1 integer damage, else a throw can do literally nothing on a bad fuzz draw
	# (AC-5.5.5 no-stall, robust form — the unfuzzed check alone missed low-intensity charges).
	var fuzz_pct: float = clampf(float(balance.get("blast_fuzz_pct", 0.0)), 0.0, 1.0)
	var centre_damage: int = int(intensity * f0 * (1.0 - fuzz_pct))
	if centre_damage <= 0:
		errors.append("explosives[%s]: free charge worst-case damage is 0 (intensity %s x falloff[0] %s x (1-fuzz %s)) — a throw can deal 0 against the scaled floor (worst-case HP %d); would stall (SPEC AC-5.5.5 / AC-5.4.6)" % [free_ids[0], str(intensity), str(f0), str(fuzz_pct), floor_hp])

## Worst-case scaled floor HP in the infinite shaft, or -1 if no diggable floor exists.
## The hardest floor sits at/below the cap depth (where the rich cap_weights apply AND the
## depth HP multiplier has hit its ceiling max_depth_hp_mult) in the hardest mine; HP =
## base_hp x min(depth_mult, max_depth_hp_mult) x mine_hardness_mult (AC-5.2.1, UNIT MAPGEN
## HP cap). We take the LOWEST-HP diggable block present in cap_weights (the easiest floor the
## player could be standing on at the richest depth) so the no-stall bound is the worst
## plausible case. The HP cap is what keeps this FINITE in an unbounded shaft.
static func _max_scaled_floor_hp(curve: Variant, blocks: Dictionary, balance: Dictionary) -> int:
	if not (curve is Dictionary):
		return -1
	var weights: Variant = (curve as Dictionary).get("cap_weights")
	if not (weights is Dictionary):
		return -1
	var min_base_hp: int = -1
	for bid in (weights as Dictionary).keys():
		if not blocks.has(bid):
			continue
		var blk: Dictionary = blocks[bid]
		if not bool(blk.get("diggable", false)):
			continue
		var hp: int = int(blk.get("max_hp", 0))
		if hp > 0 and (min_base_hp < 0 or hp < min_base_hp):
			min_base_hp = hp
	if min_base_hp < 0:
		return -1
	# depth_mult at/below the cap = the ceiling max_depth_hp_mult (HP stops scaling there).
	var depth_mult: float = float(balance.get("max_depth_hp_mult", 1.0))
	if depth_mult <= 0.0:
		depth_mult = 1.0
	var mine_mult: float = float(balance.get("mine_hardness_mult_max", 1.0))
	return int(round(float(min_base_hp) * depth_mult * mine_mult))

## U2 (v0.4): FastNoiseLite generation parameters. Coherent gen needs a positive
## frequency, >=1 octave, and a positive normalization std (the normal-CDF transform
## that keeps the coherent noise distribution-correct). These are tunables in /data.
static func _check_generation(gen: Variant, errors: Array) -> void:
	if gen == null:
		errors.append("missing table: generation.json")
		return
	if not (gen is Dictionary):
		errors.append("generation.json must be a JSON object")
		return
	var g: Dictionary = gen
	if not g.has("noise_frequency") or float(g.get("noise_frequency", 0.0)) <= 0.0:
		errors.append("generation: 'noise_frequency' must be > 0")
	if not g.has("noise_octaves") or int(g.get("noise_octaves", 0)) < 1:
		errors.append("generation: 'noise_octaves' must be >= 1")
	if not g.has("noise_std") or float(g.get("noise_std", 0.0)) <= 0.0:
		errors.append("generation: 'noise_std' must be > 0 (normal-CDF normalization)")

## Relic placement config (AC-5.6.1, UNIT MAPGEN infinite descent). The relic is the dig
## objective + terminator: a single seed-pinned cell in a deterministic DEEP window, confined
## to a center column band. The depth window [min_depth, min_depth+span) must sit BELOW the sky
## (so it's in generated solid terrain, reachable down the shaft) — there is no mine floor to
## clamp it to in the infinite shaft. The column band is checked by _check_relic_band.
static func _check_relics(relics: Variant, curve: Variant, balance: Dictionary, errors: Array) -> void:
	if relics == null:
		errors.append("missing table: relics.json")
		return
	if not (relics is Dictionary):
		errors.append("relics.json must be a JSON object")
		return
	var r: Dictionary = relics
	var min_depth: int = int(r.get("min_depth_cells", -1))
	if not r.has("min_depth_cells") or min_depth <= 0:
		errors.append("relics: 'min_depth_cells' must be present and > 0")
	var span: int = int(r.get("depth_span_cells", 0))
	if not r.has("depth_span_cells") or span < 1:
		errors.append("relics: 'depth_span_cells' must be present and >= 1")
	if not r.has("prestige_value") or int(r.get("prestige_value", 0)) != 1:
		errors.append("relics: 'prestige_value' must be exactly 1 (one prestige point per relic, SPEC v0.5 AC-5.6.6)")
	# The relic depth window must sit below the sky band (in generated solid terrain), so the
	# relic cell is actually a breakable block and not floating in the air column.
	var sky: int = int(balance.get("sky_band_cells", 0))
	if min_depth > 0 and min_depth <= sky:
		errors.append("relics: 'min_depth_cells' (%d) must be deeper than the sky band (%d) so the relic sits in solid terrain" % [min_depth, sky])
	# For a BOUNDED mine (mine_height_cells > 0) the relic window must still fit inside it.
	var mine_h: int = int(balance.get("mine_height_cells", 0))
	if mine_h > 0 and min_depth > 0 and span >= 1 and min_depth + span > mine_h:
		errors.append("relics: relic depth range [%d,%d) exceeds the bounded mine height %d" % [min_depth, min_depth + span, mine_h])
	# Continuous-gen v0.7: the relic depth is the power-CDF inverse-transform selector. The
	# GUARANTEED depth bounds it (the mine is COMPLETABLE — descend to here and the relic is on
	# the corridor). Enforce min_depth < guaranteed <= cap_depth_cells (within the rich-but-bounded
	# generated band) and a back-load k > 1 (k=1 is uniform; the design wants rare-shallow). The glow
	# is the in-world purple beacon — its color must parse + pulse period > 0 (design §3, §5.3).
	if not r.has("relic_guaranteed_depth_cells"):
		errors.append("relics: missing 'relic_guaranteed_depth_cells' (the depth the relic is guaranteed by — completability)")
	else:
		var guaranteed: int = int(r.get("relic_guaranteed_depth_cells", 0))
		if guaranteed <= min_depth:
			errors.append("relics: 'relic_guaranteed_depth_cells' (%d) must be > 'min_depth_cells' (%d)" % [guaranteed, min_depth])
		var cap_depth: int = 0
		if curve is Dictionary:
			cap_depth = int((curve as Dictionary).get("cap_depth_cells", 0))
		if cap_depth > 0 and guaranteed > cap_depth:
			errors.append("relics: 'relic_guaranteed_depth_cells' (%d) must be <= cap_depth_cells (%d) so the relic sits within the generated band (completability)" % [guaranteed, cap_depth])
	if not r.has("relic_back_load_k"):
		errors.append("relics: missing 'relic_back_load_k' (relic depth back-load exponent)")
	elif int(r.get("relic_back_load_k", 0)) <= 1:
		errors.append("relics: 'relic_back_load_k' %s must be > 1 (k=1 is uniform; the relic should be rarer shallow)" % str(r.get("relic_back_load_k")))
	if not r.has("glow_color"):
		errors.append("relics: missing 'glow_color' (the in-world purple relic beacon)")
	elif not Color.html_is_valid(str(r.get("glow_color", ""))):
		errors.append("relics: 'glow_color' '%s' must be a valid hex color" % str(r.get("glow_color")))
	if not r.has("glow_pulse_seconds"):
		errors.append("relics: missing 'glow_pulse_seconds' (relic glow pulse period)")
	elif float(r.get("glow_pulse_seconds", 0.0)) <= 0.0:
		errors.append("relics: 'glow_pulse_seconds' %s must be > 0" % str(r.get("glow_pulse_seconds")))
	_check_relic_band(r, balance, errors)

## AC-5.6.1 (relic center band): the relic column is confined to |relic_col - center| <=
## relic_band_half_cells (a 13-wide band at 6). The band must be present, >= 0, and FIT the
## configured mine width (a band wider than the mine is meaningless). Keeps the relic on/near
## the descent corridor in the infinite shaft.
static func _check_relic_band(r: Dictionary, balance: Dictionary, errors: Array) -> void:
	if not r.has("relic_band_half_cells"):
		errors.append("relics: missing 'relic_band_half_cells' (AC-5.6.1 center band)")
		return
	var half: int = int(r.get("relic_band_half_cells", -1))
	if half < 0:
		errors.append("relics: 'relic_band_half_cells' must be >= 0 (AC-5.6.1)")
		return
	# Continuous-gen v0.7: the band is capped at 5 (an 11-wide band) — the relic anchor clamps to
	# this cap, so a value above 5 silently wouldn't widen the band, and the gate makes that explicit.
	if half > 5:
		errors.append("relics: 'relic_band_half_cells' %d must be <= 5 (11-wide cap; the 2×2 relic stays on the descent corridor) (AC-5.6.1)" % half)
	var width: int = int(balance.get("mine_width_cells", 0))
	if width > 0 and (2 * half + 1) > width:
		errors.append("relics: relic band width %d (2*%d+1) exceeds mine width %d (AC-5.6.1)" % [2 * half + 1, half, width])
	# The 2×2 footprint (relic_at uses RELIC_W=2) must fit in [0,width): the rightmost band column
	# is center+half and the footprint extends one more cell right, so center+half+1 < width.
	if width > 0:
		var center: int = int(width / 2)
		if center + half + 1 >= width:
			errors.append("relics: the 2×2 relic footprint at the band's right edge (col %d..%d) overflows mine width %d (AC-5.6.1)" % [center + half, center + half + 1, width])

## AC-5.5.x (pack affordability): the player can always afford to PARTICIPATE in the shop loop —
## the cheapest pack's price must be <= starting_money. Otherwise a fresh dig can't buy any pack
## even though the shop is presented (the free charge still works, so it's not a stall, but the
## economy loop would be unreachable on dig 1).
static func _check_pack_affordability(packs: Dictionary, balance: Dictionary, errors: Array) -> void:
	if packs.is_empty():
		return  # emptiness reported by _check_packs
	var cheapest: int = -1
	for id in packs.keys():
		var p: Variant = packs[id]
		if not (p is Dictionary):
			continue
		var price: int = int((p as Dictionary).get("price", 0))
		if cheapest < 0 or price < cheapest:
			cheapest = price
	if cheapest < 0:
		return
	var starting: int = int(balance.get("starting_money", 0))
	if cheapest > starting:
		errors.append("packs: cheapest pack price %d exceeds starting_money %d — the player can't afford to participate in the shop loop on dig 1 (UNIT MAPGEN economy)" % [cheapest, starting])

## U9 (v0.4): minimal prestige upgrades (AC-5.6.4 / power growth). Each upgrade must
## declare a positive prestige cost, a known effect, a positive magnitude, and a
## positive max_level — so a purchase debits a currency, is bounded, and measurably
## changes a dig stat (no declared-but-inert upgrade). The table must be non-empty so
## the minimal prestige purchase exists (VERTICAL_SLICE §1: "buy one permanent upgrade").
static func _check_prestige(prestige: Variant, errors: Array) -> void:
	if prestige == null:
		errors.append("missing table: prestige.json")
		return
	if not (prestige is Dictionary):
		errors.append("prestige.json must be a JSON object")
		return
	var ups: Dictionary = prestige
	if ups.is_empty():
		errors.append("prestige: registry is empty (need at least one power-growth upgrade)")
		return
	var known_effects := ["blast_intensity_mult", "light_radius_mult", "throw_cooldown_mult"]
	for id in ups.keys():
		var up: Variant = ups[id]
		if not (up is Dictionary):
			errors.append("prestige[%s]: must be an object" % id)
			continue
		for k in ["display_name", "effect", "magnitude", "cost_prestige", "max_level"]:
			if not up.has(k):
				errors.append("prestige[%s]: missing '%s'" % [id, k])
		if int(up.get("cost_prestige", 0)) <= 0:
			errors.append("prestige[%s]: cost_prestige must be > 0" % id)
		var effect: String = str(up.get("effect", ""))
		var mag: float = float(up.get("magnitude", 0.0))
		if effect == "throw_cooldown_mult":
			if mag >= 0.0:
				errors.append("prestige[%s]: throw_cooldown_mult magnitude must be < 0 (a reduction)" % id)
		elif mag <= 0.0:
			errors.append("prestige[%s]: magnitude must be > 0" % id)
		if int(up.get("max_level", 0)) <= 0:
			errors.append("prestige[%s]: max_level must be > 0" % id)
		if up.has("effect") and not known_effects.has(effect):
			errors.append("prestige[%s]: unknown effect '%s' (known: %s)" % [id, effect, str(known_effects)])


## Per-dig MONEY upgrades (Shaft Engineering, etc.): bought with in-dig money via the shop,
## reset each dig (no persistence). Each must declare a money price > 0, a known effect, a
## negative reduction magnitude, and a positive max_level. The table may be empty (the slice
## can ship with zero money upgrades) but if present every entry must be well-formed.
static func _check_upgrades(upgrades: Variant, balance: Variant, errors: Array) -> void:
	if upgrades == null:
		return  # optional table
	if not (upgrades is Dictionary):
		errors.append("upgrades.json must be a JSON object")
		return
	var known_effects := ["shaft_width_reduction"]
	for id in (upgrades as Dictionary).keys():
		var up: Variant = (upgrades as Dictionary)[id]
		if not (up is Dictionary):
			errors.append("upgrades[%s]: must be an object" % id)
			continue
		for k in ["display_name", "effect", "magnitude", "price", "max_level"]:
			if not up.has(k):
				errors.append("upgrades[%s]: missing '%s'" % [id, k])
		if int(up.get("price", 0)) <= 0:
			errors.append("upgrades[%s]: price must be > 0 (a money cost)" % id)
		if int(up.get("max_level", 0)) <= 0:
			errors.append("upgrades[%s]: max_level must be > 0" % id)
		var effect: String = str(up.get("effect", ""))
		var mag: float = float(up.get("magnitude", 0.0))
		if not known_effects.has(effect):
			errors.append("upgrades[%s]: unknown effect '%s' (known: %s)" % [id, effect, str(known_effects)])
		if effect == "shaft_width_reduction":
			if mag >= 0.0:
				errors.append("upgrades[%s]: shaft_width_reduction magnitude must be < 0 (a reduction)" % id)
			if balance is Dictionary:
				var base_w: int = int((balance as Dictionary).get("shaft_width_cells", 0))
				var plat_w: int = int((balance as Dictionary).get("platform_width_cells", 1))
				var max_reduction: int = int(round(absf(mag))) * int(up.get("max_level", 0))
				if base_w - max_reduction < plat_w:
					errors.append("upgrades[%s]: reduction would narrow the shaft (%d) below the platform width (%d)" % [id, base_w - max_reduction, plat_w])


## Mines (surface + deeper money-gated mines). Optional table; if present it must declare at
## least one FREE (access_cost 0) starting mine, and every mine must have a positive hardness
## and ore multiplier (hardness bounded by the same scaling cap the HP formula honors), a
## non-negative access cost, and a valid tint hex. Keeps the no-lose, money-per-dig model sane.
static func _check_mines(mines: Variant, balance: Variant, errors: Array) -> void:
	if mines == null:
		return  # optional table
	if not (mines is Dictionary):
		errors.append("mines.json must be a JSON object")
		return
	var dict: Dictionary = mines
	if dict.is_empty():
		errors.append("mines: registry is empty (need at least one starting mine)")
		return
	var hardness_cap: float = 99.0
	if balance is Dictionary:
		hardness_cap = float((balance as Dictionary).get("mine_hardness_mult_max", 99.0))
	var free_count: int = 0
	for id in dict.keys():
		var m: Variant = dict[id]
		if not (m is Dictionary):
			errors.append("mines[%s]: must be an object" % id)
			continue
		for k in ["display_name", "access_cost", "hardness_mult", "ore_value_mult", "tile_tint"]:
			if not (m as Dictionary).has(k):
				errors.append("mines[%s]: missing '%s'" % [id, k])
		var cost: int = int((m as Dictionary).get("access_cost", 0))
		if cost < 0:
			errors.append("mines[%s]: access_cost must be >= 0" % id)
		if cost == 0:
			free_count += 1
		if float((m as Dictionary).get("hardness_mult", 0.0)) <= 0.0:
			errors.append("mines[%s]: hardness_mult must be > 0" % id)
		if float((m as Dictionary).get("hardness_mult", 0.0)) > hardness_cap:
			errors.append("mines[%s]: hardness_mult (%s) exceeds mine_hardness_mult_max (%s)" % [id, str((m as Dictionary).get("hardness_mult")), str(hardness_cap)])
		if float((m as Dictionary).get("ore_value_mult", 0.0)) <= 0.0:
			errors.append("mines[%s]: ore_value_mult must be > 0" % id)
		var tint: String = str((m as Dictionary).get("tile_tint", ""))
		if not Color.html_is_valid(tint):
			errors.append("mines[%s]: tile_tint '%s' is not a valid hex color" % [id, tint])
	if free_count < 1:
		errors.append("mines: at least one mine must be free (access_cost 0) as the starting mine")
