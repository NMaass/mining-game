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
	_configure_body_geometry()
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


## Apply a short screenshake offset to the camera. Intensity is scaled by the
## motion-intensity accessibility setting by the caller.
func shake(intensity_px: float) -> void:
	if _camera == null or intensity_px <= 0.0:
		return
	var tween := create_tween()
	var duration := 0.18
	var half := intensity_px * 0.5
	var base := _camera.offset
	tween.tween_property(_camera, "offset", base + Vector2(randf_range(-half, half), randf_range(-half, half)), duration * 0.5)
	tween.tween_property(_camera, "offset", base, duration * 0.5)


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
