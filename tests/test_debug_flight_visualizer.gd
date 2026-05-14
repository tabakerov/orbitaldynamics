extends Node

const ShipScene = preload("res://scenes/ship.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")


func _ready() -> void:
	await _test_ship_reports_active_thrust_samples()
	await _test_visualizer_predicts_forward_motion()
	_test_celestial_sim_predicts_body_paths()
	await _test_level_toggle_controls_visualizer()
	print("All debug flight visualizer tests passed!")
	get_tree().quit()


func _test_ship_reports_active_thrust_samples() -> void:
	var ship := _make_ship()

	Input.action_press("mount_front")
	Input.action_press("thrust")
	Input.flush_buffered_events()
	ship._update_module_inputs()

	var samples := ship.get_debug_thrust_force_samples()
	assert(samples.size() == 1, "One active mount should produce one thrust debug sample.")
	var force := samples[0]["force"] as Vector3
	assert(absf(force.length() - 100.0) < 0.01, "Standard engine thrust sample should be 100.")
	print("  PASS: ship reports active thrust samples")

	Input.action_release("mount_front")
	Input.action_release("thrust")
	Input.flush_buffered_events()
	ship.queue_free()
	await get_tree().process_frame


func _test_visualizer_predicts_forward_motion() -> void:
	CelestialSim.initialize([], PackedVector3Array(), PackedVector3Array())
	var ship := _make_ship()
	ship.linear_velocity = Vector3(10.0, 0.0, 0.0)

	var visualizer := DebugFlightVisualizer.new()
	visualizer.ship = ship
	visualizer.trajectory_seconds = 1.0
	visualizer.trajectory_step = 0.5
	add_child(visualizer)

	var points := visualizer.get_prediction_points()
	assert(points.size() == 3, "One second at 0.5s steps should produce start + 2 points.")
	assert(points[2].x > points[0].x, "Predicted trajectory should continue along current velocity.")
	print("  PASS: visualizer predicts forward motion")

	visualizer.queue_free()
	ship.queue_free()
	await get_tree().process_frame


func _test_celestial_sim_predicts_body_paths() -> void:
	var left_body := CelestialBodyData.new()
	left_body.mass = 1000.0
	var right_body := CelestialBodyData.new()
	right_body.mass = 1000.0

	CelestialSim.initialize(
		[left_body, right_body],
		PackedVector3Array([Vector3(-5.0, 0.0, 0.0), Vector3(5.0, 0.0, 0.0)]),
		PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		[false, false],
	)

	var left_gravity := CelestialSim.get_body_gravity_acceleration(0)
	assert(left_gravity.x > 0.0, "Left body gravity should point toward right body.")

	var paths := CelestialSim.predict_body_paths(1.0, 0.5)
	assert(paths.size() == 2, "Prediction should return one path per simulated body.")
	assert(paths[0][2].x > paths[0][0].x, "Left body should move toward the right body.")
	assert(paths[1][2].x < paths[1][0].x, "Right body should move toward the left body.")
	print("  PASS: celestial sim predicts body paths")


func _test_level_toggle_controls_visualizer() -> void:
	var level := Level.new()
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	level.add_child(ship)
	add_child(level)
	await get_tree().process_frame

	var visualizer := level.get_node_or_null("DebugFlightVisualizer") as DebugFlightVisualizer
	assert(visualizer != null, "Level should create a debug visualizer for its ship.")
	assert(not visualizer.enabled, "Debug visualizer should start disabled.")

	level.toggle_debug_visuals()
	assert(visualizer.enabled, "Debug visualizer should enable when level toggles debug visuals.")
	print("  PASS: level toggle controls visualizer")

	level.queue_free()
	await get_tree().process_frame


func _make_ship() -> Ship:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)
	return ship
