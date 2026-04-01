extends Control

signal level_selected(index: int)
signal restart_requested
signal quit_requested

var _buttons: Array[Button] = []
var _restart_btn: Button
var _quit_btn: Button


func setup(level_names: Array[String]) -> void:
	var container := %LevelList
	for child in container.get_children():
		child.queue_free()
	_buttons.clear()

	for i in level_names.size():
		var btn := Button.new()
		btn.text = level_names[i]
		btn.custom_minimum_size = Vector2(300, 50)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(_on_level_pressed.bind(i))
		container.add_child(btn)
		_buttons.append(btn)

	_restart_btn = Button.new()
	_restart_btn.text = "Restart Level"
	_restart_btn.custom_minimum_size = Vector2(300, 50)
	_restart_btn.focus_mode = Control.FOCUS_ALL
	_restart_btn.pressed.connect(func() -> void: restart_requested.emit())
	container.add_child(_restart_btn)

	_quit_btn = Button.new()
	_quit_btn.text = "Quit"
	_quit_btn.custom_minimum_size = Vector2(300, 50)
	_quit_btn.focus_mode = Control.FOCUS_ALL
	_quit_btn.pressed.connect(func() -> void: quit_requested.emit())
	container.add_child(_quit_btn)


func show_menu(has_active_level: bool) -> void:
	_restart_btn.visible = has_active_level
	visible = true
	if has_active_level:
		_restart_btn.call_deferred("grab_focus")
	elif _buttons.size() > 0:
		_buttons[0].call_deferred("grab_focus")


func _process(_delta: float) -> void:
	if not visible:
		return
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("engine_rear"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button:
			focused.emit_signal("pressed")


func _on_level_pressed(index: int) -> void:
	level_selected.emit(index)
