class_name Platform
extends Node2D
## Platform — the mining platform + camera anchor system (U7, v0.4).
##
## Thin Node wrapper around the pure `PlatformLogic` (scripts/core/platform.gd):
## the system owns the platform body, the descent tween, and the child Camera2D;
## the COUNTING / threshold / descent-step decision is delegated to PlatformLogic
## so it stays headless-testable as a pure function.
##
## Descent (AC-5.7.2): WHILE enough cells directly beneath the platform are cleared
## (threshold from /data), the platform's TARGET ROW lowers and `position` is
## *tweened* toward the new target over `descent_tween_seconds` (never snapped).
##
## Camera (AC-5.7.3): the child Camera2D uses position smoothing and is anchored to
## the platform's TARGET position (offset down by `camera_lookahead_cells`). The
## camera target is recomputed only when the platform target changes — it is NOT
## hard-set per frame, so it never fights the smoothing.
##
## All tunables (threshold, max steps, tween duration, camera lookahead, cell size)
## come from /data via Registry — no balance literals here.
##
## ACs: AC-5.7.1 (platform is the anchor; muzzle is at the platform),
##      AC-5.7.2 (tweened descent, not a snap),
##      AC-5.7.3 (camera follows the platform TARGET via smoothing, not hard-set).

## Emitted after the target row changes (descent committed). `new_row` is the
## absolute cell row the platform now targets.
signal descended(new_row: int)

var _tables: Dictionary

## Absolute cell row the platform currently TARGETS (the descent tween animates
## `position.y` toward this row * cell_size). Starts at 0 (top of the shaft).
var _target_row: int = 0

var _cell_size: int
var _mine_width: int
var _shaft_width: int
var _shaft_left: int
var _threshold: int
var _max_steps: int
var _tween_seconds: float
var _lookahead_cells: int
var _camera_zoom: float

## Child nodes (authored in platform.tscn, or built on demand for headless tests).
@onready var _body: Node2D = get_node_or_null("Body")
@onready var _camera: Camera2D = get_node_or_null("Camera")

## Optional live tween for the descent animation (kept so a new trigger can
## restart cleanly without stacking tweens).
var _descent_tween: Tween = null


## Horizontal look-ahead in cells: the camera nudges toward the aim direction so the
## player can see where the charge is going. Applied on top of the vertical lookahead.
var _look_ahead_cells: int = 0

# ── Trauma-based camera shake (v0.5 arcade pass) ──────────────────────────────
## A decaying "trauma" model (GDC "Juice it or lose it" lineage): each blast ADDS
## trauma (clamped to 1); the per-frame camera OFFSET is `trauma²` × (a directional
## kick away from the impact + a smooth FastNoiseLite wobble), and trauma decays
## linearly each second. Bigger breaks add more trauma → a larger, longer kick. ALL
## writes go to `_camera.offset` (and zoom) — NEVER `_camera.position` or the platform
## target — so AC-5.7.3 (camera follows the platform target via smoothing) stays green;
## when trauma reaches 0 the offset is hard-set EXACTLY to Vector2.ZERO so it can never
## fight the position smoothing. All magnitudes are /data (Registry.vfx_*), not literals.
var _trauma: float = 0.0
var _shake_t: float = 0.0
var _kick_dir: Vector2 = Vector2.ZERO
var _noise: FastNoiseLite = null
## Live zoom-punch tween (kept so a fresh punch restarts cleanly without stacking).
var _zoom_tween: Tween = null

# ── Launch recoil (v0.5 arcade pass) ──────────────────────────────────────────
## A throw kicks the platform DECK opposite the launch direction then springs it back — a
## tactile "shove" that sells the launch. The kick is applied to the `Body/Visual` child ONLY
## (never `Body.position`, which the descent tween owns, and never the collider/muzzle/camera),
## so recoil can never fight the descent animation or drift the launch point. The rest position
## is the Visual's authored local position; every recoil tweens back to exactly that, so an
## interrupted recoil mid-descent (or a second throw) can never strand the deck off-center.
var _recoil_tween: Tween = null
## The Visual child's authored rest position (captured once at configure) — recoil springs back here.
var _visual_rest: Vector2 = Vector2.ZERO

## Configure the platform from /data tables. Call once after instancing. Idempotent
## w.r.t. tunables; resets the target row to `start_row` (default 0).
func configure(tables: Dictionary, start_row: int = 0) -> void:
	_tables = tables
	_cell_size = Registry.block_pixel_size(tables)
	_mine_width = Registry.mine_width_cells(tables)
	_shaft_width = Registry.shaft_width(tables)
	_shaft_left = Registry.shaft_left_cell(tables)
	_threshold = Registry.platform_clear_threshold(tables)
	_max_steps = Registry.descent_max_steps(tables)
	_tween_seconds = Registry.descent_tween_seconds(tables)
	_lookahead_cells = Registry.camera_lookahead_cells(tables)
	_camera_zoom = Registry.camera_zoom(tables)
	_target_row = start_row
	# Smooth (non-jitter) shake noise — frequency is data-driven so the wobble character
	# is a tunable. FastNoiseLite is already a known-good dep (block_gen.gd uses it).
	if _noise == null:
		_noise = FastNoiseLite.new()
	_noise.frequency = Registry.vfx_f(tables, "shake_noise_freq", 5.0)
	_configure_body_geometry()
	# Capture the deck Visual's authored rest position so launch recoil always springs back to it.
	var visual_node := get_node_or_null("Body/Visual") as Node2D
	if visual_node != null:
		_visual_rest = visual_node.position
	# Place the platform + camera at the starting target (no tween on initial place).
	if _body != null:
		_body.position = platform_target_position()
	if _camera != null:
		_camera.position_smoothing_enabled = true
		_camera.zoom = Vector2(_camera_zoom, _camera_zoom)
		_camera.position = camera_target_position()
		_configure_camera_limits()


## The absolute cell row the platform currently targets.
var target_row: int:
	get:
		return _target_row


## World-space position the platform body is tweening toward (its target).
## Pure function of the target row + cell size — assertable headless.
func platform_target_position() -> Vector2:
	return Vector2(_shaft_x_center(), float(_target_row * _cell_size))


## World-space anchor the camera follows. By contract (AC-5.7.3) this is DERIVED
## from the platform target — same x, offset DOWN by the data-driven lookahead — so
## the camera always tracks the platform target and never the raw body/explosion.
## A small horizontal look-ahead follows the aim angle for route planning.
func camera_target_position() -> Vector2:
	var pt: Vector2 = platform_target_position()
	return Vector2(pt.x + float(_look_ahead_cells * _cell_size), pt.y + float(_lookahead_cells * _cell_size))


## Clamp the camera to the bounded mine rectangle so empty space outside the volume
## is never shown.
func _configure_camera_limits() -> void:
	if _camera == null:
		return
	var mine_w_px: float = float(_mine_width * _cell_size)
	var mine_h_px: float = float(Registry.mine_height_cells(_tables) * _cell_size)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(mine_w_px)
	_camera.limit_bottom = int(mine_h_px)
	_camera.limit_smoothed = true


## Nudge the camera horizontally toward the aim direction. `angle` is the launch
## angle in radians (0 = down, negative = left, positive = right).
func set_look_ahead(angle: float) -> void:
	var max_cells: int = 6
	# sin(angle) is roughly horizontal component for the clamped launch arc.
	_look_ahead_cells = int(round(clampf(sin(angle), -1.0, 1.0) * float(max_cells)))
	_reanchor_camera()


## Add trauma to the decaying camera-shake model and aim its directional kick AWAY
## from the impact. `amount` is the trauma to add (caller scales it by the motion-
## intensity accessibility setting + the cleared-cell count); `from_world_pos` is the
## blast center in world space — the kick points from the impact toward the camera
## anchor so a blast "shoves" the view away from itself. Trauma is clamped to 1; the
## per-frame offset (computed in _process) is `trauma²`-shaped so it decays softly.
## Writes nothing to the camera directly — _process owns the offset (NEVER position).
func add_trauma(amount: float, from_world_pos: Vector2) -> void:
	if amount <= 0.0:
		return
	_trauma = minf(1.0, _trauma + amount)
	var anchor: Vector2 = camera_target_position()
	var dir: Vector2 = anchor - from_world_pos
	# Degenerate (blast exactly at the anchor): keep the last direction so the kick
	# still reads; otherwise point away from the impact.
	if dir.length_squared() > 0.0001:
		_kick_dir = dir.normalized()


## Per-frame camera-shake offset (AC-5.7.3-safe: writes _camera.offset ONLY). Decays the
## trauma, shapes it `trauma²`, and combines a directional kick away from the last impact
## with a smooth FastNoiseLite wobble. When trauma reaches 0 the offset is hard-set EXACTLY
## to Vector2.ZERO so a residual sub-pixel offset never fights the position smoothing.
func _process(delta: float) -> void:
	if _camera == null:
		return
	if _trauma <= 0.0:
		# Idle: ensure the offset is exactly zero (set once, then cheap no-op).
		if _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		return
	var decay: float = Registry.vfx_f(_tables, "shake_decay_per_sec", 1.8)
	_trauma = maxf(_trauma - decay * delta, 0.0)
	_shake_t += delta
	if _trauma <= 0.0:
		# Trauma fully spent this frame — snap the offset back to dead center exactly.
		_camera.offset = Vector2.ZERO
		return
	var amt: float = _trauma * _trauma
	var kick_px: float = Registry.vfx_f(_tables, "shake_kick_px", 6.0)
	var max_offset: float = Registry.vfx_f(_tables, "shake_max_offset_px", 10.0)
	# Two decorrelated noise lanes (one per axis) sampled along the shake clock. The
	# FastNoiseLite `frequency` (vfx.shake_noise_freq) sets the wobble speed, so the time
	# coordinate is passed raw — a smooth, non-jittery sway rather than per-frame random.
	var wobble := Vector2(
		max_offset * amt * _noise.get_noise_2d(_shake_t, 0.0),
		max_offset * amt * _noise.get_noise_2d(0.0, _shake_t)
	)
	_camera.offset = _kick_dir * kick_px * amt + wobble


## Punch the camera ZOOM in briefly then ease it back to the base zoom — a snappy "kick"
## that sells the detonation's weight. `strength` (>= 0) scales the punch fraction; the
## punch magnitude/settle time are /data (vfx.zoom_punch / vfx.zoom_punch_seconds). Writes
## _camera.zoom ONLY (never position). _reanchor_camera re-asserts the base zoom on descent
## so a punch in flight can never strand the zoom off-base.
func zoom_punch(strength: float) -> void:
	if _camera == null or strength <= 0.0:
		return
	var punch: float = Registry.vfx_f(_tables, "zoom_punch", 0.06) * clampf(strength, 0.0, 1.0)
	if punch <= 0.0:
		return
	var seconds: float = Registry.vfx_f(_tables, "zoom_punch_seconds", 0.18)
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	var base: Vector2 = Vector2(_camera_zoom, _camera_zoom)
	# Zoom IN = larger zoom value in Godot (Camera2D.zoom multiplies). Punch in, ease back.
	_camera.zoom = base * (1.0 + punch)
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(_camera, "zoom", base, seconds) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


## Kick the platform DECK opposite the launch direction then spring it back — a tactile recoil
## on every throw. `angle` is the launch angle in radians (0 = down; → Aim.angle_to_direction);
## `px` is the recoil distance (caller scales it by the motion-intensity accessibility setting, so
## motion 0 → no kick). Writes ONLY the `Body/Visual` child's local position (the deck art) — never
## `Body.position` (the descent tween owns that), the collider, the muzzle, or the camera — so AC-5.7.x
## stays green and recoil can't fight the descent. The spring-back ALWAYS targets the authored rest
## position, so an interrupted/overlapping recoil can never strand the deck off-center.
func recoil(angle: float, px: float) -> void:
	if px <= 0.0:
		return
	var visual := get_node_or_null("Body/Visual") as Node2D
	if visual == null:
		return
	# Launch direction (0 = straight down). Recoil is the OPPOSITE — the deck is shoved back.
	var launch_dir := Vector2(sin(angle), cos(angle))
	var kick: Vector2 = _visual_rest - launch_dir.normalized() * px
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	# Apply the kick IMMEDIATELY (a snappy shove the same frame as the throw) then SPRING back to the
	# authored rest over a short tween (TRANS_BACK eases past-and-settle). Setting the kick directly —
	# rather than tweening into it — makes the recoil read instantly and keeps the deck deterministic
	# at rest once the tween finishes (no timing-dependent intermediate the next throw could stack on).
	visual.position = kick
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(visual, "position", _visual_rest, 0.18) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _shaft_x_center() -> float:
	return float(_mine_width * _cell_size) / 2.0


## World-space muzzle: where the predicted arc AND live charges launch from (AC-5.7.1).
## Reads the AUTHORED `Body/Muzzle` marker so the launch point is data (the scene), not a
## code constant — and it is anchored to the platform TARGET (stable; aiming happens at
## rest), offset by the marker's local position. Falls back to half a cell above the target
## if the scene has no marker (headless bare instance).
func muzzle_position() -> Vector2:
	var marker: Node2D = get_node_or_null("Body/Muzzle")
	# AC-5.3.9: the muzzle must be BELOW the platform body so a default downward
	# throw enters the mine instead of resting on the launcher/platform line.
	var offset: Vector2 = marker.position if marker != null else Vector2(0.0, float(_cell_size))
	return platform_target_position() + offset


## Count cleared cells directly beneath the platform target (delegates to the pure
## PlatformLogic). `hp_grid` is {Vector2i(x, row): hp}; missing / <= 0 = cleared.
func cleared_beneath(hp_grid: Dictionary) -> int:
	return PlatformLogic.cleared_beneath(hp_grid, _target_row, _shaft_width, _shaft_left)


## True iff the cleared count beneath the target meets the data-driven threshold.
func should_descend(hp_grid: Dictionary) -> bool:
	return PlatformLogic.should_descend(hp_grid, _target_row, _shaft_width, _threshold, _shaft_left)


## Attempt a descent against the given HP grid. Lowers the target row by the number
## of consecutive cleared rows (capped at `descent_max_steps`), then TWEENS the body
## toward the new target and re-anchors the camera. Returns the number of rows
## descended (0 = no trigger). Emits `descended(new_row)` only when rows > 0.
func try_descend(hp_grid: Dictionary) -> int:
	var steps: int = PlatformLogic.descent_steps(
		hp_grid, _target_row, _shaft_width, _threshold, _max_steps, _shaft_left
	)
	if steps <= 0:
		return 0
	_target_row += steps
	_tween_to_target()
	_reanchor_camera()
	descended.emit(_target_row)
	return steps


## True iff the platform can be manually moved up one row (not already at the top).
func can_move_up() -> bool:
	return _target_row > 0


## True iff the platform can be manually moved down one row (not already at the bottom).
func can_move_down() -> bool:
	var bottom: int = Registry.mine_height_cells(_tables) - 1
	return _target_row < bottom


## Manually move the platform up by one row. Clamps to 0, tweens + re-anchors the
## camera via the same path as auto-descent, and emits `descended(_target_row)`.
## Returns true if the row actually changed.
func move_up() -> bool:
	if not can_move_up():
		return false
	_target_row -= 1
	_tween_to_target()
	_reanchor_camera()
	descended.emit(_target_row)
	return true


## Manually move the platform down by one row. Clamps to the bottom of the mine,
## tweens + re-anchors the camera via the same path as auto-descent, and emits
## `descended(_target_row)`. Returns true if the row actually changed.
func move_down() -> bool:
	var bottom: int = Registry.mine_height_cells(_tables) - 1
	if _target_row >= bottom:
		return false
	_target_row = mini(_target_row + 1, bottom)
	_tween_to_target()
	_reanchor_camera()
	descended.emit(_target_row)
	return true


## Tween the platform body toward the current target (AC-5.7.2: animate, never snap).
func _tween_to_target() -> void:
	if _body == null:
		return
	if _descent_tween != null and _descent_tween.is_valid():
		_descent_tween.kill()
	_descent_tween = create_tween()
	_descent_tween.tween_property(
		_body, "position", platform_target_position(), _tween_seconds
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Re-point the camera at the (new) platform target. The smoothing eases the actual
## camera there; we set the *target* once per descent, NOT every frame (AC-5.7.3).
func _reanchor_camera() -> void:
	if _camera == null:
		return
	_camera.zoom = Vector2(_camera_zoom, _camera_zoom)
	_camera.position = camera_target_position()

func _configure_body_geometry() -> void:
	var width_px: float = float(_shaft_width * _cell_size)
	var height_px: float = maxf(6.0, float(_cell_size) * 0.5)
	var shape_node := get_node_or_null("Body/CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		shape_node.position = Vector2(0.0, -height_px * 0.5)
		var rect := shape_node.shape as RectangleShape2D
		if rect == null:
			rect = RectangleShape2D.new()
			shape_node.shape = rect
		rect.size = Vector2(width_px, height_px)
	var visual := get_node_or_null("Body/Visual") as Node2D
	if visual is Polygon2D:
		(visual as Polygon2D).polygon = PackedVector2Array([
			Vector2(-width_px * 0.5, -height_px),
			Vector2(width_px * 0.5, -height_px),
			Vector2(width_px * 0.5, 0.0),
			Vector2(-width_px * 0.5, 0.0),
		])
	elif visual is Sprite2D:
		# Texture is authored at 144 px wide; scale to fit the dynamic platform width.
		var sprite := visual as Sprite2D
		var tex_size: Vector2 = sprite.texture.get_size() if sprite.texture != null else Vector2(144.0, 24.0)
		var scale_x: float = width_px / tex_size.x
		sprite.scale = Vector2(scale_x, scale_x)
		sprite.position = Vector2(0.0, -height_px * 0.5)
	var edge := get_node_or_null("Body/VisualEdge") as Polygon2D
	if edge != null:
		edge.polygon = PackedVector2Array([
			Vector2(-width_px * 0.5, -height_px),
			Vector2(width_px * 0.5, -height_px),
			Vector2(width_px * 0.5, -height_px + 2.0),
			Vector2(-width_px * 0.5, -height_px + 2.0),
		])
	var marker := get_node_or_null("Body/Muzzle") as Marker2D
	if marker != null:
		# AC-5.3.9: launch point is below the platform deck, not above it.
		marker.position = Vector2(0.0, float(_cell_size))

var shaft_left_cell: int:
	get:
		return _shaft_left


## Current camera-shake trauma in [0,1] (read-only). Exposed so the shake decay-to-zero
## invariant is assertable headless without reaching into the camera every frame.
var trauma: float:
	get:
		return _trauma


## The live camera offset (read-only convenience for tests/callers). By contract the shake
## writes ONLY this and zoom — never position/target — so AC-5.7.3 stays green.
func camera_offset() -> Vector2:
	return _camera.offset if _camera != null else Vector2.ZERO
