class_name Rocket
extends FloatingObject

## Weapon projectile: boosts along its launch direction for a short time
## (engine plume and all), then coasts on gravity like any other rock.
## Destroys the first asteroid it touches; planets burn it up and black
## holes swallow it like any FloatingObject.

const EXPLOSION_PARTICLE_COUNT: int = 60
const EXPLOSION_PARTICLE_LIFETIME: float = 0.7

@export var boost_time: float = 0.2
@export var boost_acceleration: float = 80.0

## World-space direction of the boost burn; the weapon sets this at launch.
var boost_direction: Vector3 = Vector3.FORWARD

var _boost_remaining: float = 0.0
var _exploded: bool = false

@onready var _exhaust_particles: GPUParticles3D = $ExhaustParticles


func _ready() -> void:
	super()
	gravity_affected = true
	_boost_remaining = boost_time
	area_entered.connect(_on_area_entered)


func tick(delta: float) -> void:
	if _boost_remaining > 0.0:
		_boost_remaining -= delta
		velocity += boost_direction * boost_acceleration * delta
	if _exhaust_particles:
		_exhaust_particles.emitting = _boost_remaining > 0.0
	super(delta)
	if velocity.length_squared() > 0.0001:
		look_at(global_position + velocity, Vector3.UP)


func _on_area_entered(area: Area3D) -> void:
	if area is Asteroid:
		# Area callbacks arrive while the physics server is flushing queries;
		# freeing nodes must run deferred (same rule as FloatingObject).
		_explode_on.call_deferred(area)


func _explode_on(asteroid: Node3D) -> void:
	if _exploded or is_queued_for_deletion() or not is_inside_tree():
		return
	if not is_instance_valid(asteroid) or asteroid.is_queued_for_deletion():
		return
	_exploded = true
	_spawn_explosion(global_position.lerp(asteroid.global_position, 0.5))
	asteroid.queue_free()
	queue_free()


func _spawn_explosion(position: Vector3) -> void:
	var parent := get_parent()
	if not parent or not is_instance_valid(parent):
		return

	var particles := GPUParticles3D.new()
	particles.name = "RocketExplosion"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.one_shot = true
	particles.amount = EXPLOSION_PARTICLE_COUNT
	particles.lifetime = EXPLOSION_PARTICLE_LIFETIME
	particles.explosiveness = 0.95
	particles.randomness = 0.35
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	particles.process_material = build_explosion_material()
	particles.draw_pass_1 = build_explosion_mesh()

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.5, 0.15)
	light.light_energy = 3.0
	light.omni_range = 7.0
	light.omni_attenuation = 1.4
	particles.add_child(light)

	parent.add_child(particles)
	particles.global_position = position
	particles.restart()
	particles.emitting = true
	# The rocket frees itself right after exploding, so the cleanup timer
	# must not live on this node — an await here would die with the rocket.
	var timer := particles.get_tree().create_timer(particles.lifetime + 0.3, true)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)


# Static and public: EffectWarmup replays the effect at boot to pre-compile
# its shaders.
static func build_explosion_material() -> ParticleProcessMaterial:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 0.9, 0.5, 1.0),
		Color(1.0, 0.4, 0.1, 0.9),
		Color(0.5, 0.1, 0.04, 0.5),
		Color(0.08, 0.07, 0.07, 0.0),
	])

	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient

	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.3
	material.direction = Vector3.UP
	material.spread = 180.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 10.0
	material.gravity = Vector3.ZERO
	material.damping_min = 2.0
	material.damping_max = 4.0
	material.scale_min = 0.18
	material.scale_max = 0.9
	material.color_ramp = ramp
	return material


static func build_explosion_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES

	var mesh := QuadMesh.new()
	mesh.material = material
	mesh.size = Vector2(0.3, 0.3)
	return mesh
