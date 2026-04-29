extends Node3D

@export var levels: Array[PackedScene] = []

const CRASH_OVERLAY_DELAY_SECONDS: float = 2.0

var _current_level: Level
var _level_index: int = 0
var _loading: bool = false
var _crash_sequence: int = 0
var _crash_overlay: Control
var _crash_restart_btn: Button
var _crash_menu_btn: Button
var _completion_overlay: Control
var _completion_next_btn: Button
var _completion_menu_btn: Button

@onready var _camera_rig: CameraRig = $CameraRig
@onready var _hud: Control = $CanvasLayer/HUD
@onready var _level_select: Control = $MenuLayer/LevelSelect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var names: Array[String] = []
	for i in levels.size():
		names.append("Level %d" % (i + 1))
	_level_select.setup(names)
	_level_select.level_selected.connect(_on_level_selected)
	_level_select.restart_requested.connect(_on_restart_requested)
	_level_select.quit_requested.connect(_on_quit_requested)
	_setup_crash_overlay()
	_setup_completion_overlay()
	_show_menu()


func _show_menu() -> void:
	_cancel_crash_sequence()
	_hide_crash_overlay()
	_hide_completion_overlay()
	_level_select.show_menu(_current_level != null)
	_hud.visible = false
	get_tree().paused = true


func _hide_menu() -> void:
	_cancel_crash_sequence()
	_level_select.visible = false
	_hide_crash_overlay()
	_hide_completion_overlay()
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
	_cancel_crash_sequence()
	_hide_crash_overlay()
	_hide_completion_overlay()
	_loading = true

	if _current_level:
		_current_level.queue_free()
		await _current_level.tree_exited

	_level_index = clampi(index, 0, levels.size() - 1)
	var scene_instance := levels[_level_index].instantiate()
	_current_level = scene_instance as Level
	if not _current_level:
		push_error("Failed to load level %d" % index)
		_loading = false
		return
	add_child(_current_level)

	_current_level.level_completed.connect(_on_level_completed)
	_current_level.ship_crashed.connect(_on_ship_crashed)

	var ship := _current_level.get_ship()
	if ship:
		_camera_rig.set_target(ship)
		_hud.setup(ship, _camera_rig.get_camera(), _current_level.get_target())

	_loading = false


func _on_level_completed() -> void:
	if _loading or (_completion_overlay and _completion_overlay.visible):
		return
	_cancel_crash_sequence()
	_show_completion_overlay()


func _on_ship_crashed(crash_position: Vector3) -> void:
	if (
		_loading
		or (_crash_overlay and _crash_overlay.visible)
		or (_completion_overlay and _completion_overlay.visible)
	):
		return
	var crashed_level := _current_level
	_crash_sequence += 1
	var crash_sequence := _crash_sequence
	if _current_level:
		_current_level.spawn_crash_explosion(crash_position)

	_hud.visible = false
	await get_tree().create_timer(CRASH_OVERLAY_DELAY_SECONDS, true).timeout
	if crash_sequence != _crash_sequence or _loading:
		return
	if _current_level != crashed_level:
		return
	_show_crash_overlay()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("engine_rear"):
		var focused := get_viewport().gui_get_focus_owner()
		if _crash_overlay and _crash_overlay.visible and (focused == _crash_restart_btn or focused == _crash_menu_btn):
			focused.emit_signal("pressed")
			get_viewport().set_input_as_handled()
		elif (
			_completion_overlay
			and _completion_overlay.visible
			and (focused == _completion_next_btn or focused == _completion_menu_btn)
		):
			focused.emit_signal("pressed")
			get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	if _crash_overlay and _crash_overlay.visible:
		if Input.is_action_just_pressed("restart"):
			_on_crash_restart_requested()
			get_viewport().set_input_as_handled()
		elif Input.is_action_just_pressed("ui_cancel"):
			_on_crash_menu_requested()
			get_viewport().set_input_as_handled()
		return

	if _completion_overlay and _completion_overlay.visible:
		if Input.is_action_just_pressed("ui_cancel"):
			_on_completion_menu_requested()
			get_viewport().set_input_as_handled()
		return

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


func _setup_crash_overlay() -> void:
	_crash_overlay = Control.new()
	_crash_overlay.name = "CrashOverlay"
	_crash_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_crash_overlay.visible = false
	_crash_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_crash_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	$MenuLayer.add_child(_crash_overlay)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.03, 0.01, 0.01, 0.78)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crash_overlay.add_child(background)

	var panel := VBoxContainer.new()
	panel.name = "Prompt"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240.0
	panel.offset_top = -130.0
	panel.offset_right = 240.0
	panel.offset_bottom = 130.0
	panel.add_theme_constant_override("separation", 16)
	_crash_overlay.add_child(panel)

	var title := Label.new()
	title.text = "вы разбились"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Перезапустить уровень или выйти в главное меню?"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 20)
	panel.add_child(subtitle)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	panel.add_child(buttons)

	_crash_restart_btn = Button.new()
	_crash_restart_btn.text = "Перезапустить уровень"
	_crash_restart_btn.custom_minimum_size = Vector2(320.0, 50.0)
	_crash_restart_btn.focus_mode = Control.FOCUS_ALL
	_crash_restart_btn.pressed.connect(_on_crash_restart_requested)
	buttons.add_child(_crash_restart_btn)

	_crash_menu_btn = Button.new()
	_crash_menu_btn.text = "В главное меню"
	_crash_menu_btn.custom_minimum_size = Vector2(320.0, 50.0)
	_crash_menu_btn.focus_mode = Control.FOCUS_ALL
	_crash_menu_btn.pressed.connect(_on_crash_menu_requested)
	buttons.add_child(_crash_menu_btn)


func _setup_completion_overlay() -> void:
	_completion_overlay = Control.new()
	_completion_overlay.name = "LevelCompleteOverlay"
	_completion_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_completion_overlay.visible = false
	_completion_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_completion_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	$MenuLayer.add_child(_completion_overlay)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.01, 0.04, 0.05, 0.82)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_completion_overlay.add_child(background)

	var panel := VBoxContainer.new()
	panel.name = "Prompt"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240.0
	panel.offset_top = -120.0
	panel.offset_right = 240.0
	panel.offset_bottom = 120.0
	panel.add_theme_constant_override("separation", 16)
	_completion_overlay.add_child(panel)

	var title := Label.new()
	title.text = "уровень завершён"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	panel.add_child(title)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	panel.add_child(buttons)

	_completion_next_btn = Button.new()
	_completion_next_btn.text = "следующий"
	_completion_next_btn.custom_minimum_size = Vector2(320.0, 50.0)
	_completion_next_btn.focus_mode = Control.FOCUS_ALL
	_completion_next_btn.pressed.connect(_on_completion_next_requested)
	buttons.add_child(_completion_next_btn)

	_completion_menu_btn = Button.new()
	_completion_menu_btn.text = "в меню"
	_completion_menu_btn.custom_minimum_size = Vector2(320.0, 50.0)
	_completion_menu_btn.focus_mode = Control.FOCUS_ALL
	_completion_menu_btn.pressed.connect(_on_completion_menu_requested)
	buttons.add_child(_completion_menu_btn)


func _show_crash_overlay() -> void:
	_level_select.visible = false
	_hide_completion_overlay()
	_hud.visible = false
	_crash_overlay.visible = true
	_crash_restart_btn.call_deferred("grab_focus")
	get_tree().paused = true


func _hide_crash_overlay() -> void:
	if _crash_overlay:
		_crash_overlay.visible = false


func _show_completion_overlay() -> void:
	_level_select.visible = false
	_hide_crash_overlay()
	_hud.visible = false
	_completion_next_btn.disabled = _level_index + 1 >= levels.size()
	_completion_overlay.visible = true
	if _completion_next_btn.disabled:
		_completion_menu_btn.call_deferred("grab_focus")
	else:
		_completion_next_btn.call_deferred("grab_focus")
	get_tree().paused = true


func _hide_completion_overlay() -> void:
	if _completion_overlay:
		_completion_overlay.visible = false


func _cancel_crash_sequence() -> void:
	_crash_sequence += 1


func _on_crash_restart_requested() -> void:
	if _loading:
		return
	_cancel_crash_sequence()
	_hide_crash_overlay()
	_hud.visible = true
	get_tree().paused = false
	_load_level(_level_index)


func _on_completion_next_requested() -> void:
	if _loading:
		return
	if _level_index + 1 >= levels.size():
		return
	_hide_completion_overlay()
	_hud.visible = true
	get_tree().paused = false
	_load_level(_level_index + 1)


func _on_completion_menu_requested() -> void:
	if _loading:
		return
	_return_to_main_menu()


func _on_crash_menu_requested() -> void:
	if _loading:
		return
	_cancel_crash_sequence()
	_return_to_main_menu()


func _return_to_main_menu() -> void:
	_loading = true
	_hide_crash_overlay()
	_hide_completion_overlay()
	_hud.visible = false
	get_tree().paused = false

	var level_to_free := _current_level
	_current_level = null
	if level_to_free:
		level_to_free.queue_free()
		await level_to_free.tree_exited

	_camera_rig.set_target(null)
	CelestialSim.clear()
	_loading = false
	_show_menu()
