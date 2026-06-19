class_name PrestigeOffer
extends CanvasLayer
## Modal prestige-offer overlay (AC-5.6.2). When the relic block breaks, the dig pauses and this
## overlay asks the player to "Prestige Now" (bank +1 prestige point and end the dig) or
## "Keep Digging" (decline and resume clearing the bounded mine). The overlay subtree runs with
## process_mode = ALWAYS (set in the scene) so its buttons stay interactive while the rest of the
## tree is paused.
##
## It owns no game state — the Mine controller listens to `accepted` / `declined` and performs the
## bank / end-dig / resume actions. Headless-safe (get_node_or_null lookups).
##
## ACs: AC-5.6.2 (prestige offer on relic break; accept banks +1 point and ends dig; decline resumes
##      play).

## Emitted when the player presses "Prestige Now".
signal accepted
## Emitted when the player presses "Keep Digging".
signal declined

const PIXEL_UI_SCRIPT := preload("res://scripts/ui/pixel_ui.gd")

@onready var _panel: PanelContainer = get_node_or_null("Panel")
@onready var _backdrop: Control = get_node_or_null("Backdrop")
@onready var _accept_button: Button = get_node_or_null("Panel/Box/AcceptButton")
@onready var _decline_button: Button = get_node_or_null("Panel/Box/DeclineButton")

## Data tables (for the scale-in duration). Set via configure(); empty → code-default fallback.
var _tables: Dictionary = {}
## Live tween handle so a re-show kills a prior pop-in (no compounding scale / stuck alpha).
var _tween: Tween = null
var _motion: float = 1.0


func _ready() -> void:
	visible = false
	_connect_once()
	PIXEL_UI_SCRIPT.apply_panel(_panel)
	PIXEL_UI_SCRIPT.apply_button(_accept_button, "primary", 20)
	PIXEL_UI_SCRIPT.apply_button(_decline_button, "secondary", 20)
	PIXEL_UI_SCRIPT.bind_button_feel(_accept_button, Callable(self, "_motion_value"))
	PIXEL_UI_SCRIPT.bind_button_feel(_decline_button, Callable(self, "_motion_value"))


## Provide the data tables (the scale-in duration is a /data tunable). Idempotent.
func configure(tables: Dictionary) -> void:
	_tables = tables


func _in_seconds() -> float:
	if _tables.is_empty():
		return 0.22
	return Registry.ui_panel_in_seconds(_tables)


func _connect_once() -> void:
	if _accept_button != null and not _accept_button.pressed.is_connected(_on_accept):
		_accept_button.pressed.connect(_on_accept)
	if _decline_button != null and not _decline_button.pressed.is_connected(_on_decline):
		_decline_button.pressed.connect(_on_decline)


## Show the prestige offer and pause the game tree. The overlay itself keeps running (process_mode
## = ALWAYS), so the pop-in tween advances while the rest of the tree is paused.
##
## v0.5 arcade pass: the Panel POPS IN (scale 0.85→1.0 + alpha 0→1, TRANS_BACK) over
## ui_panel_in_seconds, with a dimmed backdrop. `visible` is set TRUE SYNCHRONOUSLY first so the
## smoke test reading offer.visible right after stays green. At motion ~0 it snaps (no tween).
func show_offer(motion: float = 1.0) -> void:
	_motion = clampf(motion, 0.0, 1.0)
	visible = true
	var tree := get_tree()
	if tree != null:
		tree.paused = true
	Audio.notify_user_gesture()
	Audio.play("modal_open")
	_animate_in(motion)


## Hide the offer and unpause the game tree. SYNCHRONOUS (the smoke test reads offer.visible ==
## false immediately after accept/decline) — no out-tween; we snap hidden and reset the transform.
func hide_offer() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	if _panel != null:
		_panel.scale = Vector2.ONE
		_panel.modulate = Color(1, 1, 1, 1)
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	Audio.notify_user_gesture()
	Audio.play("modal_close")


## Pop the Panel into view (the backdrop fades in alongside). Pure presentation; visible is true.
func _animate_in(motion: float) -> void:
	if _panel == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	if motion <= 0.01:
		_panel.scale = Vector2.ONE
		_panel.modulate = Color(1, 1, 1, 1)
		if _backdrop != null:
			_backdrop.modulate = Color(1, 1, 1, 1)
		return
	_panel.scale = Vector2(0.85, 0.85)
	_panel.modulate = Color(1, 1, 1, 0)
	if _backdrop != null:
		_backdrop.modulate = Color(1, 1, 1, 0)
	var seconds: float = _in_seconds()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2.ONE, seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate", Color(1, 1, 1, 1), seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _backdrop != null:
		_tween.tween_property(_backdrop, "modulate", Color(1, 1, 1, 1), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_accept() -> void:
	hide_offer()
	accepted.emit()


func _on_decline() -> void:
	hide_offer()
	declined.emit()


func _motion_value() -> float:
	return _motion
