class_name DebugFlightVisualizer
extends Node3D

const THRUST_COLOR := Color(0.2, 1.0, 0.35, 0.95)
const GRAVITY_COLOR := Color(0.25, 0.75, 1.0, 0.95)
const TRAJECTORY_COLOR := Color(1.0, 0.82, 0.2, 0.85)
const VELOCITY_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const BODY_GRAVITY_COLOR := Color(1.0, 0.35, 0.95, 0.9)
const BODY_TRAJECTORY_COLOR := Color(1.0, 0.45, 0.15, 0.72)

@export var enabled: bool = false:
	set(value):
		enabled = value
		visible = value
		set_physics_process(value)
		if not value:
			_clear_mesh()

@export var force_scale: float = 0.04
@export var gravity_scale: float = 0.45
@export var velocity_scale: float = 0.12
@export var min_arrow_length: float = 0.75
@export var max_arrow_length: float = 5.0
@export var arrow_head_length: float = 0.45
@export var arrow_head_width: float = 0.22
@export var visual_height_offset: float = 0.45
@export var trajectory_seconds: float = 4.0
@export var trajectory_step: float = 0.12

var ship: Ship
var celestial_bodies: Array[CelestialBody] = []

var _mesh := ImmediateMesh.new()
var _mesh_instance := MeshInstance3D.new()
var _material := StandardMaterial3D.new()


func _ready() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true

	_mesh_instance.name = "DebugLines"
	_mesh_instance.mesh = _mesh
	add_child(_mesh_instance)

	visible = enabled
	set_physics_process(enabled)


func _physics_process(_delta: float) -> void:
	_rebuild_mesh()


func get_prediction_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	if not is_instance_valid(ship):
		return points

	var step := maxf(trajectory_step, 0.01)
	var total_steps := maxi(1, int(ceil(maxf(trajectory_seconds, step) / step)))
	var pos := ship.global_position
	var vel := ship.linear_velocity
	var thrust_accel := Vector3.ZERO
	if ship.mass > 0.0:
		thrust_accel = ship.get_debug_total_thrust_force() / ship.mass

	points.append(_debug_pos(pos))
	for _i in total_steps:
		var accel := CelestialSim.get_gravity_at(pos) + thrust_accel
		vel += accel * step
		pos += vel * step
		pos.y = ship.global_position.y
		vel.y = 0.0
		points.append(_debug_pos(pos))
	return points


func _rebuild_mesh() -> void:
	_clear_mesh()
	if not enabled:
		return

	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	if is_instance_valid(ship):
		_draw_thrust_arrows()
		_draw_gravity_arrow()
		_draw_velocity_arrow()
		_draw_trajectory()
	_draw_body_gravity_arrows()
	_draw_body_trajectories()
	_mesh.surface_end()


func _clear_mesh() -> void:
	if _mesh:
		_mesh.clear_surfaces()


func _draw_thrust_arrows() -> void:
	for sample: Dictionary in ship.get_debug_thrust_force_samples():
		var origin := sample["origin"] as Vector3
		var force := sample["force"] as Vector3
		_add_arrow(_debug_pos(origin), force, force_scale, THRUST_COLOR)


func _draw_gravity_arrow() -> void:
	var gravity := ship.get_debug_gravity_acceleration()
	_add_arrow(_debug_pos(ship.global_position), gravity, gravity_scale, GRAVITY_COLOR)


func _draw_velocity_arrow() -> void:
	_add_arrow(_debug_pos(ship.global_position), ship.linear_velocity, velocity_scale, VELOCITY_COLOR)


func _draw_trajectory() -> void:
	var points := get_prediction_points()
	if points.size() < 2:
		return
	for i in range(points.size() - 1):
		_add_line(points[i], points[i + 1], TRAJECTORY_COLOR)


func _draw_body_gravity_arrows() -> void:
	for body: CelestialBody in celestial_bodies:
		if not is_instance_valid(body) or body.sim_index < 0:
			continue
		if CelestialSim.is_body_stationary(body.sim_index):
			continue
		var gravity := CelestialSim.get_body_gravity_acceleration(body.sim_index)
		_add_arrow(_debug_pos(body.global_position), gravity, gravity_scale, BODY_GRAVITY_COLOR)


func _draw_body_trajectories() -> void:
	var body_paths := CelestialSim.predict_body_paths(trajectory_seconds, trajectory_step)
	for body: CelestialBody in celestial_bodies:
		if not is_instance_valid(body) or body.sim_index < 0:
			continue
		if CelestialSim.is_body_stationary(body.sim_index):
			continue
		if body.sim_index >= body_paths.size():
			continue
		var points := _offset_points(body_paths[body.sim_index])
		for i in range(points.size() - 1):
			_add_line(points[i], points[i + 1], BODY_TRAJECTORY_COLOR)


func _add_arrow(origin: Vector3, vector: Vector3, scale: float, color: Color) -> void:
	vector.y = 0.0
	if vector.length_squared() <= 0.000001:
		return

	var direction := vector.normalized()
	var length := clampf(vector.length() * scale, min_arrow_length, max_arrow_length)
	var end := origin + direction * length
	var side := Vector3(-direction.z, 0.0, direction.x)
	var head_base := end - direction * minf(arrow_head_length, length * 0.45)

	_add_line(origin, end, color)
	_add_line(end, head_base + side * arrow_head_width, color)
	_add_line(end, head_base - side * arrow_head_width, color)


func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(from)
	_mesh.surface_set_color(color)
	_mesh.surface_add_vertex(to)


func _debug_pos(pos: Vector3) -> Vector3:
	return Vector3(pos.x, pos.y + visual_height_offset, pos.z)


func _offset_points(points: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	for point in points:
		result.append(_debug_pos(point))
	return result
