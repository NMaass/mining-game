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
	# AC-5.13.1: each core event has a real, non-null, non-empty stream (v0.5 adds descend + throw).
	var a := _fresh_audio()
	var events: Array = ["detonate", "crack", "break", "ore_credited",
		"pack_open", "relic_found", "prestige_banked", "descend", "throw"]
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
	# AC-5.13.1 names exactly these core events; pin the set so one can't silently drop. v0.5 adds
	# the descent (ka-chunk) + throw (whoosh) cues that filled the previously-silent moments — update
	# this set in lockstep with EVENTS or a missing cue would slip through.
	var expected := ["break", "crack", "descend", "detonate", "ore_credited",
		"pack_open", "prestige_banked", "relic_found", "throw"]
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

# ── Data-driven SFX + pitch jitter (v0.5 arcade audio pass) ─────────────────────
# The synthesis params now live in data/audio.json (consumed via GameData), validated by
# DataValidator._check_audio. These tests prove the live behaviour: per-play pitch jitter
# de-robotizes repeated cues; tonal cues (relic/prestige) stay exactly on pitch; the break combo
# climbs; the detonate boom is layered; descend/throw fire.

func test_repeated_jittered_cue_varies_pitch() -> void:
	# A jittered event (break) must NOT play at the same pitch every time — the #1 robotic tell. Play
	# many times and require at least two DISTINCT pitch_scales (robust to the rare RNG collision).
	var a := _fresh_audio()
	var seen := {}
	for i in range(24):
		a.play("break")
		seen[snappedf(a.last_pitch_scale(), 0.0001)] = true
	assert_int(seen.size()).override_failure_message(
		"break pitch never varied across 24 plays — pitch jitter not applied"
	).is_greater(1)

func test_tonal_cues_stay_on_pitch() -> void:
	# relic_found / prestige_banked carry pitch_jitter 0 so the reward chimes stay tonal — every play
	# must be exactly 1.0 (pooled voices reset pitch_scale each play, so no leak from a jittered cue).
	var a := _fresh_audio()
	for ev in ["relic_found", "prestige_banked"]:
		for i in range(8):
			a.play("break")           # leave a jittered pitch on a pooled voice...
			a.play(ev)                # ...then assert the tonal cue resets it to exactly 1.0
			assert_float(a.last_pitch_scale()).override_failure_message(
				"tonal cue '%s' must play at pitch 1.0 (jitter 0)" % ev
			).is_equal_approx(1.0, 0.0001)

func test_break_combo_increments_play_count_and_ascends() -> void:
	# play_break_combo(N) fires min(N, combo.max_voices) voices; the first fires synchronously so
	# play_count ticks at least once. The base-pitch sequence is strictly ascending (the arpeggio).
	var a := _fresh_audio()
	var before: int = a.play_count
	a.play_break_combo(5)
	assert_int(a.play_count).override_failure_message(
		"play_break_combo fired no voice synchronously"
	).is_greater(before)
	var pitches: Array = a.combo_pitches(5)
	assert_int(pitches.size()).is_greater(1)
	for i in range(1, pitches.size()):
		assert_float(float(pitches[i])).override_failure_message(
			"combo pitch %d (%s) must exceed pitch %d (%s) — rattle should rise" % [i, str(pitches[i]), i - 1, str(pitches[i - 1])]
		).is_greater(float(pitches[i - 1]))

func test_break_combo_caps_voice_count() -> void:
	# A wide ore vein must not spawn an unbounded rattle — the sequence length is capped at
	# combo.max_voices even for a huge cleared count.
	var a := _fresh_audio()
	var capped: Array = a.combo_pitches(10000)
	var single: Array = a.combo_pitches(1)
	assert_int(single.size()).is_equal(1)
	# Cap is data-driven (combo.max_voices); just require it's bounded and >= a single voice.
	assert_int(capped.size()).is_greater_equal(1)
	assert_int(capped.size()).is_less_equal(64)  # sanity: never an unbounded blowup

func test_detonate_resolves_to_layered_boom() -> void:
	# play_detonate fires a LAYERED boom (low body + bright transient + noise tail) — >= 3 voices in
	# one call, so play_count jumps by >= 3.
	var a := _fresh_audio()
	assert_int(a.detonate_layer_count()).override_failure_message(
		"detonate must resolve to >= 3 layered voices"
	).is_greater_equal(3)
	var before: int = a.play_count
	a.play_detonate()
	assert_int(a.play_count - before).override_failure_message(
		"play_detonate must fire >= 3 layer voices in one call"
	).is_greater_equal(3)

func test_descend_and_throw_cues_fire() -> void:
	# The new descent (ka-chunk) + throw (whoosh) cues each have a stream and increment play_count —
	# proving the previously-silent moments now sound.
	var a := _fresh_audio()
	for ev in ["descend", "throw"]:
		assert_object(a.stream_for(ev)).override_failure_message(
			"new cue '%s' has no placeholder stream" % ev
		).is_not_null()
	var before: int = a.play_count
	a.play_descend()
	a.play_throw()
	assert_int(a.play_count).is_equal(before + 2)
