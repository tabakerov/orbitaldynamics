extends Node

const BodyScene = preload("res://scenes/celestial_body.tscn")
const EngineScene = preload("res://scenes/engine.tscn")
const ShipScene = preload("res://scenes/ship.tscn")


func _ready() -> void:
	_test_ship_has_no_space_damping()
	_test_ship_engines_stop_without_fuel()
	_test_ship_crashes_on_any_celestial_body_contact()
	_test_crash_explosion_spawns_particles()
	print("All crash flow tests passed!")
	get_tree().quit()


func _test_ship_has_no_space_damping() -> void:
	var ship := ShipScene.instantiate() as Ship
	add_child(ship)

	assert(
		ship.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE,
		"Ship should replace project linear damping so it keeps drifting in empty space.",
	)
	assert(
		is_zero_approx(ship.linear_damp),
		"Ship linear damping should be zero in empty space. Got: %f" % ship.linear_damp,
	)
	assert(
		ship.angular_damp_mode == RigidBody3D.DAMP_MODE_REPLACE,
		"Ship should replace project angular damping so rotation is not artificially slowed.",
	)
	assert(
		is_zero_approx(ship.angular_damp),
		"Ship angular damping should be zero in empty space. Got: %f" % ship.angular_damp,
	)
	print("  PASS: ship has no space damping")

	ship.queue_free()


func _test_ship_engines_stop_without_fuel() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.front_engine_scene = EngineScene
	add_child(ship)
	ship.fuel = 0.0

	Input.action_press("engine_front")
	Input.action_press("thrust")
	ship._handle_engine_toggles()
	ship._update_thrust()
	Input.action_release("engine_front")
	Input.action_release("thrust")

	var engine := ship.get_node("MountFront").get_child(0) as ShipEngine
	assert(not engine.active, "Engine should not stay active when fuel is empty.")
	assert(
		is_zero_approx(engine.thrust_magnitude),
		"Engine thrust magnitude should be zero when fuel is empty. Got: %f" % engine.thrust_magnitude,
	)
	print("  PASS: ship engines stop without fuel")

	ship.queue_free()


func _test_ship_crashes_on_any_celestial_body_contact() -> void:
	var ship := ShipScene.instantiate() as Ship
	var body := BodyScene.instantiate() as CelestialBody
	var body_data := CelestialBodyData.new()
	body_data.radius = 3.0
	body.body_data = body_data

	add_child(body)
	add_child(ship)
	body.global_position = Vector3.ZERO
	ship.global_position = Vector3(3.0, 0.0, 0.0)
	ship.linear_velocity = Vector3.ZERO

	var crash_positions: Array[Vector3] = []
	ship.crashed.connect(func(crash_position: Vector3) -> void: crash_positions.append(crash_position))

	ship._on_body_entered(body)
	ship._on_body_entered(body)

	assert(crash_positions.size() == 1, "Ship should crash once on celestial body contact.")
	assert(
		crash_positions[0].distance_to(Vector3(3.0, 0.0, 0.0)) < 0.01,
		"Crash position should be on the contacted body surface. Got: %s" % crash_positions[0],
	)
	print("  PASS: ship crashes on any celestial body contact")

	ship.queue_free()
	body.queue_free()


func _test_crash_explosion_spawns_particles() -> void:
	var level := Level.new()
	add_child(level)

	level.spawn_crash_explosion(Vector3(1.0, 0.0, 2.0))
	var particles := level.get_node_or_null("CrashExplosion") as GPUParticles3D

	assert(particles != null, "Crash explosion should spawn GPUParticles3D.")
	assert(particles.one_shot, "Crash explosion should be one-shot.")
	assert(particles.emitting, "Crash explosion should start emitting immediately.")
	assert(
		particles.process_mode == Node.PROCESS_MODE_ALWAYS,
		"Crash explosion should keep processing while the crash menu pauses the tree.",
	)
	print("  PASS: crash explosion spawns particles")

	level.queue_free()
