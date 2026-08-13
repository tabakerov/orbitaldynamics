extends Node

## The off-screen target arrow carries the range to the target, so a pilot who
## cannot see the target still knows whether it is a nudge or a long burn away.

const ShipScene = preload("res://scenes/ship.tscn")
const TargetScene = preload("res://scenes/target.tscn")
const HudScene = preload("res://scenes/hud.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")


func _ready() -> void:
	_test_range_is_written_in_metres_then_kilometres()
	_test_indicator_reads_the_range_from_the_ship()
	print("All HUD tests passed!")
	get_tree().quit()


func _test_range_is_written_in_metres_then_kilometres() -> void:
	var indicator = _spawn_hud().get_node("TargetIndicator")

	assert(indicator.format_distance(0.0) == "0 м", "Zero should still read as metres.")
	assert(indicator.format_distance(29.3) == "29 м", "Short ranges round to whole metres.")
	assert(indicator.format_distance(999.4) == "999 м", "Just under a kilometre stays in metres.")
	assert(indicator.format_distance(1000.0) == "1.0 км", "A kilometre switches units.")
	assert(indicator.format_distance(2540.0) == "2.5 км", "Long ranges read in kilometres.")
	print("  PASS: range is written in metres then kilometres")


func _test_indicator_reads_the_range_from_the_ship() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)
	ship.global_position = Vector3(10.0, 0.0, 0.0)

	var target := TargetScene.instantiate() as Target
	add_child(target)
	target.global_position = Vector3(510.0, 0.0, 0.0)

	# Straight down at the ship: a target 500 m to the side is far off screen.
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(10.0, 60.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	var hud = _spawn_hud()
	hud.setup(ship, camera, target)
	hud._update_target_indicator()

	var indicator = hud.get_node("TargetIndicator")
	assert(indicator.visible, "A target this far off screen should raise the arrow.")
	assert(
		is_equal_approx(indicator.distance, 500.0),
		"The arrow should report the ship's distance to the target, got %f" % indicator.distance,
	)

	ship.global_position = Vector3(310.0, 0.0, 0.0)
	hud._update_target_indicator()
	assert(
		is_equal_approx(indicator.distance, 200.0),
		"Closing the gap should move the number, got %f" % indicator.distance,
	)
	print("  PASS: indicator reads the range from the ship")

	hud.queue_free()
	camera.queue_free()
	target.queue_free()
	ship.queue_free()


func _spawn_hud() -> Control:
	var hud := HudScene.instantiate() as Control
	add_child(hud)
	return hud
