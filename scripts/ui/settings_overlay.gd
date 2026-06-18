class_name SettingsOverlay
extends CanvasLayer
## Modal Settings overlay (AC-5.8.3 modal-overlay structure + AC-5.10.1 settings). Opening it
## PAUSES the whole SceneTree (the Mine stays instanced + frozen — in-flight charge, terrain,
## money all preserved) and shows a SECTIONED dialog: Audio (SFX/Music volume), Accessibility
## (motion intensity, UI text scale), and Controls (rebindable keys for the five D1 actions + an
## elevator-side Left/Right toggle). Closing un-pauses and restores play. The overlay subtree runs
## with process_mode = ALWAYS (set in the scene) so its controls stay interactive while paused.
##
## It is a thin VIEW over a shared SettingsState: a control move mutates the SettingsState and emits
## `settings_changed`; the mine controller is the integrator (applies to Audio + HUD + InputMap +
## explosion and persists). The same SettingsState instance is shared with mine.gd, so there is one
## source of truth.
##
## Rebind flow (AC-5.10.1 controls): tapping a key button enters CAPTURE mode; the next key press
## (read in _input, which fires even while paused because this layer is process_mode = ALWAYS) is
## written into the SettingsState AND applied to the live InputMap. ESC cancels the capture. The
## content is wrapped in a ScrollContainer so the now-taller menu stays usable on a narrow portrait
## phone (the bottom Close button stays pinned outside the scroll).
##
## ACs: AC-5.8.3 (nav → modal overlay; Mine paused + state preserved), AC-5.10.1 (motion + text
##      scale + SFX/Music volume + rebindable controls + elevator side), AC-5.11.1 (changes persist).

## Emitted after the overlay closes (so the controller can re-enable aim / refresh).
signal closed
## Emitted whenever a setting changes (so the controller applies it live + persists it).
signal settings_changed
## Emitted when a keybind capture commits a new key for `action` (the controller mirrors it into the
## live InputMap). The SettingsState is ALSO updated here, so settings_changed fires alongside.
signal keybind_rebound(action: String, keycode: int)

var _tables: Dictionary = {}
var _settings: SettingsState = null
## Guards the slider→handler path while we push values INTO the sliders (avoids feedback).
var _syncing: bool = false
## Live tween handle for the open pop-in so a rapid re-open kills a prior one (no stuck alpha).
var _tween: Tween = null
## The action whose key is being captured ("" when not capturing). While set, the next key press
## rebinds it. Mirrors a "press a key…" label on its row button.
var _capturing_action: String = ""
## action → its rebind Button (built in _build_rebind_rows), so a capture can update one row's text.
var _rebind_buttons: Dictionary = {}

@onready var _dim: Control = get_node_or_null("Dim")
@onready var _dialog: Control = get_node_or_null("Center/Dialog")
@onready var _content: VBoxContainer = get_node_or_null("Center/Dialog/Box/Scroll/Content")
@onready var _sfx_slider: HSlider = get_node_or_null("Center/Dialog/Box/Scroll/Content/SfxSlider")
@onready var _music_slider: HSlider = get_node_or_null("Center/Dialog/Box/Scroll/Content/MusicSlider")
@onready var _motion_slider: HSlider = get_node_or_null("Center/Dialog/Box/Scroll/Content/MotionSlider")
@onready var _text_scale_slider: HSlider = get_node_or_null("Center/Dialog/Box/Scroll/Content/TextScaleSlider")
@onready var _elevator_side_button: Button = get_node_or_null("Center/Dialog/Box/Scroll/Content/ElevatorSideButton")
@onready var _rebind_rows: VBoxContainer = get_node_or_null("Center/Dialog/Box/Scroll/Content/RebindRows")
@onready var _close_button: Button = get_node_or_null("Center/Dialog/Box/CloseButton")
@onready var _sfx_label: Label = get_node_or_null("Center/Dialog/Box/Scroll/Content/SfxLabel")
@onready var _music_label: Label = get_node_or_null("Center/Dialog/Box/Scroll/Content/MusicLabel")
@onready var _motion_label: Label = get_node_or_null("Center/Dialog/Box/Scroll/Content/MotionLabel")
@onready var _text_scale_label: Label = get_node_or_null("Center/Dialog/Box/Scroll/Content/TextScaleLabel")

## Friendly display names for the rebind rows (the action ids are internal).
const _ACTION_LABELS := {
	"aim_left": "Aim left",
	"aim_right": "Aim right",
	"fire": "Throw",
	"elevator_up": "Elevator up",
	"elevator_down": "Elevator down",
}


## Bind the shared SettingsState + data tables, set the slider ranges from /data, build the rebind
## rows, reflect the current values, and wire the control handlers. Idempotent.
func configure(tables: Dictionary, settings: SettingsState) -> void:
	_tables = tables
	_settings = settings
	if _text_scale_slider != null and _settings != null:
		_text_scale_slider.min_value = _settings.text_scale_min
		_text_scale_slider.max_value = _settings.text_scale_max
	_build_rebind_rows()
	_sync_from_settings()
	_connect_once()
	_refresh_labels()


## Open the modal overlay: reflect current settings, show, and PAUSE the tree (AC-5.8.3). The Mine
## (and its in-flight charge / physics) freezes; this overlay keeps running (process_mode = ALWAYS).
## v0.5 arcade pass: the Dialog POPS IN (scale 0.85→1.0 + alpha 0→1, TRANS_BACK) over
## ui_panel_in_seconds while the Dim backdrop fades in. The overlay is process_mode = ALWAYS, so the
## tween advances even though open() pauses the tree. `visible` (and thus is_open()) is set TRUE
## SYNCHRONOUSLY before the tween so the overlay-state test reading is_open() right after stays green.
## At motion ~0 (reduced motion) it snaps with no tween.
func open() -> void:
	_cancel_capture()
	_sync_from_settings()
	_refresh_labels()
	visible = true
	var tree := get_tree()
	if tree != null:
		tree.paused = true
	_animate_in()


func _animate_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var motion: float = _settings.motion_intensity if _settings != null else 1.0
	if _dialog != null:
		_dialog.pivot_offset = _dialog.size * 0.5
	if motion <= 0.01:
		if _dialog != null:
			_dialog.scale = Vector2.ONE
			_dialog.modulate = Color(1, 1, 1, 1)
		if _dim != null:
			_dim.modulate = Color(1, 1, 1, 1)
		return
	if _dialog != null:
		_dialog.scale = Vector2(0.85, 0.85)
		_dialog.modulate = Color(1, 1, 1, 0)
	if _dim != null:
		_dim.modulate = Color(1, 1, 1, 0)
	var seconds: float = Registry.ui_panel_in_seconds(_tables) if not _tables.is_empty() else 0.22
	_tween = create_tween().set_parallel(true)
	if _dialog != null:
		_tween.tween_property(_dialog, "scale", Vector2.ONE, seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_dialog, "modulate", Color(1, 1, 1, 1), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _dim != null:
		_tween.tween_property(_dim, "modulate", Color(1, 1, 1, 1), seconds) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Close the overlay: hide, UN-pause the tree (restore play), and notify the controller (AC-5.8.3).
func close() -> void:
	_cancel_capture()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if _dialog != null:
		_dialog.scale = Vector2.ONE
		_dialog.modulate = Color(1, 1, 1, 1)
	visible = false
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	closed.emit()


## Whether the overlay is currently open (shown + pausing).
func is_open() -> bool:
	return visible


# ── Slider ↔ settings binding ────────────────────────────────────────────────────

func _sync_from_settings() -> void:
	if _settings == null:
		return
	_syncing = true
	if _sfx_slider != null:
		_sfx_slider.value = _settings.sfx_volume
	if _music_slider != null:
		_music_slider.value = _settings.music_volume
	if _motion_slider != null:
		_motion_slider.value = _settings.motion_intensity
	if _text_scale_slider != null:
		_text_scale_slider.value = _settings.text_scale
	_syncing = false
	_refresh_elevator_button()
	_refresh_rebind_buttons()


func _connect_once() -> void:
	if _sfx_slider != null and not _sfx_slider.value_changed.is_connected(_on_sfx_changed):
		_sfx_slider.value_changed.connect(_on_sfx_changed)
	if _music_slider != null and not _music_slider.value_changed.is_connected(_on_music_changed):
		_music_slider.value_changed.connect(_on_music_changed)
	if _motion_slider != null and not _motion_slider.value_changed.is_connected(_on_motion_changed):
		_motion_slider.value_changed.connect(_on_motion_changed)
	if _text_scale_slider != null and not _text_scale_slider.value_changed.is_connected(_on_text_scale_changed):
		_text_scale_slider.value_changed.connect(_on_text_scale_changed)
	if _elevator_side_button != null and not _elevator_side_button.pressed.is_connected(_on_elevator_side_pressed):
		_elevator_side_button.pressed.connect(_on_elevator_side_pressed)
	if _close_button != null and not _close_button.pressed.is_connected(close):
		_close_button.pressed.connect(close)


func _on_sfx_changed(v: float) -> void:
	if _syncing or _settings == null:
		return
	_settings.set_sfx_volume(v)
	_refresh_labels()
	settings_changed.emit()


func _on_music_changed(v: float) -> void:
	if _syncing or _settings == null:
		return
	_settings.set_music_volume(v)
	_refresh_labels()
	settings_changed.emit()


func _on_motion_changed(v: float) -> void:
	if _syncing or _settings == null:
		return
	_settings.set_motion_intensity(v)
	_refresh_labels()
	settings_changed.emit()


func _on_text_scale_changed(v: float) -> void:
	if _syncing or _settings == null:
		return
	_settings.set_text_scale(v)
	_refresh_labels()
	settings_changed.emit()


# ── Elevator side toggle (AC-5.10.1 controls) ────────────────────────────────────

func _on_elevator_side_pressed() -> void:
	if _settings == null:
		return
	_settings.toggle_elevator_side()
	_refresh_elevator_button()
	settings_changed.emit()


func _refresh_elevator_button() -> void:
	if _elevator_side_button == null or _settings == null:
		return
	_elevator_side_button.text = "Left" if _settings.elevator_side == "left" else "Right"


# ── Keybind rebinding (AC-5.10.1 controls) ───────────────────────────────────────

## Build one rebind row (label + key button) per D1 action. Rebuilt from scratch each configure so
## a re-configure (e.g. test re-boot) never duplicates rows. The button text shows the current key.
func _build_rebind_rows() -> void:
	if _rebind_rows == null:
		return
	for child in _rebind_rows.get_children():
		_rebind_rows.remove_child(child)
		child.queue_free()
	_rebind_buttons.clear()
	for action in SettingsState.KEYBIND_ACTIONS:
		var row := HBoxContainer.new()
		row.name = "Row_" + action
		row.add_theme_constant_override("separation", 10)
		var label := Label.new()
		label.text = str(_ACTION_LABELS.get(action, action))
		label.add_theme_font_size_override("font_size", 20)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var btn := Button.new()
		btn.name = "Key"
		btn.custom_minimum_size = Vector2(180, 48)
		btn.add_theme_font_size_override("font_size", 20)
		# Bind the action id so one shared handler knows which row was tapped.
		btn.pressed.connect(_on_rebind_pressed.bind(action))
		row.add_child(btn)
		_rebind_rows.add_child(row)
		_rebind_buttons[action] = btn
	_refresh_rebind_buttons()


## Reflect the current keybind for every row on its button (e.g. "Space", "Left"). A row in capture
## mode shows the prompt instead. Pulls the keycode from the SettingsState (the durable record).
func _refresh_rebind_buttons() -> void:
	for action in _rebind_buttons.keys():
		var btn: Button = _rebind_buttons[action]
		if btn == null:
			continue
		if action == _capturing_action:
			btn.text = "Press a key…"
			continue
		var kc: int = _settings.keybind_for(action) if _settings != null else 0
		btn.text = _keycode_display(kc)


## A short human label for a physical keycode (uses Godot's key name; "—" for unbound).
func _keycode_display(keycode: int) -> String:
	if keycode <= 0:
		return "—"
	var name := OS.get_keycode_string(keycode)
	return name if not name.is_empty() else "Key %d" % keycode


func _on_rebind_pressed(action: String) -> void:
	# Tapping the currently-capturing row cancels; tapping another switches the capture to it.
	if _capturing_action == action:
		_cancel_capture()
		return
	_capturing_action = action
	_refresh_rebind_buttons()


## Capture the next key press while a rebind row is armed. Runs even while the tree is paused because
## this CanvasLayer is process_mode = ALWAYS. ESC cancels; any other physical key commits the rebind
## into the SettingsState + signals the controller (which mirrors it into the live InputMap).
func _input(event: InputEvent) -> void:
	if _capturing_action == "":
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	get_viewport().set_input_as_handled()
	if key.keycode == KEY_ESCAPE:
		_cancel_capture()
		return
	var keycode: int = key.physical_keycode if key.physical_keycode != 0 else key.keycode
	_commit_rebind(_capturing_action, keycode)


## Apply a rebind (used by _input on capture; also a public seam for headless tests, since injected
## key events do not fire in a headless run). Writes the SettingsState, refreshes the row, exits
## capture, and notifies the controller (settings_changed + keybind_rebound).
func commit_rebind(action: String, keycode: int) -> void:
	_capturing_action = action
	_commit_rebind(action, keycode)


func _commit_rebind(action: String, keycode: int) -> void:
	if _settings == null or keycode <= 0 or not (action in SettingsState.KEYBIND_ACTIONS):
		_cancel_capture()
		return
	# UNIT INFRA (crash-triage #1): set_keybind rejects a key already owned by ANOTHER action. On a
	# rejected (colliding) bind, abandon capture WITHOUT notifying the controller — the old binding
	# stands and the InputMap is left untouched, so no two actions ever share a key.
	if not _settings.set_keybind(action, keycode):
		_cancel_capture()
		_refresh_rebind_buttons()
		return
	_capturing_action = ""
	_refresh_rebind_buttons()
	keybind_rebound.emit(action, keycode)
	settings_changed.emit()


func _cancel_capture() -> void:
	_capturing_action = ""
	_refresh_rebind_buttons()


## Live value readouts on the labels (non-color, text — so the slider position is also a number).
func _refresh_labels() -> void:
	if _settings == null:
		return
	if _sfx_label != null:
		_sfx_label.text = "SFX volume   %d%%" % int(round(_settings.sfx_volume * 100.0))
	if _music_label != null:
		_music_label.text = "Music volume   %d%%" % int(round(_settings.music_volume * 100.0))
	if _motion_label != null:
		_motion_label.text = "Motion intensity   %d%%" % int(round(_settings.motion_intensity * 100.0))
	if _text_scale_label != null:
		_text_scale_label.text = "UI text scale   %.1fx" % _settings.text_scale


# ── Test/inspection accessors (the controls the integration test drives) ─────────

func sfx_slider() -> HSlider:
	return _sfx_slider

func music_slider() -> HSlider:
	return _music_slider

func motion_slider() -> HSlider:
	return _motion_slider

func text_scale_slider() -> HSlider:
	return _text_scale_slider

func elevator_side_button() -> Button:
	return _elevator_side_button

## The rebind Button for `action` (or null). For tests/inspection.
func rebind_button(action: String) -> Button:
	return _rebind_buttons.get(action, null)

## The action currently armed for capture ("" if none). For tests/inspection.
func capturing_action() -> String:
	return _capturing_action
