extends Node

const ShipModifierScreenScene = preload("res://scenes/ship_modifier_screen.tscn")
const StationScene = preload("res://scenes/station.tscn")
const ShipScene = preload("res://scenes/ship.tscn")
const FullServiceStation = preload("res://resources/stations/full_service.tres")
const DefaultLoadout = preload("res://resources/loadouts/default.tres")


func _ready() -> void:
	_test_gamepad_accept_opens_module_picker()
	await get_tree().process_frame
	_test_gamepad_accept_applies_selected_module()
	await get_tree().process_frame
	_test_gamepad_cancel_backs_out_of_module_picker()
	print("All ship modifier screen tests passed!")
	get_tree().quit()


func _test_gamepad_accept_opens_module_picker() -> void:
	var screen := _make_screen()

	_press_action("menu_accept")
	screen._process(0.0)
	_release_action("menu_accept")

	assert(
		screen._state == ShipModifierScreen.State.PICK_MODULE,
		"Gamepad accept should open the module picker.",
	)
	print("  PASS: gamepad accept opens module picker")

	_discard_screen(screen)


func _test_gamepad_accept_applies_selected_module() -> void:
	var screen := _make_screen()
	var applied := {
		"binding": -1,
		"profile": null,
	}
	screen.apply_loadout_change.connect(
		func(binding: int, profile: ModuleProfile) -> void:
			applied["binding"] = binding
			applied["profile"] = profile
	)

	screen._enter_module_pick()
	screen._selected_module_idx = 1
	screen._refresh_module_highlight()

	_press_action("menu_accept")
	screen._process(0.0)
	_release_action("menu_accept")

	assert(
		applied["binding"] == MountSlot.Binding.FRONT,
		"Gamepad accept should apply the selected module to the selected slot.",
	)
	assert(applied["profile"] == FullServiceStation.available_modules[1], "Applied module should match selection.")
	assert(screen._state == ShipModifierScreen.State.PICK_MOUNT, "Applying should return to mount picker.")
	print("  PASS: gamepad accept applies selected module")

	_discard_screen(screen)


func _test_gamepad_cancel_backs_out_of_module_picker() -> void:
	var screen := _make_screen()
	screen._enter_module_pick()

	_press_action("menu_cancel")
	screen._process(0.0)
	_release_action("menu_cancel")

	assert(
		screen._state == ShipModifierScreen.State.PICK_MOUNT,
		"Gamepad cancel should back out of the module picker.",
	)
	print("  PASS: gamepad cancel backs out of module picker")

	_discard_screen(screen)


func _make_screen() -> ShipModifierScreen:
	var fixture := Node.new()
	add_child(fixture)

	var station := StationScene.instantiate() as Station
	station.profile = FullServiceStation
	fixture.add_child(station)

	var ship := ShipScene.instantiate() as Ship
	ship.loadout = DefaultLoadout
	fixture.add_child(ship)

	var screen := ShipModifierScreenScene.instantiate() as ShipModifierScreen
	fixture.add_child(screen)
	screen.set_meta("fixture", fixture)
	screen.open(station, ship)
	screen._open_cooldown_frames = 0
	return screen


func _press_action(action_name: StringName) -> void:
	Input.action_press(action_name)
	Input.flush_buffered_events()


func _release_action(action_name: StringName) -> void:
	Input.action_release(action_name)
	Input.flush_buffered_events()


func _discard_screen(screen: ShipModifierScreen) -> void:
	if screen.is_open():
		screen.close()
	var fixture := screen.get_meta("fixture") as Node
	if fixture:
		fixture.queue_free()
	else:
		screen.queue_free()
