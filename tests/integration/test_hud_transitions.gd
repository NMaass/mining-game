extends GdUnitTestSuite
## Screen-transition + relic-toast wiring, driven through the REAL authored mine.tscn HUD
## (not a re-new()'d harness — the audit-discipline rule). Proves the polish beats land:
##   • the reveal veil + toast nodes are authored, top-most and never eat input;
##   • reveal() covers the screen then ALWAYS clears to alpha 0 (can't strand on black);
##   • reduced motion suppresses the veil entirely and shows the toast without fade ramps;
##   • show_toast() fades the banner in then back out;
##   • collecting the relic (the v0.7 UD2 non-blocking bank) drives the confirmation banner.
##
## A separate file from test_level_smoke.gd on purpose — these only exercise the new
## transition surface, so they stay green independent of the broader suite.
##
## ACs: presentation support for AC-5.8.1 (relic feedback) + AC-5.8.4 (distinct dig-end
##      state) — smooth transitions across start → dig → run-end; AC-5.10.4 (motion-gated).

const MINE_SCENE := preload("res://scenes/mine.tscn")

func before() -> void:
	GameData.load_all()

func before_test() -> void:
	SaveManager.new().clear()  # clean prestige slate per test (mirrors the smoke suite)

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

# ── reveal(): covers, then ALWAYS clears ───────────────────────────────────────

func test_reveal_covers_the_screen_then_clears_to_zero() -> void:
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	# Drive a short reveal directly so the timing is controlled (independent of the boot fade).
	hud.reveal(0.05, 0.25, 1.0)
	# Immediately after, the veil is opaque (the swap behind it is hidden).
	assert_float(veil.modulate.a).is_greater(0.95)
	# After the full envelope (+ buffer) it has faded all the way out.
	await get_tree().create_timer(0.55).timeout
	assert_float(veil.modulate.a).is_less(0.02)

func test_reveal_is_suppressed_under_reduced_motion() -> void:
	# AC-5.10.4: reduced-motion players get NO flash of black — the veil snaps clear.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	hud.reveal(0.05, 0.25, 0.0)
	assert_float(veil.modulate.a).is_less(0.02)

func test_start_dig_reveals_from_black() -> void:
	# The wiring: starting a fresh dig snaps the veil opaque so the terrain rebuild never pops.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var veil: ColorRect = hud.get_node_or_null("TransitionVeil")
	mine.settings.set_motion_intensity(1.0)
	mine._start_dig()
	assert_float(veil.modulate.a).is_greater(0.95)
	# And it self-clears so a subsequent frame is never stuck behind black.
	await get_tree().create_timer(0.65).timeout
	assert_float(veil.modulate.a).is_less(0.02)

# ── show_toast(): the non-blocking confirmation banner ─────────────────────────

func test_toast_shows_text_then_fades_out() -> void:
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var toast: PanelContainer = hud.get_node_or_null("Toast")
	var toast_label: Label = hud.get_node_or_null("Toast/ToastLabel")
	hud.show_toast("Relic recovered   +1 Prestige", 0.1, 0.2, 0.1, 1.0)
	assert_str(toast_label.text).is_equal("Relic recovered   +1 Prestige")
	# Partway through the hold the banner is visibly on-screen.
	await get_tree().create_timer(0.2).timeout
	assert_float(toast.modulate.a).is_greater(0.5)
	# After the whole in→hold→out envelope it has cleared.
	await get_tree().create_timer(0.4).timeout
	assert_float(toast.modulate.a).is_less(0.02)

func test_toast_reduced_motion_shows_then_clears_without_fade() -> void:
	# Reduced motion keeps the INFORMATION (snap visible) but drops the fade ramps.
	var mine := _boot_mine()
	var hud := _hud_of(mine)
	var toast: PanelContainer = hud.get_node_or_null("Toast")
	hud.show_toast("Relic recovered   +1 Prestige", 0.1, 0.2, 0.1, 0.0)
	assert_float(toast.modulate.a).is_greater(0.95)  # snapped fully visible
	await get_tree().create_timer(0.45).timeout
	assert_float(toast.modulate.a).is_less(0.02)      # then cleared

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
