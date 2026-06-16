extends Node
## Audio — the minimal SFX layer for the slice (v0.4.1). Provides placeholder SFX for
## the core gameplay events, routes them through the Master → {SFX, Music} bus layout,
## exposes per-bus volume control for the §5.10 sliders, and unlocks the web audio
## context on the first user gesture.
##
## Placeholder SFX are SYNTHESISED IN CODE (short decaying tones, optional noise) so the
## slice ships real, playable sound without committing binary assets or adding deps —
## "placeholder SFX present from the step-1 slice" (AC-5.13.1). Final sound design/mix is
## ROADMAP (U24); this is the bus + hook + placeholder infrastructure those assets drop into.
##
## Registered as the `Audio` autoload (project.godot). The mine controller calls the thin
## play_*() wrappers at the real event sites. Headless-safe: under the dummy audio driver
## play() is a harmless no-op; the bus layout + stream bindings still exist and are tested.
##
## ACs: AC-5.13.1 (SFX for core events, present from the slice), AC-5.13.2 (Master→{SFX,
##      Music} bus routing), AC-5.13.3 (resume audio on first web gesture),
##      AC-5.10.1 (independent SFX/Music volume control).

const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const MASTER_BUS := "Master"

## The core gameplay events that carry placeholder SFX (AC-5.13.1).
const EVENTS: Array[String] = [
	"detonate", "crack", "break", "ore_credited",
	"pack_open", "relic_found", "prestige_banked",
]

## Voice pool size — enough for overlapping cues (detonate + break + ore in one blast).
const VOICES := 4
const MIX_RATE := 22050

var _streams: Dictionary = {}            # event -> AudioStreamWAV
var _players: Array[AudioStreamPlayer] = []
var _voice: int = 0
var _unlocked: bool = false
# Observability so wiring can be asserted (a cue actually fired), not just that the hook exists.
var _play_count: int = 0
var _last_event: String = ""

func _ready() -> void:
	_build_streams()
	for i in range(VOICES):
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
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

var audio_unlocked: bool:
	get:
		return _unlocked

# ── Playback (AC-5.13.1) ────────────────────────────────────────────────────────

## Play the placeholder SFX bound to a core event. Unknown event → no-op. Round-robins
## a small voice pool so co-occurring cues (detonate + break) don't cut each other off.
func play(event: String) -> void:
	var stream: AudioStream = _streams.get(event, null)
	if stream == null or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_voice]
	_voice = (_voice + 1) % _players.size()
	p.stream = stream
	p.play()
	_play_count += 1
	_last_event = event

## Number of cues played + the last event id (for wiring assertions / inspection).
var play_count: int:
	get:
		return _play_count

var last_event: String:
	get:
		return _last_event

func play_detonate() -> void: play("detonate")
func play_crack() -> void: play("crack")
func play_break() -> void: play("break")
func play_ore_credited() -> void: play("ore_credited")
func play_pack_open() -> void: play("pack_open")
func play_relic_found() -> void: play("relic_found")
func play_prestige_banked() -> void: play("prestige_banked")

## The stream bound to an event (for tests/inspection), or null if none.
func stream_for(event: String) -> AudioStream:
	return _streams.get(event, null)

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

# ── Placeholder SFX synthesis (no binary assets, no deps) ──────────────────────

func _build_streams() -> void:
	# A distinct short tone per event so each is identifiable. freq = pitch (Hz),
	# sweep = end pitch (Hz, 0 = no sweep), dur = seconds, noise = white-noise mix
	# [0,1] (higher = more "thud"/"crunch").
	var specs := {
		"detonate":        {"freq": 55.0,  "dur": 0.22, "noise": 0.85, "sweep": 30.0},
		"crack":           {"freq": 420.0, "dur": 0.04, "noise": 0.60, "sweep": 0.0},
		"break":           {"freq": 140.0, "dur": 0.12, "noise": 0.70, "sweep": 90.0},
		"ore_credited":    {"freq": 1250.0,"dur": 0.07, "noise": 0.0,  "sweep": 0.0},
		"pack_open":       {"freq": 620.0, "dur": 0.14, "noise": 0.1,  "sweep": 820.0},
		"relic_found":     {"freq": 523.0, "dur": 0.45, "noise": 0.0,  "sweep": 1047.0},
		"prestige_banked": {"freq": 740.0, "dur": 0.25, "noise": 0.0,  "sweep": 1109.0},
	}
	for ev in EVENTS:
		var s: Dictionary = specs.get(ev, {"freq": 440.0, "dur": 0.1, "noise": 0.0, "sweep": 0.0})
		_streams[ev] = _make_tone(float(s["freq"]), float(s["dur"]), float(s["noise"]), float(s.get("sweep", 0.0)))

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
