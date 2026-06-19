class_name SaveManager
extends RefCounted
## Thin save-file system (U20 / AC-5.11.3, AC-5.11.4). Owns the disk I/O — atomic write
## (temp → rename), one rolling backup, and a recovery chain (primary → backup → clean default
## with a non-destructive warning). All (de)serialization + migration is delegated to the pure
## `SaveCodec`, so this layer is only about robust file handling.
##
## The save path is injectable so tests write to a throwaway file. On web, `user://` maps to
## IndexedDB, which can be unavailable or temporary; this manager exposes that status and manual
## JSON export/import so the Settings UI can warn and give the player a backup path (AC-5.11.5).
##
## ACs: AC-5.11.3 (atomic write + backup + recovery), AC-5.11.4 (autosave at boundaries — the
##      callers decide WHEN; this provides the durable WRITE).

const DEFAULT_PRIMARY := "user://mining_game/save.json"
const LEGACY_PRIMARY := "user://mining_game_save.json"
const TEST_PRIMARY_NAME := "mining_game_save_gdunit.json"
const WEB_PERSISTENCE_WARNING := "Browser storage is temporary here. Export Save before closing."

var _primary: String
var _backup: String
var _tmp: String

## True when the last load() fell all the way through to a clean default because BOTH the primary
## and the backup were unreadable (a real corruption event the UI should warn about, non-destructively).
var last_recovered_with_warning: bool = false

func _init(primary_path: String = "") -> void:
	if primary_path == "":
		primary_path = _default_primary_path()
	_primary = primary_path
	_backup = primary_path + ".bak"
	_tmp = primary_path + ".tmp"
	if _primary == DEFAULT_PRIMARY:
		_migrate_legacy_default_save()


static func _default_primary_path() -> String:
	if _running_gdunit():
		return OS.get_temp_dir().path_join(TEST_PRIMARY_NAME)
	return DEFAULT_PRIMARY


static func _running_gdunit() -> bool:
	for arg in OS.get_cmdline_args():
		if str(arg).contains("GdUnitCmdTool"):
			return true
	return false

## Atomically persist `state`. Sequence: write the full new content to a temp file; roll the
## current good primary → backup; rename temp → primary (atomic on Unix; on platforms that won't
## overwrite, falls back to remove-then-rename). A crash before the rename leaves the old primary
## intact; after, the new one — never a half-written primary — and the previous good save survives
## as the backup (AC-5.11.3).
func save_state(state: Dictionary) -> bool:
	if not _ensure_parent_dir(_tmp):
		return false
	var f := FileAccess.open(_tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(SaveCodec.encode(state))
	f.close()
	# Roll the current good save to backup BEFORE replacing it.
	if FileAccess.file_exists(_primary):
		DirAccess.copy_absolute(_primary, _backup)
	# Atomic replace: try rename first (atomic on Unix). If the target exists and the OS
	# won't overwrite, fall back to remove-then-rename (the backup already holds the
	# previous good save, so the brief gap is recoverable).
	var err := DirAccess.rename_absolute(_tmp, _primary)
	if err != OK and FileAccess.file_exists(_primary):
		DirAccess.remove_absolute(_primary)
		err = DirAccess.rename_absolute(_tmp, _primary)
	return err == OK

## Load with a recovery chain (AC-5.11.3): primary → backup → clean default (+warning). Always
## returns a valid, normalized state dict. Sets `last_recovered_with_warning` only when a clean
## default had to be substituted despite a save file existing (i.e. real corruption, not a new game).
func load_state() -> Dictionary:
	last_recovered_with_warning = false
	var primary: Dictionary = _read_decode(_primary)
	if not primary.is_empty():
		return primary
	var backup: Dictionary = _read_decode(_backup)
	if not backup.is_empty():
		return backup
	# Neither readable. If a file existed, this is a corruption event → warn (non-destructively).
	last_recovered_with_warning = FileAccess.file_exists(_primary) or FileAccess.file_exists(_backup)
	return SaveCodec.default_state()

func _read_decode(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	return SaveCodec.decode(text)


## Return the normalized JSON text the player can copy/download from the Settings overlay.
func export_save_text() -> String:
	return SaveCodec.encode(load_state())


## Import a manual save export. Corrupt JSON is rejected; parseable content is normalized/migrated
## by SaveCodec before the usual atomic write path persists it.
func import_save_text(text: String) -> bool:
	if text.strip_edges().is_empty():
		return false
	var decoded: Dictionary = SaveCodec.decode(text)
	if decoded.is_empty():
		return false
	return save_state(decoded)


## Browser persistence status for AC-5.11.5. Native targets are durable enough for the local-save
## contract; web is durable only when the browser reports persistent userfs/IndexedDB support.
static func persistence_status() -> Dictionary:
	var is_web := OS.has_feature("web")
	var available := true
	var warning := ""
	if is_web:
		available = OS.is_userfs_persistent()
		if not available:
			warning = WEB_PERSISTENCE_WARNING
	return {"is_web": is_web, "available": available, "warning": warning}


func persistence_warning() -> String:
	return str(persistence_status().get("warning", ""))


func persistence_available() -> bool:
	return bool(persistence_status().get("available", true))

## True if a primary save file exists (a returning player vs a fresh game).
func has_save() -> bool:
	return FileAccess.file_exists(_primary)

## Remove the save, backup, and any stray temp (a "reset progress" action / test teardown).
func clear() -> void:
	var paths: Array[String] = [_primary, _backup, _tmp]
	if _primary == DEFAULT_PRIMARY:
		paths.append_array([LEGACY_PRIMARY, LEGACY_PRIMARY + ".bak", LEGACY_PRIMARY + ".tmp"])
	for p: String in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func primary_path() -> String:
	return _primary


func backup_path() -> String:
	return _backup


static func _ensure_parent_dir(path: String) -> bool:
	var dir_path := path.get_base_dir()
	if dir_path.is_empty() or dir_path == "user://":
		return true
	if dir_path.begins_with("user://"):
		var current := "user://"
		for part: String in dir_path.trim_prefix("user://").split("/", false):
			var next := current.path_join(part)
			if not DirAccess.dir_exists_absolute(next):
				var da := DirAccess.open(current)
				if da == null or da.make_dir(part) != OK:
					return false
			current = next
		return true
	return DirAccess.make_dir_recursive_absolute(dir_path) == OK


func _migrate_legacy_default_save() -> void:
	if FileAccess.file_exists(_primary):
		return
	if not _ensure_parent_dir(_primary):
		return
	if FileAccess.file_exists(LEGACY_PRIMARY):
		DirAccess.copy_absolute(LEGACY_PRIMARY, _primary)
	if not FileAccess.file_exists(_backup) and FileAccess.file_exists(LEGACY_PRIMARY + ".bak"):
		DirAccess.copy_absolute(LEGACY_PRIMARY + ".bak", _backup)
