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
