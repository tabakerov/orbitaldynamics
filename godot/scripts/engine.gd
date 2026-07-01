class_name EngineModule
extends ShipModule

var gimbal_angle: float = 0.0
var _gimbal_range_rad: float = deg_to_rad(30.0)

@onready var _exhaust: MeshInstance3D = $Exhaust
@onready var _active_light: OmniLight3D = $ActiveLight
@onready var _particles: GPUParticles3D = $ExhaustParticles


func _configure() -> void:
	var ep := profile as EngineProfile
	if ep:
		_gimbal_range_rad = deg_to_rad(ep.gimbal_range_deg)


func _ready() -> void:
	if _active_light:
		_active_light.visible = false
	rotation.y = gimbal_angle


func _process(_delta: float) -> void:
	if not _exhaust:
		return
	var has_fuel := _has_effective_fuel_supply()
	var thrusting: bool = active and intensity > 0.0 and has_fuel
	_exhaust.visible = thrusting
	_active_light.visible = active
	_particles.emitting = thrusting


func get_mass() -> float:
	var ep := profile as EngineProfile
	return ep.dry_mass if ep else 0.0


func apply_gimbal_delta(delta: float) -> void:
	if active and delta != 0.0:
		gimbal_angle = clampf(gimbal_angle + delta, -_gimbal_range_rad, _gimbal_range_rad)
		rotation.y = gimbal_angle


func get_thrust_vector() -> Vector3:
	if not active or intensity <= 0.0:
		return Vector3.ZERO
	if not _has_effective_fuel_supply():
		return Vector3.ZERO
	var ep := profile as EngineProfile
	if not ep:
		return Vector3.ZERO
	return -global_transform.basis.z * ep.max_thrust * intensity * fuel_supply_ratio


func get_requested_fuel_drain(delta: float) -> float:
	if not active or intensity <= 0.0:
		return 0.0
	if not ship:
		return 0.0
	var ep := profile as EngineProfile
	if not ep:
		return 0.0
	return ep.fuel_consumption_rate * intensity * delta


func get_fuel_drain(delta: float) -> float:
	if not _has_effective_fuel_supply():
		return 0.0
	return get_requested_fuel_drain(delta) * fuel_supply_ratio


func _has_effective_fuel_supply() -> bool:
	if not ship or fuel_supply_ratio <= 0.0:
		return false
	if fuel_supply_ratio < 1.0:
		return true
	return ship.fuel > 0.0
