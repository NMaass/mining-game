extends GdUnitTestSuite
## Settings model (AC-5.10.1 motion/text-scale/volume settings; AC-5.11.1 settings persist).
## Pure headless tests over SettingsState: data-driven defaults, clamping, linear→dB volume
## mapping, and save round-trip/sanitization. Preloaded so the class resolves under a cold cache.

const Settings := preload("res://scripts/core/settings_state.gd")

var _tables: Dictionary

func before() -> void:
	_tables = _load_real_tables()

func _load_real_tables() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/")
	assert_object(dir).is_not_null()
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open("res://data/" + file_name, FileAccess.READ)
		var json := JSON.new()
		assert_int(json.parse(f.get_as_text())).is_equal(OK)
		out[file_name.get_basename()] = json.data
	return out

# ── Data-driven defaults (AC-5.10.1: settings defaults are /data, not code) ──────

func test_from_defaults_reads_data_block() -> void:
	# AC-5.10.1: a fresh SettingsState seeds from balance.settings, not code literals.
	var sd: Dictionary = _tables["balance"]["settings"]
	var s := Settings.from_defaults(_tables)
	assert_float(s.sfx_volume).is_equal_approx(float(sd["default_sfx_volume"]), 0.0001)
	assert_float(s.music_volume).is_equal_approx(float(sd["default_music_volume"]), 0.0001)
	assert_float(s.motion_intensity).is_equal_approx(float(sd["default_motion_intensity"]), 0.0001)
	assert_float(s.text_scale).is_equal_approx(float(sd["default_text_scale"]), 0.0001)
	assert_float(s.text_scale_min).is_equal_approx(float(sd["text_scale_min"]), 0.0001)
	assert_float(s.text_scale_max).is_equal_approx(float(sd["text_scale_max"]), 0.0001)

func test_from_defaults_tolerates_missing_data() -> void:
	# A bare table set falls back to FALLBACK rather than crashing (the data gate guarantees real
	# data ships; this keeps tools/tests robust).
	var s := Settings.from_defaults({})
	assert_float(s.sfx_volume).is_equal_approx(float(Settings.FALLBACK["sfx_volume"]), 0.0001)
	assert_float(s.text_scale).is_equal_approx(float(Settings.FALLBACK["text_scale"]), 0.0001)

# ── Clamping (a slider can never push a value out of range) ──────────────────────

func test_volume_and_motion_clamp_to_unit_range() -> void:
	var s := Settings.from_defaults(_tables)
	s.set_sfx_volume(5.0)
	assert_float(s.sfx_volume).is_equal(1.0)
	s.set_sfx_volume(-2.0)
	assert_float(s.sfx_volume).is_equal(0.0)
	s.set_music_volume(1.5)
	assert_float(s.music_volume).is_equal(1.0)
	s.set_motion_intensity(-0.1)
	assert_float(s.motion_intensity).is_equal(0.0)

func test_text_scale_clamps_to_data_band() -> void:
	# AC-5.10.1 / AC-5.8.6: the UI text scale is bounded to the data-driven [min,max] band.
	var s := Settings.from_defaults(_tables)
	s.set_text_scale(100.0)
	assert_float(s.text_scale).is_equal(s.text_scale_max)
	s.set_text_scale(0.0)
	assert_float(s.text_scale).is_equal(s.text_scale_min)

# ── Volume → dB mapping (the audio-bus contract) ─────────────────────────────────

func test_volume_db_mapping() -> void:
	var s := Settings.from_defaults(_tables)
	# Unity (1.0) → 0 dB; silence (0.0) → the finite SILENCE_DB floor (never -inf).
	s.set_sfx_volume(1.0)
	assert_float(s.sfx_volume_db()).is_equal_approx(0.0, 0.001)
	s.set_sfx_volume(0.0)
	assert_float(s.sfx_volume_db()).is_equal(Settings.SILENCE_DB)
	# A mid volume is attenuated (negative dB) but above the silence floor.
	s.set_music_volume(0.5)
	assert_float(s.music_volume_db()).is_less(0.0)
	assert_float(s.music_volume_db()).is_greater(Settings.SILENCE_DB)

# ── Save round-trip + sanitization (AC-5.11.1) ───────────────────────────────────

func test_to_state_round_trips_through_from_state() -> void:
	var s := Settings.from_defaults(_tables)
	s.set_sfx_volume(0.42)
	s.set_music_volume(0.13)
	s.set_motion_intensity(0.9)
	s.set_text_scale(1.5)
	var restored := Settings.from_state(s.to_state(), _tables)
	assert_float(restored.sfx_volume).is_equal_approx(0.42, 0.0001)
	assert_float(restored.music_volume).is_equal_approx(0.13, 0.0001)
	assert_float(restored.motion_intensity).is_equal_approx(0.9, 0.0001)
	assert_float(restored.text_scale).is_equal_approx(1.5, 0.0001)

func test_from_state_overlays_defaults_for_missing_keys() -> void:
	# A partial save (only sfx_volume) inherits the /data defaults for the other settings.
	var s := Settings.from_state({"sfx_volume": 0.25}, _tables)
	assert_float(s.sfx_volume).is_equal_approx(0.25, 0.0001)
	var sd: Dictionary = _tables["balance"]["settings"]
	assert_float(s.music_volume).is_equal_approx(float(sd["default_music_volume"]), 0.0001)
	assert_float(s.text_scale).is_equal_approx(float(sd["default_text_scale"]), 0.0001)

func test_from_state_sanitizes_out_of_range_values() -> void:
	# A hand-edited save with garbage values is clamped, not trusted.
	var s := Settings.from_state(
		{"sfx_volume": 99.0, "music_volume": -5.0, "motion_intensity": 2.0, "text_scale": 50.0},
		_tables,
	)
	assert_float(s.sfx_volume).is_equal(1.0)
	assert_float(s.music_volume).is_equal(0.0)
	assert_float(s.motion_intensity).is_equal(1.0)
	assert_float(s.text_scale).is_equal(s.text_scale_max)

# ── Controls: elevator side + keybinds (D2, AC-5.10.1 controls; AC-5.11.1 persist) ──

func test_elevator_side_default_from_data_and_toggle() -> void:
	# AC-5.10.1: the elevator side default comes from /data (balance.settings.default_elevator_side),
	# and the toggle flips left↔right.
	var sd: Dictionary = _tables["balance"]["settings"]
	var s := Settings.from_defaults(_tables)
	assert_str(s.elevator_side).is_equal(str(sd["default_elevator_side"]))
	var first: String = s.elevator_side
	s.toggle_elevator_side()
	assert_str(s.elevator_side).is_not_equal(first)
	s.toggle_elevator_side()
	assert_str(s.elevator_side).is_equal(first)

func test_set_elevator_side_rejects_garbage() -> void:
	# A bad side coerces to the fallback rather than corrupting the layout.
	var s := Settings.from_defaults(_tables)
	s.set_elevator_side("left")
	assert_str(s.elevator_side).is_equal("left")
	s.set_elevator_side("diagonal")
	assert_str(s.elevator_side).is_equal(Settings.FALLBACK["elevator_side"])

func test_keybinds_seed_from_injected_defaults() -> void:
	# AC-5.10.1: keybind DEFAULTS are injected (the live InputMap), not code literals — from_defaults
	# seeds the per-action keycode from the passed map; an unknown action / bad keycode is dropped.
	var defaults := {"fire": 32, "aim_left": 4194319, "bogus": 5, "elevator_up": 0}
	var s := Settings.from_defaults(_tables, defaults)
	assert_int(s.keybind_for("fire")).is_equal(32)
	assert_int(s.keybind_for("aim_left")).is_equal(4194319)
	assert_int(s.keybind_for("bogus")).is_equal(0)        # unknown action dropped
	assert_int(s.keybind_for("elevator_up")).is_equal(0)  # kc<=0 dropped (unbound)

func test_set_keybind_rejects_unknown_action_and_bad_keycode() -> void:
	var s := Settings.from_defaults(_tables, {"fire": 32})
	assert_bool(s.set_keybind("fire", 65)).is_true()
	assert_int(s.keybind_for("fire")).is_equal(65)
	assert_bool(s.set_keybind("not_an_action", 70)).is_false()
	assert_int(s.keybind_for("not_an_action")).is_equal(0)
	assert_bool(s.set_keybind("aim_right", 0)).is_false()  # non-positive ignored
	assert_int(s.keybind_for("aim_right")).is_equal(0)

func test_set_keybind_rejects_collision_with_another_action() -> void:
	# UNIT INFRA (crash-triage #1): binding `elevator_up` to a key `fire` already owns must be
	# rejected so a single press can't trigger two gameplay actions (the highest-blast-radius
	# rebind hazard — a throw also moving the elevator reads as a "weird state" report).
	var s := Settings.from_defaults(_tables, {"fire": 32, "elevator_up": 4194320})
	assert_bool(s.set_keybind("elevator_up", 32)).is_false()  # 32 is already fire's key
	assert_int(s.keybind_for("elevator_up")).is_equal(4194320)  # unchanged
	assert_int(s.keybind_for("fire")).is_equal(32)              # fire still owns it

func test_set_keybind_allows_rebinding_action_to_its_own_key() -> void:
	# Re-applying an action's CURRENT key is not a collision (idempotent) — only a DIFFERENT action
	# holding the key blocks it.
	var s := Settings.from_defaults(_tables, {"fire": 32})
	assert_bool(s.set_keybind("fire", 32)).is_true()
	assert_int(s.keybind_for("fire")).is_equal(32)

func test_controls_round_trip_through_state() -> void:
	# AC-5.11.1: elevator side + keybinds survive to_state → from_state exactly. A save MISSING an
	# action inherits the injected default for that action (overlay-on-defaults).
	var defaults := {"aim_left": 4194319, "aim_right": 4194321, "fire": 32,
		"elevator_up": 4194320, "elevator_down": 4194322}
	var s := Settings.from_defaults(_tables, defaults)
	s.set_elevator_side("left")
	s.set_keybind("fire", 65)            # rebind fire to A; leave the rest at the defaults
	var restored := Settings.from_state(s.to_state(), _tables, defaults)
	assert_str(restored.elevator_side).is_equal("left")
	assert_int(restored.keybind_for("fire")).is_equal(65)
	# The non-rebound actions persisted at their default keycodes too.
	assert_int(restored.keybind_for("aim_left")).is_equal(4194319)
	assert_int(restored.keybind_for("elevator_down")).is_equal(4194322)
