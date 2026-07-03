extends Node

const AsteroidScene = preload("res://scenes/asteroid.tscn")
const FuelPickupScene = preload("res://scenes/fuel_pickup.tscn")


func _ready() -> void:
	_test_register_and_unregister_lifecycle()
	_test_non_overlapping_pair_is_untouched()
	_test_overlapping_pair_gets_separated()
	_test_equal_mass_head_on_collision_bounces_back()
	_test_restitution_damps_resulting_speed()
	_test_already_separating_pair_keeps_its_velocity()
	_test_non_asteroids_never_collide()
	_test_gentle_impact_merges_mass_momentum_and_size()
	_test_merge_uses_the_stricter_of_the_two_thresholds()
	_test_hard_impact_does_not_merge()
	_test_impact_spawns_a_particle_effect()
	_test_already_separating_pair_spawns_no_particles()
	_test_three_way_cluster_does_not_double_process_a_merge()
	print("All asteroid collision tests passed!")
	get_tree().quit()


## Each test gets its own scope node; freeing it (a real, immediate free —
## not queue_free) recursively and synchronously tears down everything
## under it: asteroids, any merge-absorbed asteroid still pending its own
## deferred queue_free(), and any particle effect spawned along the way.
## That isolation matters here because the whole suite runs inside one
## synchronous _ready() with no real frame boundary, so queue_free() never
## actually flushes on its own between tests.
func _make_scope() -> Node3D:
	var scope := Node3D.new()
	add_child(scope)
	return scope


func _make_asteroid(scope: Node3D, position: Vector3, velocity: Vector3, mass: float = 8.0) -> Asteroid:
	var asteroid := AsteroidScene.instantiate() as Asteroid
	asteroid.scale_variation = 0.0  # keep collision_radius deterministic (0.9)
	asteroid.mass = mass
	scope.add_child(asteroid)
	asteroid.global_position = position
	asteroid.velocity = velocity
	return asteroid


func _count_impact_particles(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is GPUParticles3D:
			count += 1
	return count


func _test_register_and_unregister_lifecycle() -> void:
	var scope := _make_scope()
	var asteroid := _make_asteroid(scope, Vector3.ZERO, Vector3.ZERO)
	AsteroidCollisions._physics_process(0.0)  # prune any stale entries first
	assert(
		AsteroidCollisions._asteroids.has(asteroid),
		"Asteroid should register itself with AsteroidCollisions on _ready.",
	)
	scope.free()
	assert(
		AsteroidCollisions._asteroids.is_empty(),
		"Freeing an asteroid should unregister it immediately.",
	)
	print("  PASS: register/unregister lifecycle")


func _test_non_overlapping_pair_is_untouched() -> void:
	var scope := _make_scope()
	var a := _make_asteroid(scope, Vector3(-10, 0, 0), Vector3(1, 0, 0))
	var b := _make_asteroid(scope, Vector3(10, 0, 0), Vector3(-1, 0, 0))

	AsteroidCollisions._resolve_pair(a, b)
	assert(a.global_position.is_equal_approx(Vector3(-10, 0, 0)), "Non-overlapping pair should not move.")
	assert(a.velocity.is_equal_approx(Vector3(1, 0, 0)), "Non-overlapping pair should keep its velocity.")
	assert(b.velocity.is_equal_approx(Vector3(-1, 0, 0)), "Non-overlapping pair should keep its velocity.")

	scope.free()
	print("  PASS: non-overlapping pair is left untouched")


func _test_overlapping_pair_gets_separated() -> void:
	var scope := _make_scope()
	# collision_radius is 0.9 each (scale_variation = 0), so anything closer
	# than 1.8 apart overlaps.
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3.ZERO)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3.ZERO)

	AsteroidCollisions._resolve_pair(a, b)
	var dist := a.global_position.distance_to(b.global_position)
	assert(
		absf(dist - 1.8) < 0.001,
		"Overlapping pair should be pushed apart to exactly touch. Got dist: %f" % dist,
	)
	assert(is_zero_approx(a.global_position.y), "Positional correction must stay on the Y=0 plane.")

	scope.free()
	print("  PASS: overlapping pair gets separated to touching distance")


func _test_equal_mass_head_on_collision_bounces_back() -> void:
	AsteroidCollisions.restitution_min = 1.0
	AsteroidCollisions.restitution_max = 1.0  # isolate the elastic exchange itself

	var scope := _make_scope()
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(5, 0, 0), 8.0)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(-5, 0, 0), 8.0)

	AsteroidCollisions._resolve_pair(a, b)
	# Equal masses in a head-on elastic collision exchange velocities exactly.
	assert(
		a.velocity.is_equal_approx(Vector3(-5, 0, 0)),
		"Equal-mass elastic collision should swap velocities. Got: %s" % str(a.velocity),
	)
	assert(
		b.velocity.is_equal_approx(Vector3(5, 0, 0)),
		"Equal-mass elastic collision should swap velocities. Got: %s" % str(b.velocity),
	)

	scope.free()
	AsteroidCollisions.restitution_min = 0.90
	AsteroidCollisions.restitution_max = 0.95
	print("  PASS: equal-mass head-on collision swaps velocities")


func _test_restitution_damps_resulting_speed() -> void:
	AsteroidCollisions.restitution_min = 0.9
	AsteroidCollisions.restitution_max = 0.9  # fixed, for a deterministic check

	var scope := _make_scope()
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(5, 0, 0), 8.0)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(-5, 0, 0), 8.0)
	var speed_before := a.velocity.length() + b.velocity.length()

	AsteroidCollisions._resolve_pair(a, b)
	var speed_after := a.velocity.length() + b.velocity.length()
	assert(
		absf(speed_after / speed_before - 0.9) < 0.001,
		"Resulting speed sum should be exactly the restitution fraction of before. Ratio: %f"
			% (speed_after / speed_before),
	)

	scope.free()
	AsteroidCollisions.restitution_min = 0.90
	AsteroidCollisions.restitution_max = 0.95
	print("  PASS: restitution damps the resulting speed to the requested fraction")


func _test_already_separating_pair_keeps_its_velocity() -> void:
	var scope := _make_scope()
	# Overlapping, but already moving apart along the normal.
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(-5, 0, 0))
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(5, 0, 0))

	AsteroidCollisions._resolve_pair(a, b)
	assert(
		a.velocity.is_equal_approx(Vector3(-5, 0, 0)),
		"A pair already separating should not receive a collision impulse.",
	)
	assert(
		b.velocity.is_equal_approx(Vector3(5, 0, 0)),
		"A pair already separating should not receive a collision impulse.",
	)

	scope.free()
	print("  PASS: an already-separating pair keeps its velocity (position still corrected)")


func _test_non_asteroids_never_collide() -> void:
	var scope := _make_scope()
	var fuel := FuelPickupScene.instantiate() as FuelPickup
	scope.add_child(fuel)
	fuel.global_position = Vector3.ZERO

	assert(
		AsteroidCollisions._asteroids.is_empty(),
		"Non-asteroid FloatingObjects must never register with AsteroidCollisions.",
	)

	scope.free()
	print("  PASS: non-asteroid floating objects never participate in asteroid collisions")


func _test_gentle_impact_merges_mass_momentum_and_size() -> void:
	var scope := _make_scope()
	# closing_speed = 1.0 - (-0.2) = 1.2, below the default 1.5 threshold.
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(1.0, 0, 0), 8.0)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(-0.2, 0, 0), 4.0)
	var expected_radius := pow(pow(a.collision_radius, 3.0) + pow(b.collision_radius, 3.0), 1.0 / 3.0)
	var expected_velocity := (a.velocity * a.mass + b.velocity * b.mass) / (a.mass + b.mass)
	var expected_position := a.global_position.lerp(b.global_position, b.mass / (a.mass + b.mass))

	AsteroidCollisions._resolve_pair(a, b)

	# a is heavier, so it should be the survivor; b gets absorbed.
	assert(not is_instance_valid(b) or b.is_queued_for_deletion(), "The lighter asteroid should be absorbed.")
	assert(is_instance_valid(a) and not a.is_queued_for_deletion(), "The heavier asteroid should survive.")
	assert(
		is_equal_approx(a.mass, 12.0),
		"Survivor's mass should be the sum of both. Got: %f" % a.mass,
	)
	assert(
		a.velocity.is_equal_approx(expected_velocity),
		"Survivor's velocity should be the momentum-weighted average. Got: %s" % str(a.velocity),
	)
	assert(
		a.global_position.is_equal_approx(expected_position),
		"Survivor should move to the mass-weighted midpoint. Got: %s" % str(a.global_position),
	)
	assert(
		absf(a.collision_radius - expected_radius) < 0.0001,
		"Survivor's radius should reflect the combined volume. Got: %f, expected: %f"
			% [a.collision_radius, expected_radius],
	)

	scope.free()
	print("  PASS: a gentle impact merges mass, momentum and size")


func _test_merge_uses_the_stricter_of_the_two_thresholds() -> void:
	var scope := _make_scope()
	# closing_speed = 2.0. a alone would merge (threshold 3.0), but b's
	# stricter threshold (1.0) should force a bounce instead.
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(1.0, 0, 0), 8.0)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(-1.0, 0, 0), 8.0)
	a.merge_speed_threshold = 3.0
	b.merge_speed_threshold = 1.0

	AsteroidCollisions._resolve_pair(a, b)

	assert(is_instance_valid(a) and is_instance_valid(b), "Neither asteroid should be absorbed.")
	assert(is_equal_approx(a.mass, 8.0), "Masses should be unchanged — this should have bounced.")

	scope.free()
	print("  PASS: merge only happens below the stricter of the two thresholds")


func _test_hard_impact_does_not_merge() -> void:
	var scope := _make_scope()
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(5, 0, 0), 8.0)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(-5, 0, 0), 8.0)

	AsteroidCollisions._resolve_pair(a, b)

	assert(is_instance_valid(a) and is_instance_valid(b), "A hard impact should not merge either asteroid away.")
	assert(is_equal_approx(a.mass, 8.0) and is_equal_approx(b.mass, 8.0), "Masses should stay unchanged.")

	scope.free()
	print("  PASS: a hard impact bounces instead of merging")


func _test_impact_spawns_a_particle_effect() -> void:
	var scope := _make_scope()
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(5, 0, 0), 8.0)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(-5, 0, 0), 8.0)
	assert(_count_impact_particles(scope) == 0, "Sanity check: no particles before any impact.")

	AsteroidCollisions._resolve_pair(a, b)

	assert(
		_count_impact_particles(scope) == 1,
		"An impact should spawn one particle effect at the collision point.",
	)

	scope.free()
	print("  PASS: an impact spawns a dust/debris particle effect")


func _test_already_separating_pair_spawns_no_particles() -> void:
	var scope := _make_scope()
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(-5, 0, 0))
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(5, 0, 0))

	AsteroidCollisions._resolve_pair(a, b)

	assert(
		_count_impact_particles(scope) == 0,
		"A pair that isn't actually impacting should not spawn a particle effect.",
	)

	scope.free()
	print("  PASS: a non-impact (already separating) spawns no particle effect")


func _test_three_way_cluster_does_not_double_process_a_merge() -> void:
	var scope := _make_scope()
	# Three mutually-overlapping asteroids, all gently drifting together —
	# some pair should merge; the third should end up interacting with
	# whichever asteroid is still around, never with a stale, already-
	# absorbed instance from earlier in the same physics tick.
	var a := _make_asteroid(scope, Vector3(-0.5, 0, 0), Vector3(0.3, 0, 0), 8.0)
	var b := _make_asteroid(scope, Vector3(0.5, 0, 0), Vector3(-0.3, 0, 0), 8.0)
	var c := _make_asteroid(scope, Vector3(0.0, 0, 0.5), Vector3(0, 0, -0.3), 8.0)

	AsteroidCollisions._physics_process(1.0 / 60.0)

	var survivors := 0
	var total_mass := 0.0
	for asteroid in [a, b, c]:
		if is_instance_valid(asteroid) and not asteroid.is_queued_for_deletion():
			survivors += 1
			total_mass += asteroid.mass
	assert(survivors <= 2, "At least one merge should have reduced the trio. Survivors: %d" % survivors)
	assert(
		absf(total_mass - 24.0) < 0.0001,
		"Total mass across survivors must be conserved regardless of merge order. Got: %f" % total_mass,
	)

	scope.free()
	print("  PASS: a three-way cluster resolves without double-processing a merged asteroid")
