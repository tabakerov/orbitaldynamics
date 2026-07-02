extends Node

const SurvivalLevelScene = preload("res://scenes/levels/level_survival.tscn")


func _ready() -> void:
	await _test_structure_and_absorption_flow()
	print("All survival level tests passed!")
	get_tree().quit()


func _test_structure_and_absorption_flow() -> void:
	var level := SurvivalLevelScene.instantiate() as Level
	add_child(level)

	var hole: BlackHole = null
	for body in level.get_celestial_bodies():
		if body is BlackHole:
			hole = body
	assert(hole != null, "Survival level should contain a black hole.")
	assert(hole.stationary, "The black hole should be stationary.")
	assert(level.get_ship() != null, "Survival level should contain a ship.")
	assert(level.get_score_tracker() != null, "Survival level should track score.")

	var spawners := level.get_spawners()
	assert(spawners.size() == 1, "Survival level should have one spawner.")
	var spawner := spawners[0]
	assert(spawner.entries.size() == 3, "Spawner should have fuel, star and asteroid entries.")
	print("  PASS: survival level structure")

	# Fast-forward the spawner: objects appear and inherit gravity.
	spawner.tick(30.0)
	var objects := level.get_floating_objects()
	assert(objects.size() > 0, "Spawner should produce objects after 30s.")
	for object in objects:
		assert(object.gravity_affected, "Survival entries should enable gravity on spawn.")
	print("  PASS: spawner fast-forward produces gravity-affected objects")

	# Park one object on the hole: real physics contact should absorb it
	# (deferred handler) and grow the hole.
	var radius_before: float = hole.body_data.radius
	var object := objects[0]
	object.gravity_affected = false
	object.velocity = Vector3.ZERO
	object.global_position = hole.global_position
	for i in 10:
		await get_tree().physics_frame
	assert(
		not is_instance_valid(object) or object.is_queued_for_deletion(),
		"Object parked on the hole should be absorbed.",
	)
	assert(
		hole.body_data.radius > radius_before,
		"Absorbed mass should grow the hole. Radius: %f" % hole.body_data.radius,
	)
	print("  PASS: physics contact absorbs object and grows the hole")

	level.queue_free()
	await level.tree_exited
	CelestialSim.clear()
