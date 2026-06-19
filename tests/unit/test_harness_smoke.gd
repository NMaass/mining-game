extends GdUnitTestSuite
## Smoke test proving the headless gdUnit4 harness runs.
## Acceptance: this passes under `tools/run_tests.sh` with no editor open.

func test_game_data_autoload_present() -> void:
	# GameData autoload should exist and expose its API even with no /data yet.
	var gd: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("GameData")
	assert_object(gd).is_not_null()
	assert_bool(gd.has_method("load_all")).is_true()
