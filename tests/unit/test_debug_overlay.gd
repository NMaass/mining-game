extends GdUnitTestSuite
## UNIT INFRA — DebugOverlay pure readout formatter (scripts/ui/debug_overlay.gd). The overlay's
## Node side gathers live engine/Mine/Logger stats into a plain Dictionary, then renders them through
## the PURE static `format_readout`. The viewport/Node half can't run headless (no GL, injected input
## doesn't fire), but the formatter is pure — so these drive it directly per the spec's
## "test pure functions" rule.
##
## The gate this protects: a partially-built gather (no Mine bound yet, no Logger) must still produce
## a stable, well-formed readout (absent keys → "—") rather than crashing the overlay or showing a raw
## null — exactly the boot-order edge the overlay exists to make visible.
##
## Preloaded so the class resolves under a cold cache.
##
## ACs: supports AC-5.2.9 (the FPS/frame-time line surfaces a perf regression). Otherwise developer
## infrastructure — no player-facing AC.

const DebugOverlay := preload("res://scripts/ui/debug_overlay.gd")

func test_format_readout_full_stats() -> void:
	# A complete gather renders every labelled row with the supplied values (seed/depth/charge/mine
	# come from the Mine controller; warn/err from the Logger; fps/frame_ms/bodies from the engine).
	var out: String = DebugOverlay.format_readout({
		"fps": 60, "frame_ms": 16.7, "bodies": 3,
		"seed": 12345, "depth": 8, "charge": "free_charge", "mine": "home",
		"warns": 1, "errors": 0,
	})
	assert_str(out).contains("fps      60  (16.7 ms)")
	assert_str(out).contains("bodies   3")
	assert_str(out).contains("seed     12345")
	assert_str(out).contains("depth    8")
	assert_str(out).contains("charge   free_charge")
	assert_str(out).contains("mine     home")
	assert_str(out).contains("warn/err 1 / 0")

func test_format_readout_absent_keys_render_dash() -> void:
	# Pre-boot / no-Mine-bound gather: only engine stats are present. The Mine/Logger rows degrade to
	# "—" so the readout stays well-formed instead of showing a raw null or crashing.
	var out: String = DebugOverlay.format_readout({"fps": 0, "frame_ms": 0.0, "bodies": 0})
	assert_str(out).contains("seed     —")
	assert_str(out).contains("depth    —")
	assert_str(out).contains("charge   —")
	assert_str(out).contains("mine     —")
	assert_str(out).contains("warn/err — / —")

func test_format_readout_empty_stats_is_stable() -> void:
	# An entirely empty dict (the gather found nothing) still produces a complete, header-led block —
	# never an exception, never a blank string. The FPS row is always present (label only here).
	var out: String = DebugOverlay.format_readout({})
	assert_str(out).contains("DEBUG (F3)")
	assert_int(out.split("\n").size()).is_equal(8)  # header + 7 stat rows, always

func test_format_readout_null_value_renders_dash() -> void:
	# A present-but-null value (e.g. a Mine method that returned null) renders "—", not "<null>".
	var out: String = DebugOverlay.format_readout({"seed": null, "fps": 60, "frame_ms": 16.7})
	assert_str(out).contains("seed     —")

func test_format_readout_frame_ms_one_decimal() -> void:
	# Frame time is formatted to one decimal (readable, not noisy) — the perf-regression signal.
	var out: String = DebugOverlay.format_readout({"fps": 30, "frame_ms": 33.333})
	assert_str(out).contains("(33.3 ms)")
