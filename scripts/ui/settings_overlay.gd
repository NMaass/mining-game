class_name SettingsOverlay
extends CanvasLayer
## Modal Settings overlay (AC-5.8.3 modal-overlay structure + AC-5.10.1 settings). Opening it
## PAUSES the whole SceneTree (the Mine stays instanced + frozen — in-flight charge, terrain,
## money all preserved) and shows a dialog with the four accessibility settings (SFX/Music volume,
## motion intensity, UI text scale). Closing un-pauses and restores play. The overlay subtree runs
## with process_mode = ALWAYS (set in the scene) so its controls stay interactive while paused.
##
## It is a thin VIEW over a shared SettingsState: a slider move mutates the SettingsState and emits
## `settings_changed`; the mine controller is the integrator (applies to Audio + HUD + explosion and
## persists). The same SettingsState instance is shared with mine.gd, so there is one source of truth.
##
## In the slice this overlay hosts Settings; the Hub/Shop/Upgrades tabs named in AC-5.8.3 are ROADMAP
## (U16–U26) — the modal-pause-restore structure they need is what this establishes.
##
## ACs: AC-5.8.3 (nav → modal overlay; Mine paused + state preserved), AC-5.10.1 (motion + text
##      scale + SFX/Music volume), AC-5.11.1 (changes persist — via mine.gd's _save_progress).

## Emitted after the overlay closes (so the controller can re-enable aim / refresh).
signal closed
## Emitted whenever a setting changes (so the controller applies it live + persists it).
signal settings_changed

var _tables: Dictionary = {}
var _settings: SettingsState = null
## Guards the slider→handler path while we push values INTO the sliders (avoids feedback).
var _syncing: bool = false

@onready var _sfx_slider: HSlider = get_node_or_null("Center/Dialog/Box/SfxSlider")
@onready var _music_slider: HSlider = get_node_or_null("Center/Dialog/Box/MusicSlider")
@onready var _motion_slider: HSlider = get_node_or_null("Center/Dialog/Box/MotionSlider")
@onready var _text_scale_slider: HSlider = get_node_or_null("Center/Dialog/Box/TextScaleSlider")
@onready var _close_button: Button = get_node_or_null("Center/Dialog/Box/CloseButton")
@onready var _sfx_label: Label = get_node_or_null("Center/Dialog/Box/SfxLabel")
@onready var _music_label: Label = get_node_or_null("Center/Dialog/Box/MusicLabel")
@onready var _motion_label: Label = get_node_or_null("Center/Dialog/Box/MotionLabel")
@onready var _text_scale_label: Label = get_node_or_null("Center/Dialog/Box/TextScaleLabel")


## Bind the shared SettingsState + data tables, set the slider ranges from /data, reflect the
## current values, and wire the slider/close handlers. Idempotent.
func configure(tables: Dictionary, settings: SettingsState) -> void:
	_tables = tables
	_settings = settings
	if _text_scale_slider != null and _settings != null:
		_text_scale_slider.min_value = _settings.text_scale_min
		_text_scale_slider.max_value = _settings.text_scale_max
	_sync_from_settings()
	_connect_once()
	_refresh_labels()


## Open the modal overlay: reflect current settings, show, and PAUSE the tree (AC-5.8.3). The Mine
## (and its in-flight charge / physics) freezes; this overlay keeps running (process_mode = ALWAYS).
func open() -> void:
	_sync_from_settings()
	_refresh_labels()
	visible = true
	var tree := get_tree()
	if tree != null:
		tree.paused = true


## Close the overlay: hide, UN-pause the tree (restore play), and notify the controller (AC-5.8.3).
func close() -> void:
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


func _connect_once() -> void:
	if _sfx_slider != null and not _sfx_slider.value_changed.is_connected(_on_sfx_changed):
		_sfx_slider.value_changed.connect(_on_sfx_changed)
	if _music_slider != null and not _music_slider.value_changed.is_connected(_on_music_changed):
		_music_slider.value_changed.connect(_on_music_changed)
	if _motion_slider != null and not _motion_slider.value_changed.is_connected(_on_motion_changed):
		_motion_slider.value_changed.connect(_on_motion_changed)
	if _text_scale_slider != null and not _text_scale_slider.value_changed.is_connected(_on_text_scale_changed):
		_text_scale_slider.value_changed.connect(_on_text_scale_changed)
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


# ── Test/inspection accessors (the sliders the integration test drives) ──────────

func sfx_slider() -> HSlider:
	return _sfx_slider

func music_slider() -> HSlider:
	return _music_slider

func motion_slider() -> HSlider:
	return _motion_slider

func text_scale_slider() -> HSlider:
	return _text_scale_slider
