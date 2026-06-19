extends Node2D
class_name AimLine
## Marching dashed aim-trajectory line, drawn in _draw() (Node2D canvas primitive path) so it
## renders under GL-Compatibility / WebGL2 with no Line2D UV / texture-tiling fragility (the prior
## ShaderMaterial on a 1x1 GradientTexture2D rendered nothing — see reports/aim-line-method.md).
##
## Points are in this node's LOCAL space; mine.gd feeds the SAME PackedVector2Array it used to push
## into Line2D.add_point() (Aim.preview_path output, already in world/scene space — keep this node at
## the origin with no transform, exactly as the old Line2D was). The march is a pure phase offset
## advanced by mine.gd; reduced-motion / pause freeze it by simply not advancing that offset.
##
## ACs: AC-5.3.1 (initial-arc preview while aiming — now visibly drawn), AC-5.10.4 (reduced-motion:
## the dashes hold still but the line stays visible).

## Tunables, mirrored from data/balance.json "feel" (mine.gd pushes them in each refresh).
var width: float = 5.0:
	set(value):
		width = value
		queue_redraw()
var dash_px: float = 18.0
var gap_px: float = 14.0
## Per-vertex-style tip fade: alpha at the tip end as a fraction of head alpha (0..1). The arc
## dissolves toward the impact reticle instead of ending on a hard dash.
var tip_fade_frac: float = 0.12
## Head color (alpha included). mine.gd sets this; we fade alpha toward the tip.
var line_color: Color = Color(1, 1, 0.6, 0.85)
## Global alpha multiplier the throw fade-out / dimming tween animates (0..1). Replaces the old
## Line2D.self_modulate:a — mine.gd tweens THIS instead.
var alpha_mult: float = 1.0:
	set(value):
		alpha_mult = value
		queue_redraw()

var _points: PackedVector2Array = PackedVector2Array()
## March phase in along-line pixels (advanced by mine.gd; frozen for reduced-motion / pause).
var _march_px: float = 0.0

## Replace the line's polyline. `pts` are the Aim.preview_path points (same as the old add_point loop).
func set_points(pts: PackedVector2Array) -> void:
	_points = pts
	queue_redraw()

func clear() -> void:
	_points = PackedVector2Array()
	queue_redraw()

func has_points() -> bool:
	return _points.size() >= 2

func point_count() -> int:
	return _points.size()

## Advance the march. mine.gd calls this each frame with (delta * march_px_per_sec); when the gate
## says "no motion" (reduced motion or paused) it simply passes 0, so the dashes hold still.
func advance_march(px: float) -> void:
	if px == 0.0:
		return
	var period: float = max(dash_px + gap_px, 0.0001)
	_march_px = fposmod(_march_px + px, period)  # bounded → no float drift over a long aim
	queue_redraw()

## PURE march-speed easing (v0.5 aim-indicator pass). The dash crawls at `base` px/sec normally and
## speeds up to `base * boost_mult` while the player is actively turning the aim (holding ←/→). The
## effective multiplier eases between 1.0 (idle) and `boost_mult` (aiming) at `ease_rate` per second
## so the speed-up ramps in / out instead of snapping. Returns the NEXT eased multiplier given the
## current one. Frame-rate independent (the ease step scales with delta) and clamped to [1, boost_mult]
## so it can't overshoot. No Node deps → headless-testable (the gating live state is driven by mine.gd).
##  - `current`: this frame's multiplier (start at 1.0).
##  - `aiming`: true while a keyboard aim key is held (the march should be speeding up).
##  - `boost_mult`: the data-driven peak multiplier (balance.feel.aim_march_aim_mult, >= 1).
##  - `ease_rate`: how fast (per second) the multiplier moves toward its target.
##  - `delta`: frame time in seconds.
static func ease_march_mult(current: float, aiming: bool, boost_mult: float, ease_rate: float, delta: float) -> float:
	var peak: float = maxf(boost_mult, 1.0)
	var target: float = peak if aiming else 1.0
	var lo: float = 1.0
	var hi: float = peak
	if delta <= 0.0 or ease_rate <= 0.0:
		return clampf(target, lo, hi)  # no easing budget → snap to the target (still clamped)
	var step: float = ease_rate * delta
	var next: float = move_toward(current, target, step)
	return clampf(next, lo, hi)

## PURE visibility gate (v0.5 aim-indicator pass). The aim arc + reticle are drawn ONLY when a real
## aim is in play: the dig is still running, no charge is mid-flight, the throw fade-out isn't
## animating the line away, and the launch point (platform/elevator/supports) is NOT moving — a drawn
## arc from a moving muzzle would be a stale lie. Returns true when the preview should be shown.
## mine.gd reads the live state into these primitives; keeping the rule pure makes the gate (incl. the
## "hidden while the platform is in motion" requirement) headless-testable without a GL context.
static func preview_visible(dig_ended: bool, charge_in_flight: bool, fading: bool, launch_moving: bool) -> bool:
	if dig_ended:
		return false
	if charge_in_flight:
		return false
	if fading:
		return false
	if launch_moving:
		return false
	return true

# Hard cap on TOTAL dash/gap walk iterations. A 360° aim (especially straight up, with no surface
# to stop the projected arc) can produce an enormous/near-unbounded segment; without this cap the
# walk iterates seg_len/period times and HANGS the renderer (a real freeze caught in the field —
# only triggered by upward aim, so the boot screenshot never saw it). The cap bounds the work no
# matter what the preview feeds us; a normal few-hundred-px arc never approaches it.
const MAX_DASHES := 1024

## PURE walk: turn `points` into dash sub-segments [{a,b,mid}], where mid is the dash-midpoint's
## along-line distance (for the tip fade). Bounded to MAX_DASHES total iterations and skips
## non-finite segments, so it can NEVER iterate unbounded on a pathological arc. No Node/draw deps,
## so the anti-hang guarantee is headless-testable (test_aim.dash_spans). _draw just renders these.
static func dash_spans(points: PackedVector2Array, march_px: float, dash: float, gap: float) -> Array:
	var spans: Array = []
	if points.size() < 2:
		return spans
	var period: float = max(dash + gap, 0.0001)
	var dist: float = 0.0
	var iters: int = 0  # counts EVERY iteration (dash or gap) — a run of gaps can't loop unbounded either
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var seg_len: float = a.distance_to(b)
		if not is_finite(seg_len) or seg_len <= 0.0001:
			continue
		var dir: Vector2 = (b - a) / seg_len
		var s: float = 0.0
		while s < seg_len:
			if iters >= MAX_DASHES:
				return spans
			iters += 1
			var phase: float = fposmod(dist + s - march_px, period)
			if phase < dash:
				var run: float = min(dash - phase, seg_len - s)
				spans.append({"a": a + dir * s, "b": a + dir * (s + run), "mid": dist + s + run * 0.5})
				s += maxf(run, 0.5)  # always advance: float round-off near a boundary can't stall it
			else:
				s += maxf(period - phase, 0.5)
		dist += seg_len
	return spans

func _draw() -> void:
	if _points.size() < 2 or alpha_mult <= 0.0 or width <= 0.0:
		return
	var total_len: float = 0.0
	for i in range(1, _points.size()):
		var sl: float = _points[i - 1].distance_to(_points[i])
		if is_finite(sl):
			total_len += sl
	var fade_start: float = total_len * (1.0 - clampf(tip_fade_frac, 0.0, 1.0))
	for span in dash_spans(_points, _march_px, dash_px, gap_px):
		_draw_dash(span["a"], span["b"], span["mid"], fade_start, total_len)

func _draw_dash(p0: Vector2, p1: Vector2, mid: float, fade_start: float, total_len: float) -> void:
	var c: Color = line_color
	c.a *= alpha_mult * _tip_alpha(mid, fade_start, total_len)
	if c.a <= 0.0:
		return
	# antialiased=true matches the old Line2D look; the most-portable canvas call under WebGL2.
	draw_line(p0, p1, c, width, true)

func _tip_alpha(d: float, fade_start: float, total_len: float) -> float:
	if total_len <= 0.0 or d <= fade_start:
		return 1.0
	return clampf(1.0 - (d - fade_start) / max(total_len - fade_start, 0.0001), 0.0, 1.0)
