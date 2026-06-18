extends Node
## GameData — single source of truth for all tunables.
## Loads schema-validated JSON from res://data/ at startup and exposes typed accessors.
## Balance is NEVER hardcoded; everything here comes from /data. See AGENTS.md.

const DATA_DIR := "res://data/"

## Raw loaded tables, keyed by file stem (e.g. "block_types").
var tables: Dictionary = {}
var load_errors: Array[String] = []

func _ready() -> void:
	load_all()

## Loads every *.json in DATA_DIR (ignoring the schemas/ subfolder).
## Returns true if all files loaded and parsed; records problems in load_errors.
func load_all() -> bool:
	tables.clear()
	load_errors.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		# No data dir yet (early scaffolding) — not fatal for the harness.
		return true
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var stem := file_name.get_basename()
		var parsed: Variant = _load_json(DATA_DIR + file_name)
		if parsed == null:
			load_errors.append("Failed to parse %s" % file_name)
			continue
		tables[stem] = parsed
	# Surface any parse failures through the Logger so a malformed table in the field leaves
	# evidence on disk instead of silently dropping (then crashing later with a confusing
	# null-deref far from the cause). Behavior is unchanged — the same bool/array are returned;
	# this only ADDS a log breadcrumb. Logger may not be ready yet under some boot orders, so it
	# is looked up defensively (get_node_or_null) and skipped if absent.
	if not load_errors.is_empty():
		var logger: Node = get_node_or_null("/root/GameLog")
		if logger != null and logger.has_method("report_error"):
			logger.call("report_error", "GameData", "data load errors: %s" % str(load_errors))
	return load_errors.is_empty()

func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	if err != OK:
		return null
	return json.data

## Convenience accessor; returns {} if the table is absent.
func table(stem: String) -> Variant:
	return tables.get(stem, {})
