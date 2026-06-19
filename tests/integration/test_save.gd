extends GdUnitTestSuite
## U20 — SaveManager (atomic file write + rolling backup + recovery chain) and the durable-state
## round-trip through Prestige. Touches the FS (a throwaway user:// path), so it's an integration
## suite. Proves AC-5.11.3 (atomic write, backup, recovery) + AC-5.11.4-write + AC-5.11.1 round-trip.
##
## ACs: AC-5.11.1 (persist prestige), AC-5.11.3 (atomic + backup + corrupt→backup→default recovery).

const Manager := preload("res://scripts/systems/save_manager.gd")
const Codec := preload("res://scripts/core/save_codec.gd")

var TEST_PATH: String

func _mgr() -> SaveManager:
	return Manager.new(TEST_PATH)

func _corrupt(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{{{ not valid json ,,,")
	f.close()

func before_test() -> void:
	TEST_PATH = OS.get_temp_dir().path_join("test_mining_save.json")
	_mgr().clear()

func after_test() -> void:
	_mgr().clear()

func test_round_trip_through_disk() -> void:
	# AC-5.11.1/5.11.3: save → a FRESH manager loads back the same durable state.
	var state := {"version": Codec.CURRENT_VERSION, "prestige": {"points": 17, "levels": {"blast_power": 2}}}
	assert_bool(_mgr().save_state(state)).is_true()
	var loaded: Dictionary = _mgr().load_state()
	assert_int(int(loaded["prestige"]["points"])).is_equal(17)
	assert_int(int(loaded["prestige"]["levels"]["blast_power"])).is_equal(2)

func test_write_is_atomic_no_temp_left() -> void:
	# AC-5.11.3: after a completed save the primary exists and NO temp file is observable (the
	# temp→rename completed; a partial primary is never left behind).
	_mgr().save_state(Codec.default_state())
	assert_bool(FileAccess.file_exists(TEST_PATH)).is_true()
	assert_bool(FileAccess.file_exists(TEST_PATH + ".tmp")).is_false()

func test_second_save_rolls_previous_into_backup() -> void:
	# AC-5.11.3: the backup holds the PREVIOUS good save (one rolling backup).
	var m := _mgr()
	m.save_state({"prestige": {"points": 1, "levels": {}}})
	m.save_state({"prestige": {"points": 2, "levels": {}}})
	# Primary = newest (2); backup = previous (1).
	assert_int(int(m.load_state()["prestige"]["points"])).is_equal(2)
	var backup_f := FileAccess.open(TEST_PATH + ".bak", FileAccess.READ)
	assert_object(backup_f).is_not_null()
	var backup: Dictionary = Codec.decode(backup_f.get_as_text())
	backup_f.close()
	assert_int(int(backup["prestige"]["points"])).is_equal(1)

func test_corrupt_primary_recovers_from_backup_without_warning() -> void:
	# AC-5.11.3: a corrupt primary falls back to the backup; recovering from backup is NOT a
	# data-loss warning (the previous good save is intact).
	var m := _mgr()
	m.save_state({"prestige": {"points": 5, "levels": {}}})  # becomes backup after next save
	m.save_state({"prestige": {"points": 6, "levels": {}}})  # primary=6, backup=5
	_corrupt(TEST_PATH)
	var loaded: Dictionary = m.load_state()
	assert_int(int(loaded["prestige"]["points"])).is_equal(5)  # recovered the backup
	assert_bool(m.last_recovered_with_warning).is_false()

func test_corrupt_primary_and_backup_recovers_clean_default_with_warning() -> void:
	# AC-5.11.3: both corrupt → clean default + a non-destructive warning flag.
	var m := _mgr()
	m.save_state({"prestige": {"points": 9, "levels": {}}})
	m.save_state({"prestige": {"points": 9, "levels": {}}})
	_corrupt(TEST_PATH)
	_corrupt(TEST_PATH + ".bak")
	var loaded: Dictionary = m.load_state()
	assert_int(int(loaded["prestige"]["points"])).is_equal(0)  # clean default
	assert_bool(m.last_recovered_with_warning).is_true()

func test_fresh_game_has_no_save_and_loads_default_without_warning() -> void:
	var m := _mgr()
	assert_bool(m.has_save()).is_false()
	var loaded: Dictionary = m.load_state()
	assert_int(int(loaded["prestige"]["points"])).is_equal(0)
	assert_bool(m.last_recovered_with_warning).is_false()  # a new game is not a corruption event

func test_prestige_durable_state_round_trips_through_save() -> void:
	# AC-5.11.1 end to end with the REAL durable state: bank + buy on one Prestige, save its snapshot,
	# load it into a fresh Prestige, and assert points + purchased levels + the derived dig multiplier
	# all survive (the power-growth hook persists across an app restart).
	GameData.load_all()
	var tables: Dictionary = GameData.tables
	var up_id: String = str(Registry.prestige_upgrade_ids(tables)[0])
	var p1 := Prestige.new(tables)
	p1.bank(1000)
	assert_bool(p1.buy_upgrade(up_id)).is_true()
	var mult_before: float = p1.blast_intensity_mult()

	_mgr().save_state({"prestige": p1.to_state()})

	var loaded: Dictionary = _mgr().load_state()
	var p2 := Prestige.new(tables)
	p2.from_state(loaded["prestige"])
	assert_int(p2.points).is_equal(p1.points)
	assert_int(p2.level(up_id)).is_equal(1)
	assert_float(p2.blast_intensity_mult()).is_equal(mult_before)
	assert_bool(mult_before > 1.0).override_failure_message(
		"the bought upgrade should raise the multiplier — otherwise the round-trip proves nothing"
	).is_true()

func test_manual_export_import_round_trips_save_text() -> void:
	# AC-5.11.5: manual export/import is a normalized JSON save path for web users whose IndexedDB
	# storage can be evicted or temporary.
	var m := _mgr()
	assert_bool(m.save_state({"prestige": {"points": 12, "levels": {"blast_power": 1}}})).is_true()
	var exported: String = m.export_save_text()
	assert_str(exported).contains("\"version\"")
	assert_str(exported).contains("\"prestige\"")

	m.clear()
	assert_bool(m.import_save_text(exported)).is_true()
	var loaded: Dictionary = m.load_state()
	assert_int(int(loaded["prestige"]["points"])).is_equal(12)
	assert_int(int(loaded["prestige"]["levels"]["blast_power"])).is_equal(1)

func test_manual_import_rejects_corrupt_json_without_overwriting() -> void:
	# AC-5.11.5: a pasted corrupt export must not clobber the existing good save.
	var m := _mgr()
	assert_bool(m.save_state({"prestige": {"points": 7, "levels": {}}})).is_true()
	assert_bool(m.import_save_text("{{{ nope")).is_false()
	assert_int(int(m.load_state()["prestige"]["points"])).is_equal(7)

func test_default_save_path_is_namespaced() -> void:
	# AC-5.11.5: web IndexedDB state is per-origin and evictable, so the shipped save path is
	# namespaced under the game instead of a flat user:// filename.
	var m := Manager.new(Manager.DEFAULT_PRIMARY)
	assert_str(m.primary_path()).is_equal(Manager.DEFAULT_PRIMARY)
	assert_str(m.primary_path()).contains("user://mining_game/")

func test_native_persistence_status_is_available() -> void:
	var status: Dictionary = Manager.persistence_status()
	assert_bool(bool(status.get("available"))).is_true()
	assert_str(str(status.get("warning", ""))).is_empty()
