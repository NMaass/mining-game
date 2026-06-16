extends GdUnitTestSuite
## U-audio (v0.4.1) — the minimal SFX layer: bus layout, placeholder streams for the
## core events, volume routing, and the web-unlock flag. Headless-safe: the dummy audio
## driver means play() is a no-op, but the bus structure + stream bindings + volume math
## are all real and asserted here.
##
## ACs: AC-5.13.1 (placeholder SFX for core events, present from the slice),
##      AC-5.13.2 (Master → {SFX, Music} bus routing),
##      AC-5.13.3 (web audio unlock on first gesture),
##      AC-5.10.1 (independent SFX/Music volume control).

const AudioScript := preload("res://scripts/systems/audio.gd")

## A fresh, isolated Audio instance (its own players/streams) so tests don't mutate the
## global `Audio` autoload's state. _ready() runs on add_child → streams + voices built.
func _fresh_audio() -> Node:
	var a: Node = AudioScript.new()
	add_child(a)
	auto_free(a)
	return a

# ── Bus layout (AC-5.13.2) ──────────────────────────────────────────────────────
# Asserted against the live AudioServer, which loads default_bus_layout.tres at startup —
# so this proves the shipped bus layout, not just the autoload's expectations.

func test_bus_layout_is_master_sfx_music() -> void:
	# AC-5.13.2: the three buses exist.
	assert_int(AudioServer.get_bus_index("Master")).is_greater_equal(0)
	assert_int(AudioServer.get_bus_index("SFX")).is_greater_equal(0)
	assert_int(AudioServer.get_bus_index("Music")).is_greater_equal(0)

func test_sfx_and_music_route_to_master() -> void:
	# AC-5.13.2: SFX and Music send into Master (so a master volume governs both).
	var sfx: int = AudioServer.get_bus_index("SFX")
	var music: int = AudioServer.get_bus_index("Music")
	assert_str(AudioServer.get_bus_send(sfx)).is_equal("Master")
	assert_str(AudioServer.get_bus_send(music)).is_equal("Master")

# ── Placeholder SFX for every core event (AC-5.13.1) ────────────────────────────

func test_every_core_event_has_a_placeholder_stream() -> void:
	# AC-5.13.1: each of the seven core events has a real, non-null, non-empty stream.
	var a := _fresh_audio()
	var events: Array = ["detonate", "crack", "break", "ore_credited",
		"pack_open", "relic_found", "prestige_banked"]
	for ev in events:
		var s: AudioStream = a.stream_for(ev)
		assert_object(s).override_failure_message(
			"event '%s' has no placeholder stream (AC-5.13.1)" % ev
		).is_not_null()
		# A real synthesised tone carries PCM data.
		assert_int((s as AudioStreamWAV).data.size()).override_failure_message(
			"event '%s' stream has no PCM data" % ev
		).is_greater(0)

func test_events_list_matches_spec_core_events() -> void:
	# AC-5.13.1 names exactly these core events; pin the set so one can't silently drop.
	var expected := ["break", "crack", "detonate", "ore_credited",
		"pack_open", "prestige_banked", "relic_found"]
	var got: Array = (AudioScript.EVENTS as Array).duplicate()
	got.sort()
	assert_array(got).is_equal(expected)

func test_play_known_event_is_safe_and_unknown_is_noop() -> void:
	# play() must not crash for a known event (headless = dummy driver) and must no-op for
	# an unknown one (no exception, nothing bound).
	var a := _fresh_audio()
	a.play("detonate")          # known → safe
	a.play("does_not_exist")    # unknown → no-op
	assert_object(a.stream_for("does_not_exist")).is_null()

# ── Volume routing (AC-5.10.1 → AC-5.13.2) ──────────────────────────────────────

func test_sfx_volume_routes_to_the_sfx_bus() -> void:
	# AC-5.10.1: the SFX slider drives the SFX bus volume independently. Save/restore so
	# the global bus state isn't leaked to other suites.
	var a := _fresh_audio()
	var idx: int = AudioServer.get_bus_index("SFX")
	var prev: float = AudioServer.get_bus_volume_db(idx)
	a.set_sfx_volume_db(-18.0)
	assert_float(AudioServer.get_bus_volume_db(idx)).is_equal_approx(-18.0, 0.01)
	AudioServer.set_bus_volume_db(idx, prev)

func test_music_volume_routes_to_the_music_bus() -> void:
	var a := _fresh_audio()
	var idx: int = AudioServer.get_bus_index("Music")
	var prev: float = AudioServer.get_bus_volume_db(idx)
	a.set_music_volume_db(-9.0)
	assert_float(AudioServer.get_bus_volume_db(idx)).is_equal_approx(-9.0, 0.01)
	AudioServer.set_bus_volume_db(idx, prev)

# ── Web audio unlock (AC-5.13.3) ────────────────────────────────────────────────

func test_audio_starts_locked_and_unlocks_on_user_gesture() -> void:
	# AC-5.13.3: audio is "locked" until the first user gesture, then unlocked (idempotent).
	# Real web-context resume needs a browser (Verifier-E); the flag makes intent testable.
	var a := _fresh_audio()
	assert_bool(a.audio_unlocked).is_false()
	a.notify_user_gesture()
	assert_bool(a.audio_unlocked).is_true()
	a.notify_user_gesture()  # idempotent
	assert_bool(a.audio_unlocked).is_true()
