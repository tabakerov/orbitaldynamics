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
@onready var _particles: GPUParticles3D = $ExhaustParticles


func _ready() -> void:
	_gimbal_range_rad = deg_to_rad(gimbal_range_deg)
	_active_light.visible = false


func _process(_delta: float) -> void:
	var thrusting := active and thrust_magnitude > 0.0
	_exhaust.visible = thrusting
	_active_light.visible = active
	_particles.emitting = thrusting


func set_gimbal_target(target: float) -> void:
	if active:
		gimbal_angle = clampf(target, -_gimbal_range_rad, _gimbal_range_rad)
		rotation.y = gimbal_angle


func get_thrust_vector() -> Vector3:
	if not active or thrust_magnitude <= 0.0:
		return Vector3.ZERO
	return -global_transform.basis.z * max_thrust * thrust_magnitude


func get_fuel_drain(delta: float) -> float:
	if not active or thrust_magnitude <= 0.0:
		return 0.0
	return fuel_consumption_rate * thrust_magnitude * delta
