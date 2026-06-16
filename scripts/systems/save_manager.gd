class_name SaveManager
extends RefCounted
## Thin save-file system (U20 / AC-5.11.3, AC-5.11.4). Owns the disk I/O — atomic write
## (temp → rename), one rolling backup, and a recovery chain (primary → backup → clean default
## with a non-destructive warning). All (de)serialization + migration is delegated to the pure
## `SaveCodec`, so this layer is only about robust file handling.
##
## The save path is injectable so tests write to a throwaway `user://` file. Web reality (AC-5.11.5:
## IndexedDB eviction / incognito detection + export/import) is ROADMAP — it needs the web build and
## a settings UI; this slice covers the local atomic-save + recovery behaviour (AC-5.11.3/4).
##
## ACs: AC-5.11.3 (atomic write + backup + recovery), AC-5.11.4 (autosave at boundaries — the
##      callers decide WHEN; this provides the durable WRITE).

const DEFAULT_PRIMARY := "user://mining_game_save.json"

var _primary: String
var _backup: String
var _tmp: String

## True when the last load() fell all the way through to a clean default because BOTH the primary
## and the backup were unreadable (a real corruption event the UI should warn about, non-destructively).
var last_recovered_with_warning: bool = false

func _init(primary_path: String = DEFAULT_PRIMARY) -> void:
	_primary = primary_path
	_backup = primary_path + ".bak"
	_tmp = primary_path + ".tmp"

## Atomically persist `state`. Sequence: write the full new content to a temp file; roll the
## current good primary → backup; rename temp → primary (an atomic FS replace). A crash at any
## point leaves either the old primary intact (rename not yet done) or the new one (rename done) —
## never a half-written primary — and the previous good save survives as the backup (AC-5.11.3).
func save_state(state: Dictionary) -> bool:
	var f := FileAccess.open(_tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(SaveCodec.encode(state))
	f.close()
	# Roll the current good save to backup BEFORE replacing it.
	if FileAccess.file_exists(_primary):
		DirAccess.copy_absolute(_primary, _backup)
	# Atomic replace. rename may not overwrite on every platform, so remove first if needed.
	if FileAccess.file_exists(_primary):
		DirAccess.remove_absolute(_primary)
	return DirAccess.rename_absolute(_tmp, _primary) == OK

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

## True if a primary save file exists (a returning player vs a fresh game).
func has_save() -> bool:
	return FileAccess.file_exists(_primary)

## Remove the save, backup, and any stray temp (a "reset progress" action / test teardown).
func clear() -> void:
	for p: String in [_primary, _backup, _tmp]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
