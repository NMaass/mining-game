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

func _draw() -> void:
	if _points.size() < 2 or alpha_mult <= 0.0 or width <= 0.0:
		return
	var period: float = max(dash_px + gap_px, 0.0001)
	# Total arc length, for the tip fade.
	var total_len: float = 0.0
	for i in range(1, _points.size()):
		total_len += _points[i - 1].distance_to(_points[i])
	var fade_start: float = total_len * (1.0 - clampf(tip_fade_frac, 0.0, 1.0))
	# Walk the polyline emitting dash sub-segments. `dist` is cumulative along-line distance from the
	# muzzle. `phase` (offset by the march) decides whether we're inside a dash or a gap.
	var dist: float = 0.0
	for i in range(1, _points.size()):
		var a: Vector2 = _points[i - 1]
		var b: Vector2 = _points[i]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0001:
			continue
		var dir: Vector2 = (b - a) / seg_len
		var s: float = 0.0
		while s < seg_len:
			# Where are we in the dash/gap cycle at along-line distance (dist + s)?
			var phase: float = fposmod(dist + s - _march_px, period)
			if phase < dash_px:
				# Inside a dash: draw to the end of the dash or the segment, whichever comes first.
				var run: float = min(dash_px - phase, seg_len - s)
				var p0: Vector2 = a + dir * s
				var p1: Vector2 = a + dir * (s + run)
				_draw_dash(p0, p1, dist + s, dist + s + run, fade_start, total_len)
				s += run
			else:
				# Inside a gap: skip to the next dash start.
				s += (period - phase)
		dist += seg_len

func _draw_dash(p0: Vector2, p1: Vector2, d0: float, d1: float, fade_start: float, total_len: float) -> void:
	var c: Color = line_color
	c.a *= alpha_mult * _tip_alpha((d0 + d1) * 0.5, fade_start, total_len)
	if c.a <= 0.0:
		return
	# antialiased=true matches the old Line2D look; the most-portable canvas call under WebGL2.
	draw_line(p0, p1, c, width, true)

func _tip_alpha(d: float, fade_start: float, total_len: float) -> float:
	if total_len <= 0.0 or d <= fade_start:
		return 1.0
	return clampf(1.0 - (d - fade_start) / max(total_len - fade_start, 0.0001), 0.0, 1.0)
