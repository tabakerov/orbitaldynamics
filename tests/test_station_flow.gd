extends Node

const StationScene = preload("res://scenes/station.tscn")
const ShipScene = preload("res://scenes/ship.tscn")
const FullServiceStation = preload("res://resources/stations/full_service.tres")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")
const StandardEngine = preload("res://resources/engines/engine_standard.tres")
const LargeCrate = preload("res://resources/cargo/crate_large.tres")
const BasicTank = preload("res://resources/fuel_tanks/tank_basic.tres")


func _ready() -> void:
	_test_station_applies_dock_radius_from_profile()
	_test_station_exposes_available_modules()
	_test_hot_swap_replaces_module_and_updates_mass()
	_test_hot_swap_to_null_clears_slot()
	_test_hot_swap_updates_loadout_reference()
	_test_loadout_is_duplicated_so_swaps_dont_bleed_across_ships()
	print("All station flow tests passed!")
	get_tree().quit()


func _test_station_applies_dock_radius_from_profile() -> void:
	var station := StationScene.instantiate() as Station
	station.profile = FullServiceStation
	add_child(station)

	var collision := station.get_node("CollisionShape3D") as CollisionShape3D
	var sphere := collision.shape as SphereShape3D
	assert(
		is_equal_approx(sphere.radius, 8.0),
		"Station dock radius should match profile (8.0), got %f" % sphere.radius,
	)
	print("  PASS: station applies dock radius from profile")

	station.queue_free()


func _test_station_exposes_available_modules() -> void:
	var station := StationScene.instantiate() as Station
	station.profile = FullServiceStation
	add_child(station)

	var modules := station.get_available_modules()
	assert(modules.size() == 5, "Full service station should offer 5 modules, got %d" % modules.size())
	print("  PASS: station exposes available_modules")

	station.queue_free()


func _test_hot_swap_replaces_module_and_updates_mass() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)

	var mass_before := ship.mass  # 10 hull + 200*0.02 fuel = 14, engines dry_mass = 0
	ship.apply_loadout_change(MountSlot.Binding.FRONT, LargeCrate)

	var module: ShipModule = ship._modules.get(MountSlot.Binding.FRONT)
	assert(module is CargoModule, "Front slot should now hold CargoModule")
	assert(
		is_equal_approx(ship.mass, mass_before + 20.0),
		"Mass should grow by 20 (cargo), got %f (was %f)" % [ship.mass, mass_before],
	)
	assert(
		ship.center_of_mass.z < -0.1,
		"CoM should shift forward (negative Z) toward cargo at front mount, got z=%f" % ship.center_of_mass.z,
	)
	print("  PASS: hot-swap replaces module and updates mass + CoM")

	ship.queue_free()


func _test_hot_swap_to_null_clears_slot() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)

	ship.apply_loadout_change(MountSlot.Binding.LEFT, null)

	assert(
		not ship._modules.has(MountSlot.Binding.LEFT),
		"Left slot should be empty after hot-swap to null",
	)
	print("  PASS: hot-swap to null clears slot")

	ship.queue_free()


func _test_hot_swap_updates_loadout_reference() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)

	ship.apply_loadout_change(MountSlot.Binding.REAR, BasicTank)

	assert(
		ship.loadout.rear_module == BasicTank,
		"Loadout's rear_module reference should be updated to BasicTank after swap",
	)
	print("  PASS: hot-swap updates loadout reference")

	ship.queue_free()


func _test_loadout_is_duplicated_so_swaps_dont_bleed_across_ships() -> void:
	var ship_a := ShipScene.instantiate() as Ship
	ship_a.loadout = DefaultLoadout
	add_child(ship_a)
	ship_a.apply_loadout_change(MountSlot.Binding.FRONT, LargeCrate)

	var ship_b := ShipScene.instantiate() as Ship
	ship_b.loadout = DefaultLoadout
	add_child(ship_b)

	assert(
		ship_b.loadout.front_module == StandardEngine,
		"Second ship's front_module should still be standard engine — DefaultLoadout must not have been mutated",
	)
	assert(
		ship_a.loadout.front_module == LargeCrate,
		"First ship's front_module should be LargeCrate after swap",
	)
	print("  PASS: loadout is per-ship via duplicate()")

	ship_a.queue_free()
	ship_b.queue_free()
