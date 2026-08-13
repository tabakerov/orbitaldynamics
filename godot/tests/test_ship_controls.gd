extends Node

## The ship flies on two side engines: left trigger drives the left one, right
## trigger the right one, and the matching bumper flips that engine's thrust.
## The trigger's travel, squared, is the thrust the pilot asks for; the engine
## reaches it with a spool delay. Front and rear mounts keep the
## hold-the-button activation.

const ShipScene = preload("res://scenes/ship.tscn")
const HudScene = preload("res://scenes/hud.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")
const RectangularHull = preload("res://resources/hulls/rectangular.tres")
const StandardEngine = preload("res://resources/engines/engine_standard.tres")
const RocketWeapon = preload("res://resources/weapons/weapon_rockets.tres")


func _ready() -> void:
	_test_each_trigger_drives_only_its_own_engine()
	_test_engine_thrust_lags_behind_the_trigger()
	_test_small_throttle_changes_lag_as_much_as_big_ones()
	_test_trigger_travel_is_squared()
	_test_bumper_reverses_only_its_own_engine()
	await _test_symmetric_thrust_lock_levels_both_engines()
	_test_front_mount_module_runs_off_its_button()
	_test_throttle_gauges_mirror_the_engines()
	print("All ship control tests passed!")
	get_tree().quit()


func _test_each_trigger_drives_only_its_own_engine() -> void:
	var ship := _spawn_ship(DefaultLoadout)

	_press("thrust_left")
	ship._update_module_inputs()

	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule
	var right := ship._modules[MountSlot.Binding.RIGHT] as EngineModule
	assert(left.active and is_equal_approx(left.throttle, 1.0), "Left trigger should run the left engine.")
	assert(not right.active, "Left trigger must not touch the right engine.")

	_release("thrust_left")
	_press("thrust_right")
	ship._update_module_inputs()

	assert(right.active and is_equal_approx(right.throttle, 1.0), "Right trigger should run the right engine.")
	assert(is_zero_approx(left.throttle), "Right trigger must not touch the left engine.")
	print("  PASS: each trigger drives only its own engine")

	_release("thrust_right")
	ship.queue_free()


func _test_engine_thrust_lags_behind_the_trigger() -> void:
	var ship := _spawn_ship(DefaultLoadout)
	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule
	var delta := 1.0 / 60.0

	_press("thrust_left")
	ship._update_module_inputs()
	assert(is_equal_approx(left.throttle, 1.0), "The trigger commands full thrust at once.")
	assert(is_zero_approx(left.intensity), "The engine must not jump to it in the same frame.")

	for i in 6:
		left.physics_tick(delta)
	assert(
		left.intensity > 0.0 and left.intensity < 1.0,
		"A tenth of a second in, the engine should be spooling up, got %f" % left.intensity,
	)

	for i in 300:
		left.physics_tick(delta)
	assert(is_equal_approx(left.intensity, 1.0), "Held long enough, the engine reaches the commanded thrust.")

	# Letting go leaves a fading tail of thrust rather than an instant cut.
	_release("thrust_left")
	ship._update_module_inputs()
	left.physics_tick(delta)
	assert(
		left.intensity > 0.0 and left.intensity < 1.0,
		"Releasing the trigger should start a spool-down, not a cut, got %f" % left.intensity,
	)
	assert(left.active, "The engine stays active while it spools down — that thrust is still real.")

	for i in 300:
		left.physics_tick(delta)
	ship._update_module_inputs()
	assert(is_zero_approx(left.intensity), "The engine should settle at idle.")
	assert(not left.active, "A spooled-down engine with the trigger up is off.")
	print("  PASS: engine thrust lags behind the trigger")

	ship.queue_free()


## The lag is a time constant, not a fixed rate: asking for a little thrust
## has to take just as long as asking for a lot, or fine corrections would
## land instantly and the inertia would only exist at high power.
func _test_small_throttle_changes_lag_as_much_as_big_ones() -> void:
	var ship := _spawn_ship(DefaultLoadout)
	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule
	var delta := 1.0 / 60.0

	_press("thrust_left", 0.4)  # squared: a 0.16 command
	ship._update_module_inputs()
	for i in 12:
		left.physics_tick(delta)
	var small_progress := left.intensity / left.throttle

	_release("thrust_left")
	_spool_up(ship)
	_press("thrust_left", 1.0)
	ship._update_module_inputs()
	left.intensity = 0.0
	for i in 12:
		left.physics_tick(delta)
	var large_progress := left.intensity / left.throttle

	assert(
		small_progress < 0.6,
		"A fifth of a second should not get a small command most of the way there, got %f"
			% small_progress,
	)
	assert(
		is_equal_approx(small_progress, large_progress),
		"Both commands should be the same fraction of the way there, got %f vs %f"
			% [small_progress, large_progress],
	)
	print("  PASS: small throttle changes lag as much as big ones")

	_release("thrust_left")
	ship.queue_free()


func _test_trigger_travel_is_squared() -> void:
	var ship := _spawn_ship(DefaultLoadout)
	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule

	_press("thrust_left", 0.5)
	ship._update_module_inputs()
	_spool_up(ship)
	assert(
		is_equal_approx(left.get_thrust_vector().length(), 25.0),
		"Half-pulled trigger should give a quarter of the standard engine's 100 thrust, got %f"
			% left.get_thrust_vector().length(),
	)

	_press("thrust_left", 1.0)
	ship._update_module_inputs()
	_spool_up(ship)
	assert(
		is_equal_approx(left.get_thrust_vector().length(), 100.0),
		"A trigger pulled all the way should still give full thrust, got %f"
			% left.get_thrust_vector().length(),
	)
	print("  PASS: trigger travel is squared")

	_release("thrust_left")
	ship.queue_free()


func _test_bumper_reverses_only_its_own_engine() -> void:
	var ship := _spawn_ship(DefaultLoadout)

	_press("thrust_left")
	_press("thrust_right")
	_press("reverse_left")
	ship._update_module_inputs()
	_spool_up(ship)

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


func _test_symmetric_thrust_lock_levels_both_engines() -> void:
	var ship := _spawn_ship(DefaultLoadout)
	var left := ship._modules[MountSlot.Binding.LEFT] as EngineModule
	var right := ship._modules[MountSlot.Binding.RIGHT] as EngineModule
	assert(not ship.thrust_locked, "The lock is off until the pilot asks for it.")

	_press("thrust_left", 1.0)
	_press("thrust_right", 0.5)
	ship._update_module_inputs()
	assert(
		is_equal_approx(left.throttle, 1.0) and is_equal_approx(right.throttle, 0.25),
		"Unlocked, each side answers only to its own trigger.",
	)

	# The button is a mode switch: it toggles on press and stays put when let go.
	_press("thrust_lock")
	ship._update_thrust_lock()
	assert(ship.thrust_locked, "The button should engage the lock.")
	_release("thrust_lock")
	await get_tree().process_frame
	ship._update_thrust_lock()
	assert(ship.thrust_locked, "Letting the button go must not disengage it — it is a mode.")

	ship._update_module_inputs()
	assert(
		is_equal_approx(left.throttle, 1.0) and is_equal_approx(right.throttle, 1.0),
		"Locked, the harder-pulled trigger drives both sides, got %f / %f"
			% [left.throttle, right.throttle],
	)

	# Direction is levelled too: one bumper turns both engines around, so the
	# locked ship backs up straight instead of spinning.
	_press("reverse_right")
	ship._update_module_inputs()
	_spool_up(ship)
	assert(left.reversed and right.reversed, "Either bumper should reverse both engines under the lock.")
	assert(
		left.get_thrust_vector().is_equal_approx(right.get_thrust_vector()),
		"Both engines should push the same way, just as hard, got %s vs %s"
			% [left.get_thrust_vector(), right.get_thrust_vector()],
	)

	# Releasing the harder trigger hands the lock over to the other one.
	_release("thrust_left")
	ship._update_module_inputs()
	assert(
		is_equal_approx(left.throttle, 0.25) and is_equal_approx(right.throttle, 0.25),
		"With the strongest trigger let go, both sides fall to what is left.",
	)

	_press("thrust_lock")
	ship._update_thrust_lock()
	assert(not ship.thrust_locked, "A second press should switch the lock back off.")
	ship._update_module_inputs()
	assert(is_zero_approx(left.throttle), "Unlocked again, an untouched trigger means no thrust.")
	print("  PASS: symmetric thrust lock levels both engines")

	_release("thrust_lock")
	_release("thrust_right")
	_release("reverse_right")
	ship.queue_free()


func _test_front_mount_module_runs_off_its_button() -> void:
	var loadout := ShipLoadout.new()
	loadout.hull = RectangularHull
	loadout.starting_internal_fuel = 100.0
	loadout.front_module = RocketWeapon
	loadout.rear_module = StandardEngine
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

	# An engine bolted to a mount without a trigger still behaves like an
	# engine: its button is a full-throttle command, and it spools up to it.
	var rear := ship._modules[MountSlot.Binding.REAR] as EngineModule
	_press("mount_rear")
	ship._update_module_inputs()
	assert(is_equal_approx(rear.throttle, 1.0), "The mount button should command full thrust.")
	assert(is_zero_approx(rear.intensity), "Even here the engine spools up rather than jumping.")
	_spool_up(ship)
	assert(
		is_equal_approx(rear.get_thrust_vector().length(), 100.0),
		"Spooled up, the rear engine should give its full rated thrust.",
	)
	print("  PASS: front mount module runs off its own button")

	_release("mount_rear")
	ship.queue_free()


## The HUD levers are the pilot's only view of the spool lag, so they have to
## show the commanded and the delivered thrust as two separate readings.
func _test_throttle_gauges_mirror_the_engines() -> void:
	var ship := _spawn_ship(DefaultLoadout)
	var hud = HudScene.instantiate()
	add_child(hud)
	hud.setup(ship)

	var left_gauge = hud.get_node("ThrottleLeft")
	var right_gauge = hud.get_node("ThrottleRight")
	assert(left_gauge.visible and right_gauge.visible, "Both side engines should get a lever.")
	assert(right_gauge.mirrored, "The right lever is mirrored so its scale stays at the screen edge.")

	_press("thrust_left", 0.5)
	_press("reverse_left")
	ship._update_module_inputs()
	hud._update_throttle_gauges()
	assert(
		is_equal_approx(left_gauge._throttle, 0.25),
		"The lever shows commanded thrust, not trigger travel — half a pull is quarter power.",
	)
	assert(is_zero_approx(left_gauge._thrust), "The needle should read zero until the engine spools up.")
	assert(left_gauge._reversed, "The reverse lamp should light while the bumper is held.")

	_spool_up(ship)
	hud._update_throttle_gauges()
	assert(is_equal_approx(left_gauge._thrust, 0.25), "The needle should catch up with the lever.")
	assert(is_zero_approx(right_gauge._throttle), "The other side's lever should not move.")

	# Symmetric thrust is a ship-wide mode, so both levers light their lamp.
	assert(not left_gauge._locked and not right_gauge._locked, "The lock lamp is dark by default.")
	ship.thrust_locked = true
	ship._update_module_inputs()
	hud._update_throttle_gauges()
	assert(left_gauge._locked and right_gauge._locked, "Both levers should light LOCKED together.")
	ship.thrust_locked = false

	ship.apply_loadout_change(MountSlot.Binding.RIGHT, null)
	hud._update_throttle_gauges()
	assert(not right_gauge.visible, "A side left without an engine should hide its lever.")
	print("  PASS: throttle gauges mirror the engines")

	_release("thrust_left")
	_release("reverse_left")
	hud.queue_free()
	ship.queue_free()


func _spawn_ship(loadout: ShipLoadout) -> Ship:
	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	add_child(ship)
	return ship


## Runs every engine's spool to completion. The approach is exponential, so a
## deliberately huge tick is the cheap way to land exactly on the commanded
## thrust instead of a hair short of it.
func _spool_up(ship: Ship) -> void:
	for module: ShipModule in ship._modules.values():
		module.physics_tick(10.0)


func _press(action: StringName, strength: float = 1.0) -> void:
	Input.action_press(action, strength)
	Input.flush_buffered_events()


func _release(action: StringName) -> void:
	Input.action_release(action)
	Input.flush_buffered_events()
