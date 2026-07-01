extends SceneTree

const PVD = preload("res://scripts/planet_visual_data.gd")


func _init() -> void:
	_test_defaults()
	_test_biome_weights_nonzero()
	print("All PlanetVisualData tests passed!")
	quit()


func _test_defaults() -> void:
	var data := PVD.new()
	assert(data.sea_level >= 0.0 and data.sea_level <= 1.0, "sea_level should be in [0,1]")
	assert(data.mountain_intensity >= 0.0, "mountain_intensity should be non-negative")
	assert(data.cloud_coverage_lower >= 0.0 and data.cloud_coverage_lower <= 1.0, "cloud_coverage_lower in [0,1]")
	assert(data.cloud_coverage_upper >= 0.0 and data.cloud_coverage_upper <= 1.0, "cloud_coverage_upper in [0,1]")
	assert(data.atmosphere_density >= 0.0, "atmosphere_density should be non-negative")
	assert(data.atmosphere_radius >= 1.0, "atmosphere_radius must be >= 1.0")
	assert(data.atmosphere_steps >= 1, "atmosphere_steps must be >= 1")
	assert(data.noise_scale > 0.0, "noise_scale must be positive")
	print("  PASS: defaults valid")


func _test_biome_weights_nonzero() -> void:
	var data := PVD.new()
	var total := data.biome_vegetation + data.biome_sand + data.biome_rock
	assert(total > 0.0, "At least one biome weight must be > 0")
	print("  PASS: biome weights nonzero")
