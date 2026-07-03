extends Node

const ShipScene = preload("res://scenes/ship.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")


func _ready() -> void:
	_test_register_and_unregister_lifecycle()
	_test_source_pulls_another_floating_object()
	_test_self_exclusion_no_self_pull()
	_test_attraction_range_cutoff()
	_test_freeing_source_removes_its_pull()
	_test_ship_feels_pull_from_attracting_object()
	_test_gravity_affected_object_accelerates_toward_source()
	print("All floating gravity tests passed!")
	get_tree().quit()


func _make_source(mass: float, strength: float, range_: float) -> FloatingObject:
	var source := FloatingObject.new()
	source.mass = mass
	source.attracts_others = true
	source.attraction_strength = strength
	source.attraction_range = range_
	source.attraction_min_range = 1.0
	return source


func _test_register_and_unregister_lifecycle() -> void:
	assert(not FloatingGravity.has_sources(), "Registry should start empty.")
	var source := _make_source(10.0, 1.0, 50.0)
	add_child(source)
	assert(FloatingGravity.has_sources(), "Registering an attracting object should populate the registry.")
	source.free()
	assert(not FloatingGravity.has_sources(), "Freeing the source should unregister it immediately.")
	print("  PASS: register/unregister lifecycle")


func _test_source_pulls_another_floating_object() -> void:
	var source := _make_source(1000.0, 1.0, 50.0)
	add_child(source)
	source.global_position = Vector3(10, 0, 0)

	var target := FloatingObject.new()
	add_child(target)
	target.global_position = Vector3.ZERO

	# mu / dist^2 = 1000 / 10^2 = 10, pointing toward the source (+X).
	var gravity := FloatingGravity.get_gravity_at(target.global_position)
	assert(
		absf(gravity.length() - 10.0) < 0.01,
		"Gravity magnitude should follow mass/strength/falloff. Got: %f" % gravity.length(),
	)
	assert(
		gravity.normalized().is_equal_approx(Vector3(1, 0, 0)),
		"Gravity should point toward the source. Got: %s" % str(gravity.normalized()),
	)

	source.free()
	target.free()
	print("  PASS: an attracting object pulls another floating object")


func _test_self_exclusion_no_self_pull() -> void:
	var source := _make_source(1000.0, 1.0, 50.0)
	add_child(source)
	source.global_position = Vector3(5, 0, 0)

	var gravity := FloatingGravity.get_gravity_at(source.global_position, source)
	assert(gravity.is_equal_approx(Vector3.ZERO), "A source must not pull on itself when excluded.")

	source.free()
	print("  PASS: self-exclusion prevents self-pull")


func _test_attraction_range_cutoff() -> void:
	var source := _make_source(1000.0, 1.0, 50.0)
	add_child(source)
	source.global_position = Vector3.ZERO

	var near := FloatingGravity.get_gravity_at(Vector3(49, 0, 0))
	var far := FloatingGravity.get_gravity_at(Vector3(51, 0, 0))
	assert(near.length() > 0.0, "Just inside attraction_range should still pull.")
	assert(far.is_equal_approx(Vector3.ZERO), "Beyond attraction_range, pull should be exactly zero.")

	source.free()
	print("  PASS: attraction_range cuts off gravity beyond its reach")


func _test_freeing_source_removes_its_pull() -> void:
	var source := _make_source(1000.0, 1.0, 50.0)
	add_child(source)
	source.global_position = Vector3(10, 0, 0)
	assert(
		FloatingGravity.get_gravity_at(Vector3.ZERO).length() > 0.0,
		"Sanity check: source should be pulling before it's freed.",
	)

	source.free()
	assert(
		FloatingGravity.get_gravity_at(Vector3.ZERO).is_equal_approx(Vector3.ZERO),
		"A freed source must stop pulling immediately.",
	)
	print("  PASS: freeing a source removes its pull")


func _test_ship_feels_pull_from_attracting_object() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)
	ship.global_position = Vector3.ZERO

	var source := _make_source(2000.0, 1.0, 50.0)
	add_child(source)
	source.global_position = Vector3(20, 0, 0)

	var gravity := FloatingGravity.get_gravity_at(ship.global_position)
	assert(gravity.length() > 0.0, "Ship position should feel a pull from a nearby attracting object.")
	assert(
		gravity.normalized().is_equal_approx(Vector3(1, 0, 0)),
		"Pull should point toward the attracting object. Got: %s" % str(gravity.normalized()),
	)

	ship.queue_free()
	source.free()
	print("  PASS: an attracting object's pull reaches the ship's position")


func _test_gravity_affected_object_accelerates_toward_source() -> void:
	var source := _make_source(1000.0, 1.0, 50.0)
	add_child(source)
	source.global_position = Vector3(10, 0, 0)

	var target := FloatingObject.new()
	target.gravity_affected = true
	add_child(target)
	target.global_position = Vector3.ZERO

	target.tick(1.0 / 60.0)
	assert(
		target.velocity.x > 0.0,
		"gravity_affected object should accelerate toward the attracting source. Velocity: %s" % str(target.velocity),
	)
	# accel = 1000 / 10^2 = 10 toward the source -> velocity.x ~= 10/60
	assert(
		absf(target.velocity.x - 10.0 / 60.0) < 0.01,
		"Velocity magnitude should match the attracting source's field. Got: %f" % target.velocity.x,
	)

	source.free()
	target.free()
	print("  PASS: gravity_affected objects accelerate toward other attracting objects")
