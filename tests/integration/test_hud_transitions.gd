extends GdUnitTestSuite
## Screen-transition + relic-toast WIRING, driven through the REAL authored mine.tscn HUD
## (not a re-new()'d harness — the audit-discipline rule). Proves the polish beats land:
##   • the reveal veil + toast nodes are authored, top-most and never eat input;
##   • reveal()/show_toast() set the correct SYNCHRONOUS entry state (opaque veil / snapped
##     reduced-motion banner / transparent full-motion banner / suppressed-under-reduced-motion);
##   • the runtime alpha binding (the tween_method callbacks _set_veil_alpha / _set_toast_alpha,
##     evaluated against the captured durations) maps elapsed → alpha correctly and ALWAYS lands
##     at 0 — proven DETERMINISTICALLY by calling those callbacks with explicit elapsed times, so
##     there is no flaky wall-clock await in a shared, loaded SceneTree;
##   • collecting the relic (the v0.7 UD2 non-blocking bank) drives the confirmation banner.
##
## The alpha CURVE itself (ramps, plateau, monotonicity, endpoints) is exhaustively pinned in the
## pure unit suite test_screen_transition.gd; this file proves the HUD is wired to that curve.
## A separate file from test_level_smoke.gd on purpose — order-independent, no shared-state deps.
##
## ACs: presentation support for AC-5.8.1 (relic feedback) + AC-5.8.4 (distinct dig-end state) —
##      smooth transitions across start → dig → run-end; AC-5.10.4 (motion-gated).

const MINE_SCENE := preload("res://scenes/mine.tscn")

func before() -> void:
	GameData.load_all()

func before_test() -> void:
	SaveManager.new().clear()  # clean prestige slate per test (mirrors the smoke suite)
	# Defensive: a PRIOR suite (e.g. the Settings-overlay tests) shares the SceneTree and could
	# leave it paused or time-scaled. Reset both so this suite is fully order-independent.
	if get_tree() != null:
		get_tree().paused = false
	Engine.time_scale = 1.0

func after_test() -> void:
	if get_tree() != null:
		get_tree().paused = false
	Engine.time_scale = 1.0

func after() -> void:
	SaveManager.new().clear()

func _boot_mine() -> Mine:
	var mine: Mine = MINE_SCENE.instantiate()
	add_child(mine)          # runs _ready → boot() → _start_dig(true)
	auto_free(mine)
	return mine

func _hud_of(mine: Mine) -> Hud:
	return mine.get_node_or_null("Hud") as Hud

# ── Authored nodes: present, top-most, non-interactive ─────────────────────────

func test_transition_nodes_are_authored_and_ignore_input() -> void:
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	var toast: PanelContainer = hud.get_node_or_null("Toast")
	var toast_label: Label = hud.get_node_or_null("Toast/ToastLabel")
	assert_object(veil).is_not_null()
	assert_object(toast).is_not_null()
	assert_object(toast_label).is_not_null()
	# Neither effect may ever swallow a touch (mouse_filter IGNORE == 2).
	assert_int(veil.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(toast.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	# The veil must draw ABOVE the rest of the HUD (last child = top-most in a CanvasLayer).
	assert_int(veil.get_index()).is_equal(hud.get_child_count() - 1)

# ── reveal(): covers synchronously; the runtime binding lands at 0 ─────────────

func test_reveal_covers_the_screen_synchronously() -> void:
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	hud.reveal(0.05, 0.25, 1.0)
	# Immediately after, the veil is opaque (the state swap behind it is hidden) — synchronous,
	# set before any tween frame, so this is order/load-independent.
	assert_float(veil.modulate.a).is_greater(0.95)

func test_reveal_runtime_binding_holds_then_lands_at_zero() -> void:
	# Drive the live tween callback (_set_veil_alpha) directly with explicit elapsed times — proves
	# the HUD evaluates the pure reveal envelope against the durations it captured, and ALWAYS clears.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	hud.reveal(0.05, 0.25, 1.0)        # hold 0.05, out 0.25 → total 0.30
	hud._set_veil_alpha(0.0)
	assert_float(veil.modulate.a).is_greater(0.95)   # opaque at t=0
	hud._set_veil_alpha(0.30)
	assert_float(veil.modulate.a).is_less(0.02)       # cleared at the end — never strands on black

func test_reveal_is_suppressed_under_reduced_motion() -> void:
	# AC-5.10.4: reduced-motion players get NO flash of black — the veil snaps clear, no tween.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	hud.reveal(0.05, 0.25, 0.0)
	assert_float(veil.modulate.a).is_less(0.02)

func test_start_dig_reveals_from_black() -> void:
	# The WIRING: starting a fresh dig snaps the veil opaque so the terrain rebuild never pops.
	# Synchronous claim (reveal() sets alpha 1 before any tween); the clear-to-0 half is covered by
	# test_reveal_runtime_binding_holds_then_lands_at_zero — so no wall-clock await here.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	mine.settings.set_motion_intensity(1.0)
	mine._start_dig()
	assert_float(veil.modulate.a).override_failure_message(
		"_start_dig must reveal-from-black (veil opaque); got a=%s motion=%s"
		% [str(veil.modulate.a), str(mine.settings.motion_intensity)]
	).is_greater(0.95)

# ── show_toast(): the non-blocking confirmation banner ─────────────────────────

func test_toast_full_motion_sets_text_and_starts_transparent() -> void:
	# Under full motion the banner FADES IN, so it begins transparent and shows its text. The fade
	# itself is the pure curve (test_screen_transition); here we prove the synchronous entry state.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var toast: PanelContainer = hud.get_node_or_null("Toast")
	var toast_label: Label = hud.get_node_or_null("Toast/ToastLabel")
	hud.show_toast("Relic recovered   +1 Prestige", 0.1, 0.2, 0.1, 1.0)
	assert_str(toast_label.text).is_equal("Relic recovered   +1 Prestige")
	assert_float(toast.modulate.a).is_less(0.05)   # starts transparent (fade-in)

func test_toast_runtime_binding_holds_then_lands_at_zero() -> void:
	# Drive the live tween callback (_set_toast_alpha) directly: full at the hold plateau, clear at
	# the end. Deterministic proof the banner reaches peak then always fades out (no stuck banner).
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var toast: PanelContainer = hud.get_node_or_null("Toast")
	hud.show_toast("Relic recovered   +1 Prestige", 0.1, 0.2, 0.1, 1.0)  # in.1 hold.2 out.1 → 0.4
	hud._set_toast_alpha(0.2)
	assert_float(toast.modulate.a).is_greater(0.95)   # full on the hold plateau
	hud._set_toast_alpha(0.4)
	assert_float(toast.modulate.a).is_less(0.02)       # cleared at the end

func test_toast_reduced_motion_snaps_visible_with_text() -> void:
	# Reduced motion keeps the INFORMATION (snap fully visible) but drops the fade ramps.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var toast: PanelContainer = hud.get_node_or_null("Toast")
	var toast_label: Label = hud.get_node_or_null("Toast/ToastLabel")
	hud.show_toast("Relic recovered   +1 Prestige", 0.1, 0.2, 0.1, 0.0)
	assert_float(toast.modulate.a).is_greater(0.95)
	assert_str(toast_label.text).is_equal("Relic recovered   +1 Prestige")

# ── relic collection drives the toast (the UD2 non-blocking bank) ──────────────

func test_relic_collection_drives_confirmation_toast() -> void:
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var toast_label: Label = hud.get_node_or_null("Toast/ToastLabel")
	mine.settings.set_motion_intensity(1.0)
	# Collect the relic (the v0.7 UD2 non-blocking path). This drives the confirmation banner.
	mine._on_relic_collected(Vector2i(0, 120))
	# The non-blocking banner spells out what happened (the exact prestige count it shows is
	# whatever _last_banked resolves to — the wiring under test is "relic → toast with the
	# recovery message", independent of the run_state banking reconciliation still in flight).
	assert_str(toast_label.text).contains("Relic recovered")
	assert_str(toast_label.text).contains("Prestige")
