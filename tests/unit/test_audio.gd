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
	# AC-5.13.1: each gameplay/UI event has a real, non-null, non-empty placeholder stream.
	var a := _fresh_audio()
	for ev in AudioScript.EVENTS:
		var s: AudioStream = a.stream_for(ev)
		assert_object(s).override_failure_message(
			"event '%s' has no placeholder stream (AC-5.13.1)" % ev
		).is_not_null()
		# A real synthesised tone carries PCM data.
		assert_int((s as AudioStreamWAV).data.size()).override_failure_message(
			"event '%s' stream has no PCM data" % ev
		).is_greater(0)

func test_events_list_matches_spec_core_events() -> void:
	# AC-5.13.1 names exactly these gameplay/UI events; pin the set so one can't silently drop.
	var expected := ["break", "button_disabled", "button_hover", "button_press", "charge_select",
		"coin_fly", "crack", "crate_creak", "crate_drop", "crate_smash", "descend",
		"detonate", "insufficient_funds", "modal_close", "modal_open", "ore_credited",
		"pack_open", "prestige_bank", "prestige_banked", "rare_reveal_sting",
		"relic_found", "run_end_jingle", "throw", "upgrade_purchase"]
	var got: Array = (AudioScript.EVENTS as Array).duplicate()
	got.sort()
	assert_array(got).is_equal(expected)

func test_every_music_track_has_loop_stream() -> void:
	# AC-5.13.2: placeholder chiptune beds live on the Music bus and compile into loopable streams.
	var a := _fresh_audio()
	var expected := ["music_deep", "music_menu", "music_mining", "music_relic", "music_shop"]
	var tracks: Array = (AudioScript.MUSIC_TRACKS as Array).duplicate()
	tracks.sort()
	assert_array(tracks).is_equal(expected)
	for track in AudioScript.MUSIC_TRACKS:
		var s: AudioStream = a.music_stream_for(track)
		assert_object(s).override_failure_message("music track '%s' missing" % track).is_not_null()
		assert_int((s as AudioStreamWAV).data.size()).is_greater(0)

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

# ── Fallback/data drift (CONV-04) ─────────────────────────────────────────────

func test_fallback_specs_match_shipped_audio_json() -> void:
	# The hardcoded FALLBACK_SPECS in audio.gd must match the shipped audio.json — if they drift,
	# a load failure or boot-order race falls back to STALE balance silently (CONV-04).
	GameData.load_all()
	var data: Dictionary = GameData.tables.get("audio", {})
	var events: Dictionary = data.get("events", {})
	assert_bool(events.is_empty()).is_false()
	for ev in AudioScript.FALLBACK_SPECS:
		assert_bool(events.has(ev)).override_failure_message(
			"fallback event '%s' not in audio.json" % ev
		).is_true()
		if events.has(ev):
			var fb: Dictionary = AudioScript.FALLBACK_SPECS[ev]
			var dt: Dictionary = events[ev]
			for key in fb:
				assert_float(float(dt.get(key, -999.0))).override_failure_message(
					"event '%s' key '%s': fallback %s != data %s" % [ev, key, str(fb[key]), str(dt.get(key))]
				).is_equal(float(fb[key]))
	for ev in events:
		assert_bool(AudioScript.FALLBACK_SPECS.has(ev)).override_failure_message(
			"audio.json event '%s' has no fallback in FALLBACK_SPECS" % ev
		).is_true()

func test_fallback_combo_music_detonate_match_shipped_audio_json() -> void:
	GameData.load_all()
	var data: Dictionary = GameData.tables.get("audio", {})
	var combo: Dictionary = data.get("combo", {})
	for key in AudioScript.FALLBACK_COMBO:
		assert_float(float(combo.get(key, -999.0))).override_failure_message(
			"combo key '%s': fallback %s != data %s" % [key, str(AudioScript.FALLBACK_COMBO[key]), str(combo.get(key))]
		).is_equal(float(AudioScript.FALLBACK_COMBO[key]))
	var music: Dictionary = data.get("music", {})
	for track in AudioScript.FALLBACK_MUSIC:
		assert_bool(music.has(track)).override_failure_message(
			"fallback music track '%s' not in audio.json" % track
		).is_true()
		if music.has(track):
			var fbm: Dictionary = AudioScript.FALLBACK_MUSIC[track]
			var dtm: Dictionary = music[track]
			for key in fbm:
				if key == "notes":
					var fb_notes: Array = fbm[key]
					var dt_notes: Array = dtm.get(key, [])
					assert_int(dt_notes.size()).is_equal(fb_notes.size())
					for i in range(fb_notes.size()):
						assert_float(float(dt_notes[i])).is_equal(float(fb_notes[i]))
				else:
					assert_float(float(dtm.get(key, -999.0))).override_failure_message(
						"music '%s' key '%s': fallback %s != data %s" % [track, key, str(fbm[key]), str(dtm.get(key))]
					).is_equal(float(fbm[key]))
	var det: Dictionary = data.get("detonate", {})
	var layers: Array = det.get("layers", [])
	assert_int(layers.size()).is_equal(AudioScript.FALLBACK_DETONATE_LAYERS.size())
	for i in range(mini(layers.size(), AudioScript.FALLBACK_DETONATE_LAYERS.size())):
		var fbl: Dictionary = AudioScript.FALLBACK_DETONATE_LAYERS[i]
		var dtl: Dictionary = layers[i]
		for key in fbl:
			assert_float(float(dtl.get(key, -999.0))).override_failure_message(
				"detonate layer %d key '%s': fallback %s != data %s" % [i, key, str(fbl[key]), str(dtl.get(key))]
			).is_equal(float(fbl[key]))
