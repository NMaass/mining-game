class_name ScreenTransition
extends RefCounted
## Pure screen-transition envelope math (no Node/scene deps → headless-testable).
##
## Two presentation effects share one envelope so the timing math is proven once:
##  • a TOAST / banner fade — `fade_alpha_at`: a 0→1→1→0 ramp (fade IN, HOLD, fade OUT),
##    used for the non-blocking "Relic recovered  +1 Prestige" confirmation banner; and
##  • a screen-REVEAL veil — `reveal_alpha_at`: a 1→1→0 ramp (HOLD opaque, then fade OUT),
##    used to fade a fresh dig / app boot up from black so a state swap never hard-cuts.
##
## The reveal is just the fade envelope with a zero IN phase, so a single function backs both.
## Everything is `f(elapsed, durations)` — the UI drives it via a single tween_method over the
## elapsed time, and the unit tests pin the curve shape (endpoints, plateau, monotonicity).
##
## Conventions: negative durations are treated as 0 (a phase with 0 duration is skipped, no
## divide-by-zero), elapsed is clamped to [0, total], and the returned alpha is clamped to [0,1].
##
## ACs: presentation polish for AC-5.8.1 (relic feedback) + AC-5.8.4 (distinct dig-end state) —
##      smooth transitions across the start → dig → run-end states; motion-gating stays in the UI.


## The toast/banner alpha at `elapsed` seconds for a fade IN → HOLD → fade OUT envelope.
## Ramps 0→1 over `in_s`, holds at 1 for `hold_s`, ramps 1→0 over `out_s`, then stays 0.
static func fade_alpha_at(elapsed: float, in_s: float, hold_s: float, out_s: float) -> float:
	var i: float = maxf(0.0, in_s)
	var h: float = maxf(0.0, hold_s)
	var o: float = maxf(0.0, out_s)
	if elapsed <= 0.0:
		# Before the ramp starts the banner is invisible — UNLESS there is no fade-in phase, in
		# which case it begins fully opaque (the reveal veil case).
		return 0.0 if i > 0.0 else 1.0
	if elapsed < i:
		return clampf(elapsed / i, 0.0, 1.0)
	if elapsed < i + h:
		return 1.0
	if o <= 0.0:
		# No fade-out phase: snap to 0 once the hold ends.
		return 0.0
	var into_out: float = elapsed - i - h
	if into_out >= o:
		return 0.0
	return clampf(1.0 - into_out / o, 0.0, 1.0)


## The veil alpha at `elapsed` for a HOLD-opaque → fade-OUT reveal (starts at 1, ends at 0).
## Equivalent to `fade_alpha_at` with no fade-in phase.
static func reveal_alpha_at(elapsed: float, hold_s: float, out_s: float) -> float:
	return fade_alpha_at(elapsed, 0.0, hold_s, out_s)


## Total duration of a fade IN → HOLD → fade OUT envelope (seconds).
static func fade_total_seconds(in_s: float, hold_s: float, out_s: float) -> float:
	return maxf(0.0, in_s) + maxf(0.0, hold_s) + maxf(0.0, out_s)


## Total duration of a reveal (HOLD → fade OUT) envelope (seconds).
static func reveal_total_seconds(hold_s: float, out_s: float) -> float:
	return fade_total_seconds(0.0, hold_s, out_s)
