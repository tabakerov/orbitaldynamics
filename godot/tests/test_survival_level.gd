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
	var planet: Planet = null
	for body in level.get_celestial_bodies():
		if body is BlackHole:
			hole = body
		elif body is Planet:
			planet = body
	assert(hole != null, "Survival level should contain a black hole.")
	assert(hole.stationary, "The black hole should be stationary.")
	assert(planet != null, "Survival level should contain an orbiting planet.")
	assert(not planet.stationary, "The planet should move under orbital dynamics.")
	assert(
		planet.initial_velocity.length() > 0.0,
		"The planet should start with an orbital velocity.",
	)
	var ship := level.get_ship()
	assert(ship != null, "Survival level should contain a ship.")
	assert(
		ship.get_weapon_modules().size() == 1,
		"Survival ship should mount a weapon module instead of the front engine.",
	)
	assert(
		not (ship._modules.get(MountSlot.Binding.FRONT) is EngineModule),
		"The front mount should carry the gun, not an engine.",
	)
	var weapon := ship.get_weapon_modules()[0]
	assert(
		weapon.current_type == WeaponProfile.AmmoType.ROCKET,
		"The survival gun should start in rocket mode.",
	)
	assert(weapon.rocket_charges > 0, "The survival gun should start with rockets loaded.")
	assert(
		weapon.laser_charges == 0,
		"Lasers on the survival level should come from pickups only.",
	)
	assert(level.get_score_tracker() != null, "Survival level should track score.")

	var spawners := level.get_spawners()
	assert(
		spawners.size() == 3,
		"Survival level should have a fuel ring spawner, a bonus eruption spawner and a planet asteroid spawner.",
	)
	var ring_spawner: ObjectSpawner = null
	var eruption_spawner: ObjectSpawner = null
	var asteroid_spawner: ObjectSpawner = null
	for spawner in spawners:
		if spawner.volume_shape != ObjectSpawner.VolumeShape.AROUND_SOURCE:
			ring_spawner = spawner
		elif spawner.get_parent() == hole:
			eruption_spawner = spawner
		else:
			asteroid_spawner = spawner
	assert(ring_spawner != null, "Survival level should have a ring spawner for fuel.")
	assert(
		ring_spawner.entries.size() == 3,
		"Ring spawner should carry fuel, laser ammo and rocket ammo entries.",
	)
	var has_fuel := false
	var has_laser_ammo := false
	var has_rocket_ammo := false
	for entry: SpawnEntry in ring_spawner.entries:
		var sample := entry.scene.instantiate()
		if sample is FuelPickup:
			has_fuel = true
		elif sample is AmmoPickup:
			if sample.ammo_type == WeaponProfile.AmmoType.LASER:
				has_laser_ammo = true
			else:
				has_rocket_ammo = true
		sample.free()
	assert(has_fuel, "Ring spawner should still spawn fuel.")
	assert(has_laser_ammo, "Ring spawner should spawn laser ammo crates.")
	assert(has_rocket_ammo, "Ring spawner should spawn rocket ammo crates.")
	assert(eruption_spawner != null, "Survival level should have a bonus eruption spawner around the black hole.")
	assert(eruption_spawner.entries.size() == 1, "Eruption spawner should have one bonus star entry.")
	var eruption_entry := eruption_spawner.entries[0]
	assert(
		eruption_entry.radial_speed_mode == SpawnEntry.RadialSpeedMode.TURNAROUND_AT_RANGE,
		"Bonus entry should use the turnaround launch mode.",
	)
	assert(asteroid_spawner != null, "Survival level should have an asteroid spawner tracking the planet.")
	assert(asteroid_spawner.entries.size() == 1, "Asteroid spawner should have one asteroid entry.")
	assert(
		asteroid_spawner.get_node(asteroid_spawner.gravity_source) == planet,
		"Asteroid spawner should emit from the planet's surface.",
	)
	print("  PASS: survival level structure")

	# Fast-forward the spawners: objects appear and inherit gravity.
	ring_spawner.tick(30.0)
	eruption_spawner.tick(30.0)
	asteroid_spawner.tick(30.0)
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
	var asteroids := objects.filter(func(o: FloatingObject) -> bool: return o is Asteroid)
	assert(asteroids.size() > 0, "The planet spawner should have produced asteroids.")
	for asteroid: FloatingObject in asteroids:
		var dist := asteroid.global_position.distance_to(planet.global_position)
		assert(
			dist <= asteroid_spawner.source_surface_margin + planet.body_data.radius + 0.01,
			"Asteroids should spawn at the planet's surface. Distance: %f" % dist,
		)
	print("  PASS: spawner fast-forward produces gravity-affected objects, bonuses erupt from the hole, asteroids from the planet")

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
