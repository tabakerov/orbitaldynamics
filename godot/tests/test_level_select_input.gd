extends Node

const LevelSelectScript = preload("res://scripts/level_select.gd")
const MainScene = preload("res://scenes/main.tscn")


func _ready() -> void:
	await _test_gamepad_accept_selects_focused_level()
	await _test_pause_menu_action_opens_level_list()
	await _test_loaded_level_freezes_while_intro_is_shown()
	print("All level select input tests passed!")
	get_tree().quit()


func _test_gamepad_accept_selects_focused_level() -> void:
	var level_select := Control.new()
	level_select.set_script(LevelSelectScript)
	add_child(level_select)

	var level_list := VBoxContainer.new()
	level_list.name = "LevelList"
	level_select.add_child(level_list)
	level_list.owner = level_select
	level_list.unique_name_in_owner = true

	var selected_index := {"value": -1}
	level_select.level_selected.connect(
		func(index: int) -> void:
			selected_index["value"] = index
	)

	var level_names: Array[String] = ["Level 1"]
	level_select.setup(level_names)
	level_select.show_menu(false)
	await get_tree().process_frame

	Input.action_press("menu_accept")
	Input.flush_buffered_events()
	level_select._process(0.0)
	Input.action_release("menu_accept")
	Input.flush_buffered_events()

	assert(selected_index["value"] == 0, "Gamepad menu_accept should press the focused level button.")
	print("  PASS: gamepad accept selects focused level")

	level_select.queue_free()
	await get_tree().process_frame


func _test_pause_menu_action_opens_level_list() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame

	main._hide_menu()
	assert(not main._level_select.visible, "Level list should be hidden before pressing pause_menu.")

	Input.action_press("pause_menu")
	Input.flush_buffered_events()
	main._unhandled_input(InputEventAction.new())
	Input.action_release("pause_menu")
	Input.flush_buffered_events()

	assert(main._level_select.visible, "Gamepad pause_menu should open the level list.")
	print("  PASS: gamepad pause opens level list")

	get_tree().paused = false
	main.queue_free()
	await get_tree().process_frame


func _test_loaded_level_freezes_while_intro_is_shown() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame

	main._on_level_selected(0)
	while main._loading:
		await get_tree().process_frame

	assert(main._current_level != null, "Level 0 should load.")
	assert(main._intro_overlay.visible, "Level 0 has an intro message, so the intro overlay should be shown.")
	assert(get_tree().paused, "The tree should be paused while the intro overlay is shown.")
	assert(
		not main._current_level.can_process(),
		"The loaded level must pause with the tree; it must not inherit Main's PROCESS_MODE_ALWAYS.",
	)
	print("  PASS: loaded level freezes while intro is shown")

	get_tree().paused = false
	main.queue_free()
	await get_tree().process_frame
	CelestialSim.clear()
	FloatingGravity.clear()
	AsteroidCollisions.clear()
