class_name ShaftSupports
extends Node2D
## Visual mine-shaft support beams that replace the dotted-line guide. Supports are
## anchored at the left/right edges of the active shaft width and extend downward one
## full layer at a time as layers are cleared. They gate platform descent: the platform
## may not move below the deepest supported row.
##
## The visual is intentionally a simple placeholder: two vertical beams with periodic
## cross-braces, drawn via _draw() and animated by tweening a float row value so the
## extension reads as a mechanical "screw-jack" advance.

## Emitted when the support animation finishes and the supports have reached `row`.
signal support_reached(row: int)

var _tables: Dictionary = {}
var _cell_size: int = 16
var _shaft_left: int = 0
var _shaft_width: int = 9
var _support_row: int = 0
var _draw_row: float = 0.0
var _extend_seconds: float = 0.25
var _tween: Tween = null

## Configure the supports from /data. `shaft_left` and `shaft_width` may be the
## effective (upgrade-modified) values.
func configure(tables: Dictionary, shaft_left: int, shaft_width: int, start_row: int = 0) -> void:
	_tables = tables
	_cell_size = Registry.block_pixel_size(tables)
	_shaft_left = shaft_left
	_shaft_width = shaft_width
	_support_row = start_row
	_draw_row = float(start_row)
	_extend_seconds = Registry.support_extend_seconds(tables)
	queue_redraw()

## The deepest row currently supported (platform may not descend below this).
var support_row: int:
	get:
		return _support_row

## True if the supports are currently animating.
var is_extending: bool:
	get:
		return _tween != null and _tween.is_valid()

## Advance the supports down to `row` (must be >= current support row). Animates the
## visual extension and emits `support_reached(row)` when the tween completes.
func advance_to(row: int) -> bool:
	row = clampi(row, _support_row, Registry.mine_bottom_row(_tables))
	if row <= _support_row:
		return false
	_support_row = row
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_draw_row, _draw_row, float(row), _extend_seconds) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.finished.connect(func() -> void: support_reached.emit(row), CONNECT_ONE_SHOT)
	return true

func _set_draw_row(value: float) -> void:
	_draw_row = value
	queue_redraw()

# How far below the deepest supported row the guide lines extend, in cells. The shaft is
# an infinite/very-deep volume (mine_bottom_row can be a ~1e9 sentinel), so we cap the drawn
# span at the supported depth plus this on-screen buffer — far enough to cover the visible
# region below the platform, finite enough that the dash loop never runs unbounded.
const GUIDE_LOOKAHEAD_ROWS := 80

func _draw() -> void:
	if _cell_size <= 0 or _shaft_width <= 0:
		return
	# Two DOTTED (dashed) vertical guide lines marking the shaft width down the shaft (UNIT
	# TUNE). These are aim/alignment guides, not structural beams — they draw OVER the terrain
	# (high z_index, set in the scene) so the player can always see the shaft edges through
	# cleared and uncleared cells alike. The span tracks the supported depth + a screen buffer,
	# clamped to the real mine bottom for bounded mines.
	var left_x: float = float(_shaft_left * _cell_size)
	var right_x: float = float((_shaft_left + _shaft_width) * _cell_size)
	var bottom_row: int = mini(
		int(ceil(_draw_row)) + GUIDE_LOOKAHEAD_ROWS,
		Registry.mine_bottom_row(_tables) + 1)
	var bottom_y: float = float(maxi(_shaft_width, bottom_row) * _cell_size)
	var color := Color(0.85, 0.87, 0.92, 0.85)
	_draw_dashed_vertical(left_x, bottom_y, color)
	_draw_dashed_vertical(right_x, bottom_y, color)

## Draw a vertical dashed line at `x` from y=0 down to `bottom_y`. Dash and gap lengths
## scale with the cell size so the dotting reads consistently at the configured zoom.
func _draw_dashed_vertical(x: float, bottom_y: float, color: Color) -> void:
	var line_w: float = maxf(2.0, float(_cell_size) * 0.18)
	var dash: float = float(_cell_size) * 0.5
	var gap: float = float(_cell_size) * 0.4
	var y: float = 0.0
	while y < bottom_y:
		var seg_end: float = minf(y + dash, bottom_y)
		draw_line(Vector2(x, y), Vector2(x, seg_end), color, line_w)
		y = seg_end + gap
