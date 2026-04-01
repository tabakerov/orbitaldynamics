class_name ShipEngine
extends Node3D

@export var max_thrust: float = 100.0
@export var gimbal_range_deg: float = 30.0
@export var fuel_consumption_rate: float = 10.0

var active: bool = false
var gimbal_angle: float = 0.0
var thrust_magnitude: float = 0.0

var _gimbal_range_rad: float

@onready var _exhaust: MeshInstance3D = $Exhaust
@onready var _active_light: OmniLight3D = $ActiveLight


func _ready() -> void:
	_gimbal_range_rad = deg_to_rad(gimbal_range_deg)
	_active_light.visible = false


func _process(_delta: float) -> void:
	_exhaust.visible = active and thrust_magnitude > 0.0
	_active_light.visible = active


func set_gimbal_target(target: float) -> void:
	gimbal_angle = clampf(target, -_gimbal_range_rad, _gimbal_range_rad)


func get_thrust_vector() -> Vector3:
	if not active or thrust_magnitude <= 0.0:
		return Vector3.ZERO
	var local_dir := Vector3(0, 0, -1).rotated(Vector3.UP, gimbal_angle)
	return global_transform.basis * local_dir * max_thrust * thrust_magnitude


func get_fuel_drain(delta: float) -> float:
	if not active or thrust_magnitude <= 0.0:
		return 0.0
	return fuel_consumption_rate * thrust_magnitude * delta
