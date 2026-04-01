extends SceneTree


func _init() -> void:
	_test_single_body_gravity_direction()
	_test_single_body_gravity_magnitude()
	_test_gravity_inverse_square_falloff()
	_test_gravity_max_range_cutoff()
	_test_gravity_min_range_clamp()
	_test_two_body_orbit_bounded()
	_test_plane_constraint()
	print("All celestial simulation tests passed!")
	quit()


func _make_sim() -> CelestialSim:
	var sim := CelestialSim.new()
	sim.gravitational_constant = 1.0
	return sim


func _make_body(
	m: float = 1000.0,
	gs: float = 1.0,
	fe: float = 2.0,
	maxr: float = 80.0,
	minr: float = 0.5,
) -> CelestialBodyData:
	var d := CelestialBodyData.new()
	d.mass = m
	d.gravity_strength = gs
	d.falloff_exponent = fe
	d.max_range = maxr
	d.min_range = minr
	d.radius = 3.0
	return d


func _test_single_body_gravity_direction() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body()],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	var gravity := sim.get_gravity_at(Vector3(10, 0, 0))
	assert(
		gravity.normalized().is_equal_approx(Vector3(-1, 0, 0)),
		"Gravity should point toward body. Got: %s" % str(gravity.normalized()),
	)
	print("  PASS: single body gravity direction")


func _test_single_body_gravity_magnitude() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body()],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	# gravity_strength(1) * mass(1000) / dist(10)^2 = 10.0
	var gravity := sim.get_gravity_at(Vector3(10, 0, 0))
	assert(
		absf(gravity.length() - 10.0) < 0.01,
		"Gravity magnitude should be ~10.0, got %f" % gravity.length(),
	)
	print("  PASS: single body gravity magnitude")


func _test_gravity_inverse_square_falloff() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body()],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	var g_at_5 := sim.get_gravity_at(Vector3(5, 0, 0)).length()
	var g_at_10 := sim.get_gravity_at(Vector3(10, 0, 0)).length()
	var ratio := g_at_5 / g_at_10
	assert(
		absf(ratio - 4.0) < 0.01,
		"Inverse square ratio should be 4.0, got %f" % ratio,
	)
	print("  PASS: inverse square falloff")


func _test_gravity_max_range_cutoff() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body(1000.0, 1.0, 2.0, 50.0)],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	var gravity := sim.get_gravity_at(Vector3(51, 0, 0))
	assert(
		gravity.is_equal_approx(Vector3.ZERO),
		"Gravity beyond max_range should be zero. Got: %s" % str(gravity),
	)
	print("  PASS: max range cutoff")


func _test_gravity_min_range_clamp() -> void:
	var sim := _make_sim()
	sim.initialize(
		[_make_body(1000.0, 1.0, 2.0, 80.0, 5.0)],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
	)
	# At distance 1.0 (less than min_range 5.0), distance is clamped to 5.0
	var g_at_1 := sim.get_gravity_at(Vector3(1, 0, 0)).length()
	var g_at_5 := sim.get_gravity_at(Vector3(5, 0, 0)).length()
	assert(
		absf(g_at_1 - g_at_5) < 0.01,
		"Gravity inside min_range should equal gravity at min_range. Got %f vs %f" % [g_at_1, g_at_5],
	)
	print("  PASS: min range clamp")


func _test_two_body_orbit_bounded() -> void:
	var sim := _make_sim()
	var body := _make_body(100.0)
	sim.initialize(
		[body, body],
		PackedVector3Array([Vector3(-5, 0, 0), Vector3(5, 0, 0)]),
		PackedVector3Array([Vector3(0, 0, -1), Vector3(0, 0, 1)]),
	)
	for i in 1000:
		sim.step(1.0 / 60.0)
	var dist := sim.get_body_position(0).distance_to(sim.get_body_position(1))
	assert(
		dist < 200.0,
		"Two-body system should remain bounded. Distance: %f" % dist,
	)
	print("  PASS: two body orbit bounded")


func _test_plane_constraint() -> void:
	var sim := _make_sim()
	var body := _make_body(100.0)
	# Intentionally give Y velocity — should be zeroed
	sim.initialize(
		[body],
		PackedVector3Array([Vector3(0, 5, 0)]),
		PackedVector3Array([Vector3(0, 10, 0)]),
	)
	sim.step(1.0 / 60.0)
	assert(
		absf(sim.get_body_position(0).y) < 0.001,
		"Body should be constrained to Y=0. Got Y=%f" % sim.get_body_position(0).y,
	)
	assert(
		absf(sim.get_body_velocity(0).y) < 0.001,
		"Velocity Y should be zeroed. Got %f" % sim.get_body_velocity(0).y,
	)
	print("  PASS: plane constraint enforced")
