extends SceneTree
## Headless data-integrity gate. Loads every /data table and runs DataValidator.
## Preloaded (not via class_name) so it works even before the global class cache is built.
const Validator := preload("res://scripts/core/data_validator.gd")
##
## Exit 0 = valid, Exit 1 = errors found. Wired into CI and runnable by workflows:
##   godot --headless --path . -s res://tools/validate_data.gd
##
## This is the SPEC §7 data-validation gate as an executable.

func _init() -> void:
	var tables := _load_all("res://data/")
	var errors: Array = Validator.validate(tables)
	if errors.is_empty():
		print("DATA OK: %d tables validated." % tables.size())
		quit(0)
		return
	push_error("DATA VALIDATION FAILED (%d issue(s)):" % errors.size())
	for e in errors:
		print("  - %s" % e)
	print("DATA VALIDATION FAILED: %d issue(s)." % errors.size())
	quit(1)

func _load_all(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open(dir_path + file_name, FileAccess.READ)
		if f == null:
			continue
		var json := JSON.new()
		if json.parse(f.get_as_text()) == OK:
			out[file_name.get_basename()] = json.data
		else:
			print("  - parse error in %s: %s (line %d)" % [file_name, json.get_error_message(), json.get_error_line()])
	return out
