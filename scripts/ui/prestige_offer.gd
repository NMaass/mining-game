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

@onready var _panel: PanelContainer = get_node_or_null("Panel")
@onready var _accept_button: Button = get_node_or_null("Panel/Box/AcceptButton")
@onready var _decline_button: Button = get_node_or_null("Panel/Box/DeclineButton")


func _ready() -> void:
	visible = false
	_connect_once()


func _connect_once() -> void:
	if _accept_button != null and not _accept_button.pressed.is_connected(_on_accept):
		_accept_button.pressed.connect(_on_accept)
	if _decline_button != null and not _decline_button.pressed.is_connected(_on_decline):
		_decline_button.pressed.connect(_on_decline)


## Show the prestige offer and pause the game tree. The overlay itself keeps running.
func show_offer() -> void:
	visible = true
	var tree := get_tree()
	if tree != null:
		tree.paused = true


## Hide the offer and unpause the game tree.
func hide_offer() -> void:
	visible = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false


func _on_accept() -> void:
	hide_offer()
	accepted.emit()


func _on_decline() -> void:
	hide_offer()
	declined.emit()
