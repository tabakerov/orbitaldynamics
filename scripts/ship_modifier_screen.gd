class_name ShipModifierScreen
extends Control

enum State { PICK_MOUNT, PICK_MODULE }

signal closed
signal apply_loadout_change(binding: int, new_profile: ModuleProfile)

const CHIP_BINDINGS: Array[int] = [
	MountSlot.Binding.FRONT,
	MountSlot.Binding.REAR,
	MountSlot.Binding.LEFT,
	MountSlot.Binding.RIGHT,
]

var _state: State = State.PICK_MOUNT
var _selected_binding: int = MountSlot.Binding.FRONT
var _selected_module_idx: int = 0
var _station: Station
var _ship: Ship
var _open_cooldown_frames: int = 0

var _title_label: Label
var _subtitle_label: Label
var _chip_panels: Dictionary = {}
var _chip_labels: Dictionary = {}
var _hull_panel: Panel
var _module_list_panel: Panel
var _module_list_vbox: VBoxContainer
var _help_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()


func open(station: Station, ship: Ship) -> void:
	_station = station
	_ship = ship
	_state = State.PICK_MOUNT
	_selected_binding = MountSlot.Binding.FRONT
	_subtitle_label.text = station.get_display_name()
	_refresh_chips()
	_hide_module_list()
	_refresh_help()
	visible = true
	_open_cooldown_frames = 2
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false
	closed.emit()


func is_open() -> bool:
	return visible


func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.015, 0.025, 0.055, 0.92)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	_title_label = _make_label("СТАНЦИЯ ОБСЛУЖИВАНИЯ", 38, Color(0.95, 0.6, 1, 1))
	_title_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_title_label.offset_left = -400.0
	_title_label.offset_right = 400.0
	_title_label.offset_top = 40.0
	_title_label.offset_bottom = 100.0
	add_child(_title_label)

	_subtitle_label = _make_label("", 22, Color(0.8, 0.75, 0.9, 1))
	_subtitle_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_subtitle_label.offset_left = -400.0
	_subtitle_label.offset_right = 400.0
	_subtitle_label.offset_top = 100.0
	_subtitle_label.offset_bottom = 140.0
	add_child(_subtitle_label)

	_hull_panel = _make_panel(Color(0.18, 0.32, 0.7, 0.9), Color(0.4, 0.55, 1, 1))
	_hull_panel.set_anchors_preset(Control.PRESET_CENTER)
	_hull_panel.offset_left = -90.0
	_hull_panel.offset_right = 90.0
	_hull_panel.offset_top = -90.0
	_hull_panel.offset_bottom = 90.0
	add_child(_hull_panel)
	var hull_label := _make_label("КОРПУС", 20, Color(0.95, 0.95, 1, 1))
	hull_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hull_panel.add_child(hull_label)

	_make_chip(MountSlot.Binding.FRONT, Vector2(-150, -270), Vector2(150, -160))
	_make_chip(MountSlot.Binding.REAR, Vector2(-150, 160), Vector2(150, 270))
	_make_chip(MountSlot.Binding.LEFT, Vector2(-430, -55), Vector2(-110, 55))
	_make_chip(MountSlot.Binding.RIGHT, Vector2(110, -55), Vector2(430, 55))

	_module_list_panel = _make_panel(Color(0.05, 0.08, 0.15, 0.96), Color(0.55, 0.35, 0.7, 1))
	_module_list_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_module_list_panel.offset_left = -440.0
	_module_list_panel.offset_right = -40.0
	_module_list_panel.offset_top = 180.0
	_module_list_panel.offset_bottom = -120.0
	_module_list_panel.visible = false
	add_child(_module_list_panel)

	_module_list_vbox = VBoxContainer.new()
	_module_list_vbox.name = "Items"
	_module_list_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_module_list_vbox.offset_left = 24.0
	_module_list_vbox.offset_top = 24.0
	_module_list_vbox.offset_right = -24.0
	_module_list_vbox.offset_bottom = -24.0
	_module_list_vbox.add_theme_constant_override("separation", 10)
	_module_list_panel.add_child(_module_list_vbox)

	_help_label = _make_label("", 18, Color(0.7, 0.7, 0.78, 1))
	_help_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_help_label.offset_left = -800.0
	_help_label.offset_right = 800.0
	_help_label.offset_top = -56.0
	_help_label.offset_bottom = -20.0
	add_child(_help_label)


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_panel(bg: Color, border: Color) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	style.border_color = border
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_chip(binding: int, top_left: Vector2, bottom_right: Vector2) -> void:
	var panel := _make_panel(Color(0.08, 0.08, 0.14, 0.92), Color(0.4, 0.3, 0.6, 1))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = top_left.x
	panel.offset_top = top_left.y
	panel.offset_right = bottom_right.x
	panel.offset_bottom = bottom_right.y
	add_child(panel)
	_chip_panels[binding] = panel

	var label := _make_label("", 18, Color(0.9, 0.9, 0.95, 1))
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 8.0
	label.offset_right = -8.0
	label.offset_top = 6.0
	label.offset_bottom = -6.0
	panel.add_child(label)
	_chip_labels[binding] = label


func _refresh_chips() -> void:
	for binding: int in CHIP_BINDINGS:
		var label: Label = _chip_labels[binding]
		var panel: Panel = _chip_panels[binding]
		label.text = _chip_text(binding)
		var is_selected: bool = binding == _selected_binding and _state == State.PICK_MOUNT
		label.add_theme_color_override(
			"font_color",
			Color(1, 0.85, 0.3, 1) if is_selected else Color(0.9, 0.9, 0.95, 1),
		)
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style:
			style.border_color = Color(1, 0.7, 0.2, 1) if is_selected else Color(0.4, 0.3, 0.6, 1)
			style.set_border_width_all(4 if is_selected else 2)


func _chip_text(binding: int) -> String:
	var name := _chip_name(binding)
	var profile: ModuleProfile = null
	if _ship and _ship.loadout:
		profile = _ship.loadout.get_module(binding)
	var module_text := "(пусто)"
	if profile and not profile.display_name.is_empty():
		module_text = profile.display_name
	elif profile:
		module_text = profile.resource_path.get_file().get_basename()
	return "%s\n%s" % [name, module_text]


func _chip_name(binding: int) -> String:
	match binding:
		MountSlot.Binding.FRONT: return "НОС"
		MountSlot.Binding.REAR: return "КОРМА"
		MountSlot.Binding.LEFT: return "ЛЕВЫЙ"
		MountSlot.Binding.RIGHT: return "ПРАВЫЙ"
	return "?"


func _process(_delta: float) -> void:
	if not visible:
		return
	if _open_cooldown_frames > 0:
		_open_cooldown_frames -= 1
		return
	if _state == State.PICK_MOUNT:
		_handle_pick_mount_polling()
	else:
		_handle_pick_module_polling()


func _handle_pick_mount_polling() -> void:
	if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("station_dock"):
		close()
	elif Input.is_action_just_pressed("ui_accept"):
		_enter_module_pick()
	elif Input.is_action_just_pressed("ui_up"):
		_select_binding(MountSlot.Binding.FRONT)
	elif Input.is_action_just_pressed("ui_down"):
		_select_binding(MountSlot.Binding.REAR)
	elif Input.is_action_just_pressed("ui_left"):
		_select_binding(MountSlot.Binding.LEFT)
	elif Input.is_action_just_pressed("ui_right"):
		_select_binding(MountSlot.Binding.RIGHT)


func _select_binding(binding: int) -> void:
	_selected_binding = binding
	_refresh_chips()


func _enter_module_pick() -> void:
	_state = State.PICK_MODULE
	_build_module_list()
	_selected_module_idx = _find_current_module_idx()
	_refresh_module_highlight()
	_module_list_panel.visible = true
	_refresh_help()


func _find_current_module_idx() -> int:
	if not _ship or not _ship.loadout:
		return 0
	var current := _ship.loadout.get_module(_selected_binding)
	var available := _station.get_available_modules() if _station else []
	if not current:
		return available.size()  # last item is "(снять модуль)"
	for i in available.size():
		if available[i] == current:
			return i
	return available.size()


func _build_module_list() -> void:
	for child in _module_list_vbox.get_children():
		child.queue_free()

	var header := _make_label("В %s поставить:" % _chip_name(_selected_binding), 22, Color(0.95, 0.7, 1, 1))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_module_list_vbox.add_child(header)

	var separator := HSeparator.new()
	_module_list_vbox.add_child(separator)

	var available := _station.get_available_modules() if _station else []
	for profile: ModuleProfile in available:
		_module_list_vbox.add_child(_make_module_item(profile))
	_module_list_vbox.add_child(_make_module_item(null))
	_refresh_module_highlight()


func _make_module_item(profile: ModuleProfile) -> Label:
	var item := Label.new()
	if profile:
		var name := profile.display_name if not profile.display_name.is_empty() else profile.resource_path.get_file().get_basename()
		item.text = "  %s" % name
	else:
		item.text = "  (снять модуль)"
	item.add_theme_font_size_override("font_size", 19)
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95, 1))
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.set_meta("profile", profile)
	return item


func _refresh_module_highlight() -> void:
	var idx := 0
	for child in _module_list_vbox.get_children():
		if not child.has_meta("profile"):
			continue
		var label := child as Label
		var is_selected := idx == _selected_module_idx
		label.add_theme_color_override(
			"font_color",
			Color(1, 0.85, 0.3, 1) if is_selected else Color(0.9, 0.9, 0.95, 1),
		)
		idx += 1


func _handle_pick_module_polling() -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		_exit_module_pick()
	elif Input.is_action_just_pressed("ui_accept"):
		_apply_selected_module()
	elif Input.is_action_just_pressed("ui_up"):
		_step_module(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_step_module(1)


func _step_module(delta: int) -> void:
	var count := _count_module_items()
	if count <= 0:
		return
	_selected_module_idx = (_selected_module_idx + delta + count) % count
	_refresh_module_highlight()


func _count_module_items() -> int:
	var count := 0
	for child in _module_list_vbox.get_children():
		if child.has_meta("profile"):
			count += 1
	return count


func _apply_selected_module() -> void:
	var item := _get_module_item_at(_selected_module_idx)
	if not item:
		return
	var profile: ModuleProfile = item.get_meta("profile")
	apply_loadout_change.emit(_selected_binding, profile)
	_refresh_chips()
	_exit_module_pick()


func _get_module_item_at(idx: int) -> Label:
	var counter := 0
	for child in _module_list_vbox.get_children():
		if not child.has_meta("profile"):
			continue
		if counter == idx:
			return child as Label
		counter += 1
	return null


func _exit_module_pick() -> void:
	_state = State.PICK_MOUNT
	_hide_module_list()
	_refresh_chips()
	_refresh_help()


func _hide_module_list() -> void:
	if _module_list_panel:
		_module_list_panel.visible = false


func _refresh_help() -> void:
	if _state == State.PICK_MOUNT:
		_help_label.text = "↑↓←→ — выбор слота · A/Enter — поменять модуль · LB/B/Esc — закрыть"
	else:
		_help_label.text = "↑↓ — выбор модуля · A/Enter — установить · B/Esc — назад"
