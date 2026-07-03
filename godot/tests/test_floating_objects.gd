extends Node

const FuelPickupScene = preload("res://scenes/fuel_pickup.tscn")
const BonusStarScene = preload("res://scenes/bonus_star.tscn")
const AsteroidScene = preload("res://scenes/asteroid.tscn")
const BlackHoleScene = preload("res://scenes/black_hole.tscn")
const CelestialBodyScene = preload("res://scenes/celestial_body.tscn")
const ShipScene = preload("res://scenes/ship.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")


func _ready() -> void:
	_test_gravity_pulls_object_toward_body()
	_test_gravity_disabled_keeps_velocity()
	_test_despawn_beyond_distance()
	_test_fuel_pickup_refuels_ship()
	_test_black_hole_absorbs_and_grows()
	_test_black_hole_growth_stacks_without_jumping()
	_test_absorption_effect_orients_cone_along_velocity()
	_test_absorption_effect_falls_back_to_radial_burst()
	_test_absorption_effect_scales_velocity_with_absorbed_speed()
	_test_absorption_effect_scales_particle_count_with_mass()
	_test_asteroid_crashes_ship()
	_test_star_emits_collected()
	_test_object_burns_on_planet()
	print("All floating object tests passed!")
	get_tree().quit()


func _init_sim(body_mass: float = 1000.0) -> void:
	var data := CelestialBodyData.new()
	data.mass = body_mass
	data.gravity_strength = 1.0
	data.falloff_exponent = 2.0
	data.max_range = 500.0
	data.min_range = 1.0
	CelestialSim.initialize(
		[data],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
		[true],
	)


func _make_ship() -> Ship:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)
	return ship


func _test_gravity_pulls_object_toward_body() -> void:
	_init_sim(1000.0)
	var object := FloatingObject.new()
	object.gravity_affected = true
	add_child(object)
	object.global_position = Vector3(10, 0, 0)

	# A small delta (one real physics tick) keeps this close to a single
	# Euler step even though tick() substeps internally for accuracy.
	object.tick(1.0 / 60.0)
	# accel = 1000 / 10^2 = 10 toward origin -> velocity.x ~= -10/60
	assert(
		absf(object.velocity.x + 10.0 / 60.0) < 0.01,
		"Object should accelerate toward the body. Velocity: %s" % str(object.velocity),
	)
	assert(
		object.global_position.x < 10.0,
		"Object should move toward the body. X: %f" % object.global_position.x,
	)
	CelestialSim.clear()
	object.free()
	print("  PASS: gravity pulls floating object toward body")


func _test_gravity_disabled_keeps_velocity() -> void:
	_init_sim(1000.0)
	var object := FloatingObject.new()
	object.gravity_affected = false
	object.initial_velocity = Vector3(1, 0, 0)
	add_child(object)
	object.global_position = Vector3(10, 0, 0)

	object.tick(1.0)
	assert(
		object.velocity.is_equal_approx(Vector3(1, 0, 0)),
		"Velocity should be unaffected without gravity. Got: %s" % str(object.velocity),
	)
	assert(
		object.global_position.is_equal_approx(Vector3(11, 0, 0)),
		"Object should drift linearly. Got: %s" % str(object.global_position),
	)
	CelestialSim.clear()
	object.free()
	print("  PASS: gravity-disabled object keeps velocity")


func _test_despawn_beyond_distance() -> void:
	var object := FloatingObject.new()
	object.despawn_distance = 5.0
	add_child(object)
	object.global_position = Vector3(10, 0, 0)

	object.tick(1.0 / 60.0)
	assert(
		object.is_queued_for_deletion(),
		"Object beyond despawn_distance should free itself.",
	)
	print("  PASS: object despawns beyond distance")


func _test_fuel_pickup_refuels_ship() -> void:
	var ship := _make_ship()
	ship.fuel = 100.0
	var pickup := FuelPickupScene.instantiate() as FuelPickup
	add_child(pickup)

	var collected_objects: Array = []
	pickup.collected.connect(func(object: FloatingObject) -> void: collected_objects.append(object))
	pickup._handle_contact(ship)

	assert(
		is_equal_approx(ship.fuel, 150.0),
		"Pickup should add 50 fuel. Got: %f" % ship.fuel,
	)
	assert(pickup.is_queued_for_deletion(), "Pickup should free itself after collection.")
	assert(collected_objects.size() == 1, "Pickup should emit collected once.")
	assert(pickup.score_value == 5, "Fuel pickup should be worth 5 points.")
	ship.queue_free()
	print("  PASS: fuel pickup refuels ship and emits collected")


func _test_black_hole_absorbs_and_grows() -> void:
	_init_sim(1000.0)
	var shared_data := CelestialBodyData.new()
	shared_data.mass = 1000.0
	shared_data.radius = 3.0
	var hole := BlackHoleScene.instantiate() as BlackHole
	hole.body_data = shared_data
	hole.radius_growth_per_mass = 0.02
	hole.mass_gain_factor = 1.0
	hole.growth_duration = 0.5
	add_child(hole)
	hole.sim_index = 0

	var object := FloatingObject.new()
	object.mass = 10.0
	add_child(object)
	object._handle_contact(hole)

	assert(object.is_queued_for_deletion(), "Object should vanish into the black hole.")
	assert(
		is_equal_approx(hole.body_data.radius, 3.0),
		"Growth must not apply instantly — it should ramp over growth_duration.",
	)

	hole._physics_process(0.25)
	assert(
		absf(hole.body_data.radius - 3.1) < 0.001,
		"Halfway through growth_duration, radius should be halfway grown. Got: %f" % hole.body_data.radius,
	)
	assert(
		absf(hole.body_data.mass - 1005.0) < 0.001,
		"Halfway through growth_duration, mass should be halfway grown. Got: %f" % hole.body_data.mass,
	)

	hole._physics_process(0.25)
	assert(
		absf(hole.body_data.radius - 3.2) < 0.001,
		"Radius should fully grow by growth * mass once growth_duration elapses. Got: %f" % hole.body_data.radius,
	)
	assert(
		absf(hole.body_data.mass - 1010.0) < 0.001,
		"Hole mass should fully grow by absorbed mass once growth_duration elapses. Got: %f" % hole.body_data.mass,
	)
	var gravity: float = CelestialSim.get_gravity_at(Vector3(10, 0, 0)).length()
	assert(
		absf(gravity - 10.1) < 0.01,
		"Sim gravity should reflect the new mass. Got: %f" % gravity,
	)
	var collision := hole.get_node("CollisionShape3D") as CollisionShape3D
	assert(
		absf((collision.shape as SphereShape3D).radius - 3.2) < 0.001,
		"Collision radius should grow with the hole.",
	)
	assert(
		is_equal_approx(shared_data.radius, 3.0),
		"Original body_data resource must stay untouched (per-instance duplicate).",
	)
	CelestialSim.clear()
	hole.sim_index = -1
	hole.queue_free()
	print("  PASS: black hole absorbs mass and grows smoothly over growth_duration")


func _test_black_hole_growth_stacks_without_jumping() -> void:
	var data := CelestialBodyData.new()
	data.mass = 500.0
	data.radius = 2.0
	var hole := BlackHoleScene.instantiate() as BlackHole
	hole.body_data = data
	hole.radius_growth_per_mass = 0.1
	hole.mass_gain_factor = 1.0
	hole.growth_duration = 1.0
	add_child(hole)

	hole.absorb(1.0)  # target: radius 2.1, mass 501.0
	hole._physics_process(0.5)  # halfway: radius 2.05, mass 500.5
	assert(
		absf(hole.body_data.radius - 2.05) < 0.001,
		"Halfway through the first ramp. Got: %f" % hole.body_data.radius,
	)

	# A second absorption mid-ramp must retarget from the CURRENT (partially
	# grown) value — not snap back, and not jump ahead to the old target.
	hole.absorb(1.0)  # new target: 2.1 + 0.1 = 2.2, mass 501 + 1 = 502
	assert(
		is_equal_approx(hole.body_data.radius, 2.05),
		"A new absorption must not change the current value instantly. Got: %f" % hole.body_data.radius,
	)

	hole._physics_process(1.0)  # the new ramp fully elapses
	assert(
		absf(hole.body_data.radius - 2.2) < 0.001,
		"After the second ramp completes, radius should reflect both absorptions. Got: %f" % hole.body_data.radius,
	)
	assert(
		absf(hole.body_data.mass - 502.0) < 0.001,
		"After the second ramp completes, mass should reflect both absorptions. Got: %f" % hole.body_data.mass,
	)
	hole.queue_free()
	print("  PASS: black hole growth stacks smoothly without jumping")


func _test_absorption_effect_orients_cone_along_velocity() -> void:
	var hole := BlackHoleScene.instantiate() as BlackHole
	var data := CelestialBodyData.new()
	data.radius = 3.0
	data.mass = 1000.0
	hole.body_data = data
	add_child(hole)
	hole.global_position = Vector3(5, 0, 3)

	hole.absorb(1.0, Vector3(0, 0, 6), Vector3(8, 0, 3))  # velocity along +Z

	var particles := hole.get_node_or_null("AbsorptionEffect") as GPUParticles3D
	assert(particles != null, "absorb() should spawn an AbsorptionEffect particle system.")
	assert(particles.one_shot, "Absorption effect should be one-shot.")
	assert(particles.emitting, "Absorption effect should start emitting immediately.")
	assert(
		particles.global_position.is_equal_approx(Vector3(8, 0, 3)),
		"Absorption effect should spawn at the contact point. Got: %s" % str(particles.global_position),
	)

	var material := particles.process_material as ParticleProcessMaterial
	assert(material != null, "Absorption effect should have a ParticleProcessMaterial.")
	# +Z velocity, tilted -90 deg about X so orbit_velocity's local XY plane
	# lines up with the game's XZ ground plane -> local direction (0,-1,0).
	assert(
		material.direction.is_equal_approx(Vector3(0, -1, 0)),
		"Cone direction should reflect the absorbed object's velocity in the tilted local frame. Got: %s"
			% str(material.direction),
	)
	assert(material.spread <= 15.0, "The burst should be a narrow cone.")
	assert(
		material.radial_accel_min < 0.0 and material.radial_accel_max < 0.0,
		"radial_accel should pull particles inward, toward the hole.",
	)
	assert(
		material.orbit_velocity_max > 0.0,
		"orbit_velocity should curl the burst as it's pulled in.",
	)

	var mesh := particles.draw_pass_1 as QuadMesh
	assert(mesh != null, "Absorption effect should draw with a QuadMesh.")
	var mesh_material := mesh.material as StandardMaterial3D
	assert(mesh_material != null, "Absorption effect mesh should have a StandardMaterial3D.")
	var lensing_material := hole._get_lensing_material()
	assert(lensing_material != null, "Black hole should have a lensing material to compare against.")
	assert(
		mesh_material.render_priority > lensing_material.render_priority,
		(
			"Absorption particles must draw after (on top of) the lensing distortion plane, "
			+ "or the burst gets painted over and is invisible. Particle priority: %d, lensing priority: %d"
		) % [mesh_material.render_priority, lensing_material.render_priority],
	)

	hole.queue_free()
	print("  PASS: absorption effect orients its cone along the absorbed object's velocity")


func _test_absorption_effect_falls_back_to_radial_burst() -> void:
	var hole := BlackHoleScene.instantiate() as BlackHole
	var data := CelestialBodyData.new()
	data.radius = 3.0
	data.mass = 1000.0
	hole.body_data = data
	add_child(hole)
	hole.global_position = Vector3.ZERO

	hole.absorb(1.0, Vector3.ZERO, Vector3(4, 0, 0))  # no velocity to go on

	var particles := hole.get_node_or_null("AbsorptionEffect") as GPUParticles3D
	assert(particles != null, "absorb() should still spawn an effect without a velocity.")
	var material := particles.process_material as ParticleProcessMaterial
	assert(
		material.direction.is_equal_approx(Vector3(1, 0, 0)),
		"With no velocity, the burst should point outward from the hole through the contact point. Got: %s"
			% str(material.direction),
	)

	hole.queue_free()
	print("  PASS: absorption effect falls back to a radial burst when there's no velocity to follow")


func _test_absorption_effect_scales_velocity_with_absorbed_speed() -> void:
	var hole := BlackHoleScene.instantiate() as BlackHole
	var data := CelestialBodyData.new()
	data.radius = 3.0
	data.mass = 1000.0
	hole.body_data = data
	add_child(hole)
	hole.global_position = Vector3.ZERO
	hole.absorption_velocity_multiplier = 0.5

	hole.absorb(1.0, Vector3(0, 0, 10), Vector3(0, 0, 3))  # speed = 10

	var particles := hole.get_node_or_null("AbsorptionEffect") as GPUParticles3D
	var material := particles.process_material as ParticleProcessMaterial
	var expected_boost := 10.0 * hole.absorption_velocity_multiplier
	assert(
		is_equal_approx(material.initial_velocity_min, hole.absorption_initial_velocity_min + expected_boost),
		"initial_velocity_min should shift by absorbed speed * multiplier. Got: %f" % material.initial_velocity_min,
	)
	assert(
		is_equal_approx(material.initial_velocity_max, hole.absorption_initial_velocity_max + expected_boost),
		"initial_velocity_max should shift by absorbed speed * multiplier. Got: %f" % material.initial_velocity_max,
	)

	hole.queue_free()
	print("  PASS: absorption effect scales initial velocity with the absorbed object's speed")


func _test_absorption_effect_scales_particle_count_with_mass() -> void:
	var hole := BlackHoleScene.instantiate() as BlackHole
	var data := CelestialBodyData.new()
	data.radius = 3.0
	data.mass = 1000.0
	hole.body_data = data
	add_child(hole)
	hole.global_position = Vector3.ZERO
	hole.absorption_particles_per_mass = 2.0

	hole.absorb(1.0, Vector3(0, 0, 5), Vector3(0, 0, 3))
	var light_particles := hole.get_node_or_null("AbsorptionEffect") as GPUParticles3D
	var light_amount := light_particles.amount
	light_particles.free()  # not queue_free(): must be gone before the next absorb() below

	hole.absorb(20.0, Vector3(0, 0, 5), Vector3(0, 0, 3))
	var heavy_particles := hole.get_node_or_null("AbsorptionEffect") as GPUParticles3D
	assert(
		heavy_particles.amount == light_amount + roundi(19.0 * hole.absorption_particles_per_mass),
		"Heavier objects should spawn proportionally more particles. Light: %d, heavy: %d"
			% [light_amount, heavy_particles.amount],
	)
	assert(heavy_particles.amount > light_amount, "Absorbing more mass should never spawn fewer particles.")

	hole.queue_free()
	print("  PASS: absorption effect scales particle count with absorbed mass")


func _test_asteroid_crashes_ship() -> void:
	var ship := _make_ship()
	var asteroid := AsteroidScene.instantiate() as Asteroid
	add_child(asteroid)

	var crash_positions: Array = []
	ship.crashed.connect(func(crash_position: Vector3) -> void: crash_positions.append(crash_position))
	asteroid._handle_contact(ship)

	assert(crash_positions.size() == 1, "Asteroid contact should crash the ship.")
	assert(not asteroid.is_queued_for_deletion(), "Asteroid should survive the impact.")
	ship.queue_free()
	asteroid.queue_free()
	print("  PASS: asteroid crashes the ship")


func _test_star_emits_collected() -> void:
	var ship := _make_ship()
	var star := BonusStarScene.instantiate() as BonusStar
	add_child(star)

	var collected_objects: Array = []
	star.collected.connect(func(object: FloatingObject) -> void: collected_objects.append(object))
	star._handle_contact(ship)

	assert(collected_objects.size() == 1, "Star should emit collected on ship contact.")
	assert(star.is_queued_for_deletion(), "Star should free itself after collection.")
	assert(star.score_value == 25, "Bonus star should be worth 25 points.")
	ship.queue_free()
	print("  PASS: bonus star emits collected")


func _test_object_burns_on_planet() -> void:
	var data := CelestialBodyData.new()
	data.radius = 3.0
	var planet := CelestialBodyScene.instantiate() as CelestialBody
	planet.body_data = data
	add_child(planet)

	var object := FloatingObject.new()
	add_child(object)
	object._handle_contact(planet)

	assert(object.is_queued_for_deletion(), "Object should burn up on a planet.")
	planet.queue_free()
	print("  PASS: object burns up on planet contact")
