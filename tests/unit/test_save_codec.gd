extends GdUnitTestSuite
## U20 — Save codec (pure (de)serialization + migration). Proves the headless half of AC-5.11.1
## (serialize durable state) + AC-5.11.2 (migrate older versions, ignore unknown fields, default
## missing ones). Preloaded so the class is exercised under a cold cache.
##
## ACs: AC-5.11.1 (persist prestige points + purchases), AC-5.11.2 (schema version + migration +
##      unknown-field tolerance).

const Codec := preload("res://scripts/core/save_codec.gd")

func test_default_state_is_current_version() -> void:
	var s: Dictionary = Codec.default_state()
	assert_int(int(s["version"])).is_equal(Codec.CURRENT_VERSION)
	assert_int(int(s["prestige"]["points"])).is_equal(0)
	assert_dict(s["prestige"]["levels"]).is_empty()

func test_round_trip_preserves_prestige() -> void:
	# AC-5.11.1: encode → decode round-trips the durable state exactly (points + purchase levels).
	var state := {"version": Codec.CURRENT_VERSION, "prestige": {"points": 42, "levels": {"blast_power": 3}}}
	var decoded: Dictionary = Codec.decode(Codec.encode(state))
	assert_int(int(decoded["prestige"]["points"])).is_equal(42)
	assert_int(int(decoded["prestige"]["levels"]["blast_power"])).is_equal(3)
	assert_int(int(decoded["version"])).is_equal(Codec.CURRENT_VERSION)

func test_decode_corrupt_text_returns_empty() -> void:
	# AC-5.11.3 support: corrupt bytes decode to {} (the SaveManager's signal to try the backup).
	assert_dict(Codec.decode("{not valid json,,,")).is_empty()
	assert_dict(Codec.decode("")).is_empty()
	assert_dict(Codec.decode("[1,2,3]")).is_not_empty()  # parseable non-object → normalized default, not {}

func test_migrate_v0_flat_to_v1_nested() -> void:
	# AC-5.11.2: a legacy v0 save (flat, no `version`) migrates into the v1 nested shape.
	var v0 := {"prestige_points": 7, "prestige_levels": {"blast_power": 2}}
	var s: Dictionary = Codec.normalize(v0)
	assert_int(int(s["version"])).is_equal(Codec.CURRENT_VERSION)
	assert_int(int(s["prestige"]["points"])).is_equal(7)
	assert_int(int(s["prestige"]["levels"]["blast_power"])).is_equal(2)

func test_unknown_fields_ignored() -> void:
	# AC-5.11.2: unknown top-level + sub fields are dropped (forward-compat tolerance).
	var raw := {
		"version": Codec.CURRENT_VERSION,
		"prestige": {"points": 5, "levels": {"blast_power": 1}, "mystery": 99},
		"future_system": {"foo": "bar"},
	}
	var s: Dictionary = Codec.normalize(raw)
	assert_bool(s.has("future_system")).is_false()
	assert_bool((s["prestige"] as Dictionary).has("mystery")).is_false()
	assert_int(int(s["prestige"]["points"])).is_equal(5)

func test_missing_fields_defaulted() -> void:
	# AC-5.11.2: missing fields default rather than crash (a partial/old save still loads).
	var s: Dictionary = Codec.normalize({"version": Codec.CURRENT_VERSION})
	assert_int(int(s["prestige"]["points"])).is_equal(0)
	assert_dict(s["prestige"]["levels"]).is_empty()

func test_sanitizes_malformed_levels() -> void:
	# A hand-edited / corrupt-but-parseable save can't inject bad state: negative points clamp to 0,
	# and zero/negative purchase levels are dropped (only real purchases survive).
	var raw := {"version": 1, "prestige": {"points": -10, "levels": {"a": 0, "b": -3, "c": 2}}}
	var s: Dictionary = Codec.normalize(raw)
	assert_int(int(s["prestige"]["points"])).is_equal(0)
	assert_bool((s["prestige"]["levels"] as Dictionary).has("a")).is_false()  # level 0 dropped
	assert_bool((s["prestige"]["levels"] as Dictionary).has("b")).is_false()  # negative dropped
	assert_int(int(s["prestige"]["levels"]["c"])).is_equal(2)

func test_non_dict_input_normalizes_to_default() -> void:
	# Defensive: a non-object JSON value (array/number/string) normalizes to a clean default state.
	assert_dict(Codec.normalize([1, 2, 3])).is_equal(Codec.default_state())
	assert_dict(Codec.normalize("hello")).is_equal(Codec.default_state())

func test_encode_stamps_current_version() -> void:
	# AC-5.11.2: the written bytes always carry the current schema version (even from an old input).
	var text: String = Codec.encode({"prestige_points": 1})  # v0-ish input
	var json := JSON.new()
	assert_int(json.parse(text)).is_equal(OK)
	assert_int(int((json.data as Dictionary)["version"])).is_equal(Codec.CURRENT_VERSION)

# ── Settings block (AC-5.10.1 persisted via AC-5.11.1/2) ─────────────────────────

func test_default_state_includes_settings_block() -> void:
	# AC-5.11.1: the save shape carries the durable settings (4 normalized accessibility values).
	var s: Dictionary = Codec.default_state()
	assert_bool(s.has("settings")).is_true()
	for k in ["sfx_volume", "music_volume", "motion_intensity", "text_scale"]:
		assert_bool((s["settings"] as Dictionary).has(k)).is_true()

func test_round_trip_preserves_settings() -> void:
	# AC-5.11.1: encode → decode round-trips the settings exactly.
	var state := {
		"version": Codec.CURRENT_VERSION,
		"prestige": {"points": 1, "levels": {}},
		"settings": {"sfx_volume": 0.4, "music_volume": 0.2, "motion_intensity": 0.7, "text_scale": 1.4},
	}
	var d: Dictionary = Codec.decode(Codec.encode(state))
	assert_float(float(d["settings"]["sfx_volume"])).is_equal_approx(0.4, 0.0001)
	assert_float(float(d["settings"]["motion_intensity"])).is_equal_approx(0.7, 0.0001)
	assert_float(float(d["settings"]["text_scale"])).is_equal_approx(1.4, 0.0001)

func test_migrate_v1_to_v2_adds_default_settings() -> void:
	# AC-5.11.2 (ordered migration, 2nd real step): a v1 save (prestige only, no settings) migrates
	# FORWARD with a default settings block — and the prestige data is untouched. normalize always
	# lands at CURRENT_VERSION (the chain runs v1→v2→v3), so the version assertion is CURRENT_VERSION.
	var v1 := {"version": 1, "prestige": {"points": 9, "levels": {"blast_power": 4}}}
	var s: Dictionary = Codec.normalize(v1)
	assert_int(int(s["version"])).is_equal(Codec.CURRENT_VERSION)
	assert_int(int(s["prestige"]["points"])).is_equal(9)        # preserved
	assert_int(int(s["prestige"]["levels"]["blast_power"])).is_equal(4)
	assert_bool((s as Dictionary).has("settings")).is_true()    # defaulted in
	assert_bool((s["settings"] as Dictionary).has("text_scale")).is_true()

func test_v0_flat_migrates_through_both_steps_to_v2() -> void:
	# A legacy v0 flat save chains v0→v1→v2: prestige lifted to nested AND settings introduced.
	var v0 := {"prestige_points": 3, "prestige_levels": {"blast_power": 1}}
	var s: Dictionary = Codec.normalize(v0)
	assert_int(int(s["version"])).is_equal(Codec.CURRENT_VERSION)
	assert_int(int(s["prestige"]["points"])).is_equal(3)
	assert_bool((s as Dictionary).has("settings")).is_true()

func test_settings_sanitized_on_normalize() -> void:
	# A corrupt-but-parseable settings block clamps to range rather than injecting bad state.
	var raw := {
		"version": 2,
		"prestige": {"points": 0, "levels": {}},
		"settings": {"sfx_volume": 12.0, "music_volume": -3.0, "motion_intensity": 5.0},
	}
	var s: Dictionary = Codec.normalize(raw)
	assert_float(float(s["settings"]["sfx_volume"])).is_equal(1.0)
	assert_float(float(s["settings"]["music_volume"])).is_equal(0.0)
	assert_float(float(s["settings"]["motion_intensity"])).is_equal(1.0)

# ── Controls sub-fields: elevator side + keybinds (D2, AC-5.10.1 persisted via AC-5.11.1/2) ──

func test_default_state_includes_controls_fields() -> void:
	# AC-5.11.1: the save shape carries the durable controls config (elevator side + keybinds map).
	var s: Dictionary = Codec.default_state()
	var settings: Dictionary = s["settings"]
	assert_bool(settings.has("elevator_side")).is_true()
	assert_bool(settings.has("keybinds")).is_true()
	assert_str(str(settings["elevator_side"])).is_equal("right")

func test_migrate_v2_to_v3_adds_controls_fields() -> void:
	# AC-5.11.2 (ordered migration, 3rd real step / D2): a v2 save (the four accessibility values, no
	# controls) migrates FORWARD with elevator_side + keybinds defaulted in — accessibility untouched.
	var v2 := {
		"version": 2,
		"prestige": {"points": 2, "levels": {}},
		"settings": {"sfx_volume": 0.5, "music_volume": 0.5, "motion_intensity": 0.5, "text_scale": 1.2},
	}
	var s: Dictionary = Codec.normalize(v2)
	assert_int(int(s["version"])).is_equal(Codec.CURRENT_VERSION)
	assert_float(float(s["settings"]["text_scale"])).is_equal_approx(1.2, 0.0001)  # preserved
	assert_bool((s["settings"] as Dictionary).has("elevator_side")).is_true()      # defaulted in
	assert_str(str(s["settings"]["elevator_side"])).is_equal("right")
	assert_bool((s["settings"] as Dictionary).has("keybinds")).is_true()

func test_v0_flat_migrates_all_the_way_to_v3_controls() -> void:
	# A legacy v0 flat save chains v0→v1→v2→v3: prestige lifted, settings added, controls defaulted.
	var v0 := {"prestige_points": 3, "prestige_levels": {"blast_power": 1}}
	var s: Dictionary = Codec.normalize(v0)
	assert_int(int(s["version"])).is_equal(Codec.CURRENT_VERSION)
	assert_int(int(s["prestige"]["points"])).is_equal(3)
	assert_bool((s["settings"] as Dictionary).has("elevator_side")).is_true()
	assert_bool((s["settings"] as Dictionary).has("keybinds")).is_true()

func test_round_trip_preserves_controls_fields() -> void:
	# AC-5.11.1: encode → decode round-trips the elevator side + the keybinds map exactly (this is the
	# exact spot prior settings bugs hid, so the round-trip is asserted on the NEW fields directly).
	var state := {
		"version": Codec.CURRENT_VERSION,
		"prestige": {"points": 1, "levels": {}},
		"settings": {
			"sfx_volume": 0.4, "music_volume": 0.2, "motion_intensity": 0.7, "text_scale": 1.4,
			"elevator_side": "left",
			"keybinds": {"fire": 65, "elevator_up": 87},
		},
	}
	var d: Dictionary = Codec.decode(Codec.encode(state))
	assert_str(str(d["settings"]["elevator_side"])).is_equal("left")
	assert_int(int(d["settings"]["keybinds"]["fire"])).is_equal(65)
	assert_int(int(d["settings"]["keybinds"]["elevator_up"])).is_equal(87)

func test_controls_sanitized_on_normalize() -> void:
	# A corrupt-but-parseable controls block can't inject bad state: a bogus side coerces to the
	# default, an unknown keybind action is dropped, and a non-positive keycode is dropped.
	var raw := {
		"version": 3,
		"prestige": {"points": 0, "levels": {}},
		"settings": {
			"elevator_side": "sideways",
			"keybinds": {"fire": 70, "bogus_action": 99, "aim_left": 0},
		},
	}
	var s: Dictionary = Codec.normalize(raw)
	assert_str(str(s["settings"]["elevator_side"])).is_equal("right")          # bad side → default
	assert_int(int(s["settings"]["keybinds"]["fire"])).is_equal(70)            # valid kept
	assert_bool((s["settings"]["keybinds"] as Dictionary).has("bogus_action")).is_false()  # unknown dropped
	assert_bool((s["settings"]["keybinds"] as Dictionary).has("aim_left")).is_false()      # kc<=0 dropped
