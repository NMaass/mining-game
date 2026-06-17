class_name ExplosionFx
extends Node2D
## Layered detonation VFX (v0.5 arcade pass, AC-5.9.1). A Node2D root composing three
## web-safe layers, all of which write COLOR on the GL Compatibility / WebGL2 build:
##   - Spark:  the existing GPUParticles2D spray (ParticleProcessMaterial color_ramp →
##             the engine writes COLOR; the web-safe source — never a bare process shader).
##   - Flash:  a soft radial Sprite2D on an ADDITIVE CanvasItemMaterial (BLEND_MODE_ADD writes
##             COLOR), scaled up + faded over vfx.flash_seconds — the white-hot pop core.
##   - Ring:   a hollow-ring Sprite2D, also additive, expanded outward + faded over
##             vfx.ring_seconds — the shockwave that reads "stronger charge = bigger ring".
##
## Scale-by-blast: the flash + ring max scale grow with the blast radius (so a 4-radius blast
## reads visibly stronger than the free 1-radius tap), and BOTH are multiplied by motion
## intensity so motion=0 disables them (AC-5.10.1 / AC-5.10.4 reduced-motion). The spark amount
## is set by the caller via the existing explosion_particle_count seam.
##
## The node is one-shot + ttl-freed by the caller (mine.gd), so it leaves 0 orphans.

@onready var _spark: GPUParticles2D = get_node_or_null("Spark")
@onready var _flash: Sprite2D = get_node_or_null("Flash")
@onready var _ring: Sprite2D = get_node_or_null("Ring")

## Drive the flash + ring tweens for a blast of `radius` cells at `motion` intensity [0,1],
## reading magnitudes from the /data vfx table. At motion 0 the flash/ring are hidden entirely
## (the spark spray still plays at its reduced-motion floor, set by the caller).
func play(tables: Dictionary, radius: int, motion: float) -> void:
	var m: float = clampf(motion, 0.0, 1.0)
	var r: float = float(maxi(radius, 1))
	_play_flash(tables, r, m)
	_play_ring(tables, r, m)


func _play_flash(tables: Dictionary, r: float, m: float) -> void:
	if _flash == null:
		return
	if m <= 0.0:
		_flash.visible = false
		return
	var seconds: float = Registry.vfx_f(tables, "flash_seconds", 0.06)
	var per_radius: float = Registry.vfx_f(tables, "flash_scale_per_radius", 0.6)
	var target_scale: float = maxf(0.05, per_radius * r * m)
	_flash.visible = true
	_flash.scale = Vector2(target_scale * 0.35, target_scale * 0.35)
	_flash.modulate.a = 1.0
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_flash, "scale", Vector2(target_scale, target_scale), seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_flash, "modulate:a", 0.0, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_ring(tables: Dictionary, r: float, m: float) -> void:
	if _ring == null:
		return
	if m <= 0.0:
		_ring.visible = false
		return
	var seconds: float = Registry.vfx_f(tables, "ring_seconds", 0.18)
	var per_radius: float = Registry.vfx_f(tables, "ring_scale_per_radius", 1.2)
	var target_scale: float = maxf(0.05, per_radius * r * m)
	_ring.visible = true
	_ring.scale = Vector2(0.05, 0.05)
	_ring.modulate.a = 1.0
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_ring, "scale", Vector2(target_scale, target_scale), seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_ring, "modulate:a", 0.0, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
