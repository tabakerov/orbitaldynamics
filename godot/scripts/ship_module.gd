class_name ShipModule
extends Node3D

var ship: Node  # back-reference, typed Node to avoid cyclic class_name dependency
var profile: ModuleProfile
var active: bool = false
var intensity: float = 0.0
var fuel_supply_ratio: float = 1.0


func attach(p_ship: Node, p_profile: ModuleProfile) -> void:
	ship = p_ship
	profile = p_profile
	_configure()


func _configure() -> void:
	pass


func get_mass() -> float:
	return 0.0


func physics_tick(_delta: float) -> void:
	pass


func get_thrust_vector() -> Vector3:
	return Vector3.ZERO


func get_requested_fuel_drain(_delta: float) -> float:
	return get_fuel_drain(_delta)


func get_fuel_drain(_delta: float) -> float:
	return 0.0


func get_potential_fuel_intake(_delta: float) -> float:
	return 0.0


func commit_fuel_intake(_amount: float) -> void:
	pass


func apply_gimbal_delta(_delta: float) -> void:
	pass
