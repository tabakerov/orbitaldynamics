extends Node

const ShipScene = preload("res://scenes/ship.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")
const TutorialRearOnly = preload("res://resources/loadouts/tutorial_rear_only.tres")
const RectangularHull = preload("res://resources/hulls/rectangular.tres")
const StandardEngine = preload("res://resources/engines/engine_standard.tres")
const LargeCrate = preload("res://resources/cargo/crate_large.tres")
const BasicTank = preload("res://resources/fuel_tanks/tank_basic.tres")


func _ready() -> void:
	_test_default_loadout_spawns_four_engines()
	_test_tutorial_rear_only_spawns_one_engine()
	_test_starting_fuel_override()
	_test_recalculated_mass_includes_fuel()
	_test_cargo_shifts_center_of_mass()
	_test_fuel_tank_contributes_mass()
	_test_fuel_tank_pumps_into_ship()
	_test_fuel_tank_pump_limited_by_room()
	print("All loadout spawn tests passed!")
	get_tree().quit()


func _test_default_loadout_spawns_four_engines() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)

	assert(ship._modules.size() == 4, "Default loadout should spawn 4 modules, got %d" % ship._modules.size())
	for binding in [
		MountSlot.Binding.FRONT,
		MountSlot.Binding.REAR,
		MountSlot.Binding.LEFT,
		MountSlot.Binding.RIGHT,
	]:
		var module: ShipModule = ship._modules.get(binding)
		assert(module != null, "Module missing for binding %d" % binding)
		assert(module is EngineModule, "Module at binding %d should be EngineModule" % binding)
	assert(ship.fuel == 200.0, "Default loadout starting fuel should be 200, got %f" % ship.fuel)
	assert(ship.max_fuel == 200.0, "Default loadout max fuel should be 200, got %f" % ship.max_fuel)
	print("  PASS: default loadout spawns four engines")

	ship.queue_free()


func _test_tutorial_rear_only_spawns_one_engine() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = TutorialRearOnly
	add_child(ship)

	assert(ship._modules.size() == 1, "Tutorial loadout should spawn 1 module, got %d" % ship._modules.size())
	assert(ship._modules.has(MountSlot.Binding.REAR), "Rear slot should be occupied")
	assert(not ship._modules.has(MountSlot.Binding.FRONT), "Front slot should be empty")
	assert(ship.fuel == 10.0, "Tutorial starting fuel should be 10, got %f" % ship.fuel)
	print("  PASS: tutorial_rear_only spawns one engine")

	ship.queue_free()


func _test_starting_fuel_override() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	ship.starting_fuel_override = 30.0
	add_child(ship)

	assert(ship.fuel == 30.0, "Starting fuel override should win, got %f" % ship.fuel)
	assert(ship.max_fuel == 200.0, "Max fuel should still come from hull")
	print("  PASS: starting_fuel_override applies")

	ship.queue_free()


func _test_recalculated_mass_includes_fuel() -> void:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)

	# hull dry mass = 10, fuel = 200, FUEL_UNIT_MASS = 0.02 -> total = 10 + 4 = 14
	# All engines have dry_mass = 0 in standard profile.
	var expected := 10.0 + 200.0 * Ship.FUEL_UNIT_MASS
	assert(
		is_equal_approx(ship.mass, expected),
		"Ship mass should be %f, got %f" % [expected, ship.mass],
	)
	print("  PASS: ship mass includes fuel weight")

	ship.queue_free()


func _test_cargo_shifts_center_of_mass() -> void:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.starting_internal_fuel = 0.0
	loadout.front_module = StandardEngine
	loadout.left_module = StandardEngine
	loadout.right_module = StandardEngine
	loadout.rear_module = LargeCrate  # 20 mass at rear (0, 0, 0.9)

	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)

	# hull 10 at origin + 20 cargo at (0,0,0.9), all engines dry_mass=0
	# expected CoM = (0, 0, 0.6)
	var expected_z := 20.0 * 0.9 / (10.0 + 20.0)
	assert(
		is_equal_approx(ship.center_of_mass.z, expected_z),
		"Cargo at rear should shift CoM to z=%f, got %f" % [expected_z, ship.center_of_mass.z],
	)
	assert(
		is_equal_approx(ship.mass, 30.0),
		"Hull(10) + cargo(20) = 30, got %f" % ship.mass,
	)
	print("  PASS: cargo shifts center of mass toward its mount")

	ship.queue_free()


func _test_fuel_tank_contributes_mass() -> void:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.starting_internal_fuel = 0.0
	loadout.rear_module = BasicTank  # full at start: 1 dry + 100 * 0.02 = 3 mass

	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)

	var expected_mass := 10.0 + 1.0 + 100.0 * Ship.FUEL_UNIT_MASS
	assert(
		is_equal_approx(ship.mass, expected_mass),
		"Hull + full tank should weigh %f, got %f" % [expected_mass, ship.mass],
	)
	print("  PASS: fuel tank contributes dry_mass + fuel mass")

	ship.queue_free()


func _test_fuel_tank_pumps_into_ship() -> void:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.starting_internal_fuel = 0.0
	loadout.rear_module = BasicTank

	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)

	var tank := ship._modules[MountSlot.Binding.REAR] as ExternalFuelTankModule
	assert(tank != null, "Tank module should be spawned")
	assert(is_equal_approx(tank.current_fuel, 100.0), "Tank should start full at 100")

	tank.active = true
	tank.intensity = 1.0
	# pump for 1 second at max rate 30 -> 30 units transferred
	ship._apply_fuel_flow(1.0)

	assert(is_equal_approx(ship.fuel, 30.0), "Ship internal fuel should be 30, got %f" % ship.fuel)
	assert(is_equal_approx(tank.current_fuel, 70.0), "Tank should have 70 left, got %f" % tank.current_fuel)
	print("  PASS: tank pumps fuel into ship at trigger intensity")

	ship.queue_free()


func _test_fuel_tank_pump_limited_by_room() -> void:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.starting_internal_fuel = 195.0  # almost full, only 5 room
	loadout.rear_module = BasicTank

	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)

	var tank := ship._modules[MountSlot.Binding.REAR] as ExternalFuelTankModule
	tank.active = true
	tank.intensity = 1.0
	# would pump 30 but only 5 fits
	ship._apply_fuel_flow(1.0)

	assert(is_equal_approx(ship.fuel, 200.0), "Ship fuel should cap at max 200, got %f" % ship.fuel)
	assert(is_equal_approx(tank.current_fuel, 95.0), "Tank should give exactly 5, got %f" % tank.current_fuel)
	print("  PASS: pumping is limited by remaining room in ship")

	ship.queue_free()
