extends GdUnitTestSuite
## UNIT INFRA — Logger pure core (level filtering + formatting). The diagnostics autoload
## (scripts/systems/logger.gd) splits into a PURE static core (no Node/FileAccess/OS deps) and a thin
## side-effecting file/console layer. Injected InputEvents / file I/O are out of scope for headless
## unit tests; the spec's rule is "test the pure functions". These exercise the three pure entry
## points — level_from_name (config string → enum), should_log (the single emit gate), and
## format_line (the on-disk/console line shape) — plus the OFF threshold sentinel and the
## clamp/fail-open edge cases that keep diagnostics from silently disappearing on bad input.
##
## Preloaded so the script resolves under a cold class cache (CLAUDE.md tools convention).
##
## ACs: developer infrastructure (supports AC-5.2.9 — the perf/diagnostics surface — and the
## crash-evidence goal); no player-facing AC. The gate it protects: a config typo or an out-of-range
## level must never disable logging entirely (fail open), and OFF must suppress everything.

const LogScript := preload("res://scripts/systems/logger.gd")

# ── level_from_name (config string → enum; case-insensitive; fail-open) ──────

func test_level_from_name_maps_each_canonical_tag() -> void:
	# Every tag in LEVEL_TAGS round-trips to its enum index (the config contract the data gate enforces).
	assert_int(LogScript.level_from_name("DEBUG")).is_equal(LogScript.Level.DEBUG)
	assert_int(LogScript.level_from_name("INFO")).is_equal(LogScript.Level.INFO)
	assert_int(LogScript.level_from_name("WARN")).is_equal(LogScript.Level.WARN)
	assert_int(LogScript.level_from_name("ERROR")).is_equal(LogScript.Level.ERROR)
	assert_int(LogScript.level_from_name("OFF")).is_equal(LogScript.Level.OFF)

func test_level_from_name_is_case_and_whitespace_insensitive() -> void:
	# A config value like " info " or "Error" must still resolve (tolerant parsing of hand-edited JSON).
	assert_int(LogScript.level_from_name(" info ")).is_equal(LogScript.Level.INFO)
	assert_int(LogScript.level_from_name("Error")).is_equal(LogScript.Level.ERROR)

func test_level_from_name_unknown_fails_open_to_debug() -> void:
	# A typo must NOT silently disable diagnostics — unknown fails OPEN to the most-verbose level so
	# everything is still captured (the opposite, failing to OFF, is the dangerous regression).
	assert_int(LogScript.level_from_name("verbose")).is_equal(LogScript.Level.DEBUG)
	assert_int(LogScript.level_from_name("")).is_equal(LogScript.Level.DEBUG)

# ── should_log (the single emit gate shared by the autoload + every consumer) ──

func test_should_log_emits_at_or_above_threshold() -> void:
	# At threshold INFO: INFO/WARN/ERROR emit, DEBUG is filtered out.
	var t: int = LogScript.Level.INFO
	assert_bool(LogScript.should_log(LogScript.Level.DEBUG, t)).is_false()
	assert_bool(LogScript.should_log(LogScript.Level.INFO, t)).is_true()
	assert_bool(LogScript.should_log(LogScript.Level.WARN, t)).is_true()
	assert_bool(LogScript.should_log(LogScript.Level.ERROR, t)).is_true()

func test_should_log_debug_threshold_emits_everything() -> void:
	# Threshold DEBUG (the chatty dev default) emits every real level.
	var t: int = LogScript.Level.DEBUG
	assert_bool(LogScript.should_log(LogScript.Level.DEBUG, t)).is_true()
	assert_bool(LogScript.should_log(LogScript.Level.ERROR, t)).is_true()

func test_should_log_off_threshold_suppresses_everything() -> void:
	# Threshold OFF is the kill switch — even an ERROR is suppressed (release-silent mode).
	var t: int = LogScript.Level.OFF
	assert_bool(LogScript.should_log(LogScript.Level.DEBUG, t)).is_false()
	assert_bool(LogScript.should_log(LogScript.Level.ERROR, t)).is_false()

func test_should_log_off_is_never_a_message_level() -> void:
	# OFF is a threshold sentinel only — a message claiming level OFF (or anything out of range) is
	# never emitted, regardless of threshold (guards a caller passing a bogus level).
	assert_bool(LogScript.should_log(LogScript.Level.OFF, LogScript.Level.DEBUG)).is_false()
	assert_bool(LogScript.should_log(-1, LogScript.Level.DEBUG)).is_false()
	assert_bool(LogScript.should_log(99, LogScript.Level.DEBUG)).is_false()

# ── format_line (the on-disk / console line shape) ───────────────────────────

func test_format_line_shape() -> void:
	# "[TAG] tag: message" — deterministic + timestamp-free so the pure body is golden-stable (the
	# autoload prepends engine ticks only when it writes to the file).
	assert_str(LogScript.format_line(LogScript.Level.WARN, "Mine", "boot fell back")) \
		.is_equal("[WARN] Mine: boot fell back")
	assert_str(LogScript.format_line(LogScript.Level.ERROR, "Save", "write failed")) \
		.is_equal("[ERROR] Save: write failed")

func test_format_line_clamps_out_of_range_level() -> void:
	# An out-of-range level clamps into the tag table rather than indexing past the end (never crash a
	# log call on a bad level — diagnostics must be the most robust path).
	assert_str(LogScript.format_line(-5, "T", "m")).is_equal("[DEBUG] T: m")
	assert_str(LogScript.format_line(99, "T", "m")).is_equal("[OFF] T: m")

func test_level_tags_align_with_enum() -> void:
	# Structural invariant: the tag table indexes by the enum value (a reorder of one without the other
	# would silently mislabel every line). Assert the alignment the formatter relies on.
	assert_str(LogScript.LEVEL_TAGS[LogScript.Level.DEBUG]).is_equal("DEBUG")
	assert_str(LogScript.LEVEL_TAGS[LogScript.Level.INFO]).is_equal("INFO")
	assert_str(LogScript.LEVEL_TAGS[LogScript.Level.WARN]).is_equal("WARN")
	assert_str(LogScript.LEVEL_TAGS[LogScript.Level.ERROR]).is_equal("ERROR")
	assert_str(LogScript.LEVEL_TAGS[LogScript.Level.OFF]).is_equal("OFF")
