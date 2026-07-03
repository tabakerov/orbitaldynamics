extends Node

const BodyScene = preload("res://scenes/celestial_body.tscn")
const ShipScene = preload("res://scenes/ship.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")


func _ready() -> void:
	_test_toggle_flips_state_and_emits_signal()
	_test_cheats_make_ship_invulnerable_to_celestial_contact()
	_test_cheats_off_ship_still_crashes()
	_test_cheats_peg_fuel_to_max()
	print("All cheat mode tests passed!")
	get_tree().quit()


func _test_toggle_flips_state_and_emits_signal() -> void:
	Cheats.enabled = false
	var seen: Array[bool] = []
	Cheats.changed.connect(func(value: bool) -> void: seen.append(value))

	Cheats.toggle()
	assert(Cheats.enabled, "toggle() should flip enabled from false to true.")
	assert(seen == [true], "changed signal should fire once with the new value.")

	Cheats.toggle()
	assert(not Cheats.enabled, "toggle() should flip enabled back to false.")
	assert(seen == [true, false], "changed signal should fire again on the second toggle.")

	Cheats.enabled = false
	assert(seen == [true, false], "Setting the same value again should not re-emit changed.")

	print("  PASS: toggle flips state and emits changed exactly once per change")

	for connection in Cheats.changed.get_connections():
		Cheats.changed.disconnect(connection["callable"])


func _test_cheats_make_ship_invulnerable_to_celestial_contact() -> void:
	Cheats.enabled = true

	var ship := ShipScene.instantiate() as Ship
	var body := BodyScene.instantiate() as CelestialBody
	var body_data := CelestialBodyData.new()
	body_data.radius = 3.0
	body.body_data = body_data

	add_child(body)
	add_child(ship)
	body.global_position = Vector3.ZERO
	ship.global_position = Vector3(3.0, 0.0, 0.0)

	var crash_positions: Array[Vector3] = []
	ship.crashed.connect(func(crash_position: Vector3) -> void: crash_positions.append(crash_position))

	ship._on_body_entered(body)

	assert(crash_positions.is_empty(), "Ship should not crash on celestial contact while cheats are enabled.")
	assert(not ship._crashed, "Ship's internal crashed flag should stay false while cheats are enabled.")
	print("  PASS: cheats make the ship invulnerable to celestial-body contact")

	Cheats.enabled = false
	ship.queue_free()
	body.queue_free()


func _test_cheats_off_ship_still_crashes() -> void:
	Cheats.enabled = false

	var ship := ShipScene.instantiate() as Ship
	var body := BodyScene.instantiate() as CelestialBody
	var body_data := CelestialBodyData.new()
	body_data.radius = 3.0
	body.body_data = body_data

	add_child(body)
	add_child(ship)
	body.global_position = Vector3.ZERO
	ship.global_position = Vector3(3.0, 0.0, 0.0)

	var crash_positions: Array[Vector3] = []
	ship.crashed.connect(func(crash_position: Vector3) -> void: crash_positions.append(crash_position))

	ship._on_body_entered(body)

	assert(crash_positions.size() == 1, "Ship should still crash normally when cheats are disabled.")
	assert(ship._crashed, "Ship's internal crashed flag should be true after a normal crash.")
	print("  PASS: ship still crashes normally when cheats are off")

	ship.queue_free()
	body.queue_free()


func _test_cheats_peg_fuel_to_max() -> void:
	Cheats.enabled = true

	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	add_child(ship)
	ship.fuel = 0.0

	var module := ship._modules[MountSlot.Binding.FRONT] as EngineModule
	module.active = true
	module.intensity = 1.0

	ship._apply_fuel_flow(1.0)

	assert(
		is_equal_approx(ship.fuel, ship.max_fuel),
		"Fuel should be pegged to max_fuel every tick while cheats are enabled. Got: %s / %s" % [ship.fuel, ship.max_fuel],
	)
	assert(
		module.get_thrust_vector().length_squared() > 0.0,
		"Engine should keep producing thrust since fuel never runs out under cheats.",
	)
	print("  PASS: cheats peg fuel to max every tick")

	Cheats.enabled = false
	ship.queue_free()
