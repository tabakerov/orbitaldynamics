extends Node3D

@export var levels: Array[PackedScene] = []
@export var level_names: Array[String] = ["Level 1"]

var _current_level: Level
var _level_index: int = 0
var _loading: bool = false

@onready var _camera_rig: CameraRig = $CameraRig
@onready var _hud: Control = $CanvasLayer/HUD
@onready var _level_select: Control = $MenuLayer/LevelSelect


func _ready() -> void:
	_level_select.setup(level_names)
	_level_select.level_selected.connect(_on_level_selected)
	_level_select.restart_requested.connect(_on_restart_requested)
	_level_select.quit_requested.connect(_on_quit_requested)
	_show_menu()


func _show_menu() -> void:
	_level_select.show_menu(_current_level != null)
	_hud.visible = false
	get_tree().paused = true


func _hide_menu() -> void:
	_level_select.visible = false
	_hud.visible = true
	get_tree().paused = false


func _on_level_selected(index: int) -> void:
	_hide_menu()
	_load_level(index)


func _on_restart_requested() -> void:
	_hide_menu()
	_load_level(_level_index)


func _on_quit_requested() -> void:
	get_tree().quit()


func _load_level(index: int) -> void:
	if _loading:
		return
	_loading = true

	if _current_level:
		_current_level.queue_free()
		await _current_level.tree_exited

	_level_index = clampi(index, 0, levels.size() - 1)
	var scene_instance := levels[_level_index].instantiate()
	_current_level = scene_instance as Level
	if not _current_level:
		push_error("Failed to load level %d" % index)
		return
	add_child(_current_level)

	_current_level.level_completed.connect(_on_level_completed)
	_current_level.ship_crashed.connect(_on_ship_crashed)

	var ship := _current_level.get_ship()
	if ship:
		_camera_rig.set_target(ship)
		_hud.setup(ship)

	_loading = false


func _on_level_completed() -> void:
	if _level_index + 1 < levels.size():
		_load_level(_level_index + 1)
	else:
		_show_menu()


func _on_ship_crashed() -> void:
	_load_level(_level_index)


func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("restart"):
		if _level_select.visible:
			return
		_load_level(_level_index)
	if Input.is_action_just_pressed("ui_cancel"):
		if _level_select.visible:
			if _current_level:
				_hide_menu()
		else:
			_show_menu()
