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
	assert(spawners.size() == 2, "Survival level should have a ring spawner and a bonus eruption spawner.")
	var ring_spawner: ObjectSpawner = null
	var eruption_spawner: ObjectSpawner = null
	for spawner in spawners:
		if spawner.volume_shape == ObjectSpawner.VolumeShape.AROUND_SOURCE:
			eruption_spawner = spawner
		else:
			ring_spawner = spawner
	assert(ring_spawner != null, "Survival level should have a ring spawner for fuel and asteroids.")
	assert(ring_spawner.entries.size() == 2, "Ring spawner should have fuel and asteroid entries.")
	assert(eruption_spawner != null, "Survival level should have a bonus eruption spawner around the black hole.")
	assert(eruption_spawner.entries.size() == 1, "Eruption spawner should have one bonus star entry.")
	assert(
		eruption_spawner.get_parent() == hole,
		"Eruption spawner should be nested under the black hole so it tracks its position and growth.",
	)
	var eruption_entry := eruption_spawner.entries[0]
	assert(
		eruption_entry.radial_speed_mode == SpawnEntry.RadialSpeedMode.TURNAROUND_AT_RANGE,
		"Bonus entry should use the turnaround launch mode.",
	)
	print("  PASS: survival level structure")

	# Fast-forward both spawners: objects appear and inherit gravity.
	ring_spawner.tick(30.0)
	eruption_spawner.tick(30.0)
	var objects := level.get_floating_objects()
	assert(objects.size() > 0, "Spawners should produce objects after 30s.")
	for object in objects:
		assert(object.gravity_affected, "Survival entries should enable gravity on spawn.")
	var erupted_stars := objects.filter(func(o: FloatingObject) -> bool: return o is BonusStar)
	assert(erupted_stars.size() > 0, "The eruption spawner should have produced bonus stars.")
	for star: FloatingObject in erupted_stars:
		var r := star.global_position.distance_to(hole.global_position)
		assert(
			r <= eruption_spawner.source_surface_margin + hole.body_data.radius + 0.01,
			"Bonus stars should erupt from the hole's surface. Distance: %f" % r,
		)
	print("  PASS: spawner fast-forward produces gravity-affected objects, bonuses erupt from the hole")

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
