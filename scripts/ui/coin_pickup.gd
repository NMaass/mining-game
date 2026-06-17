class_name CoinPickup
extends Sprite2D
## Flying coin (v0.5 money juice). Spawned at a credited ore cell's world center when a blast clears
## it for value; pops outward/up (ease-out-back over coin_pop_seconds) then flies to the HUD wallet
## icon (over coin_fly_seconds, arcing via coin_arc_height_px) and, on arrival, pulses the money HUD.
##
## A COSMETIC tween-driven Sprite2D — NOT a physics body. The "pooled rigid bodies only for
## collectibles" rule is about the settled-rubble collectibles; a fly-to-wallet reward coin is a
## scripted UI affordance, so a tween is the correct (web-cheap, deterministic) tool here. Capped at
## coin_max_active by the caller and ttl-freed via the caller's timer → 0 orphans at exit.
##
## The coin lives in the Mine's WORLD space (same space as the explosion/popup fx). The wallet target
## is a HUD screen position; the caller projects it to world space once at spawn (the camera barely
## moves over the sub-second flight). Tinted copper vs gold by the caller (BlockArt.block_color).

## Emitted when the coin reaches the wallet (so the controller can pop the money HUD). The coin frees
## itself shortly after via the caller's ttl timer.
signal arrived

var _arrived: bool = false


## Configure + animate the coin: pop up from `start_world` then fly to `target_world`, arcing by
## `arc_height` px, tinted `color`. Durations from /data via the caller. Emits `arrived` at the end.
func play(start_world: Vector2, target_world: Vector2, color: Color, pop_seconds: float, fly_seconds: float, arc_height: float) -> void:
	global_position = start_world
	modulate = color
	# 1) Pop: a quick scale-up + small outward hop so the coin reads as ejected from the cell.
	var pop_apex: Vector2 = start_world + Vector2(0.0, -arc_height * 0.5)
	scale = Vector2(0.6, 0.6)
	var pop := create_tween().set_parallel(true)
	pop.tween_property(self, "global_position", pop_apex, pop_seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(self, "scale", Vector2(1.2, 1.2), pop_seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 2) Fly: a single quad ease-in toward the wallet, lifting through a mid arc so the path curves.
	pop.chain()
	var mid: Vector2 = start_world.lerp(target_world, 0.5) + Vector2(0.0, -arc_height)
	var fly := create_tween()
	fly.tween_property(self, "global_position", mid, fly_seconds * 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fly.chain().tween_property(self, "global_position", target_world, fly_seconds * 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fly.parallel().tween_property(self, "scale", Vector2(0.5, 0.5), fly_seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fly.finished.connect(_on_flight_finished)


func _on_flight_finished() -> void:
	if _arrived:
		return
	_arrived = true
	arrived.emit()
