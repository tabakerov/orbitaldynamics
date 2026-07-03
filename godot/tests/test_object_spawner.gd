extends Node

const FuelPickupScene = preload("res://scenes/fuel_pickup.tscn")
const CelestialBodyScene = preload("res://scenes/celestial_body.tscn")


func _ready() -> void:
	_test_even_cadence()
	_test_ring_positions()
	_test_box_positions()
	_test_max_alive_cap()
	_test_radial_velocity()
	_test_overrides_applied()
	_test_interval_jitter_bounds()
	_test_around_source_positions_track_growth()
	_test_turnaround_speed_matches_analytic_formula()
	_test_turnaround_launch_stops_and_falls_back()
	print("All object spawner tests passed!")
	get_tree().quit()


func _make_gravity_source(mass: float, gravity_strength: float, radius: float) -> CelestialBody:
	var data := CelestialBodyData.new()
	data.mass = mass
	data.gravity_strength = gravity_strength
	data.falloff_exponent = 2.0
	data.radius = radius
	# Matches the real black hole's config: the field must stay inverse-square
	# well past any requested turnaround distance, or it cuts off gravity
	# (see CelestialSim.get_gravity_at's max_range check) and the object
	# never turns around at all.
	data.max_range = 1000.0
	var body := CelestialBodyScene.instantiate() as CelestialBody
	body.body_data = data
	return body


func _make_entry(interval: float, jitter: float = 0.0) -> SpawnEntry:
	var entry := SpawnEntry.new()
	entry.scene = FuelPickupScene
	entry.interval = interval
	entry.interval_jitter = jitter
	return entry


func _make_spawner(entry: SpawnEntry) -> ObjectSpawner:
	var spawner := ObjectSpawner.new()
	spawner.seed_value = 12345
	var entries: Array[SpawnEntry] = [entry]
	spawner.entries = entries
	spawner.volume_shape = ObjectSpawner.VolumeShape.RING
	spawner.ring_inner_radius = 10.0
	spawner.ring_outer_radius = 20.0
	add_child(spawner)
	return spawner


func _test_even_cadence() -> void:
	var spawner := _make_spawner(_make_entry(1.0))
	var spawned: Array = []
	spawner.object_spawned.connect(func(object: Node3D) -> void: spawned.append(object))

	spawner.tick(0.5)
	assert(spawned.size() == 0, "Nothing should spawn before the first interval.")
	spawner.tick(0.5)
	assert(spawned.size() == 1, "One object should spawn after exactly one interval.")
	spawner.tick(3.0)
	assert(
		spawned.size() == 4,
		"Cadence should be one per interval, catching up over long deltas. Got: %d" % spawned.size(),
	)
	spawner.free()
	print("  PASS: even cadence without jitter")


func _test_ring_positions() -> void:
	var spawner := _make_spawner(_make_entry(1.0))
	spawner.position = Vector3(5, 0, 5)
	for i in 50:
		var object := spawner.spawn_from_entry(spawner.entries[0])
		var offset := object.global_position - spawner.global_position
		assert(is_zero_approx(object.global_position.y), "Spawned objects must sit on the Y=0 plane.")
		var radius := offset.length()
		assert(
			radius >= 10.0 - 0.001 and radius <= 20.0 + 0.001,
			"Ring spawn radius out of bounds: %f" % radius,
		)
	spawner.free()
	print("  PASS: ring positions within bounds")


func _test_box_positions() -> void:
	var spawner := _make_spawner(_make_entry(1.0))
	spawner.volume_shape = ObjectSpawner.VolumeShape.BOX
	spawner.box_size = Vector3(40, 0, 20)
	for i in 50:
		var object := spawner.spawn_from_entry(spawner.entries[0])
		var offset := object.global_position - spawner.global_position
		assert(
			absf(offset.x) <= 20.0 + 0.001 and absf(offset.z) <= 10.0 + 0.001,
			"Box spawn out of bounds: %s" % str(offset),
		)
	spawner.free()
	print("  PASS: box positions within bounds")


func _test_max_alive_cap() -> void:
	var entry := _make_entry(1.0)
	entry.max_alive = 3
	var spawner := _make_spawner(entry)
	var spawned: Array = []
	spawner.object_spawned.connect(func(object: Node3D) -> void: spawned.append(object))

	spawner.tick(10.0)
	assert(
		spawned.size() == 3,
		"max_alive should cap concurrent objects. Got: %d" % spawned.size(),
	)

	# Freeing one lets the next interval spawn a replacement.
	spawned[0].free()
	spawner.tick(1.0)
	assert(
		spawned.size() == 4,
		"A freed slot should be refilled on the next interval. Got: %d" % spawned.size(),
	)
	spawner.free()
	print("  PASS: max_alive caps concurrent objects")


func _test_radial_velocity() -> void:
	var entry := _make_entry(1.0)
	entry.velocity_frame = SpawnEntry.VelocityFrame.RADIAL
	entry.initial_velocity = Vector3(0, 0, 5)
	var spawner := _make_spawner(entry)

	for i in 20:
		var object := spawner.spawn_from_entry(entry) as FloatingObject
		var outward := (object.global_position - spawner.global_position).normalized()
		var tangent := Vector3(outward.z, 0.0, -outward.x)
		assert(
			absf(object.velocity.dot(outward)) < 0.001,
			"Pure tangential entry should have no radial component.",
		)
		assert(
			absf(object.velocity.dot(tangent) - 5.0) < 0.001,
			"Tangential speed should match entry Z. Got: %f" % object.velocity.dot(tangent),
		)
	spawner.free()
	print("  PASS: radial frame produces tangential velocity")


func _test_overrides_applied() -> void:
	var entry := _make_entry(1.0)
	entry.gravity_override = SpawnEntry.GravityOverride.ON
	var spawner := _make_spawner(entry)
	spawner.despawn_distance = 100.0
	spawner.position = Vector3(7, 0, -3)

	var object := spawner.spawn_from_entry(entry) as FloatingObject
	assert(object.gravity_affected, "Gravity override ON should enable gravity.")
	assert(
		is_equal_approx(object.despawn_distance, 100.0),
		"Spawner despawn_distance should apply to spawned objects.",
	)
	assert(
		object.despawn_center.is_equal_approx(spawner.global_position),
		"Despawn center should be the spawner position.",
	)
	spawner.free()
	print("  PASS: gravity/despawn overrides applied")


func _test_interval_jitter_bounds() -> void:
	var entry := _make_entry(2.0, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in 200:
		var interval := entry.pick_interval(rng)
		assert(
			interval >= 1.5 - 0.001 and interval <= 2.5 + 0.001,
			"Jittered interval out of bounds: %f" % interval,
		)
	print("  PASS: interval jitter stays within bounds")


func _test_around_source_positions_track_growth() -> void:
	var source := _make_gravity_source(1000.0, 1.0, 4.0)
	add_child(source)

	var entry := _make_entry(1.0)
	var spawner := ObjectSpawner.new()
	var entries: Array[SpawnEntry] = [entry]
	spawner.entries = entries
	spawner.volume_shape = ObjectSpawner.VolumeShape.AROUND_SOURCE
	spawner.source_surface_margin = 2.0
	add_child(spawner)
	spawner._gravity_source_body = source

	for i in 20:
		var object := spawner.spawn_from_entry(entry)
		var r := object.global_position.distance_to(source.global_position)
		assert(absf(r - 6.0) < 0.001, "Spawn should sit at source radius + margin. Got: %f" % r)
		assert(is_zero_approx(object.global_position.y), "Spawn must sit on the Y=0 plane.")

	# Simulate the source growing (e.g. a black hole absorbing mass): the
	# very next spawn should track the new radius with no extra wiring.
	source.body_data.radius = 10.0
	var grown_object := spawner.spawn_from_entry(entry)
	var grown_r := grown_object.global_position.distance_to(source.global_position)
	assert(absf(grown_r - 12.0) < 0.001, "Spawn radius should track source growth. Got: %f" % grown_r)

	spawner.free()
	source.free()
	print("  PASS: AROUND_SOURCE spawn position tracks the source's current radius")


func _test_turnaround_speed_matches_analytic_formula() -> void:
	var source := _make_gravity_source(500.0, 2.0, 4.0)
	add_child(source)

	var entry := _make_entry(1.0)
	entry.velocity_frame = SpawnEntry.VelocityFrame.RADIAL
	entry.radial_speed_mode = SpawnEntry.RadialSpeedMode.TURNAROUND_AT_RANGE
	entry.turnaround_distance_min = 100.0
	entry.turnaround_distance_max = 100.0  # fixed target, no randomness

	var spawner := ObjectSpawner.new()
	var entries: Array[SpawnEntry] = [entry]
	spawner.entries = entries
	spawner.volume_shape = ObjectSpawner.VolumeShape.AROUND_SOURCE
	spawner.source_surface_margin = 0.0
	add_child(spawner)
	spawner._gravity_source_body = source

	var object := spawner.spawn_from_entry(entry) as FloatingObject
	var r0 := object.global_position.distance_to(source.global_position)
	var mu := source.body_data.gravity_strength * source.body_data.mass
	var expected_v0 := sqrt(2.0 * mu * (1.0 / r0 - 1.0 / 100.0))
	assert(
		absf(object.velocity.length() - expected_v0) < 0.01,
		"Launch speed should match the energy-conservation formula. Expected %f, got %f" % [
			expected_v0, object.velocity.length(),
		],
	)
	assert(
		object.velocity.dot((object.global_position - source.global_position).normalized()) > 0.0,
		"Launch velocity should point outward.",
	)

	spawner.free()
	source.free()
	print("  PASS: turnaround launch speed matches the analytic formula")


func _test_turnaround_launch_stops_and_falls_back() -> void:
	var source := _make_gravity_source(500.0, 2.0, 4.0)
	add_child(source)
	CelestialSim.initialize(
		[source.body_data],
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3.ZERO]),
		[true],
	)

	var entry := _make_entry(1.0)
	entry.velocity_frame = SpawnEntry.VelocityFrame.RADIAL
	entry.radial_speed_mode = SpawnEntry.RadialSpeedMode.TURNAROUND_AT_RANGE
	entry.turnaround_distance_min = 100.0
	entry.turnaround_distance_max = 100.0
	entry.gravity_override = SpawnEntry.GravityOverride.ON

	var spawner := ObjectSpawner.new()
	var entries: Array[SpawnEntry] = [entry]
	spawner.entries = entries
	spawner.volume_shape = ObjectSpawner.VolumeShape.AROUND_SOURCE
	spawner.source_surface_margin = 0.0
	add_child(spawner)
	spawner._gravity_source_body = source

	var object := spawner.spawn_from_entry(entry) as FloatingObject

	var delta := 1.0 / 60.0
	var previous_radial_speed := object.velocity.length()  # positive: launched outward
	var turnaround_distance := -1.0
	for i in 6000:
		object.tick(delta)
		var offset := object.global_position - source.global_position
		var radial_speed := object.velocity.dot(offset.normalized())
		if radial_speed < 0.0 and previous_radial_speed >= 0.0:
			turnaround_distance = offset.length()
			break
		previous_radial_speed = radial_speed

	assert(turnaround_distance > 0.0, "Object should turn around within the simulated window.")
	assert(
		turnaround_distance >= 90.0 and turnaround_distance <= 110.0,
		"Turnaround should happen near the requested 100-unit distance. Got: %f" % turnaround_distance,
	)

	CelestialSim.clear()
	spawner.free()
	source.free()
	print("  PASS: turnaround launch stops near the target range and falls back")
