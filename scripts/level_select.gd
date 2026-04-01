extends Control

signal level_selected(index: int)

var _buttons: Array[Button] = []


func setup(level_names: Array[String]) -> void:
	var container := %LevelList
	for child in container.get_children():
		child.queue_free()
	_buttons.clear()

	for i in level_names.size():
		var btn := Button.new()
		btn.text = level_names[i]
		btn.custom_minimum_size = Vector2(300, 50)
		btn.pressed.connect(_on_level_pressed.bind(i))
		container.add_child(btn)
		_buttons.append(btn)


func _on_level_pressed(index: int) -> void:
	level_selected.emit(index)
