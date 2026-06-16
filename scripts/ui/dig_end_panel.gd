class_name DigEndPanel
extends PanelContainer
## The dig-end state (AC-5.8.4): a distinct, explained panel shown when the relic is
## collected. It states the relic was found, the prestige banked, and the power gained,
## and offers two actions: buy the one permanent upgrade (power growth) and start the
## next dig. It owns no game state — the controller pushes the banked/total values in
## and listens to the two action signals. Headless-safe (get_node_or_null lookups).
##
## ACs: AC-5.8.4 (dig-end is a distinct, explained state: relic found, prestige banked,
##      power gained, how to start the next dig), AC-5.6.4 (the upgrade button drives the
##      power-growth purchase that makes the next dig stronger).

## Emitted when the player buys the permanent upgrade from the panel.
signal buy_upgrade_pressed
## Emitted when the player starts the next dig from the panel.
signal next_dig_pressed

@onready var _title: Label = get_node_or_null("Box/Title")
@onready var _banked: Label = get_node_or_null("Box/Banked")
@onready var _power: Label = get_node_or_null("Box/Power")
@onready var _buy_button: Button = get_node_or_null("Box/BuyUpgrade")
@onready var _next_button: Button = get_node_or_null("Box/NextDig")


func _ready() -> void:
	visible = false
	if _buy_button != null and not _buy_button.pressed.is_connected(_on_buy):
		_buy_button.pressed.connect(_on_buy)
	if _next_button != null and not _next_button.pressed.is_connected(_on_next):
		_next_button.pressed.connect(_on_next)


func _on_buy() -> void:
	buy_upgrade_pressed.emit()


func _on_next() -> void:
	next_dig_pressed.emit()


## Show the dig-end panel with the relic/prestige summary (AC-5.8.4). `banked` is the
## prestige this dig added; `total` is the running banked total; `power_mult` is the
## current blast-intensity multiplier from purchased upgrades (the "power gained").
func show_dig_end(banked: int, total: int, power_mult: float) -> void:
	if _title != null:
		_title.text = "Relic recovered!"
	if _banked != null:
		_banked.text = "Prestige banked: +%d  (total %d)" % [banked, total]
	if _power != null:
		_power.text = "Blast power: x%.2f" % power_mult
	visible = true


## Refresh the power readout after a purchase (so the gain is visible before the next
## dig). `total` is the remaining prestige; `power_mult` the new multiplier.
func refresh_power(total: int, power_mult: float) -> void:
	if _banked != null:
		_banked.text = "Prestige available: %d" % total
	if _power != null:
		_power.text = "Blast power: x%.2f" % power_mult


## Hide the panel (e.g. when the next dig begins).
func hide_panel() -> void:
	visible = false
