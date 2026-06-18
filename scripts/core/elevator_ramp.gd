class_name ElevatorRamp
extends RefCounted
## Pure hold-to-move elevator ramp logic (no Node/scene/input deps → headless-testable).
##
## When an elevator button (or the up/down key) is HELD, the platform moves CONTINUOUSLY —
## row by row — until released or a limit. The speed RAMPS UP from a slow start to a capped
## max: starting at `start_rows_per_sec`, accelerating by `accel_rows_per_sec2` each second,
## clamped to `max_rows_per_sec`. So a tap nudges one row; a long hold glides faster and faster
## up to the cap. The ramp/cap constants are /data tunables (balance.elevator) — never literals.
##
## This object holds ONLY the transient hold state (elapsed time + a fractional row accumulator).
## `advance(delta)` integrates one frame and returns how many WHOLE rows to step this frame; the
## caller (mine.gd) then asks the Platform to move that many rows one at a time, respecting
## can_move_up/can_move_down. `reset()` clears the hold (call on release) so the next press starts
## slow again.
##
## Speed model (frame-rate independent, integrated analytically so it matches at any delta):
##   v(t) = min(start + accel * t, max)        rows/sec at hold-elapsed t
## Distance over [t, t+dt] is integrated exactly (trapezoid is exact for a clamped linear ramp
## because v is piecewise-linear), so two small frames advance the same total as one big frame.
##
## ACs: AC-5.7.2 (the platform's reachable depth is the row-by-row supported span — this only
##      decides HOW MANY rows the hold requests; the Platform still clamps to can_move_up/down).

## Seconds the button/key has been held this press (0 at the start of a fresh hold).
var _elapsed: float = 0.0
## Fractional rows banked but not yet stepped (carried across frames so partial-row progress
## isn't lost — when it crosses 1.0 a whole row is released and 1.0 is subtracted).
var _accum: float = 0.0


## Reset the hold state (call on release / when the held direction changes). The next press
## starts at the slow `start_rows_per_sec` again.
func reset() -> void:
	_elapsed = 0.0
	_accum = 0.0


## True while a hold is in progress (elapsed advanced past 0).
func is_held() -> bool:
	return _elapsed > 0.0


## Integrate one frame of a held press and return the number of WHOLE rows to step this frame
## (>= 0). `delta` is the frame time; the ramp constants are passed in from /data so this stays
## pure. The very first call of a fresh hold (elapsed == 0) ALWAYS releases at least one row, so a
## quick tap-and-release still moves a single row (a tap == one step). Subsequent frames release
## floor(accumulated distance) rows. Frame-rate independent: the speed is integrated over the
## elapsed interval, so the total rows for a given hold duration is the same at any delta.
func advance(delta: float, start_rows_per_sec: float, accel_rows_per_sec2: float, max_rows_per_sec: float) -> int:
	if delta <= 0.0:
		return 0
	var start_v: float = maxf(0.0, start_rows_per_sec)
	var max_v: float = maxf(start_v, max_rows_per_sec)
	var accel: float = maxf(0.0, accel_rows_per_sec2)
	var first_frame: bool = _elapsed <= 0.0
	# Distance travelled over [_elapsed, _elapsed + delta] under the clamped linear ramp v(t).
	var t0: float = _elapsed
	var t1: float = _elapsed + delta
	_accum += _distance(t0, t1, start_v, accel, max_v)
	_elapsed = t1
	# A fresh hold always yields at least one row (a tap moves one row), even if the integrated
	# distance for the first short frame rounds below 1.0.
	if first_frame and _accum < 1.0:
		_accum = 1.0
	var rows: int = int(floor(_accum))
	if rows > 0:
		_accum -= float(rows)
	return rows


## Exact distance (in rows) the ramp covers over the time interval [t0, t1], for the clamped
## linear speed v(t) = min(start_v + accel * t, max_v). Splits the interval at the time the
## ramp hits the cap (t_cap) so the area is exact: a linear (trapezoidal) part before the cap
## and a constant (rectangular) part after. Pure helper.
static func _distance(t0: float, t1: float, start_v: float, accel: float, max_v: float) -> float:
	if t1 <= t0:
		return 0.0
	# Time at which the ramp reaches the cap (start_v + accel * t_cap == max_v). With no accel the
	# speed is constant at start_v (already <= max_v after the clamp), so the cap is never reached.
	var t_cap: float = INF
	if accel > 0.0:
		t_cap = (max_v - start_v) / accel
	var dist: float = 0.0
	# Ramp (linear) portion: [t0, min(t1, t_cap)].
	var ramp_end: float = minf(t1, t_cap)
	if ramp_end > t0:
		var v_a: float = start_v + accel * t0
		var v_b: float = start_v + accel * ramp_end
		dist += 0.5 * (v_a + v_b) * (ramp_end - t0)
	# Capped (constant max_v) portion: [max(t0, t_cap), t1].
	var cap_start: float = maxf(t0, t_cap)
	if t1 > cap_start:
		dist += max_v * (t1 - cap_start)
	return dist


## The instantaneous ramp speed (rows/sec) at hold-elapsed time `t` — the clamped linear ramp.
## Pure; exposed for tests/inspection (e.g. "speed rises then caps").
static func speed_at(t: float, start_rows_per_sec: float, accel_rows_per_sec2: float, max_rows_per_sec: float) -> float:
	var start_v: float = maxf(0.0, start_rows_per_sec)
	var max_v: float = maxf(start_v, max_rows_per_sec)
	var accel: float = maxf(0.0, accel_rows_per_sec2)
	return minf(start_v + accel * maxf(0.0, t), max_v)
