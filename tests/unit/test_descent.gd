extends GdUnitTestSuite

func test_support_row_does_not_skip_solid_immediate_layer() -> void:
	var hp_grid: Dictionary = {}
	for x in range(3):
		hp_grid[Vector2i(x, 1)] = 10
		hp_grid[Vector2i(x, 2)] = 0
	assert_int(PlatformLogic.next_support_row(hp_grid, 0, 3, 2)).is_equal(0)

func test_support_row_advances_through_contiguous_cleared_layers() -> void:
	var hp_grid: Dictionary = {}
	for x in range(3):
		hp_grid[Vector2i(x, 1)] = 0
		hp_grid[Vector2i(x, 2)] = 0
		hp_grid[Vector2i(x, 3)] = 10
	assert_int(PlatformLogic.next_support_row(hp_grid, 0, 3, 3)).is_equal(2)
