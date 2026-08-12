extends Node

## The ship flies on two side engines: left trigger drives the left one, right
## trigger the right one, and the matching bumper flips that engine's thrust.
## Front and rear mounts keep the old hold-the-button activation.

const ShipScene = preload("res://scenes/ship.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")
const RectangularHull = preload("res://resources/hulls/rectangular.tres")
const StandardEngine = preload("res://resources/engines/engine_standard.tres")
const RocketWeapon = preload("res://resources/weapons/weapon_rockets.tres")


func _ready() -> void:
	_test_each_trigger_drives_only_its_own_engine()
	_test_trigger_strength_scales_thrust()
	_test_bumper_reverses_only_its_own_engine()
	_test_front_mount_module_runs_off_its_button()
	print("All ship control tests passed!")
	get_tree().quit()


func _test_each_trigger_drives_only_its_own_engine() -> void:
	var ship := _spawn_ship(DefaultLoadout)

	_press("thrust_left")
	ship._update_module_inputs()

	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule
	var right := ship._modules[MountSlot.Binding.RIGHT] as EngineModule
	assert(left.active and is_equal_approx(left.intensity, 1.0), "Left trigger should run the left engine.")
	assert(not right.active, "Left trigger must not touch the right engine.")

	_release("thrust_left")
	_press("thrust_right")
	ship._update_module_inputs()

	assert(right.active and is_equal_approx(right.intensity, 1.0), "Right trigger should run the right engine.")
	assert(not left.active, "Right trigger must not touch the left engine.")
	print("  PASS: each trigger drives only its own engine")

	_release("thrust_right")
	ship.queue_free()


func _test_trigger_strength_scales_thrust() -> void:
	var ship := _spawn_ship(DefaultLoadout)

	_press("thrust_left", 0.5)
	ship._update_module_inputs()

	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule
	assert(
		is_equal_approx(left.get_thrust_vector().length(), 50.0),
		"Half-pulled trigger should give half of the standard engine's 100 thrust, got %f"
			% left.get_thrust_vector().length(),
	)
	print("  PASS: trigger strength scales thrust")

	_release("thrust_left")
	ship.queue_free()


func _test_bumper_reverses_only_its_own_engine() -> void:
	var ship := _spawn_ship(DefaultLoadout)

	_press("thrust_left")
	_press("thrust_right")
	_press("reverse_left")
	ship._update_module_inputs()

	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule
	var right := ship._modules[MountSlot.Binding.RIGHT] as EngineModule
	assert(left.reversed, "Left bumper should put the left engine in reverse.")
	assert(not right.reversed, "Left bumper must not reverse the right engine.")
	# Nozzles point aft (+Z), so forward thrust is -Z and reverse thrust is +Z.
	assert(left.get_thrust_vector().z > 0.0, "Reversed engine should push the ship backwards.")
	assert(right.get_thrust_vector().z < 0.0, "The other engine should still push forwards.")

	left._process(0.0)
	right._process(0.0)
	assert(
		left._exhaust.position.z < 0.0,
		"The reversed engine's flame should move to the far side of the nozzle.",
	)
	assert(right._exhaust.position.z > 0.0, "The forward engine's flame should stay aft.")
	print("  PASS: bumper reverses only its own engine")

	_release("thrust_left")
	_release("thrust_right")
	_release("reverse_left")
	ship.queue_free()


func _test_front_mount_module_runs_off_its_button() -> void:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.starting_internal_fuel = 100.0
	loadout.front_module = RocketWeapon
	loadout.left_module = StandardEngine
	loadout.right_module = StandardEngine
	var ship := _spawn_ship(loadout)

	var weapon := ship._modules[MountSlot.Binding.FRONT] as WeaponModule
	assert(weapon != null, "Front mount should carry the gun.")

	_press("mount_front")
	ship._update_module_inputs()
	assert(weapon.active, "Holding the front mount button should activate the gun.")
	assert(
		is_equal_approx(weapon.intensity, 1.0),
		"Non-engine modules run at full intensity — there is no separate thrust trigger.",
	)

	_release("mount_front")
	ship._update_module_inputs()
	assert(not weapon.active, "Releasing the button should switch the gun off.")
	print("  PASS: front mount module runs off its own button")

	ship.queue_free()


func _spawn_ship(loadout: ShipLoadout) -> Ship:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)
	return ship


func _press(action: StringName, strength: float = 1.0) -> void:
	Input.action_press(action, strength)
	Input.flush_buffered_events()


func _release(action: StringName) -> void:
	Input.action_release(action)
	Input.flush_buffered_events()
