class_name Level
extends Node3D

signal level_completed
signal ship_crashed


func _ready() -> void:
	_init_celestial_sim()
	_connect_ship()
	_connect_targets()


func _init_celestial_sim() -> void:
	var bodies: Array[CelestialBody] = []
	for child in get_children():
		if child is CelestialBody:
			bodies.append(child)

	var data: Array[CelestialBodyData] = []
	var positions := PackedVector3Array()
	var velocities := PackedVector3Array()
	var stationary: Array[bool] = []

	for i in bodies.size():
		var body := bodies[i]
		data.append(body.body_data)
		positions.append(body.global_position)
		velocities.append(body.initial_velocity)
		stationary.append(body.stationary)
		body.sim_index = i

	CelestialSim.initialize(data, positions, velocities, stationary)


func _connect_ship() -> void:
	var ship := get_ship()
	if ship:
		ship.crashed.connect(func() -> void: ship_crashed.emit())


func _connect_targets() -> void:
	for child in get_children():
		if child is Target:
			child.target_reached.connect(func() -> void: level_completed.emit())


func get_ship() -> Ship:
	for child in get_children():
		if child is Ship:
			return child
	return null
