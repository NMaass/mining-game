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
## A full-screen dimmer sibling (authored in mine.tscn) so the world dims behind the panel.
## Optional — a bare DigEndPanel instance (unit harness) has no sibling, so guard for null.
@onready var _backdrop: Control = get_node_or_null("../DigEndBackdrop")

## Data tables (for the scale-in/out durations). Set via configure(); empty → code-default fallbacks.
var _tables: Dictionary = {}
## Live tween handle so a re-show kills a prior in/out tween (no compounding scale / stuck alpha).
var _tween: Tween = null


func _ready() -> void:
	visible = false
	if _backdrop != null:
		_backdrop.visible = false
	if _buy_button != null and not _buy_button.pressed.is_connected(_on_buy):
		_buy_button.pressed.connect(_on_buy)
	if _next_button != null and not _next_button.pressed.is_connected(_on_next):
		_next_button.pressed.connect(_on_next)


## Provide the data tables (the scale-in/out durations are /data tunables). Idempotent.
func configure(tables: Dictionary) -> void:
	_tables = tables


func _in_seconds() -> float:
	if _tables.is_empty():
		return 0.22
	return Registry.ui_panel_in_seconds(_tables)


func _on_buy() -> void:
	buy_upgrade_pressed.emit()


func _on_next() -> void:
	next_dig_pressed.emit()


## Show the dig-end panel with the relic/prestige summary (AC-5.8.4). `banked` is the
## prestige this dig added; `total` is the running banked total; `power_mult` is the
## current blast-intensity multiplier from purchased upgrades (the "power gained").
##
## v0.5 arcade pass: the panel POPS IN — scale 0.85→1.0 + modulate.a 0→1 (TRANS_BACK overshoot)
## over ui_panel_in_seconds, with a sibling backdrop dimming the world. `visible` is set TRUE
## SYNCHRONOUSLY at the start so the smoke test (reads panel.visible right after) stays green; the
## animation only drives transform/alpha. At motion ~0 (reduced motion) it snaps with no tween.
func show_dig_end(banked: int, total: int, power_mult: float, motion: float = 1.0) -> void:
	if _title != null:
		_title.text = "Relic recovered!"
	if _banked != null:
		_banked.text = "Prestige banked: +%d  (total %d)" % [banked, total]
	if _power != null:
		_power.text = "Blast power: x%.2f" % power_mult
	visible = true
	_animate_in(motion)


## Pop the panel (+ its backdrop) into view. Pure presentation: visible is already true.
func _animate_in(motion: float) -> void:
	if _backdrop != null:
		_backdrop.visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	# Reduced-motion / headless: snap to the resting state, no tween.
	if motion <= 0.01:
		pivot_offset = size * 0.5
		scale = Vector2.ONE
		modulate = Color(1, 1, 1, 1)
		if _backdrop != null:
			_backdrop.modulate = Color(1, 1, 1, 1)
		return
	pivot_offset = size * 0.5
	scale = Vector2(0.85, 0.85)
	modulate = Color(1, 1, 1, 0)
	if _backdrop != null:
		_backdrop.modulate = Color(1, 1, 1, 0)
	var seconds: float = _in_seconds()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "scale", Vector2.ONE, seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _backdrop != null:
		_tween.tween_property(_backdrop, "modulate", Color(1, 1, 1, 1), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Refresh the power readout after a purchase (so the gain is visible before the next
## dig). `total` is the remaining prestige; `power_mult` the new multiplier.
func refresh_power(total: int, power_mult: float) -> void:
	if _banked != null:
		_banked.text = "Prestige available: %d" % total
	if _power != null:
		_power.text = "Blast power: x%.2f" % power_mult


## Hide the panel (e.g. when the next dig begins). Synchronous (the next dig must read it hidden);
## kills any in-flight pop-in tween and resets the transform so a re-show starts clean.
func hide_panel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	scale = Vector2.ONE
	modulate = Color(1, 1, 1, 1)
	if _backdrop != null:
		_backdrop.visible = false
