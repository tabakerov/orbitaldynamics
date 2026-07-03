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
	_test_absorption_flares_ring_and_decays()
	_test_horizon_and_ring_particles_are_configured()
	_test_horizon_and_ring_particles_rescale_with_hole_growth()
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


func _test_absorption_flares_ring_and_decays() -> void:
	var hole := BlackHoleScene.instantiate() as BlackHole
	var data := CelestialBodyData.new()
	data.radius = 3.0
	data.mass = 1000.0
	hole.body_data = data
	hole.growth_duration = 0.0
	add_child(hole)

	var ring := hole.get_node("RingParticles") as GPUParticles3D
	var base_ratio := ring.amount_ratio
	var base_lifetime := ring.lifetime
	assert(
		is_equal_approx(base_ratio, 1.0 / hole.flare_amount_multiplier),
		"At rest the ring should emit its normal share of the flare-sized buffer. Got: %f" % base_ratio,
	)

	hole.absorb(10.0)

	assert(
		hole.get_node_or_null("AbsorptionEffect") == null,
		"Absorption must not spawn a separate burst effect anymore.",
	)
	assert(
		is_equal_approx(ring.amount_ratio, 1.0),
		"At the flare's peak the ring should emit its full particle budget. Got: %f" % ring.amount_ratio,
	)
	assert(
		is_equal_approx(ring.lifetime, hole.ring_particle_lifetime * hole.flare_lifetime_multiplier),
		"At the flare's peak ring particle lifetime should be multiplied. Got: %f" % ring.lifetime,
	)

	hole._physics_process(hole.flare_duration * 0.5)
	assert(
		ring.amount_ratio > base_ratio and ring.amount_ratio < 1.0,
		"Halfway through, the flare should be partially decayed, not snapped off. Got: %f" % ring.amount_ratio,
	)

	hole._physics_process(hole.flare_duration)
	assert(
		is_equal_approx(ring.amount_ratio, base_ratio),
		"After flare_duration the ring should be back to its normal share. Got: %f" % ring.amount_ratio,
	)
	assert(
		is_equal_approx(ring.lifetime, base_lifetime),
		"After flare_duration ring particle lifetime should be back to normal. Got: %f" % ring.lifetime,
	)

	hole.queue_free()
	print("  PASS: absorption flares the accretion ring and decays back to normal")


func _test_horizon_and_ring_particles_are_configured() -> void:
	var hole := BlackHoleScene.instantiate() as BlackHole
	var data := CelestialBodyData.new()
	data.radius = 4.0
	data.mass = 1000.0
	hole.body_data = data
	add_child(hole)

	var horizon := hole.get_node_or_null("HorizonParticles") as GPUParticles3D
	var ring := hole.get_node_or_null("RingParticles") as GPUParticles3D
	assert(horizon != null, "BlackHole should spawn a permanent HorizonParticles system.")
	assert(ring != null, "BlackHole should spawn a permanent RingParticles system.")
	assert(not horizon.one_shot and horizon.emitting, "Horizon particles should emit continuously.")
	assert(not ring.one_shot and ring.emitting, "Ring particles should emit continuously.")
	assert(
		ring.amount == ceili(hole.ring_particle_count * hole.flare_amount_multiplier),
		"Ring buffer must be allocated at the flare's peak size up front. Got: %d" % ring.amount,
	)

	var lensing_material := hole._get_lensing_material()
	var horizon_mesh_material := (horizon.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	var ring_mesh_material := (ring.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	assert(
		horizon_mesh_material.render_priority > lensing_material.render_priority,
		"Horizon particles must draw over the lensing plane or they'd be invisible.",
	)
	assert(
		ring_mesh_material.render_priority > lensing_material.render_priority,
		"Ring particles must draw over the lensing plane or they'd be invisible.",
	)

	var horizon_material := horizon.process_material as ParticleProcessMaterial
	var ring_material := ring.process_material as ShaderMaterial
	assert(
		is_equal_approx(horizon_material.emission_ring_radius, data.radius * hole.horizon_radius_multiplier),
		"Horizon particle field radius should track the hole's physical radius.",
	)
	var ring_outer: float = ring_material.get_shader_parameter("ring_outer_radius")
	var ring_inner: float = ring_material.get_shader_parameter("ring_inner_radius")
	assert(
		is_equal_approx(ring_outer, data.radius * hole.ring_radius_multiplier),
		"Ring outer radius should track the hole's physical radius.",
	)
	assert(ring_inner < ring_outer, "Ring should be a band, not a filled disc.")
	assert(
		ring_material.shader == hole.RingParticleShader,
		"Ring particles should use the tangential-velocity custom particle shader.",
	)
	assert(
		is_equal_approx(ring_material.get_shader_parameter("speed_min"), hole.ring_particle_speed_min)
			and is_equal_approx(ring_material.get_shader_parameter("speed_max"), hole.ring_particle_speed_max),
		"Ring shader speed uniforms should come from the exported speed range.",
	)
	assert(
		(ring_material.get_shader_parameter("particle_color") as Color).is_equal_approx(hole.ring_color),
		"Ring shader color uniform should come from the exported ring_color.",
	)

	hole.queue_free()
	print("  PASS: horizon and ring particle systems are configured correctly")


func _test_horizon_and_ring_particles_rescale_with_hole_growth() -> void:
	var data := CelestialBodyData.new()
	data.radius = 3.0
	data.mass = 1000.0
	var hole := BlackHoleScene.instantiate() as BlackHole
	hole.body_data = data
	hole.growth_duration = 0.0  # apply growth instantly
	add_child(hole)

	var horizon_material := (hole.get_node("HorizonParticles") as GPUParticles3D).process_material as ParticleProcessMaterial
	var ring_material := (hole.get_node("RingParticles") as GPUParticles3D).process_material as ShaderMaterial
	var horizon_radius_before := horizon_material.emission_ring_radius
	var ring_radius_before: float = ring_material.get_shader_parameter("ring_outer_radius")

	hole.absorb(50.0)

	var ring_outer: float = ring_material.get_shader_parameter("ring_outer_radius")
	assert(
		is_equal_approx(horizon_material.emission_ring_radius, hole.body_data.radius * hole.horizon_radius_multiplier),
		"Horizon particle field should grow along with the hole.",
	)
	assert(
		is_equal_approx(ring_outer, hole.body_data.radius * hole.ring_radius_multiplier),
		"Ring should grow along with the hole.",
	)
	assert(horizon_material.emission_ring_radius > horizon_radius_before, "Horizon field should have grown.")
	assert(ring_outer > ring_radius_before, "Ring should have grown.")

	hole.queue_free()
	print("  PASS: horizon and ring particles rescale as the hole grows")


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
