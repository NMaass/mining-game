class_name ChargeIcon
extends RefCounted
## Runtime placeholder pixel icons for charge slots and crate reveals.
##
## The icons are generated from the project palette at runtime instead of imported as binary
## art. That keeps the placeholders license-clean and guarantees they are quantized to
## data/palette.json (AC-5.10.3). Shape differs by charge id, so charge identity never rides
## color alone (AC-5.10.2).

const DEFAULT_SIZE := 64

static var _cache: Dictionary = {}

static func texture_for(tables: Dictionary, charge_id: String, size: int = DEFAULT_SIZE) -> Texture2D:
	var key: String = "%s:%d" % [charge_id, size]
	if _cache.has(key):
		return _cache[key]
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_charge(img, tables, charge_id)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func crate_texture(tables: Dictionary, pack_id: String, size: int = DEFAULT_SIZE) -> Texture2D:
	var key: String = "crate:%s:%d" % [pack_id, size]
	if _cache.has(key):
		return _cache[key]
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_crate(img, tables, pack_id)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func _draw_charge(img: Image, tables: Dictionary, charge_id: String) -> void:
	var size: int = img.get_width()
	var outline: Color = _pal(tables, 0, Color(0.05, 0.06, 0.08))
	var metal: Color = _pal(tables, 5, Color(0.78, 0.82, 0.85))
	var shadow: Color = _pal(tables, 6, Color(0.35, 0.42, 0.48))
	var warm: Color = _pal(tables, 9, Color(0.88, 0.32, 0.08))
	var yellow: Color = _pal(tables, 11, Color(1.0, 0.88, 0.34))
	var green: Color = _pal(tables, 4, Color(0.30, 0.58, 0.52))
	var blue: Color = _pal(tables, 8, Color(0.26, 0.62, 0.82))
	var purple: Color = _pal(tables, 7, Color(0.55, 0.44, 0.75))

	match charge_id:
		"free_charge":
			_rect(img, 17, 23, 30, 22, outline)
			_rect(img, 20, 20, 24, 24, shadow)
			_rect(img, 23, 17, 16, 18, metal)
			_rect(img, 28, 25, 8, 12, warm)
			_rect(img, 21, 42, 22, 4, outline)
		"dynamite":
			_rect(img, 23, 14, 18, 34, outline)
			_rect(img, 25, 16, 14, 30, warm)
			_rect(img, 28, 16, 5, 30, yellow)
			_rect(img, 21, 22, 22, 3, outline)
			_rect(img, 21, 37, 22, 3, outline)
			_line(img, 38, 14, 48, 7, yellow)
			_rect(img, 48, 5, 4, 4, warm)
		"charge_sticky":
			_rect(img, 16, 20, 32, 26, outline)
			_rect(img, 19, 23, 26, 20, green)
			_rect(img, 27, 14, 10, 40, outline)
			_rect(img, 30, 16, 4, 36, metal)
			_rect(img, 20, 30, 24, 5, yellow)
			_rect(img, 48, 26, 4, 14, outline)
		"heavy_bomb":
			_circle(img, 32, 34, 20, outline)
			_circle(img, 32, 34, 16, shadow)
			_rect(img, 27, 10, 11, 12, outline)
			_rect(img, 30, 7, 5, 8, yellow)
			_rect(img, 22, 24, 8, 6, metal)
		"cluster_bomb":
			for p in [Vector2i(24, 33), Vector2i(38, 33), Vector2i(31, 21)]:
				_circle(img, p.x, p.y, 11, outline)
				_circle(img, p.x, p.y, 8, warm)
			_rect(img, 27, 38, 10, 10, outline)
			_rect(img, 29, 40, 6, 6, yellow)
		"drill_charge":
			_rect(img, 18, 23, 23, 22, outline)
			_rect(img, 21, 26, 18, 16, blue)
			_triangle(img, Vector2i(39, 18), Vector2i(53, 34), Vector2i(39, 50), outline)
			_triangle(img, Vector2i(41, 23), Vector2i(49, 34), Vector2i(41, 45), metal)
			_rect(img, 16, 28, 6, 12, yellow)
		"pile_driver":
			_rect(img, 23, 10, 18, 34, outline)
			_rect(img, 26, 13, 12, 28, purple)
			_triangle(img, Vector2i(18, 43), Vector2i(46, 43), Vector2i(32, 57), outline)
			_triangle(img, Vector2i(23, 45), Vector2i(41, 45), Vector2i(32, 53), metal)
			_rect(img, 20, 20, 24, 5, yellow)
		_:
			_rect(img, 18, 18, 28, 28, outline)
			_rect(img, 21, 21, 22, 22, metal)
			_rect(img, 27, 27, 10, 10, warm)

static func _draw_crate(img: Image, tables: Dictionary, pack_id: String) -> void:
	var outline: Color = _pal(tables, 0, Color(0.05, 0.06, 0.08))
	var wood_dark: Color = _pal(tables, 2, Color(0.48, 0.34, 0.19))
	var wood: Color = _pal(tables, 3, Color(0.82, 0.62, 0.38))
	var metal: Color = _pal(tables, 6, Color(0.35, 0.42, 0.48))
	var accent: Color = _pal(tables, 9, Color(0.88, 0.32, 0.08))
	if pack_id == "deep":
		accent = _pal(tables, 4, Color(0.30, 0.58, 0.52))
	elif pack_id == "heavy_crate":
		accent = _pal(tables, 8, Color(0.26, 0.62, 0.82))
	_rect(img, 10, 18, 44, 34, outline)
	_rect(img, 14, 22, 36, 26, wood)
	_rect(img, 14, 22, 36, 6, wood_dark)
	_rect(img, 14, 42, 36, 6, wood_dark)
	_rect(img, 28, 18, 8, 34, metal)
	_rect(img, 10, 30, 44, 6, metal)
	_rect(img, 28, 30, 8, 6, accent)
	_line(img, 16, 24, 48, 47, outline)
	_line(img, 48, 24, 16, 47, outline)

static func _pal(tables: Dictionary, index: int, fallback: Color) -> Color:
	var pal: Variant = tables.get("palette", {})
	if pal is Dictionary:
		var colors: Variant = (pal as Dictionary).get("colors")
		if colors is Array and index >= 0 and index < (colors as Array).size():
			var hex: String = str((colors as Array)[index])
			if Color.html_is_valid(hex):
				return Color.html(hex)
	return fallback

static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(maxi(0, y), mini(img.get_height(), y + h)):
		for xx in range(maxi(0, x), mini(img.get_width(), x + w)):
			img.set_pixel(xx, yy, c)

static func _circle(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	var r2: int = r * r
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				if Vector2i(x - cx, y - cy).length_squared() <= r2:
					img.set_pixel(x, y, c)

static func _triangle(img: Image, a: Vector2i, b: Vector2i, c: Vector2i, col: Color) -> void:
	var min_x: int = mini(a.x, mini(b.x, c.x))
	var max_x: int = maxi(a.x, maxi(b.x, c.x))
	var min_y: int = mini(a.y, mini(b.y, c.y))
	var max_y: int = maxi(a.y, maxi(b.y, c.y))
	var denom: float = float((b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y))
	if is_zero_approx(denom):
		return
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var w1: float = float((b.y - c.y) * (x - c.x) + (c.x - b.x) * (y - c.y)) / denom
			var w2: float = float((c.y - a.y) * (x - c.x) + (a.x - c.x) * (y - c.y)) / denom
			var w3: float = 1.0 - w1 - w2
			if w1 >= 0.0 and w2 >= 0.0 and w3 >= 0.0 and x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)

static func _line(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = absi(x1 - x0)
	var sx: int = 1 if x0 < x1 else -1
	var dy: int = -absi(y1 - y0)
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var x: int = x0
	var y: int = y0
	while true:
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			img.set_pixel(x, y, c)
		if x == x1 and y == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy
