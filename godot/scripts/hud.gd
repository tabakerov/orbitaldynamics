extends Control

class TargetIndicator:
	extends Control

	const INDICATOR_SIZE := Vector2(34.0, 34.0)
	const FILL_COLOR := Color(1.0, 0.82, 0.16, 0.95)
	const OUTLINE_COLOR := Color(0.1, 0.07, 0.02, 0.9)

	var angle: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = INDICATOR_SIZE
		pivot_offset = INDICATOR_SIZE * 0.5

	func set_angle(value: float) -> void:
		if is_equal_approx(angle, value):
			return
		angle = value
		queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		var points := PackedVector2Array([
			center + Vector2(13.0, 0.0).rotated(angle),
			center + Vector2(-8.0, -8.5).rotated(angle),
			center + Vector2(-4.0, 0.0).rotated(angle),
			center + Vector2(-8.0, 8.5).rotated(angle),
		])
		draw_colored_polygon(points, FILL_COLOR)

		var outline := PackedVector2Array(points)
		outline.append(points[0])
		draw_polyline(outline, OUTLINE_COLOR, 2.0, true)

class Minimap:
	extends Control

	const MAP_SIZE := Vector2(184.0, 184.0)
	const MAP_MARGIN := 18.0
	const MAP_PADDING := 18.0
	const WORLD_PADDING := 35.0
	const MIN_WORLD_EXTENT := 80.0
	const BACKGROUND_COLOR := Color(0.015, 0.025, 0.055, 0.72)
	const BORDER_COLOR := Color(0.55, 0.72, 0.95, 0.42)
	const GRID_COLOR := Color(0.55, 0.72, 0.95, 0.13)
	const SHIP_COLOR := Color(0.72, 0.96, 1.0, 1.0)
	const TARGET_COLOR := Color(1.0, 0.82, 0.16, 1.0)
	const BODY_COLOR := Color(0.34, 0.62, 1.0, 0.9)
	const BLACK_HOLE_COLOR := Color(0.02, 0.015, 0.05, 0.96)
	const BLACK_HOLE_RING_COLOR := Color(0.82, 0.45, 1.0, 0.92)
	const STATION_COLOR := Color(0.95, 0.45, 1.0, 0.95)
	const FUEL_COLOR := Color(0.25, 1.0, 0.45, 0.95)
	const STAR_COLOR := Color(1.0, 0.85, 0.25, 0.95)
	const LASER_AMMO_COLOR := Color(0.35, 0.85, 1.0, 0.95)
	const ROCKET_AMMO_COLOR := Color(1.0, 0.55, 0.2, 0.95)
	const ROCKET_COLOR := Color(1.0, 0.35, 0.3, 0.95)
	const DEBRIS_COLOR := Color(0.62, 0.58, 0.54, 0.9)

	var level: Level
	var ship: Ship

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = MAP_SIZE
		size = MAP_SIZE
		set_anchors_preset(Control.PRESET_TOP_RIGHT)
		offset_left = -MAP_SIZE.x - MAP_MARGIN
		offset_top = MAP_MARGIN
		offset_right = -MAP_MARGIN
		offset_bottom = MAP_MARGIN + MAP_SIZE.y

	func setup(new_level: Level, new_ship: Ship) -> void:
		level = new_level
		ship = new_ship
		visible = level != null and ship != null
		queue_redraw()

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR, true)
		_draw_grid()
		draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 1.5)

		if not level or not is_instance_valid(level) or not ship or not is_instance_valid(ship):
			return

		var bounds := _calculate_world_bounds()
		var transform := _calculate_map_transform(bounds)
		_draw_celestial_bodies(transform)
		_draw_stations(transform)
		_draw_floating_objects(transform)
		_draw_target(transform)
		_draw_ship(transform)

	func _draw_grid() -> void:
		for i in range(1, 4):
			var x := size.x * float(i) / 4.0
			var y := size.y * float(i) / 4.0
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), GRID_COLOR, 1.0)
			draw_line(Vector2(0.0, y), Vector2(size.x, y), GRID_COLOR, 1.0)

	func _calculate_world_bounds() -> Rect2:
		var points: Array[Vector2] = []
		_add_node_point(points, ship)
		_add_node_point(points, level.get_target())
		for body in level.get_celestial_bodies():
			_add_node_point(points, body)
		for station in level.get_stations():
			_add_node_point(points, station)
		for object in level.get_floating_objects():
			# Spawned objects roam and would make the map scale jitter;
			# only hand-placed ones (direct children) define the bounds.
			if object.get_parent() == level:
				_add_node_point(points, object)
		for spawner in level.get_spawners():
			var extent: float = spawner.get_volume_extent()
			var center := _world_to_plane(spawner.global_position)
			points.append(center + Vector2(extent, extent))
			points.append(center - Vector2(extent, extent))

		if points.is_empty():
			points.append(Vector2.ZERO)

		var min_point := points[0]
		var max_point := points[0]
		for point in points:
			min_point.x = minf(min_point.x, point.x)
			min_point.y = minf(min_point.y, point.y)
			max_point.x = maxf(max_point.x, point.x)
			max_point.y = maxf(max_point.y, point.y)

		var center := (min_point + max_point) * 0.5
		var extents := max_point - min_point
		extents.x = maxf(extents.x + WORLD_PADDING * 2.0, MIN_WORLD_EXTENT)
		extents.y = maxf(extents.y + WORLD_PADDING * 2.0, MIN_WORLD_EXTENT)
		return Rect2(center - extents * 0.5, extents)

	func _add_node_point(points: Array[Vector2], node: Node3D) -> void:
		if node and is_instance_valid(node):
			points.append(_world_to_plane(node.global_position))

	func _calculate_map_transform(bounds: Rect2) -> Dictionary:
		var drawable_size := size - Vector2(MAP_PADDING * 2.0, MAP_PADDING * 2.0)
		var scale: float = minf(
			drawable_size.x / maxf(bounds.size.x, 1.0),
			drawable_size.y / maxf(bounds.size.y, 1.0)
		)
		var world_center := bounds.position + bounds.size * 0.5
		return {
			"scale": scale,
			"world_center": world_center,
			"screen_center": size * 0.5,
		}

	func _world_to_map(world_position: Vector3, map_transform: Dictionary) -> Vector2:
		var plane_position := _world_to_plane(world_position)
		var world_center: Vector2 = map_transform["world_center"]
		var screen_center: Vector2 = map_transform["screen_center"]
		var scale: float = map_transform["scale"]
		return screen_center + (plane_position - world_center) * scale

	func _world_to_plane(world_position: Vector3) -> Vector2:
		return Vector2(world_position.x, world_position.z)

	func _draw_celestial_bodies(map_transform: Dictionary) -> void:
		for body in level.get_celestial_bodies():
			if not is_instance_valid(body):
				continue
			var position := _world_to_map(body.global_position, map_transform)
			var radius := 5.0
			if body.body_data:
				var scale: float = map_transform["scale"]
				radius = clampf(body.body_data.radius * scale, 4.0, 18.0)
			if body is BlackHole:
				draw_circle(position, radius, BLACK_HOLE_COLOR)
				draw_arc(position, radius + 2.0, 0.0, TAU, 36, BLACK_HOLE_RING_COLOR, 2.0)
			else:
				draw_circle(position, radius, BODY_COLOR)
				draw_arc(position, radius + 1.0, 0.0, TAU, 30, Color(BODY_COLOR, 0.45), 1.5)

	func _draw_stations(map_transform: Dictionary) -> void:
		for station in level.get_stations():
			if not is_instance_valid(station):
				continue
			var position := _world_to_map(station.global_position, map_transform)
			var rect := Rect2(position - Vector2(4.5, 4.5), Vector2(9.0, 9.0))
			draw_rect(rect, STATION_COLOR, false, 2.0)
			draw_line(position + Vector2(-6.0, 0.0), position + Vector2(6.0, 0.0), STATION_COLOR, 1.5)
			draw_line(position + Vector2(0.0, -6.0), position + Vector2(0.0, 6.0), STATION_COLOR, 1.5)

	func _draw_floating_objects(map_transform: Dictionary) -> void:
		var visible_rect := Rect2(Vector2.ZERO, size)
		for object in level.get_floating_objects():
			if not is_instance_valid(object):
				continue
			var object_position := _world_to_map(object.global_position, map_transform)
			if not visible_rect.has_point(object_position):
				continue
			if object is FuelPickup:
				draw_circle(object_position, 3.5, FUEL_COLOR)
			elif object is BonusStar:
				draw_circle(object_position, 3.5, STAR_COLOR)
			elif object is AmmoPickup:
				var is_laser: bool = object.ammo_type == WeaponProfile.AmmoType.LASER
				draw_circle(object_position, 3.5, LASER_AMMO_COLOR if is_laser else ROCKET_AMMO_COLOR)
			elif object is Rocket:
				draw_circle(object_position, 2.5, ROCKET_COLOR)
			else:
				draw_circle(object_position, 2.5, DEBRIS_COLOR)

	func _draw_target(map_transform: Dictionary) -> void:
		var target := level.get_target()
		if not target or not is_instance_valid(target):
			return
		var position := _world_to_map(target.global_position, map_transform)
		var points := PackedVector2Array([
			position + Vector2(0.0, -7.0),
			position + Vector2(7.0, 0.0),
			position + Vector2(0.0, 7.0),
			position + Vector2(-7.0, 0.0),
		])
		draw_colored_polygon(points, TARGET_COLOR)
		points.append(points[0])
		draw_polyline(points, Color(0.1, 0.07, 0.02, 0.85), 1.5, true)

	func _draw_ship(map_transform: Dictionary) -> void:
		var position := _world_to_map(ship.global_position, map_transform)
		var forward_3d := -ship.global_transform.basis.z
		var forward := Vector2(forward_3d.x, forward_3d.z)
		if forward.length_squared() <= 0.0001:
			forward = Vector2(0.0, -1.0)
		forward = forward.normalized()
		var right := Vector2(-forward.y, forward.x)
		var points := PackedVector2Array([
			position + forward * 10.0,
			position - forward * 7.0 + right * 5.5,
			position - forward * 4.0,
			position - forward * 7.0 - right * 5.5,
		])
		draw_colored_polygon(points, SHIP_COLOR)
		points.append(points[0])
		draw_polyline(points, Color(0.02, 0.08, 0.1, 0.95), 1.5, true)

const TARGET_INDICATOR_EDGE_PADDING: float = 36.0
const TARGET_INDICATOR_DIRECTION_EPSILON: float = 0.001

const AMMO_LASER_FONT_COLOR := Color(0.45, 0.9, 1.0, 1.0)
const AMMO_ROCKET_FONT_COLOR := Color(1.0, 0.6, 0.25, 1.0)

var _camera: Camera3D
var _target: Target
var _level: Level
var _target_indicator: TargetIndicator
var _minimap: Minimap
var _dock_prompt: Label
var _score_label: Label
var _cheat_label: Label
var _ammo_label: Label

@onready var _fuel_bar: ProgressBar = %FuelBar
@onready var _fuel_label: Label = %FuelLabel


func _ready() -> void:
	_target_indicator = TargetIndicator.new()
	_target_indicator.name = "TargetIndicator"
	_target_indicator.visible = false
	_target_indicator.z_index = 10
	add_child(_target_indicator)

	_minimap = Minimap.new()
	_minimap.name = "Minimap"
	_minimap.z_index = 5
	add_child(_minimap)

	_dock_prompt = Label.new()
	_dock_prompt.name = "DockPrompt"
	_dock_prompt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_dock_prompt.offset_left = -220.0
	_dock_prompt.offset_top = 32.0
	_dock_prompt.offset_right = 220.0
	_dock_prompt.offset_bottom = 88.0
	_dock_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dock_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_dock_prompt.add_theme_font_size_override("font_size", 24)
	_dock_prompt.add_theme_color_override("font_color", Color(0.95, 0.6, 1, 1))
	_dock_prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.08, 1))
	_dock_prompt.add_theme_constant_override("outline_size", 4)
	_dock_prompt.visible = false
	_dock_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_prompt.z_index = 10
	add_child(_dock_prompt)

	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_score_label.offset_left = 18.0
	_score_label.offset_top = 12.0
	_score_label.offset_right = 340.0
	_score_label.offset_bottom = 56.0
	_score_label.add_theme_font_size_override("font_size", 30)
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_score_label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.01, 1.0))
	_score_label.add_theme_constant_override("outline_size", 5)
	_score_label.visible = false
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label.z_index = 10
	add_child(_score_label)

	_cheat_label = Label.new()
	_cheat_label.name = "CheatLabel"
	_cheat_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_cheat_label.offset_left = -220.0
	_cheat_label.offset_top = 12.0
	_cheat_label.offset_right = 220.0
	_cheat_label.offset_bottom = 46.0
	_cheat_label.text = "ЧИТ-РЕЖИМ: НЕУЯЗВИМОСТЬ + ТОПЛИВО"
	_cheat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cheat_label.add_theme_font_size_override("font_size", 18)
	_cheat_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35, 1.0))
	_cheat_label.add_theme_color_override("font_outline_color", Color(0.08, 0.01, 0.01, 1.0))
	_cheat_label.add_theme_constant_override("outline_size", 4)
	_cheat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cheat_label.z_index = 10
	_cheat_label.visible = Cheats.enabled
	add_child(_cheat_label)
	Cheats.changed.connect(_on_cheats_changed)

	_ammo_label = Label.new()
	_ammo_label.name = "AmmoLabel"
	# Sits just above the fuel readout (FuelLabel spans anchors 0.88–0.92).
	_ammo_label.anchor_left = 0.02
	_ammo_label.anchor_top = 0.83
	_ammo_label.anchor_right = 0.3
	_ammo_label.anchor_bottom = 0.88
	_ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_ammo_label.add_theme_font_size_override("font_size", 22)
	_ammo_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 1.0))
	_ammo_label.add_theme_constant_override("outline_size", 4)
	_ammo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ammo_label.z_index = 10
	_ammo_label.visible = false
	add_child(_ammo_label)


func show_dock_prompt(station_name: String = "станции") -> void:
	if not _dock_prompt:
		return
	_dock_prompt.text = "F · LB — стыковка с %s" % station_name
	_dock_prompt.visible = true


func hide_dock_prompt() -> void:
	if _dock_prompt:
		_dock_prompt.visible = false


func setup(ship: Ship, camera: Camera3D = null, target: Target = null, level: Level = null) -> void:
	_camera = camera
	_target = target
	_level = level
	ship.fuel_changed.connect(_on_fuel_changed)
	_on_fuel_changed(ship.fuel, ship.max_fuel)
	if _minimap:
		_minimap.setup(_level, ship)
	_setup_score(_level.get_score_tracker() if _level else null)
	_setup_ammo(ship)
	_update_target_indicator()


func _setup_score(tracker: ScoreTracker) -> void:
	if not _score_label:
		return
	_score_label.visible = tracker != null
	if tracker:
		_on_score_changed(tracker.get_score())
		tracker.score_changed.connect(_on_score_changed)


func _on_score_changed(score: int) -> void:
	_score_label.text = "Очки: %d" % score


func _setup_ammo(ship: Ship) -> void:
	if not _ammo_label:
		return
	var weapons := ship.get_weapon_modules()
	_ammo_label.visible = not weapons.is_empty()
	for weapon in weapons:
		weapon.ammo_changed.connect(_on_ammo_changed)
		_on_ammo_changed(weapon.current_type, weapon.laser_charges, weapon.rocket_charges)


func _on_ammo_changed(current_type: int, laser_charges: int, rocket_charges: int) -> void:
	if current_type == WeaponProfile.AmmoType.LASER:
		_ammo_label.text = "Лазер: %d  ·  ракеты: %d" % [laser_charges, rocket_charges]
		_ammo_label.add_theme_color_override("font_color", AMMO_LASER_FONT_COLOR)
	else:
		_ammo_label.text = "Ракеты: %d  ·  лазер: %d" % [rocket_charges, laser_charges]
		_ammo_label.add_theme_color_override("font_color", AMMO_ROCKET_FONT_COLOR)


func _on_cheats_changed(cheats_enabled: bool) -> void:
	_cheat_label.visible = cheats_enabled


func _process(_delta: float) -> void:
	_update_target_indicator()


func _on_fuel_changed(current: float, maximum: float) -> void:
	_fuel_bar.max_value = maximum
	_fuel_bar.value = current
	_fuel_label.text = "Fuel: %d%%" % roundi(current / maximum * 100.0)


func _update_target_indicator() -> void:
	if not _target_indicator:
		return
	if not _camera or not is_instance_valid(_camera) or not _target or not is_instance_valid(_target):
		_target_indicator.visible = false
		return

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		_target_indicator.visible = false
		return

	var target_position := _target.global_position
	var screen_position := _camera.unproject_position(target_position)
	var target_is_behind := _camera.is_position_behind(target_position)
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	if not target_is_behind and viewport_rect.has_point(screen_position):
		_target_indicator.visible = false
		return

	var screen_center := viewport_size * 0.5
	var direction := screen_position - screen_center
	if target_is_behind:
		direction = -direction
	if direction.length_squared() <= TARGET_INDICATOR_DIRECTION_EPSILON:
		direction = Vector2.UP

	var edge_extent := screen_center - Vector2(
		TARGET_INDICATOR_EDGE_PADDING,
		TARGET_INDICATOR_EDGE_PADDING
	)
	var scale_x: float = 1000000.0
	var scale_y: float = 1000000.0
	if absf(direction.x) > TARGET_INDICATOR_DIRECTION_EPSILON:
		scale_x = edge_extent.x / absf(direction.x)
	if absf(direction.y) > TARGET_INDICATOR_DIRECTION_EPSILON:
		scale_y = edge_extent.y / absf(direction.y)

	var edge_position := screen_center + direction * minf(scale_x, scale_y)
	var indicator_size := _target_indicator.size
	_target_indicator.position = edge_position - indicator_size * 0.5
	_target_indicator.set_angle(direction.angle())
	_target_indicator.visible = true
