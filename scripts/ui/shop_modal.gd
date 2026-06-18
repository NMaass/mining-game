class_name ShopModal
extends CanvasLayer
## Modal shop overlay: browse all packs in /data, view odds derived from pack weights,
## and buy a pack. The Mine controller owns the economy and purchase path; this UI is a
## thin view that emits `buy_pressed(pack_id)` and `closed`.
##
## The overlay pauses the game tree while open (process_mode = ALWAYS keeps its own
## buttons interactive) and unpause on close, matching the Settings/PrestigeOffer modals.

## Emitted when a pack's BUY button is pressed.
signal buy_pressed(pack_id: String)
## Emitted when a per-dig money UPGRADE's BUY button is pressed (Shaft Engineering, etc.).
signal buy_upgrade_pressed(upgrade_id: String)
## Emitted after the modal closes (whether by buy or CLOSE).
signal closed

const PIXEL_FONT := preload("res://art/fonts/PixelifySans.ttf")

## Crate icon tints: rusty (basic) and steel-blue (heavy_crate). A default gray covers
## any future pack ids without an explicit mapping.
const _CRATE_COLORS: Dictionary = {
	"basic": Color(0.85, 0.45, 0.18),
	"heavy_crate": Color(0.38, 0.48, 0.62),
}

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
var _get_upgrade_level: Callable
var _buy_buttons: Dictionary = {}
var _upgrade_buttons: Dictionary = {}  # upgrade_id -> Button
var _tween: Tween = null


func _ready() -> void:
	visible = false
	if _close_button != null and not _close_button.pressed.is_connected(close):
		_close_button.pressed.connect(close)


## Bind the data tables and a callback that returns the player's current money. The
## callback lets the modal disable BUY buttons for unaffordable packs without owning
## the Economy object.
func configure(tables: Dictionary, get_money_callback: Callable, get_upgrade_level_callback: Callable = Callable()) -> void:
	_tables = tables
	_get_money = get_money_callback
	_get_upgrade_level = get_upgrade_level_callback
	_build_entries()


## Re-run the affordability/owned pass without rebuilding (e.g. after an in-modal purchase
## so the bought upgrade flips to OWNED and pack buttons re-gate on the new money balance).
func refresh() -> void:
	_refresh_affordability(_current_money())


## Open the shop, pause the game tree, and refresh each BUY button from current money.
func open(motion: float = 1.0) -> void:
	visible = true
	var money: int = _current_money()
	_refresh_affordability(money)
	var tree := get_tree()
	if tree != null:
		tree.paused = true
	_animate_in(motion)


## Close the shop and unpause the game tree. Synchronous so callers can read visible
## immediately after.
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


func _current_money() -> int:
	if not _get_money.is_valid():
		return 0
	return _get_money.call() as int


func _build_entries() -> void:
	if _entries_container == null:
		return
	# Clear any stale entries (re-configure safety).
	for child in _entries_container.get_children():
		child.queue_free()
	_buy_buttons.clear()
	_upgrade_buttons.clear()

	var rarity_colors: Dictionary = _rarity_color_table()
	for pack_id: String in Registry.pack_ids(_tables):
		var pack_data: Dictionary = Registry.pack(_tables, pack_id)
		if pack_data.is_empty():
			continue
		var display_name: String = str(pack_data.get("display_name", pack_id))
		var price: int = int(pack_data.get("price", 0))
		var weights: Dictionary = pack_data.get("weights", {})

		var entry := VBoxContainer.new()
		entry.name = "Entry_%s" % pack_id
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.alignment = BoxContainer.ALIGNMENT_CENTER
		entry.add_theme_constant_override("separation", 6)

		var icon := ColorRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(64, 64)
		icon.color = _CRATE_COLORS.get(pack_id, Color(0.55, 0.55, 0.6))
		entry.add_child(icon)

		var title_label := Label.new()
		title_label.name = "Title"
		title_label.text = display_name
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_override("font", PIXEL_FONT)
		title_label.add_theme_font_size_override("font_size", 22)
		entry.add_child(title_label)

		var price_label := Label.new()
		price_label.name = "Price"
		price_label.text = "$%d" % price
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_label.add_theme_font_override("font", PIXEL_FONT)
		price_label.add_theme_font_size_override("font_size", 22)
		entry.add_child(price_label)

		var odds_box := VBoxContainer.new()
		odds_box.name = "Odds"
		odds_box.alignment = BoxContainer.ALIGNMENT_CENTER
		odds_box.add_theme_constant_override("separation", 2)
		var odds_rows: Array = _build_odds_rows(weights)
		var total_weight: float = _total_weight(weights)
		for row in odds_rows:
			var pct: int = 0
			if total_weight > 0.0:
				pct = int(round((row["weight"] as float) / total_weight * 100.0))
			var line := Label.new()
			line.name = "Odd_%s" % row["id"]
			line.text = "%s %d%%" % [row["name"], pct]
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			line.modulate = _rarity_color(rarity_colors, str(row["rarity"]))
			line.add_theme_font_override("font", PIXEL_FONT)
			line.add_theme_font_size_override("font_size", 18)
			odds_box.add_child(line)
		entry.add_child(odds_box)

		var buy_btn := Button.new()
		buy_btn.name = "Buy_%s" % pack_id
		buy_btn.text = "BUY"
		buy_btn.custom_minimum_size = Vector2(0, 48)
		buy_btn.add_theme_font_override("font", PIXEL_FONT)
		buy_btn.add_theme_font_size_override("font_size", 22)
		if primary_button_normal != null:
			buy_btn.add_theme_stylebox_override("normal", primary_button_normal)
		if primary_button_hover != null:
			buy_btn.add_theme_stylebox_override("hover", primary_button_hover)
			buy_btn.add_theme_stylebox_override("pressed", primary_button_hover)
		buy_btn.pressed.connect(_on_buy.bind(pack_id))
		entry.add_child(buy_btn)
		_buy_buttons[pack_id] = buy_btn

		_entries_container.add_child(entry)

	# Per-dig MONEY upgrades (Shaft Engineering, etc.) — bought with in-dig money, reset each
	# dig. Listed after the packs in the same flow container.
	for up_id: String in Registry.upgrade_ids(_tables):
		var up: Dictionary = Registry.upgrade(_tables, up_id)
		if up.is_empty():
			continue
		_entries_container.add_child(_build_upgrade_entry(up_id, up))


## Build one upgrade card: icon, name, price, description, and a BUY button that flips to
## OWNED once bought to max level (tracked in `_upgrade_buttons` for the affordability pass).
func _build_upgrade_entry(up_id: String, up: Dictionary) -> VBoxContainer:
	var entry := VBoxContainer.new()
	entry.name = "Upgrade_%s" % up_id
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.alignment = BoxContainer.ALIGNMENT_CENTER
	entry.add_theme_constant_override("separation", 6)

	var icon := ColorRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(64, 64)
	icon.color = Color(0.42, 0.62, 0.45)  # green-tinted: a permanent-feeling tool upgrade
	entry.add_child(icon)

	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = str(up.get("display_name", up_id))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", PIXEL_FONT)
	title_label.add_theme_font_size_override("font_size", 22)
	entry.add_child(title_label)

	var price_label := Label.new()
	price_label.name = "Price"
	price_label.text = "$%d" % int(up.get("price", 0))
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.add_theme_font_override("font", PIXEL_FONT)
	price_label.add_theme_font_size_override("font_size", 22)
	entry.add_child(price_label)

	var desc_label := Label.new()
	desc_label.name = "Desc"
	desc_label.text = str(up.get("description", ""))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(150, 0)
	desc_label.add_theme_font_override("font", PIXEL_FONT)
	desc_label.add_theme_font_size_override("font_size", 16)
	entry.add_child(desc_label)

	var buy_btn := Button.new()
	buy_btn.name = "Buy_%s" % up_id
	buy_btn.text = "BUY"
	buy_btn.custom_minimum_size = Vector2(0, 48)
	buy_btn.add_theme_font_override("font", PIXEL_FONT)
	buy_btn.add_theme_font_size_override("font_size", 22)
	if primary_button_normal != null:
		buy_btn.add_theme_stylebox_override("normal", primary_button_normal)
	if primary_button_hover != null:
		buy_btn.add_theme_stylebox_override("hover", primary_button_hover)
		buy_btn.add_theme_stylebox_override("pressed", primary_button_hover)
	buy_btn.pressed.connect(_on_buy_upgrade.bind(up_id))
	entry.add_child(buy_btn)
	_upgrade_buttons[up_id] = buy_btn
	return entry


func _build_odds_rows(weights: Dictionary) -> Array:
	var rows: Array = []
	for ex_id: String in weights.keys():
		var ex: Dictionary = Registry.explosive(_tables, ex_id)
		rows.append({
			"id": ex_id,
			"name": str(ex.get("display_name", ex_id)),
			"rarity": str(ex.get("rarity", "common")),
			"weight": float(weights[ex_id]),
		})
	# Highest-weight first, then alphabetical by id for deterministic order.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["weight"] != b["weight"]:
			return (a["weight"] as float) > (b["weight"] as float)
		return str(a["id"]) < str(b["id"])
	)
	return rows


func _total_weight(weights: Dictionary) -> float:
	var total: float = 0.0
	for w in weights.values():
		total += float(w)
	return total


func _rarity_color_table() -> Dictionary:
	var rarity: Variant = _tables.get("rarity")
	if rarity is Dictionary:
		var colors: Variant = (rarity as Dictionary).get("colors")
		if colors is Dictionary:
			return colors as Dictionary
	return {}


func _rarity_color(color_table: Dictionary, rarity: String) -> Color:
	var hex: String = str(color_table.get(rarity, "#ffffff"))
	if Color.html_is_valid(hex):
		return Color.html(hex)
	return Color.WHITE


func _refresh_affordability(money: int) -> void:
	for pack_id: String in _buy_buttons.keys():
		var pack_data: Dictionary = Registry.pack(_tables, pack_id)
		var price: int = int(pack_data.get("price", 0))
		var btn: Button = _buy_buttons[pack_id]
		btn.disabled = money < price
	for up_id: String in _upgrade_buttons.keys():
		var up: Dictionary = Registry.upgrade(_tables, up_id)
		var price: int = int(up.get("price", 0))
		var max_level: int = int(up.get("max_level", 1))
		var level: int = _upgrade_level(up_id)
		var btn: Button = _upgrade_buttons[up_id]
		var maxed: bool = level >= max_level
		btn.text = "OWNED" if maxed else "BUY"
		btn.disabled = maxed or money < price


## Current purchased level of an upgrade via the bound callback (0 if no callback / unbound).
func _upgrade_level(upgrade_id: String) -> int:
	if not _get_upgrade_level.is_valid():
		return 0
	return _get_upgrade_level.call(upgrade_id) as int


func _on_buy(pack_id: String) -> void:
	buy_pressed.emit(pack_id)


func _on_buy_upgrade(upgrade_id: String) -> void:
	buy_upgrade_pressed.emit(upgrade_id)


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
