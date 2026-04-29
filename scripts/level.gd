class_name Level
extends Node3D

signal level_completed
signal ship_crashed(crash_position: Vector3)


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
		ship.crashed.connect(_on_ship_crashed)


func _connect_targets() -> void:
	for child in get_children():
		if child is Target:
			child.target_reached.connect(func() -> void: level_completed.emit())


func get_ship() -> Ship:
	for child in get_children():
		if child is Ship:
			return child
	return null


func spawn_crash_explosion(crash_position: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "CrashExplosion"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.one_shot = true
	particles.amount = 180
	particles.lifetime = 1.25
	particles.explosiveness = 0.95
	particles.randomness = 0.35
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-8.0, -8.0, -8.0), Vector3(16.0, 16.0, 16.0))
	particles.process_material = _create_crash_particle_material()
	particles.draw_pass_1 = _create_crash_particle_mesh()

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.12)
	light.light_energy = 4.0
	light.omni_range = 10.0
	light.omni_attenuation = 1.4
	particles.add_child(light)

	add_child(particles)
	particles.global_position = crash_position
	particles.restart()
	particles.emitting = true
	_free_crash_explosion(particles)


func _on_ship_crashed(crash_position: Vector3) -> void:
	ship_crashed.emit(crash_position)


func _create_crash_particle_material() -> ParticleProcessMaterial:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.95, 0.55, 1.0),
		Color(1.0, 0.35, 0.08, 0.95),
		Color(0.45, 0.08, 0.03, 0.55),
		Color(0.08, 0.07, 0.07, 0.0),
	])

	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.35
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = 4.0
	material.initial_velocity_max = 14.0
	material.gravity = Vector3.ZERO
	material.damping_min = 2.0
	material.damping_max = 5.0
	material.scale_min = 0.2
	material.scale_max = 1.2
	material.color_ramp = ramp
	return material


func _create_crash_particle_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var mesh := QuadMesh.new()
	mesh.material = material
	mesh.size = Vector2(0.42, 0.42)
	return mesh


func _free_crash_explosion(particles: GPUParticles3D) -> void:
	await get_tree().create_timer(particles.lifetime + 0.5, true).timeout
	if is_instance_valid(particles):
		particles.queue_free()
