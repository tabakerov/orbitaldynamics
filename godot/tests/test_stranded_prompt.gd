extends Node

## A ship with a dry tank that is no longer closing on the target has lost the
## level — it just cannot tell yet, because nothing on screen says so. The
## level watches for that state and the HUD offers the way out.

const ShipScene = preload("res://scenes/ship.tscn")
const TargetScene = preload("res://scenes/target.tscn")
const FuelPickupScene = preload("res://scenes/fuel_pickup.tscn")
const HudScene = preload("res://scenes/hud.tscn")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")
const TankLoadout = preload("res://resources/loadouts/extended_range.tres")

const TICK: float = 1.0


func _ready() -> void:
	_test_full_tank_is_never_stranded()
	_test_dry_tank_drifting_away_strands_after_three_seconds()
	_test_closing_on_the_target_keeps_the_prompt_away()
	_test_fuel_left_on_the_level_keeps_the_prompt_away()
	_test_external_tank_fuel_keeps_the_prompt_away()
	_test_hud_shows_and_hides_the_prompt()
	print("All stranded prompt tests passed!")
	get_tree().quit()


func _test_full_tank_is_never_stranded() -> void:
	var level := _build_level(DefaultLoadout)
	var events := _watch(level)

	for i in 10:
		level._process(TICK)

	assert(events.is_empty(), "A ship with fuel is never stranded, however it drifts.")
	print("  PASS: full tank is never stranded")

	level.queue_free()


func _test_dry_tank_drifting_away_strands_after_three_seconds() -> void:
	var level := _build_level(DefaultLoadout)
	var ship := level.get_ship()
	var events := _watch(level)
	ship.fuel = 0.0

	# First tick only records where the ship is when the tank runs dry.
	level._process(TICK)
	assert(events.is_empty(), "The countdown starts when the fuel runs out, not before.")

	for i in 2:
		level._process(TICK)
	assert(events.is_empty(), "Two seconds without progress is not yet a verdict.")

	level._process(TICK)
	assert(events == [true], "Three seconds without closing on the target should raise the prompt.")

	# Gravity could still swing the ship back towards the target; the prompt
	# has to go away again when it does.
	for i in 5:
		ship.global_position -= Vector3(0.0, 0.0, 10.0)
		level._process(TICK)
	assert(events == [true, false], "Closing on the target again should take the prompt back down.")
	print("  PASS: dry tank drifting away strands after three seconds")

	level.queue_free()


func _test_closing_on_the_target_keeps_the_prompt_away() -> void:
	var level := _build_level(DefaultLoadout)
	var ship := level.get_ship()
	var events := _watch(level)
	ship.fuel = 0.0

	for i in 10:
		ship.global_position -= Vector3(0.0, 0.0, 5.0)
		level._process(TICK)

	assert(events.is_empty(), "A ship still coasting towards the target is not stranded.")
	print("  PASS: closing on the target keeps the prompt away")

	level.queue_free()


func _test_fuel_left_on_the_level_keeps_the_prompt_away() -> void:
	var level := _build_level(DefaultLoadout)
	var pickup := FuelPickupScene.instantiate()
	pickup.position = Vector3(20.0, 0.0, 0.0)
	level.add_child(pickup)
	var events := _watch(level)
	level.get_ship().fuel = 0.0

	for i in 10:
		level._process(TICK)

	assert(events.is_empty(), "While a fuel pickup is still out there the flight is recoverable.")
	print("  PASS: fuel left on the level keeps the prompt away")

	level.queue_free()


func _test_external_tank_fuel_keeps_the_prompt_away() -> void:
	var level := _build_level(TankLoadout)
	var ship := level.get_ship()
	var events := _watch(level)
	ship.fuel = 0.0

	var tank := ship._modules[MountSlot.Binding.REAR] as ExternalFuelTankModule
	assert(tank != null and tank.current_fuel > 0.0, "This loadout should carry a filled tank.")

	for i in 10:
		level._process(TICK)
	assert(events.is_empty(), "Fuel in an external tank still counts as fuel.")

	tank.current_fuel = 0.0
	for i in 10:
		level._process(TICK)
	assert(events == [true], "Once the external tank is dry too, the ship is stranded.")
	print("  PASS: external tank fuel keeps the prompt away")

	level.queue_free()


func _test_hud_shows_and_hides_the_prompt() -> void:
	var level := _build_level(DefaultLoadout)
	var hud = HudScene.instantiate()
	add_child(hud)
	hud.setup(level.get_ship(), null, level.get_target(), level)

	var prompt = hud.get_node("StrandedPrompt")
	assert(not prompt.visible, "The prompt stays down while the flight is still alive.")

	hud.show_stranded_prompt()
	assert(prompt.visible, "The prompt should appear when the level says the ship is stranded.")
	var lines := PackedStringArray()
	for child in prompt.get_children():
		lines.append((child as Label).text)
	var hint := "\n".join(lines)
	assert(hint.contains("R") and hint.contains("Esc"), "The prompt must name both keys, got: %s" % hint)

	hud.hide_stranded_prompt()
	assert(not prompt.visible, "And go back down when it is not.")
	print("  PASS: HUD shows and hides the prompt")

	hud.queue_free()
	level.queue_free()


## A bare level: one ship at the origin, one target 100 m ahead, nothing else.
func _build_level(loadout: ShipLoadout) -> Level:
	var level := Level.new()

	var ship := ShipScene.instantiate() as Ship
	ship.loadout = loadout
	level.add_child(ship)

	var target := TargetScene.instantiate() as Target
	target.position = Vector3(0.0, 0.0, -100.0)
	level.add_child(target)

	# Children first: Level wires itself to the ship and target in _ready.
	add_child(level)
	return level


func _watch(level: Level) -> Array:
	var events: Array = []
	level.stranded_changed.connect(func(stranded: bool) -> void: events.append(stranded))
	return events
