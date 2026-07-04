extends Node

const ShipScene = preload("res://scenes/ship.tscn")
const AsteroidScene = preload("res://scenes/asteroid.tscn")
const RocketScene = preload("res://scenes/rocket.tscn")
const LaserPickupScene = preload("res://scenes/ammo_pickup_laser.tscn")
const RocketPickupScene = preload("res://scenes/ammo_pickup_rocket.tscn")
const RectangularHull = preload("res://resources/hulls/rectangular.tres")
const StandardEngine = preload("res://resources/engines/engine_standard.tres")
const StandardWeapon = preload("res://resources/weapons/weapon_standard.tres")


func _ready() -> void:
	_test_weapon_spawns_with_starting_ammo()
	_test_add_ammo_switches_type()
	_test_ammo_pickup_feeds_weapon_and_frees_itself()
	_test_ammo_pickup_ignored_without_weapon()
	await _test_laser_splits_asteroid_and_recoils_ship()
	await _test_laser_vaporizes_small_asteroid()
	await _test_rocket_fire_spawns_projectile()
	await _test_rocket_destroys_asteroid_on_contact()
	print("All weapon module tests passed!")
	get_tree().quit()


func _spawn_armed_ship() -> Ship:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.starting_internal_fuel = 100.0
	loadout.front_module = StandardWeapon
	loadout.rear_module = StandardEngine
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)
	return ship


func _spawn_asteroid(parent: Node, position: Vector3, radius: float) -> Asteroid:
	var asteroid := AsteroidScene.instantiate() as Asteroid
	parent.add_child(asteroid)
	asteroid.global_position = position
	asteroid.gravity_affected = false
	asteroid.velocity = Vector3.ZERO
	asteroid.apply_merged_radius(radius)
	return asteroid


func _count_live_asteroids(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is Asteroid and not child.is_queued_for_deletion():
			count += 1
	return count


func _test_weapon_spawns_with_starting_ammo() -> void:
	var ship := _spawn_armed_ship()

	var weapons := ship.get_weapon_modules()
	assert(weapons.size() == 1, "Front weapon profile should spawn one WeaponModule.")
	var weapon := weapons[0]
	assert(
		weapon.current_type == WeaponProfile.AmmoType.LASER,
		"Standard weapon should start in laser mode.",
	)
	assert(weapon.laser_charges == 10, "Standard weapon should start with 10 laser charges.")
	assert(weapon.rocket_charges == 0, "Standard weapon should start with no rockets.")
	print("  PASS: weapon module spawns with starting ammo")

	ship.queue_free()


func _test_add_ammo_switches_type() -> void:
	var ship := _spawn_armed_ship()
	var weapon := ship.get_weapon_modules()[0]

	weapon.add_ammo(WeaponProfile.AmmoType.ROCKET, 3)
	assert(
		weapon.current_type == WeaponProfile.AmmoType.ROCKET,
		"Picking up rockets should switch the gun to rockets.",
	)
	assert(weapon.rocket_charges == 3, "Rocket pickup should add rocket charges.")

	weapon.add_ammo(WeaponProfile.AmmoType.LASER, 5)
	assert(
		weapon.current_type == WeaponProfile.AmmoType.LASER,
		"Picking up lasers should switch the gun back to the laser.",
	)
	assert(weapon.laser_charges == 15, "Laser pickup should add to stored charges.")
	assert(weapon.rocket_charges == 3, "Stored rockets should survive a laser pickup.")
	print("  PASS: add_ammo switches the active type and accumulates charges")

	ship.queue_free()


func _test_ammo_pickup_feeds_weapon_and_frees_itself() -> void:
	var ship := _spawn_armed_ship()
	var weapon := ship.get_weapon_modules()[0]
	var pickup := RocketPickupScene.instantiate() as AmmoPickup
	add_child(pickup)

	pickup._on_ship_contact(ship)
	assert(
		weapon.current_type == WeaponProfile.AmmoType.ROCKET,
		"Rocket crate contact should switch the gun to rockets.",
	)
	assert(weapon.rocket_charges == pickup.amount, "Rocket crate should add its amount.")
	assert(pickup.is_queued_for_deletion(), "Collected crate should free itself.")
	print("  PASS: ammo crate feeds the weapon and frees itself")

	ship.queue_free()


func _test_ammo_pickup_ignored_without_weapon() -> void:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.rear_module = StandardEngine
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)

	var pickup := LaserPickupScene.instantiate() as AmmoPickup
	add_child(pickup)
	pickup._on_ship_contact(ship)
	assert(
		not pickup.is_queued_for_deletion(),
		"A ship without a gun should leave the ammo crate floating.",
	)
	print("  PASS: ammo crate stays when the ship has no weapon")

	ship.queue_free()
	pickup.queue_free()


func _test_laser_splits_asteroid_and_recoils_ship() -> void:
	var arena := Node3D.new()
	add_child(arena)
	var ship := _spawn_armed_ship()
	# Ship faces -Z by default; the front-mounted gun fires forward.
	var asteroid := _spawn_asteroid(arena, Vector3(0, 0, -10), 1.0)
	var initial_mass := asteroid.mass
	for i in 2:
		await get_tree().physics_frame

	var weapon := ship.get_weapon_modules()[0]
	var charges_before: int = weapon.laser_charges
	weapon._try_fire()
	# linear_velocity only reflects the recoil impulse after the physics
	# server syncs, one step later.
	for i in 2:
		await get_tree().physics_frame

	assert(weapon.laser_charges == charges_before - 1, "Laser shot should consume one charge.")
	assert(
		not is_instance_valid(asteroid) or asteroid.is_queued_for_deletion(),
		"The hit asteroid should be replaced by fragments.",
	)
	assert(
		_count_live_asteroids(arena) == 2,
		"A large asteroid should split into two fragments, got %d" % _count_live_asteroids(arena),
	)
	var fragment_mass := 0.0
	for child in arena.get_children():
		if child is Asteroid and not child.is_queued_for_deletion():
			fragment_mass += child.mass
			assert(
				child.collision_radius < 1.0,
				"Fragments should be smaller than the parent rock.",
			)
	assert(
		is_equal_approx(fragment_mass, initial_mass),
		"Fragments should keep the parent's combined mass.",
	)
	assert(
		ship.linear_velocity.z > 0.5,
		"Laser recoil should push the ship backwards, got %s" % ship.linear_velocity,
	)
	print("  PASS: laser splits a large asteroid and recoils the ship")

	ship.queue_free()
	arena.queue_free()
	await arena.tree_exited


func _test_laser_vaporizes_small_asteroid() -> void:
	var arena := Node3D.new()
	add_child(arena)
	var ship := _spawn_armed_ship()
	var asteroid := _spawn_asteroid(arena, Vector3(0, 0, -10), 0.4)
	for i in 2:
		await get_tree().physics_frame

	var weapon := ship.get_weapon_modules()[0]
	weapon._try_fire()

	assert(asteroid.is_queued_for_deletion(), "A tiny asteroid should vaporize on a laser hit.")
	assert(
		_count_live_asteroids(arena) == 0,
		"Vaporizing must not leave fragments, got %d" % _count_live_asteroids(arena),
	)
	print("  PASS: laser vaporizes an asteroid below the split threshold")

	ship.queue_free()
	arena.queue_free()
	await arena.tree_exited


func _test_rocket_fire_spawns_projectile() -> void:
	var ship := _spawn_armed_ship()
	var weapon := ship.get_weapon_modules()[0]
	weapon.add_ammo(WeaponProfile.AmmoType.ROCKET, 2)
	await get_tree().physics_frame

	weapon._try_fire()
	assert(weapon.rocket_charges == 1, "Rocket shot should consume one rocket.")

	var holder := get_node_or_null("Projectiles")
	assert(holder != null, "Fired rockets should live in a Projectiles holder, not as level children.")
	var rockets := holder.get_children().filter(func(c: Node) -> bool: return c is Rocket)
	assert(rockets.size() == 1, "One rocket should be in flight.")
	var rocket: Rocket = rockets[0]
	assert(rocket.gravity_affected, "Rockets should coast on gravity like asteroids.")
	assert(
		rocket.velocity.z < -0.5,
		"The rocket should launch forward (ship faces -Z), got %s" % rocket.velocity,
	)
	print("  PASS: firing in rocket mode spawns a boosted projectile")

	ship.queue_free()
	holder.queue_free()
	await holder.tree_exited


func _test_rocket_destroys_asteroid_on_contact() -> void:
	var arena := Node3D.new()
	add_child(arena)
	var asteroid := _spawn_asteroid(arena, Vector3(0, 0, -8), 1.2)

	var rocket := RocketScene.instantiate() as Rocket
	rocket.initial_velocity = Vector3(0, 0, -10)
	rocket.boost_direction = Vector3(0, 0, -1)
	arena.add_child(rocket)
	rocket.global_position = Vector3(0, 0, -4)

	for i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(asteroid) or asteroid.is_queued_for_deletion():
			break
	assert(
		not is_instance_valid(asteroid) or asteroid.is_queued_for_deletion(),
		"The rocket should destroy the asteroid it hits.",
	)
	assert(
		not is_instance_valid(rocket) or rocket.is_queued_for_deletion(),
		"The rocket should be spent on impact.",
	)
	assert(
		_count_live_asteroids(arena) == 0,
		"A rocket kill must not leave fragments behind.",
	)
	print("  PASS: rocket destroys any asteroid on contact")

	arena.queue_free()
	await arena.tree_exited
