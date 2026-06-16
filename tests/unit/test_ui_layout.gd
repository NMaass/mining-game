extends GdUnitTestSuite
## U10 — UiLayout: pure portrait-HUD safe-area math (AC-5.8.5 / AC-5.8.6).
##
## The safety-critical question "do the controls land inside the device safe area" is
## proven HERE, headless, against synthetic device profiles (notch phone, gesture-bar
## phone, inset-free desktop/web) — because DisplayServer returns no insets in a headless
## run, so a live test can't exercise a notch. hud.gd feeds these same UiLayout functions
## live DisplayServer metrics; the integration test drives the HUD with the same profiles.
##
## ACs: AC-5.8.5 (bottom controls above the home-indicator/gesture zone; top below the
##      notch; >= ~44–48px touch targets), AC-5.8.6 (reflow across viewport sizes).

const Layout := preload("res://scripts/core/ui_layout.gd")

const LOGICAL := Vector2i(720, 1280)
const BASE_MARGIN := 24.0

# ── No-inset desktop/web → every inset is exactly the base margin ───────────────

func test_no_inset_falls_back_to_base_margin() -> void:
	# AC-5.8.5: on a target with no reported insets (safe == full window), every side gets
	# the data-driven base edge margin — controls never sit flush to the edge.
	var window := Vector2i(720, 1280)
	var safe := Rect2i(0, 0, 720, 1280)
	var ins: Dictionary = Layout.safe_insets(window, safe, LOGICAL, BASE_MARGIN)
	assert_float(ins["top"]).is_equal_approx(BASE_MARGIN, 0.001)
	assert_float(ins["bottom"]).is_equal_approx(BASE_MARGIN, 0.001)
	assert_float(ins["left"]).is_equal_approx(BASE_MARGIN, 0.001)
	assert_float(ins["right"]).is_equal_approx(BASE_MARGIN, 0.001)

func test_desktop_window_smaller_than_screen_safe_area() -> void:
	# A desktop windowed game: get_display_safe_area() can report the whole MONITOR while the
	# window is small, so the computed bottom_px would go negative — it must clamp to the base
	# margin, never produce a negative inset.
	var window := Vector2i(720, 1280)
	var safe := Rect2i(0, 0, 2560, 1440)  # full monitor, larger than the window
	var ins: Dictionary = Layout.safe_insets(window, safe, LOGICAL, BASE_MARGIN)
	assert_float(ins["bottom"]).is_equal_approx(BASE_MARGIN, 0.001)
	assert_float(ins["right"]).is_equal_approx(BASE_MARGIN, 0.001)

# ── iPhone-class notch + home indicator (portrait) ─────────────────────────────

func test_notch_phone_top_and_bottom_insets_exceed_margin() -> void:
	# AC-5.8.5: a notched phone (top notch + bottom home indicator) yields top + bottom insets
	# that exceed the base margin, scaled into the HUD's logical space. Profile: 1170x2532
	# physical, safe rect inset 141px at top and 135px at bottom (representative iPhone metrics).
	var window := Vector2i(1170, 2532)
	var safe := Rect2i(0, 141, 1170, 2256)  # bottom inset = 2532 - (141+2256) = 135
	var ins: Dictionary = Layout.safe_insets(window, safe, LOGICAL, BASE_MARGIN)
	var ratio_y: float = 1280.0 / 2532.0
	assert_float(ins["top"]).is_equal_approx(141.0 * ratio_y, 0.5)
	assert_float(ins["bottom"]).is_equal_approx(135.0 * ratio_y, 0.5)
	# Both must exceed the base margin (the device inset is the binding constraint here).
	assert_bool(ins["top"] > BASE_MARGIN).is_true()
	assert_bool(ins["bottom"] > BASE_MARGIN).is_true()
	# No side notch in portrait → left/right floor to the base margin.
	assert_float(ins["left"]).is_equal_approx(BASE_MARGIN, 0.001)
	assert_float(ins["right"]).is_equal_approx(BASE_MARGIN, 0.001)

func test_android_gesture_bar_bottom_only() -> void:
	# AC-5.8.5: an Android gesture-nav bar insets only the bottom; the top floors to the base
	# margin (no notch). Profile: 1080x2400, safe rect 90px shorter at the bottom.
	var window := Vector2i(1080, 2400)
	var safe := Rect2i(0, 0, 1080, 2310)  # bottom inset = 90
	var ins: Dictionary = Layout.safe_insets(window, safe, LOGICAL, BASE_MARGIN)
	assert_bool(ins["bottom"] > BASE_MARGIN).is_true()
	assert_float(ins["top"]).is_equal_approx(BASE_MARGIN, 0.001)

func test_larger_device_inset_overrides_base_margin() -> void:
	# The floor is a MAX: a device inset larger than the base margin wins; a smaller one is
	# raised to the base margin. Tiny 1px bottom inset → base margin; huge inset → the inset.
	var window := Vector2i(720, 1280)
	var tiny := Layout.safe_insets(window, Rect2i(0, 0, 720, 1279), LOGICAL, BASE_MARGIN)
	assert_float(tiny["bottom"]).is_equal_approx(BASE_MARGIN, 0.001)  # 1px < margin → margin
	var huge := Layout.safe_insets(window, Rect2i(0, 0, 720, 1180), LOGICAL, BASE_MARGIN)
	assert_bool(huge["bottom"] > BASE_MARGIN).is_true()  # 100px > margin → the inset

# ── Bottom strip span clears the gesture zone ──────────────────────────────────

func test_bottom_strip_sits_above_bottom_inset() -> void:
	# AC-5.8.5: a bottom-anchored control strip's bottom edge sits at logical.y - bottom inset
	# (clear of the home-indicator zone), and the strip is strip_h tall above that.
	var ins := {"top": 24.0, "bottom": 70.0, "left": 24.0, "right": 24.0}
	var span: Dictionary = Layout.bottom_strip_span(LOGICAL, ins, 82.0)
	assert_float(span["bottom"]).is_equal_approx(1280.0 - 70.0, 0.001)
	assert_float(span["top"]).is_equal_approx(1280.0 - 70.0 - 82.0, 0.001)
	# The whole strip is inside the safe region (above the bottom inset).
	assert_bool(span["bottom"] <= 1280.0 - ins["bottom"]).is_true()

# ── Touch-target predicate (AC-5.8.5) ──────────────────────────────────────────

func test_meets_touch_target() -> void:
	assert_bool(Layout.meets_touch_target(Vector2(48, 48), 48.0)).is_true()
	assert_bool(Layout.meets_touch_target(Vector2(96, 64), 48.0)).is_true()
	# Below the floor on either axis fails.
	assert_bool(Layout.meets_touch_target(Vector2(40, 48), 48.0)).is_false()
	assert_bool(Layout.meets_touch_target(Vector2(48, 40), 48.0)).is_false()

func test_reflows_with_viewport_size() -> void:
	# AC-5.8.6: the same device inset produces a different logical inset as the logical viewport
	# changes (the HUD reflows to the viewport, not a fixed 1280). A shorter viewport scales the
	# bottom inset down proportionally.
	var window := Vector2i(1080, 2400)
	var safe := Rect2i(0, 0, 1080, 2310)  # 90px bottom inset
	var tall := Layout.safe_insets(window, safe, Vector2i(720, 1280), BASE_MARGIN)
	var short := Layout.safe_insets(window, safe, Vector2i(720, 640), BASE_MARGIN)
	# Half the logical height → half the logical inset (same physical 90px bar).
	assert_float(short["bottom"]).is_equal_approx(tall["bottom"] * 0.5, 0.5)
