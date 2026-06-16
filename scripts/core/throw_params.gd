class_name ThrowParams
extends RefCounted
## Pure data class bundling physics + detonation parameters for a charge throw.
## Extracted from explosive data in the registry. No Node deps; headless-testable.
##
## ACs: AC-5.3.3 (charge is a rigid body), AC-5.4.1 (explosive resource shape),
##       AC-5.4.2 (detonation mode).

var explosive_id: String
var mass: float
var bounce: float
var friction: float
var base_impulse: float
var detonation_mode: String  # "fuse_seconds" | "on_first_impact" | "on_rest"
var fuse_seconds: float
var sticky: bool
var blast_radius_cells: int
var blast_intensity: int
var blast_falloff: Array

## Build ThrowParams from an explosive id via the registry.
static func from_explosive(tables: Dictionary, id: String) -> ThrowParams:
	var data: Dictionary = Registry.explosive(tables, id)
	var p := ThrowParams.new()
	p.explosive_id = id
	p.mass = float(data.get("mass", 1.0))
	p.bounce = float(data.get("bounce", 0.3))
	p.friction = float(data.get("friction", 0.5))
	p.base_impulse = float(data.get("base_impulse", 500.0))
	p.detonation_mode = str(data.get("detonation_mode", "fuse_seconds"))
	p.fuse_seconds = float(data.get("fuse_seconds", 1.0))
	p.sticky = bool(data.get("sticky", false))
	p.blast_radius_cells = int(data.get("blast_radius_cells", 2))
	p.blast_intensity = int(data.get("blast_intensity", 80))
	p.blast_falloff = data.get("blast_falloff", [1.0, 0.6, 0.25])
	return p

## Return the explosive data as a dict for Blast.resolve_explosive().
func to_explosive_dict() -> Dictionary:
	return {
		"blast_radius_cells": blast_radius_cells,
		"blast_intensity": blast_intensity,
		"blast_falloff": blast_falloff,
	}

## Compute the launch impulse vector for a given angle.
func impulse_at_angle(angle: float) -> Vector2:
	return Aim.launch_impulse(angle, base_impulse)

# ── Cell conversion (shared, floored) ─────────────────────────────────────
# Pixel→cell conversion MUST floor, not truncate toward zero. `int()` truncation
# (the v0.3 bug) maps both x = -10px and x = +10px to cell 0 for a 64px block,
# silently merging the left- and right-of-origin columns. `floori` maps -10 → -1.

## Convert a pixel position to integer cell coordinates using flooring division.
## Pure; no Node deps. Used by both the live charge (detonation center) and the
## initial-arc preview so the two agree on which cell a pixel falls in.
static func cell_at(pixel_pos: Vector2, block_pixel_size: int) -> Vector2i:
	return Vector2i(
		floori(pixel_pos.x / float(block_pixel_size)),
		floori(pixel_pos.y / float(block_pixel_size)),
	)

# ── Initial-arc preview (v0.4: pre-first-bounce only) ──────────────────────
# v0.4 drops the "preview == actual" contract (REMOVED AC-5.3.4). The preview is
# a forgiving *initial-arc hint* that stops at the first predicted surface
# contact; post-bounce flight is intentionally unpredicted. This is pure ballistic
# integration (no Rapier), pulled out of the Charge RigidBody so it is
# headless-testable. Gravity/dt come from project settings (data, not magic).

## Default gravity (px/s^2) and step (s), read from project settings when present.
## Falls back to Godot's stock 2D defaults so headless callers without a loaded
## ProjectSettings still get sane values.
static func _preview_gravity() -> float:
	if ProjectSettings.has_setting("physics/2d/default_gravity"):
		return float(ProjectSettings.get_setting("physics/2d/default_gravity"))
	return 980.0

static func _preview_dt() -> float:
	if ProjectSettings.has_setting("physics/common/physics_ticks_per_second"):
		var tps: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second"))
		if tps > 0.0:
			return 1.0 / tps
	return 1.0 / 60.0

## Predict the throw arc from the muzzle up to (and including) the first cell that
## the projectile would enter that `is_solid_cell` reports as solid — i.e. the
## first bounce surface. Returns the sampled positions (PackedVector2Array),
## starting at `spawn_pos`. If no solid cell is hit within `max_steps`, the full
## ballistic sample is returned (open arc).
##
## `is_solid_cell`: Callable(cell: Vector2i) -> bool. Pass an empty Callable to
## get a pure ballistic arc with no surface test (preview before the grid exists).
##
## v0.4 AC-5.3.1: initial throw up to the first bounce only (not multi-bounce).
func initial_arc(
	spawn_pos: Vector2,
	angle: float,
	is_solid_cell: Callable = Callable(),
	max_steps: int = 240,
	block_pixel_size: int = 64,
) -> PackedVector2Array:
	var path := PackedVector2Array()
	var gravity: float = _preview_gravity()
	var dt: float = _preview_dt()
	var vel: Vector2 = impulse_at_angle(angle) / maxf(mass, 0.0001)
	var pos: Vector2 = spawn_pos

	# The muzzle cell is excluded from the surface test so the arc doesn't
	# "bounce" off the block the muzzle is sitting in/above.
	var start_cell: Vector2i = ThrowParams.cell_at(spawn_pos, block_pixel_size)
	path.append(pos)

	for _i in range(max_steps):
		vel.y += gravity * dt
		pos += vel * dt
		path.append(pos)
		if is_solid_cell.is_valid():
			var cell: Vector2i = ThrowParams.cell_at(pos, block_pixel_size)
			if cell != start_cell and bool(is_solid_cell.call(cell)):
				break  # first bounce — stop the preview here

	return path
