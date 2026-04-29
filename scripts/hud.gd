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

const TARGET_INDICATOR_EDGE_PADDING: float = 36.0
const TARGET_INDICATOR_DIRECTION_EPSILON: float = 0.001

var _camera: Camera3D
var _target: Target
var _target_indicator: TargetIndicator

@onready var _fuel_bar: ProgressBar = %FuelBar
@onready var _fuel_label: Label = %FuelLabel


func _ready() -> void:
	_target_indicator = TargetIndicator.new()
	_target_indicator.name = "TargetIndicator"
	_target_indicator.visible = false
	_target_indicator.z_index = 10
	add_child(_target_indicator)


func setup(ship: Ship, camera: Camera3D = null, target: Target = null) -> void:
	_camera = camera
	_target = target
	ship.fuel_changed.connect(_on_fuel_changed)
	_on_fuel_changed(ship.fuel, ship.max_fuel)
	_update_target_indicator()


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
