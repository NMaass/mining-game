extends GdUnitTestSuite
## U5 — ThrowParams: pure data extraction from explosive registry.
## ACs: AC-5.3.3, AC-5.4.1, AC-5.4.2.

var _tables: Dictionary

func before() -> void:
	_tables = _load_real_tables()

func _load_real_tables() -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open("res://data/")
	assert_object(dir).is_not_null()
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open("res://data/" + file_name, FileAccess.READ)
		var json := JSON.new()
		assert_int(json.parse(f.get_as_text())).is_equal(OK)
		out[file_name.get_basename()] = json.data
	return out

# ── ThrowParams extraction (AC-5.4.1) ───────────────────────────────────

func test_dynamite_params() -> void:
	# AC-5.4.1: explosive resource shape — dynamite has correct params.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	assert_str(p.explosive_id).is_equal("dynamite")
	assert_float(p.mass).is_equal_approx(1.0, 0.01)
	assert_float(p.bounce).is_equal_approx(0.35, 0.01)
	assert_float(p.friction).is_equal_approx(0.6, 0.01)
	assert_float(p.base_impulse).is_equal_approx(520.0, 0.01)
	assert_str(p.detonation_mode).is_equal("fuse_seconds")
	assert_float(p.fuse_seconds).is_equal_approx(1.2, 0.01)
	assert_bool(p.sticky).is_false()
	assert_int(p.blast_radius_cells).is_equal(2)
	assert_int(p.blast_intensity).is_equal(80)

func test_sticky_charge_params() -> void:
	# AC-5.4.2: sticky charge has on_rest + sticky flag.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "charge_sticky")
	assert_str(p.detonation_mode).is_equal("on_rest")
	assert_bool(p.sticky).is_true()
	assert_float(p.base_impulse).is_equal_approx(460.0, 0.01)

func test_heavy_bomb_params() -> void:
	# AC-5.4.2: heavy bomb detonates on_first_impact.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "heavy_bomb")
	assert_str(p.detonation_mode).is_equal("on_first_impact")
	assert_int(p.blast_radius_cells).is_equal(3)
	assert_int(p.blast_intensity).is_equal(170)
	assert_float(p.mass).is_equal_approx(1.6, 0.01)

func test_unknown_explosive_defaults() -> void:
	# Unknown explosive should return safe defaults.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "nonexistent")
	assert_float(p.mass).is_equal_approx(1.0, 0.01)
	assert_str(p.detonation_mode).is_equal("fuse_seconds")

# ── to_explosive_dict ────────────────────────────────────────────────────

func test_to_explosive_dict() -> void:
	# to_explosive_dict returns the blast params for Blast.resolve_explosive().
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var d: Dictionary = p.to_explosive_dict()
	assert_int(int(d["blast_radius_cells"])).is_equal(2)
	assert_int(int(d["blast_intensity"])).is_equal(80)
	assert_int((d["blast_falloff"] as Array).size()).is_equal(3)

# ── impulse_at_angle (AC-5.3.3) ──────────────────────────────────────────

func test_impulse_straight_down() -> void:
	# AC-5.3.3: impulse at angle 0 = straight down.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var impulse: Vector2 = p.impulse_at_angle(0.0)
	# Straight down: x ≈ 0, y = base_impulse.
	assert_float(impulse.x).is_equal_approx(0.0, 0.1)
	assert_float(impulse.y).is_equal_approx(520.0, 0.1)

func test_impulse_angled() -> void:
	# Impulse at an angle should have both x and y components.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var angle: float = PI / 4.0  # 45 degrees right
	var impulse: Vector2 = p.impulse_at_angle(angle)
	assert_float(impulse.x).is_greater(0.0)
	assert_float(impulse.y).is_greater(0.0)
	assert_float(impulse.length()).is_equal_approx(520.0, 0.1)

# ── initial_arc preview (v0.4: pre-first-bounce only) ──────────────────────
# v0.3's "preview == actual" / multi-step determinism test was DELETED
# (REMOVED AC-5.3.4). The preview is now an initial-arc hint that stops at the
# first predicted surface contact (AC-5.3.1).

func test_initial_arc_starts_at_muzzle() -> void:
	# AC-5.3.1: the arc originates at the fixed muzzle (spawn) position.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var spawn := Vector2(100.0, 50.0)
	var path: PackedVector2Array = p.initial_arc(spawn, 0.0)
	assert_int(path.size()).is_greater(0)
	assert_float(path[0].x).is_equal_approx(spawn.x, 0.001)
	assert_float(path[0].y).is_equal_approx(spawn.y, 0.001)

func test_initial_arc_moves_in_launch_direction() -> void:
	# Angle 0 = straight down → y increases as the arc advances (no surface test).
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var spawn := Vector2(200.0, 100.0)
	var path: PackedVector2Array = p.initial_arc(spawn, 0.0, Callable(), 30)
	assert_float(path[path.size() - 1].y).is_greater(spawn.y)

func test_initial_arc_stops_at_first_bounce() -> void:
	# AC-5.3.1: the preview ends at/just past the FIRST solid cell it would enter,
	# not a full multi-bounce projection.
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var bps: int = Registry.block_pixel_size(_tables)
	var spawn := Vector2(float(bps) * 3.5, 0.0)  # muzzle in column 3, row 0
	# Solid only at row 5 (and below) — the arc thrown straight down must stop
	# the first time it enters row 5, never reaching the deeper solid rows.
	var is_solid := func(cell: Vector2i) -> bool:
		return cell.y >= 5
	var full_steps: int = 240
	var path: PackedVector2Array = p.initial_arc(spawn, 0.0, is_solid, full_steps, bps)
	# It stopped early (well before the step cap → not a full projection).
	assert_int(path.size()).is_less(full_steps + 1)
	# The last sampled point is in (or just past) the first solid row, and no
	# earlier sample is solid (single bounce, not multi).
	var last_cell: Vector2i = ThrowParams.cell_at(path[path.size() - 1], bps)
	assert_int(last_cell.y).is_greater_equal(5)
	for i in range(path.size() - 1):
		assert_bool(is_solid.call(ThrowParams.cell_at(path[i], bps))).is_false()

func test_initial_arc_open_when_no_surface_hit() -> void:
	# With no solid cell reachable, the arc runs the full sample (open preview).
	var p: ThrowParams = ThrowParams.from_explosive(_tables, "dynamite")
	var never_solid := func(_cell: Vector2i) -> bool:
		return false
	var path: PackedVector2Array = p.initial_arc(Vector2.ZERO, 0.0, never_solid, 20)
	assert_int(path.size()).is_equal(21)  # spawn + 20 steps

# ── cell_at: floored pixel→cell conversion (v0.4 bug fix) ───────────────────

func test_cell_at_floors_negative_x() -> void:
	# AC-5.4.1 plumbing: int() truncation merged -10px and +10px into column 0.
	# floori must map a left-of-origin pixel to a NEGATIVE cell.
	var bps := 64
	assert_int(ThrowParams.cell_at(Vector2(-10.0, 5.0), bps).x).is_equal(-1)
	assert_int(ThrowParams.cell_at(Vector2(10.0, 5.0), bps).x).is_equal(0)
	# A full block to the left is cell -1; one more pixel left is cell -2.
	assert_int(ThrowParams.cell_at(Vector2(-64.0, 0.0), bps).x).is_equal(-1)
	assert_int(ThrowParams.cell_at(Vector2(-65.0, 0.0), bps).x).is_equal(-2)
