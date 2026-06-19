extends Node
## Audio — the minimal SFX layer for the slice (v0.5 arcade audio pass). Provides placeholder
## SFX for the core gameplay events, routes them through the Master → {SFX, Music} bus layout,
## exposes per-bus volume control for the §5.10 sliders, and unlocks the web audio context on the
## first user gesture.
##
## Placeholder SFX are SYNTHESISED IN CODE (short decaying tones, optional noise) so the slice
## ships real, playable sound without committing binary assets or adding deps — "placeholder SFX
## present from the step-1 slice" (AC-5.13.1). Final sound design/mix is ROADMAP (U24); this is the
## bus + hook + placeholder infrastructure those assets drop into.
##
## v0.5 arcade audio pass — the synthesis params are now DATA (data/audio.json via GameData), not a
## hardcoded specs dict (tunables are data — AC-5.5.4). A hardcoded fallback (FALLBACK_SPECS) is kept
## so a missing/unparseable table can't silence the game (mirrors the boot() GameData.load_all()
## guard). Per-play PITCH JITTER (a module RNG, distinct from the per-tone seeded one) de-robotizes a
## fast dig; play_break_combo() fires a rising-pitch rattle for a multi-cell break (the arcade
## arpeggio); play_detonate() layers three voices (low body + bright transient + noise tail); and new
## `descend`/`throw` cues fill the previously-silent descent + launch holes.
##
## Registered as the `Audio` autoload (project.godot). The mine controller calls the thin play_*()
## wrappers at the real event sites. Headless-safe: under the dummy audio driver play() is a harmless
## no-op; the bus layout + stream bindings + pitch math still exist and are tested.
##
## ACs: AC-5.13.1 (SFX for core events, present from the slice), AC-5.13.2 (Master→{SFX,
##      Music} bus routing), AC-5.13.3 (resume audio on first web gesture),
##      AC-5.10.1 (independent SFX/Music volume control).

const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const MASTER_BUS := "Master"

## The core gameplay events that carry placeholder SFX (AC-5.13.1). v0.5 adds `descend` (the
## ka-chunk when the platform drops) + `throw` (the launch whoosh) — previously-silent moments.
const EVENTS: Array[String] = [
	"detonate", "crack", "break", "ore_credited",
	"pack_open", "relic_found", "prestige_banked",
	"descend", "throw",
	"crate_drop", "crate_creak", "crate_smash", "rare_reveal_sting",
	"charge_select", "button_hover", "button_press", "button_disabled",
	"modal_open", "modal_close", "insufficient_funds", "coin_fly",
	"prestige_bank", "run_end_jingle", "upgrade_purchase",
]
const MUSIC_TRACKS: Array[String] = [
	"music_menu", "music_mining", "music_deep", "music_relic", "music_shop",
]

## Voice pool size — bumped 4→8 (v0.5) so the rising-pitch break-combo rattle (up to combo.max_voices)
## doesn't steal the detonate / ore-ping / throw voices in the same blast.
const VOICES := 8
const MIX_RATE := 22050

## Per-play pitch variance ceiling clamp (defence in depth — the data gate already bounds pitch_jitter
## to [0,0.5], but a bad fallback shouldn't produce an absurd pitch). Pooled voices reset pitch_scale
## each play(), so a tonal cue (jitter 0) always plays at exactly 1.0.
const MAX_PITCH_JITTER := 0.5

## Hardcoded fallback specs — used only if data/audio.json is missing/unparseable (so a data hiccup
## can't silence the game). The shipped audio.json mirrors these and is the real contract (the data
## gate enforces it). Shape: freq (Hz), dur (s), noise [0,1], sweep (end Hz, 0=none), pitch_jitter [0,0.5].
const FALLBACK_SPECS := {
	"detonate":        {"freq": 55.0,  "dur": 0.22, "noise": 0.85, "sweep": 30.0,   "pitch_jitter": 0.12},
	"crack":           {"freq": 420.0, "dur": 0.04, "noise": 0.60, "sweep": 0.0,    "pitch_jitter": 0.12},
	"break":           {"freq": 140.0, "dur": 0.12, "noise": 0.70, "sweep": 90.0,   "pitch_jitter": 0.12},
	"ore_credited":    {"freq": 1250.0,"dur": 0.07, "noise": 0.0,  "sweep": 0.0,    "pitch_jitter": 0.06},
	"pack_open":       {"freq": 620.0, "dur": 0.14, "noise": 0.1,  "sweep": 820.0,  "pitch_jitter": 0.05},
	"relic_found":     {"freq": 523.0, "dur": 0.45, "noise": 0.0,  "sweep": 1047.0, "pitch_jitter": 0.0},
	"prestige_banked": {"freq": 740.0, "dur": 0.25, "noise": 0.0,  "sweep": 1109.0, "pitch_jitter": 0.0},
	"descend":         {"freq": 80.0,  "dur": 0.18, "noise": 0.45, "sweep": 55.0,   "pitch_jitter": 0.05},
	"throw":           {"freq": 300.0, "dur": 0.12, "noise": 0.85, "sweep": 900.0,  "pitch_jitter": 0.1},
	"crate_drop":      {"freq": 95.0,  "dur": 0.18, "noise": 0.55, "sweep": 52.0,   "pitch_jitter": 0.06},
	"crate_creak":     {"freq": 260.0, "dur": 0.22, "noise": 0.35, "sweep": 180.0,  "pitch_jitter": 0.08},
	"crate_smash":     {"freq": 120.0, "dur": 0.24, "noise": 0.90, "sweep": 40.0,   "pitch_jitter": 0.10},
	"rare_reveal_sting":{"freq": 523.0,"dur": 0.55, "noise": 0.05, "sweep": 1568.0, "pitch_jitter": 0.0},
	"charge_select":   {"freq": 780.0, "dur": 0.08, "noise": 0.0,  "sweep": 980.0,  "pitch_jitter": 0.04},
	"button_hover":    {"freq": 520.0, "dur": 0.035,"noise": 0.0,  "sweep": 620.0,  "pitch_jitter": 0.03},
	"button_press":    {"freq": 300.0, "dur": 0.055,"noise": 0.08, "sweep": 220.0,  "pitch_jitter": 0.05},
	"button_disabled": {"freq": 160.0, "dur": 0.09, "noise": 0.25, "sweep": 120.0,  "pitch_jitter": 0.04},
	"modal_open":      {"freq": 440.0, "dur": 0.14, "noise": 0.0,  "sweep": 660.0,  "pitch_jitter": 0.02},
	"modal_close":     {"freq": 360.0, "dur": 0.11, "noise": 0.0,  "sweep": 240.0,  "pitch_jitter": 0.02},
	"insufficient_funds":{"freq": 110.0,"dur": 0.16, "noise": 0.4, "sweep": 85.0,   "pitch_jitter": 0.04},
	"coin_fly":        {"freq": 1320.0,"dur": 0.045,"noise": 0.0,  "sweep": 1760.0, "pitch_jitter": 0.06},
	"prestige_bank":   {"freq": 740.0, "dur": 0.32, "noise": 0.0,  "sweep": 1480.0, "pitch_jitter": 0.0},
	"run_end_jingle":  {"freq": 660.0, "dur": 0.50, "noise": 0.0,  "sweep": 990.0,  "pitch_jitter": 0.0},
	"upgrade_purchase":{"freq": 600.0, "dur": 0.22, "noise": 0.02, "sweep": 900.0,  "pitch_jitter": 0.02},
}
const FALLBACK_COMBO := {"max_voices": 6, "step_seconds": 0.025, "semitone_step": 1.0}
## Fallback layered-boom voices (low body + bright transient + noise tail).
const FALLBACK_DETONATE_LAYERS := [
	{"freq": 48.0,  "dur": 0.26, "noise": 0.2,  "sweep": 26.0, "pitch_jitter": 0.08},
	{"freq": 180.0, "dur": 0.08, "noise": 0.4,  "sweep": 60.0, "pitch_jitter": 0.1},
	{"freq": 90.0,  "dur": 0.3,  "noise": 0.95, "sweep": 40.0, "pitch_jitter": 0.12},
]
const FALLBACK_MUSIC := {
	"music_menu": {"bpm": 108.0, "step_beats": 0.5, "volume": 0.16, "notes": [220.0, 0.0, 277.18, 0.0, 329.63, 0.0, 277.18, 0.0, 196.0, 0.0, 246.94, 0.0, 293.66, 0.0, 246.94, 0.0]},
	"music_mining": {"bpm": 126.0, "step_beats": 0.5, "volume": 0.13, "notes": [110.0, 164.81, 220.0, 164.81, 123.47, 185.0, 246.94, 185.0, 98.0, 146.83, 196.0, 146.83, 123.47, 185.0, 246.94, 185.0]},
	"music_deep": {"bpm": 118.0, "step_beats": 0.5, "volume": 0.14, "notes": [82.41, 123.47, 164.81, 123.47, 92.5, 138.59, 185.0, 138.59, 73.42, 110.0, 146.83, 110.0, 92.5, 138.59, 185.0, 138.59]},
	"music_relic": {"bpm": 96.0, "step_beats": 0.5, "volume": 0.18, "notes": [261.63, 329.63, 392.0, 523.25, 659.25, 783.99, 1046.5, 0.0]},
	"music_shop": {"bpm": 104.0, "step_beats": 0.5, "volume": 0.13, "notes": [196.0, 246.94, 293.66, 246.94, 220.0, 277.18, 329.63, 277.18, 196.0, 246.94, 293.66, 369.99, 329.63, 293.66, 246.94, 220.0]},
}
const MUSIC_FADE_DB := -60.0

var _streams: Dictionary = {}            # event -> AudioStreamWAV
var _pitch_jitter: Dictionary = {}       # event -> float (per-play pitch variance)
var _detonate_layers: Array = []         # the layered-boom voices [AudioStreamWAV, ...] + jitters
var _music_streams: Dictionary = {}       # track -> AudioStreamWAV
var _music_specs: Dictionary = {}         # track -> spec (volume)
var _combo: Dictionary = FALLBACK_COMBO.duplicate(true)
var _players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _voice: int = 0
var _music_voice: int = 0
var _unlocked: bool = false
var _current_music: String = ""
var _pending_music: String = ""
var _music_tween: Tween = null
var _duck_tween: Tween = null
# A MODULE RNG for per-play pitch jitter — distinct from the per-tone seeded RNG in _make_tone (which
# keeps the synthesised waveform stable). Randomised at startup so repeated cues vary run-to-run.
var _rng := RandomNumberGenerator.new()
# Observability so wiring can be asserted (a cue actually fired), not just that the hook exists.
var _play_count: int = 0
var _last_event: String = ""

func _ready() -> void:
	_rng.randomize()
	_build_streams()
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
	for i in range(2):
		var mp := AudioStreamPlayer.new()
		mp.bus = MUSIC_BUS
		mp.volume_db = MUSIC_FADE_DB
		add_child(mp)
		_music_players.append(mp)
	# Web: the audio context is suspended until a user gesture (AC-5.13.3). Listen for the
	# first input and unlock then. Harmless on native (the flag just flips once).
	set_process_unhandled_input(true)

func _unhandled_input(event: InputEvent) -> void:
	if _unlocked:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventKey:
		notify_user_gesture()

# ── Web audio unlock (AC-5.13.3) ───────────────────────────────────────────────

## Resume/unlock audio on the first user gesture. Idempotent + headless-safe. Godot's
## web platform resumes the AudioContext on input automatically; we make the intent
## explicit (and future-proof) by ensuring the Master bus is audible, and expose the
## state so it is testable without a real browser.
func notify_user_gesture() -> void:
	if _unlocked:
		return
	_unlocked = true
	var master: int = AudioServer.get_bus_index(MASTER_BUS)
	if master >= 0:
		AudioServer.set_bus_mute(master, false)
	if not _pending_music.is_empty():
		var track: String = _pending_music
		_pending_music = ""
		play_music(track, 0.05)

var audio_unlocked: bool:
	get:
		return _unlocked

# ── Playback (AC-5.13.1) ────────────────────────────────────────────────────────

## Play the placeholder SFX bound to a core event. Unknown event → no-op. Round-robins
## a small voice pool so co-occurring cues (detonate + break) don't cut each other off.
## v0.5: applies a per-play PITCH JITTER (from a module RNG) so repeated cues sound organic;
## tonal cues (relic/prestige, jitter 0) always play at exactly 1.0. An optional pitch override
## lets the combo rattle climb in semitones.
func play(event: String, pitch_override: float = 0.0) -> void:
	if OS.has_feature("web") and not _unlocked:
		return
	var stream: AudioStream = _streams.get(event, null)
	if stream == null or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_voice]
	_voice = (_voice + 1) % _players.size()
	p.stream = stream
	p.pitch_scale = pitch_override if pitch_override > 0.0 else _jittered_pitch(event)
	p.play()
	_play_count += 1
	_last_event = event
	_duck_music()

## The per-play pitch for an event: 1.0 ± its data-driven jitter (pooled voices reset this each play,
## so a jitter-0 cue is exactly tonal). Drawn from the module RNG, NOT the per-tone seeded one.
func _jittered_pitch(event: String) -> float:
	var j: float = clampf(float(_pitch_jitter.get(event, 0.0)), 0.0, MAX_PITCH_JITTER)
	if j <= 0.0:
		return 1.0
	return _rng.randf_range(1.0 - j, 1.0 + j)

## Number of cues played + the last event id (for wiring assertions / inspection).
var play_count: int:
	get:
		return _play_count

var last_event: String:
	get:
		return _last_event

func play_detonate() -> void:
	if OS.has_feature("web") and not _unlocked:
		return
	# Layered boom: fire the data-driven layers (low body + bright transient + noise tail) as one
	# stacked detonation. Falls back to the single `detonate` tone if no layers are bound.
	if _detonate_layers.is_empty():
		play("detonate")
		return
	for layer in _detonate_layers:
		var stream: AudioStream = layer.get("stream")
		if stream == null or _players.is_empty():
			continue
		var p: AudioStreamPlayer = _players[_voice]
		_voice = (_voice + 1) % _players.size()
		p.stream = stream
		var j: float = clampf(float(layer.get("pitch_jitter", 0.0)), 0.0, MAX_PITCH_JITTER)
		p.pitch_scale = _rng.randf_range(1.0 - j, 1.0 + j) if j > 0.0 else 1.0
		p.play()
		_play_count += 1
	_last_event = "detonate"
	_duck_music()

func play_crack() -> void: play("crack")
func play_break() -> void: play("break")
func play_ore_credited() -> void: play("ore_credited")
func play_pack_open() -> void: play("pack_open")
func play_relic_found() -> void: play("relic_found")
func play_prestige_banked() -> void: play("prestige_banked")
func play_descend() -> void: play("descend")
func play_throw() -> void: play("throw")
func play_charge_select() -> void: play("charge_select")
func play_upgrade_purchase() -> void: play("upgrade_purchase")
func play_run_end_jingle() -> void: play("run_end_jingle")

## The ASCENDING base-pitch sequence a `cleared_count`-cell break rattle resolves to: up to
## combo.max_voices voices, the i-th climbing i * combo.semitone_step semitones (1.0594 = 2^(1/12)).
## Pure f(cleared_count, combo) — strictly increasing for a positive semitone_step — so the arcade
## arpeggio's "rises in pitch" property is testable without timers. A 1-cell break → a single [1.0].
func combo_pitches(cleared_count: int) -> Array:
	var n: int = maxi(1, cleared_count)
	var cap: int = maxi(1, int(_combo.get("max_voices", FALLBACK_COMBO["max_voices"])))
	var voices: int = mini(n, cap)
	var semis: float = float(_combo.get("semitone_step", FALLBACK_COMBO["semitone_step"]))
	var out: Array = []
	for i in range(voices):
		out.append(pow(1.0594630943592953, float(i) * semis))
	return out

## A rising-pitch break RATTLE for a multi-cell blast (the arcade arpeggio). Plays up to
## combo.max_voices `break` voices, each on a small time offset (combo.step_seconds) at a pitch a
## semitone higher than the last (combo_pitches). A 1-cell break is a single immediate voice. Each
## voice still gets its own pitch jitter on top of the climb, so the rattle is organic, not mechanical.
## Headless-safe (timers + play() are no-ops under the dummy driver; the per-voice play() still
## increments play_count — the FIRST voice synchronously, the rest on staggered timers).
func play_break_combo(cleared_count: int) -> void:
	var pitches: Array = combo_pitches(cleared_count)
	var step_s: float = float(_combo.get("step_seconds", FALLBACK_COMBO["step_seconds"]))
	for i in range(pitches.size()):
		var pitch: float = float(pitches[i])
		if i == 0:
			# First voice fires immediately so a synchronous caller sees play_count tick.
			_play_combo_voice(pitch)
		else:
			# Stagger the rest; ignore_time_scale so a hit-stop freeze doesn't stall the rattle.
			var t: SceneTreeTimer = get_tree().create_timer(step_s * float(i), true, false, true)
			t.timeout.connect(_play_combo_voice.bind(pitch))

## Play one combo-rattle voice: a `break` tone at `base_pitch`, with the break event's own jitter
## layered on top of the semitone climb so successive voices both ascend AND vary.
func _play_combo_voice(base_pitch: float) -> void:
	if OS.has_feature("web") and not _unlocked:
		return
	var stream: AudioStream = _streams.get("break", null)
	if stream == null or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_voice]
	_voice = (_voice + 1) % _players.size()
	p.stream = stream
	var j: float = clampf(float(_pitch_jitter.get("break", 0.0)), 0.0, MAX_PITCH_JITTER)
	var jitter: float = _rng.randf_range(1.0 - j, 1.0 + j) if j > 0.0 else 1.0
	p.pitch_scale = maxf(0.01, base_pitch * jitter)
	p.play()
	_play_count += 1
	_last_event = "break"
	_duck_music()

## The stream bound to an event (for tests/inspection), or null if none.
func stream_for(event: String) -> AudioStream:
	return _streams.get(event, null)

## The pitch_scale of the voice used by the MOST-RECENT play() (for tests/inspection). play() advances
## _voice AFTER using _players[_voice], so the last-used voice is one behind. Headless-safe: pitch_scale
## is set on the player even though the dummy driver no-ops the actual playback.
func last_pitch_scale() -> float:
	if _players.is_empty():
		return 1.0
	var idx: int = (_voice - 1 + _players.size()) % _players.size()
	return _players[idx].pitch_scale

## The number of layered-boom voices the detonate cue resolves to (for tests/inspection).
func detonate_layer_count() -> int:
	return _detonate_layers.size()

# ── Volume routing (AC-5.10.1 sliders → AC-5.13.2 buses) ───────────────────────

func set_sfx_volume_db(db: float) -> void:
	var idx: int = AudioServer.get_bus_index(SFX_BUS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func set_music_volume_db(db: float) -> void:
	var idx: int = AudioServer.get_bus_index(MUSIC_BUS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func set_master_volume_db(db: float) -> void:
	var idx: int = AudioServer.get_bus_index(MASTER_BUS)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

# ── Music playback (AC-5.13.2 Music bus; placeholder loops) ───────────────────

func play_music(track: String, fade_seconds: float = 0.65) -> void:
	if OS.has_feature("web") and not _unlocked:
		_pending_music = track
		return
	var stream: AudioStream = _music_streams.get(track, null)
	if stream == null or _music_players.is_empty():
		return
	if _current_music == track and _music_players[_music_voice].playing:
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	var next_index: int = 1 - _music_voice
	var next: AudioStreamPlayer = _music_players[next_index]
	var prev: AudioStreamPlayer = _music_players[_music_voice]
	next.stream = stream
	next.volume_db = MUSIC_FADE_DB
	next.play()
	var target_db: float = _music_volume_db(track)
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(next, "volume_db", target_db, maxf(0.01, fade_seconds)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if prev.playing:
		_music_tween.tween_property(prev, "volume_db", MUSIC_FADE_DB, maxf(0.01, fade_seconds)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_music_tween.chain().tween_callback(prev.stop)
	_music_voice = next_index
	_current_music = track

func stop_music(fade_seconds: float = 0.35) -> void:
	if _music_players.is_empty():
		return
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for p in _music_players:
		if p.playing:
			_music_tween.tween_property(p, "volume_db", MUSIC_FADE_DB, maxf(0.01, fade_seconds))
	_music_tween.chain().tween_callback(func() -> void:
		for p in _music_players:
			p.stop()
		_current_music = ""
	)

func current_music() -> String:
	return _current_music

func music_stream_for(track: String) -> AudioStream:
	return _music_streams.get(track, null)

func _music_volume_db(track: String) -> float:
	var spec: Dictionary = _music_specs.get(track, FALLBACK_MUSIC.get(track, {"volume": 0.12}))
	var v: float = clampf(float(spec.get("volume", 0.12)), 0.0, 1.0)
	return linear_to_db(maxf(0.001, v))

func _duck_music() -> void:
	if _music_players.is_empty() or _current_music.is_empty():
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	var active: AudioStreamPlayer = _music_players[_music_voice]
	if not active.playing:
		return
	var target: float = _music_volume_db(_current_music)
	_duck_tween = create_tween()
	_duck_tween.tween_property(active, "volume_db", target - 5.0, 0.035)
	_duck_tween.tween_interval(0.12)
	_duck_tween.tween_property(active, "volume_db", target, 0.18)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_set_music_focus_muted(true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_set_music_focus_muted(false)

func _set_music_focus_muted(muted: bool) -> void:
	var idx: int = AudioServer.get_bus_index(MUSIC_BUS)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)

# ── Placeholder SFX synthesis (data-driven; no binary assets, no deps) ─────────

## Build the per-event streams + pitch-jitter table + the layered-boom voices from data/audio.json
## (via the GameData autoload), falling back to FALLBACK_SPECS if the table is missing/unparseable so
## a data hiccup can't silence the game (mirrors the boot() load_all() guard). _ready may run before
## GameData has loaded under some boot orders — the fallback covers that too.
func _build_streams() -> void:
	var events_data: Dictionary = _audio_events_table()
	var combo_data: Variant = _audio_subtable("combo")
	if combo_data is Dictionary:
		_combo = (combo_data as Dictionary).duplicate(true)
	for ev in EVENTS:
		var s: Dictionary = events_data.get(ev, FALLBACK_SPECS.get(ev, {"freq": 440.0, "dur": 0.1, "noise": 0.0, "sweep": 0.0, "pitch_jitter": 0.0}))
		_streams[ev] = _make_tone(float(s["freq"]), float(s["dur"]), float(s["noise"]), float(s.get("sweep", 0.0)))
		_pitch_jitter[ev] = float(s.get("pitch_jitter", 0.0))
	# Layered detonate boom: synth one stream per data-driven layer (or the fallback layers).
	_detonate_layers.clear()
	var det: Variant = _audio_subtable("detonate")
	var layers: Variant = (det as Dictionary).get("layers") if det is Dictionary else null
	if not (layers is Array) or (layers as Array).is_empty():
		layers = FALLBACK_DETONATE_LAYERS
	for layer in (layers as Array):
		if not (layer is Dictionary):
			continue
		var ld: Dictionary = layer
		var stream: AudioStreamWAV = _make_tone(
			float(ld.get("freq", 100.0)), float(ld.get("dur", 0.2)),
			float(ld.get("noise", 0.5)), float(ld.get("sweep", 0.0))
		)
		_detonate_layers.append({"stream": stream, "pitch_jitter": float(ld.get("pitch_jitter", 0.0))})
	_build_music_streams()

func _build_music_streams() -> void:
	_music_streams.clear()
	_music_specs.clear()
	var music_data: Variant = _audio_subtable("music")
	var md: Dictionary = music_data if music_data is Dictionary else {}
	for track in MUSIC_TRACKS:
		var spec: Dictionary = md.get(track, FALLBACK_MUSIC.get(track, {}))
		if spec.is_empty():
			continue
		_music_specs[track] = spec.duplicate(true)
		_music_streams[track] = _make_music_loop(spec)

## The `events` sub-object from data/audio.json, or {} if GameData/the table is unavailable. Each
## caller then falls back per-event so a partial table is still safe.
func _audio_events_table() -> Dictionary:
	var ev: Variant = _audio_subtable("events")
	return ev if ev is Dictionary else {}

## A top-level key from the audio table via GameData (headless-/boot-order-safe). Returns null if
## GameData isn't ready or the table/key is absent — callers fall back to the hardcoded defaults.
func _audio_subtable(key: String) -> Variant:
	var gd: Node = get_node_or_null("/root/GameData")
	if gd == null:
		return null
	var audio: Variant = gd.table("audio")
	if not (audio is Dictionary):
		return null
	return (audio as Dictionary).get(key)

## Build a short 16-bit PCM mono placeholder tone: a sine at `freq` mixed with white
## noise (`noise_mix`), under an exponential decay envelope. If `sweep_hz` is nonzero,
## the pitch glides from `freq` to `sweep_hz` over the duration. Pure code — no external
## asset. Deterministic (RNG seeded from the frequency) so the placeholder is stable.
func _make_tone(freq: float, duration: float, noise_mix: float, sweep_hz: float = 0.0) -> AudioStreamWAV:
	var count: int = maxi(1, int(MIX_RATE * duration))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	var end_freq: float = sweep_hz if sweep_hz > 0.0 else freq
	var rng := RandomNumberGenerator.new()
	rng.seed = int(freq * 1000.0)
	for i in range(count):
		var t: float = float(i) / float(count)
		var env: float = pow(1.0 - t, 2.0)               # decay to silence
		var cur_freq: float = lerpf(freq, end_freq, t)
		var phase_step: float = TAU * cur_freq / float(MIX_RATE)
		var tone: float = sin(phase)
		var noise: float = rng.randf_range(-1.0, 1.0)
		var sample: float = lerpf(tone, noise, noise_mix) * env * 0.5
		var v: int = clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, v)
		phase += phase_step
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav

func _make_music_loop(spec: Dictionary) -> AudioStreamWAV:
	var notes: Array = spec.get("notes", [])
	if notes.is_empty():
		notes = [220.0, 0.0, 277.18, 0.0]
	var bpm: float = maxf(1.0, float(spec.get("bpm", 120.0)))
	var step_beats: float = maxf(0.01, float(spec.get("step_beats", 0.5)))
	var step_seconds: float = 60.0 / bpm * step_beats
	var count: int = maxi(1, int(float(MIX_RATE) * step_seconds * float(notes.size())))
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase: float = 0.0
	for i in range(count):
		var t: float = float(i) / float(MIX_RATE)
		var step: int = mini(notes.size() - 1, int(floor(t / step_seconds)))
		var freq: float = float(notes[step])
		var sample: float = 0.0
		if freq > 0.0:
			var local_t: float = fmod(t, step_seconds) / step_seconds
			var env: float = minf(1.0, local_t * 18.0) * pow(maxf(0.0, 1.0 - local_t), 0.35)
			var square: float = 1.0 if sin(phase) >= 0.0 else -1.0
			var octave: float = 1.0 if sin(phase * 2.0) >= 0.0 else -1.0
			sample = (square * 0.65 + octave * 0.25) * env * 0.25
			phase += TAU * freq / float(MIX_RATE)
		var v: int = clampi(int(sample * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav
