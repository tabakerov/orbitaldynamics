extends Node

## Resolves asteroid-vs-asteroid collisions as a lightweight elastic bounce
## with damping. Asteroids are FloatingObject/Area3D — areas don't get a
## physical collision response from the engine, so this manually separates
## overlapping pairs and exchanges velocity along the collision normal.
## Runs once per physics frame over every currently-alive asteroid; O(n^2)
## but n stays small (Asteroid entries cap max_alive).

## Fraction of the resulting velocity kept per collision, picked randomly in
## this range each time. Below 1.0 so collisions bleed off a little energy
## per hit instead of bouncing forever at full strength.
@export_range(0.5, 1.0, 0.01) var restitution_min: float = 0.90
@export_range(0.5, 1.0, 0.01) var restitution_max: float = 0.95

const IMPACT_PARTICLE_COUNT: int = 28
const IMPACT_PARTICLE_LIFETIME: float = 0.6

var _asteroids: Array[Asteroid] = []


func register(asteroid: Asteroid) -> void:
	if not _asteroids.has(asteroid):
		_asteroids.append(asteroid)


func unregister(asteroid: Asteroid) -> void:
	_asteroids.erase(asteroid)


func _physics_process(_delta: float) -> void:
	# Untyped lambda parameter: freed instances fail typed-argument conversion.
	_asteroids = _asteroids.filter(func(a): return is_instance_valid(a))

	# A merge frees one asteroid, but queue_free() only actually removes it
	# at the end of the frame — it's still is_instance_valid() and still
	# sitting in this snapshot, so later pairs in this same double loop could
	# process it again as if nothing happened. Track absorbed asteroids and
	# skip them for the rest of this tick.
	var consumed := {}
	for i in _asteroids.size():
		var a: Asteroid = _asteroids[i]
		if consumed.has(a):
			continue
		for j in range(i + 1, _asteroids.size()):
			var b: Asteroid = _asteroids[j]
			if consumed.has(b):
				continue
			var absorbed := _resolve_pair(a, b)
			if absorbed:
				consumed[absorbed] = true
				if absorbed == a:
					break  # a itself is gone; stop checking more pairs against it


## Resolves one overlapping pair: separates them, and either bounces them
## apart or merges them (see merge_speed_threshold). Returns whichever
## asteroid was absorbed by a merge, or null if none was.
func _resolve_pair(a: Asteroid, b: Asteroid) -> Asteroid:
	var offset := b.global_position - a.global_position
	offset.y = 0.0
	var dist := offset.length()
	var min_dist := a.collision_radius + b.collision_radius
	if dist >= min_dist:
		return null

	var normal := offset / dist if dist > 0.0001 else Vector3.RIGHT
	var total_mass := a.mass + b.mass

	# Positional correction: separate the pair proportional to inverse mass
	# (the heavier one moves less) so they don't sink into each other.
	var overlap := min_dist - dist
	a.global_position -= normal * overlap * (b.mass / total_mass)
	b.global_position += normal * overlap * (a.mass / total_mass)
	a.global_position.y = 0.0
	b.global_position.y = 0.0

	var a_normal_speed := a.velocity.dot(normal)
	var b_normal_speed := b.velocity.dot(normal)
	var closing_speed := a_normal_speed - b_normal_speed
	if closing_speed <= 0.0:
		return null  # already separating along the normal, no impact

	var impact_point := a.global_position.lerp(b.global_position, b.mass / total_mass)
	spawn_impact_effect(impact_point, a.get_parent())

	var merge_threshold := minf(a.merge_speed_threshold, b.merge_speed_threshold)
	if closing_speed <= merge_threshold:
		return _merge(a, b)

	var a_tangent := a.velocity - normal * a_normal_speed
	var b_tangent := b.velocity - normal * b_normal_speed

	# Standard 1D elastic exchange along the collision normal.
	var a_new_normal_speed := (
		((a.mass - b.mass) * a_normal_speed + 2.0 * b.mass * b_normal_speed) / total_mass
	)
	var b_new_normal_speed := (
		((b.mass - a.mass) * b_normal_speed + 2.0 * a.mass * a_normal_speed) / total_mass
	)

	var restitution := randf_range(restitution_min, restitution_max)
	a.velocity = (a_tangent + normal * a_new_normal_speed) * restitution
	b.velocity = (b_tangent + normal * b_new_normal_speed) * restitution
	return null


## A gentle-enough impact fuses the pair into one rock instead of bouncing:
## momentum and mass add together (perfectly inelastic collision), and the
## combined volume determines the survivor's new size. Returns the asteroid
## that was absorbed (queue_free()'d) into the other.
func _merge(a: Asteroid, b: Asteroid) -> Asteroid:
	var total_mass := a.mass + b.mass
	var survivor := a if a.mass >= b.mass else b
	var absorbed := b if survivor == a else a

	var merged_radius := pow(pow(a.collision_radius, 3.0) + pow(b.collision_radius, 3.0), 1.0 / 3.0)
	survivor.global_position = a.global_position.lerp(b.global_position, b.mass / total_mass)
	survivor.global_position.y = 0.0
	survivor.velocity = (a.velocity * a.mass + b.velocity * b.mass) / total_mass
	survivor.mass = total_mass
	survivor.apply_merged_radius(merged_radius)

	absorbed.queue_free()
	return absorbed


## Dust puff at an impact point. Public: laser hits reuse it (see
## Asteroid.hit_by_laser), not just asteroid-vs-asteroid bounces.
func spawn_impact_effect(position: Vector3, parent: Node) -> void:
	if not parent or not is_instance_valid(parent):
		return

	var particles := GPUParticles3D.new()
	particles.name = "AsteroidImpact"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.one_shot = true
	particles.amount = IMPACT_PARTICLE_COUNT
	particles.lifetime = IMPACT_PARTICLE_LIFETIME
	particles.explosiveness = 0.9
	particles.randomness = 0.4
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	particles.process_material = build_impact_material()
	particles.draw_pass_1 = build_impact_mesh()

	parent.add_child(particles)
	particles.global_position = position
	particles.restart()
	particles.emitting = true
	_free_impact_effect(particles)


# Static and public: EffectWarmup replays the effect at boot to pre-compile
# its shaders.
static func build_impact_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.3
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 7.0
	material.gravity = Vector3.ZERO
	material.damping_min = 1.0
	material.damping_max = 3.0
	material.scale_min = 0.15
	material.scale_max = 0.6
	material.color = Color(0.45, 0.4, 0.35, 1.0)
	return material


static func build_impact_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(0.5, 0.45, 0.4, 0.9)

	var mesh := QuadMesh.new()
	mesh.material = material
	mesh.size = Vector2(0.12, 0.12)
	return mesh


func _free_impact_effect(particles: GPUParticles3D) -> void:
	await particles.get_tree().create_timer(particles.lifetime + 0.3, true).timeout
	if is_instance_valid(particles):
		particles.queue_free()


func clear() -> void:
	_asteroids.clear()
