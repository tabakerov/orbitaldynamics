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
var _stationary: Array[bool]


func initialize(
	data: Array,
	positions: PackedVector3Array,
	velocities: PackedVector3Array,
	stationary: Array[bool] = [],
) -> void:
	_count = data.size()
	_positions = positions.duplicate()
	_velocities = velocities.duplicate()
	_masses = PackedFloat64Array()
	_gravity_strengths = PackedFloat64Array()
	_falloff_exponents = PackedFloat64Array()
	_max_ranges = PackedFloat64Array()
	_min_ranges = PackedFloat64Array()
	_stationary = []
	for i in data.size():
		var d = data[i]
		_masses.append(d.mass)
		_gravity_strengths.append(d.gravity_strength)
		_falloff_exponents.append(d.falloff_exponent)
		_max_ranges.append(d.max_range)
		_min_ranges.append(d.min_range)
		_stationary.append(stationary[i] if i < stationary.size() else false)
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
	_stationary = []


func _physics_process(delta: float) -> void:
	if active and _count > 0:
		step(delta)


func step(delta: float) -> void:
	var accels := _get_body_accelerations(_positions)

	# Symplectic Euler: velocity first, then position
	for i in _count:
		if _stationary[i]:
			continue
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


func get_body_gravity_acceleration(index: int) -> Vector3:
	if index < 0 or index >= _count:
		return Vector3.ZERO
	return _get_body_acceleration(index, _positions)


func is_body_stationary(index: int) -> bool:
	if index < 0 or index >= _count:
		return true
	return _stationary[index]


func predict_body_paths(seconds: float, step_delta: float) -> Array[PackedVector3Array]:
	var paths: Array[PackedVector3Array] = []
	paths.resize(_count)
	for i in _count:
		var path := PackedVector3Array()
		if _count > 0:
			path.append(_positions[i])
		paths[i] = path

	if _count <= 0:
		return paths

	var step := maxf(step_delta, 0.01)
	var total_steps := maxi(1, int(ceil(maxf(seconds, step) / step)))
	var positions := _positions.duplicate()
	var velocities := _velocities.duplicate()

	for _step_idx in total_steps:
		var accels := _get_body_accelerations(positions)
		for i in _count:
			if not _stationary[i]:
				velocities[i] += accels[i] * step
				positions[i] += velocities[i] * step
				positions[i].y = 0.0
				velocities[i].y = 0.0
			paths[i].append(positions[i])
	return paths


func get_body_count() -> int:
	return _count


## Updates a body's mass at runtime (e.g. a black hole growing by absorption).
## Affects both inter-body attraction and the gravity field from get_gravity_at.
func set_body_mass(index: int, new_mass: float) -> void:
	if index < 0 or index >= _count:
		return
	_masses[index] = maxf(new_mass, 0.0)


func _get_body_accelerations(positions: PackedVector3Array) -> Array[Vector3]:
	var accels: Array[Vector3] = []
	accels.resize(_count)
	for i in _count:
		accels[i] = Vector3.ZERO

	for i in _count:
		for j in range(i + 1, _count):
			var offset := positions[j] - positions[i]
			var dist := offset.length()
			if dist < 0.001:
				continue
			var dir := offset / dist
			var accel_on_i := gravitational_constant * _masses[j] / (dist * dist)
			var accel_on_j := gravitational_constant * _masses[i] / (dist * dist)
			accels[i] += dir * accel_on_i
			accels[j] -= dir * accel_on_j
	return accels


func _get_body_acceleration(index: int, positions: PackedVector3Array) -> Vector3:
	if index < 0 or index >= _count:
		return Vector3.ZERO

	var accel := Vector3.ZERO
	for i in _count:
		if i == index:
			continue
		var offset := positions[i] - positions[index]
		var dist := offset.length()
		if dist < 0.001:
			continue
		accel += offset.normalized() * gravitational_constant * _masses[i] / (dist * dist)
	return accel
