class_name ShaftGuide
extends Node2D
## Draws the centered descent corridor marker over the wide mine.
## The fill is intentionally subtle: it hints "clear this width to descend" without
## turning the corridor into a separate terrain type.

var _cell_size: int = 16
var _mine_height: int = 0
var _shaft_left: int = 0
var _shaft_width: int = 9

func configure(tables: Dictionary) -> void:
	_cell_size = Registry.block_pixel_size(tables)
	_mine_height = Registry.mine_height_cells(tables)
	_shaft_left = Registry.shaft_left_cell(tables)
	_shaft_width = Registry.shaft_width(tables)
	queue_redraw()

func _draw() -> void:
	if _cell_size <= 0 or _mine_height <= 0 or _shaft_width <= 0:
		return
	var left: float = float(_shaft_left * _cell_size)
	var width: float = float(_shaft_width * _cell_size)
	var height: float = float(_mine_height * _cell_size)
	draw_rect(Rect2(left, 0.0, width, height), Color(0.82, 0.70, 0.46, 0.08), true)
	_draw_dotted_line(left, height)
	_draw_dotted_line(left + width, height)

func _draw_dotted_line(x: float, height: float) -> void:
	var step: float = float(_cell_size)
	var radius: float = maxf(1.5, float(_cell_size) * 0.12)
	var color := Color(0.94, 0.80, 0.48, 0.50)
	var y: float = float(_cell_size) * 0.5
	while y < height:
		draw_circle(Vector2(x, y), radius, color)
		y += step
