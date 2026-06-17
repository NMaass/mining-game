class_name ValuePopup
extends Node2D
## Floating "+$N" value popup (v0.5 arcade pass). Spawned at a credited ore cell's world
## center when a blast clears it for value; rises by vfx.popup_rise_px and fades to alpha 0
## over vfx.popup_seconds (TRANS_QUAD / EASE_OUT), then frees itself via the caller's ttl
## timer. Cosmetic + capped (vfx.popup_max_active) + ttl-freed → 0 orphans at exit.
##
## z_index sits above the light mask so the reward reads even outside the headlamp bubble.
## The label color is tinted per-ore by the caller (BlockArt.block_color) so the popup is
## material-specific (copper vs gold). $0 dirt breaks never spawn a popup (caller-gated).

@onready var _label: Label = get_node_or_null("Label")

## Configure the popup text + color, then run the rise+fade tween. Reads magnitudes from /data.
func play(tables: Dictionary, amount: int, color: Color) -> void:
	if _label != null:
		_label.text = "+$%d" % amount
		_label.modulate = color
	var rise: float = Registry.vfx_f(tables, "popup_rise_px", 24.0)
	var seconds: float = Registry.vfx_f(tables, "popup_seconds", 0.6)
	var start_y: float = position.y
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", start_y - rise, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
