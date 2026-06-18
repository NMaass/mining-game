class_name MineSelect
extends CanvasLayer
## Dedicated mine-select screen: browse the mines in /data, see each one's stats (hardness,
## ore value, access cost), unlock a money-gated mine (one-time, session-only), and ENTER a mine
## to start a fresh dig in it. The Mine controller owns the economy + mine state; this UI is a thin
## view that emits `unlock_pressed(mine_id)` / `enter_pressed(mine_id)` and reads money + unlock
## state via bound callbacks.
##
## Opening pauses the game tree (process_mode = ALWAYS keeps the buttons live), matching the
## Shop/Settings/PrestigeOffer modals; closing unpauses.

## Emitted when a locked mine's UNLOCK button is pressed (pay its access cost).
signal unlock_pressed(mine_id: String)
## Emitted when an unlocked mine's ENTER button is pressed (start a dig there).
signal enter_pressed(mine_id: String)
## Emitted after the screen closes (whether by ENTER or CLOSE).
signal closed

const PIXEL_FONT := preload("res://art/fonts/PixelifySans.ttf")

@export var primary_button_normal: StyleBoxFlat
@export var primary_button_hover: StyleBoxFlat
@export var secondary_button_normal: StyleBoxFlat
@export var secondary_button_hover: StyleBoxFlat

@onready var _panel: PanelContainer = get_node_or_null("Panel")
@onready var _backdrop: Control = get_node_or_null("Backdrop")
@onready var _entries_container: HFlowContainer = get_node_or_null("Panel/Box/EntriesContainer")
@onready var _close_button: Button = get_node_or_null("Panel/Box/CloseButton")

var _tables: Dictionary = {}
var _get_money: Callable
var _is_unlocked: Callable
var _buttons: Dictionary = {}  # mine_id -> Button
var _tween: Tween = null


func _ready() -> void:
	visible = false
	if _close_button != null and not _close_button.pressed.is_connected(close):
		_close_button.pressed.connect(close)


## Bind the data tables and callbacks: current money, and whether a mine id is unlocked.
func configure(tables: Dictionary, get_money_callback: Callable, is_unlocked_callback: Callable) -> void:
	_tables = tables
	_get_money = get_money_callback
	_is_unlocked = is_unlocked_callback
	_build_entries()


func open(motion: float = 1.0) -> void:
	visible = true
	refresh()
	var tree := get_tree()
	if tree != null:
		tree.paused = true
	_animate_in(motion)


func close() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	visible = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	if _panel != null:
		_panel.scale = Vector2.ONE
		_panel.modulate = Color(1, 1, 1, 1)
	if _backdrop != null:
		_backdrop.modulate = Color(1, 1, 1, 1)
	closed.emit()


## Re-run the button state pass (ENTER vs UNLOCK $cost, affordability) without rebuilding.
func refresh() -> void:
	var money: int = _current_money()
	for mine_id: String in _buttons.keys():
		var btn: Button = _buttons[mine_id]
		var cost: int = Registry.mine_access_cost(_tables, mine_id)
		if _unlocked(mine_id):
			btn.text = "ENTER"
			btn.disabled = false
		else:
			btn.text = "UNLOCK $%d" % cost
			btn.disabled = money < cost


func _current_money() -> int:
	if not _get_money.is_valid():
		return 0
	return _get_money.call() as int


func _unlocked(mine_id: String) -> bool:
	if not _is_unlocked.is_valid():
		return Registry.mine_access_cost(_tables, mine_id) == 0
	return _is_unlocked.call(mine_id) as bool


func _build_entries() -> void:
	if _entries_container == null:
		return
	for child in _entries_container.get_children():
		child.queue_free()
	_buttons.clear()

	for mine_id: String in Registry.mine_ids(_tables):
		var m: Dictionary = Registry.mine(_tables, mine_id)
		if m.is_empty():
			continue
		_entries_container.add_child(_build_mine_entry(mine_id, m))


func _build_mine_entry(mine_id: String, m: Dictionary) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.name = "Mine_%s" % mine_id
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.alignment = BoxContainer.ALIGNMENT_CENTER
	entry.add_theme_constant_override("separation", 6)

	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(72, 72)
	icon.color = Registry.mine_tile_tint(_tables, mine_id) * Color(0.55, 0.45, 0.32)
	entry.add_child(icon)

	var title := Label.new()
	title.name = "Title"
	title.text = str(m.get("display_name", mine_id))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", PIXEL_FONT)
	title.add_theme_font_size_override("font_size", 22)
	entry.add_child(title)

	var desc := Label.new()
	desc.name = "Desc"
	desc.text = str(m.get("description", ""))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(170, 0)
	desc.add_theme_font_override("font", PIXEL_FONT)
	desc.add_theme_font_size_override("font_size", 16)
	entry.add_child(desc)

	var stats := Label.new()
	stats.name = "Stats"
	stats.text = "Hardness x%.1f\nOre x%.1f" % [
		Registry.mine_hardness_mult(_tables, mine_id),
		Registry.mine_ore_value_mult(_tables, mine_id),
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_override("font", PIXEL_FONT)
	stats.add_theme_font_size_override("font_size", 16)
	entry.add_child(stats)

	var btn := Button.new()
	btn.name = "Action_%s" % mine_id
	btn.text = "ENTER"
	btn.custom_minimum_size = Vector2(0, 48)
	btn.add_theme_font_override("font", PIXEL_FONT)
	btn.add_theme_font_size_override("font_size", 22)
	if primary_button_normal != null:
		btn.add_theme_stylebox_override("normal", primary_button_normal)
	if primary_button_hover != null:
		btn.add_theme_stylebox_override("hover", primary_button_hover)
		btn.add_theme_stylebox_override("pressed", primary_button_hover)
	btn.pressed.connect(_on_action.bind(mine_id))
	entry.add_child(btn)
	_buttons[mine_id] = btn
	return entry


## A mine's action button: ENTER if unlocked, else pay-to-UNLOCK. Routed by current state so
## the same button serves both phases (it flips to ENTER after a successful unlock + refresh).
func _on_action(mine_id: String) -> void:
	if _unlocked(mine_id):
		enter_pressed.emit(mine_id)
	else:
		unlock_pressed.emit(mine_id)


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
	var seconds: float = Registry.ui_panel_in_seconds(_tables) if not _tables.is_empty() else 0.22
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "scale", Vector2.ONE, seconds) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "modulate", Color(1, 1, 1, 1), seconds) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _backdrop != null:
		_tween.tween_property(_backdrop, "modulate", Color(1, 1, 1, 1), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
