class_name CelestialSim
extends Node

## Gravitational constant for inter-body attraction.
@export var gravitational_constant: float = 1.0

var active: bool = false

var _count: int = 0
var _positions: PackedVector3Array
var _velocities: PackedVector3Array
var _masses: PackedFloat64Array
var _gravity_strengths: PackedFloat64Array
var _falloff_exponents: PackedFloat64Array
var _max_ranges: PackedFloat64Array
var _min_ranges: PackedFloat64Array


func initialize(
	data: Array[CelestialBodyData],
	positions: PackedVector3Array,
	velocities: PackedVector3Array
) -> void:
	_count = data.size()
	_positions = positions.duplicate()
	_velocities = velocities.duplicate()
	_masses = PackedFloat64Array()
	_gravity_strengths = PackedFloat64Array()
	_falloff_exponents = PackedFloat64Array()
	_max_ranges = PackedFloat64Array()
	_min_ranges = PackedFloat64Array()
	for d in data:
		_masses.append(d.mass)
		_gravity_strengths.append(d.gravity_strength)
		_falloff_exponents.append(d.falloff_exponent)
		_max_ranges.append(d.max_range)
		_min_ranges.append(d.min_range)
	active = true


func clear() -> void:
	active = false
	_count = 0
	_positions = PackedVector3Array()
	_velocities = PackedVector3Array()
	_masses = PackedFloat64Array()
	_gravity_strengths = PackedFloat64Array()
	_falloff_exponents = PackedFloat64Array()
	_max_ranges = PackedFloat64Array()
	_min_ranges = PackedFloat64Array()


func _physics_process(delta: float) -> void:
	if active and _count > 0:
		step(delta)


func step(delta: float) -> void:
	# Compute inter-body gravitational accelerations
	var accels: Array[Vector3] = []
	accels.resize(_count)
	for i in _count:
		accels[i] = Vector3.ZERO

	for i in _count:
		for j in range(i + 1, _count):
			var offset := _positions[j] - _positions[i]
			var dist := offset.length()
			if dist < 0.001:
				continue
			var dir := offset / dist
			var accel_on_i := gravitational_constant * _masses[j] / (dist * dist)
			var accel_on_j := gravitational_constant * _masses[i] / (dist * dist)
			accels[i] += dir * accel_on_i
			accels[j] -= dir * accel_on_j

	# Symplectic Euler: velocity first, then position
	for i in _count:
		_velocities[i] += accels[i] * delta
		_positions[i] += _velocities[i] * delta
		# Enforce Y=0 plane constraint
		_positions[i].y = 0.0
		_velocities[i].y = 0.0


func get_gravity_at(pos: Vector3) -> Vector3:
	var total := Vector3.ZERO
	for i in _count:
		var offset := _positions[i] - pos
		var raw_dist := offset.length()
		if raw_dist > _max_ranges[i]:
			continue
		var dist := clampf(raw_dist, _min_ranges[i], _max_ranges[i])
		var strength := _gravity_strengths[i] * _masses[i] / pow(dist, _falloff_exponents[i])
		total += offset.normalized() * strength
	return total


func get_body_position(index: int) -> Vector3:
	return _positions[index]


func get_body_velocity(index: int) -> Vector3:
	return _velocities[index]


func get_body_count() -> int:
	return _count
