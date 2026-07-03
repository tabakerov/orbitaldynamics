@tool
class_name BlackHole
extends CelestialBody

@export_group("Absorption")
## Radius gained per unit of absorbed mass.
@export var radius_growth_per_mass: float = 0.02
## Fraction of absorbed mass added to the gravitational mass.
@export var mass_gain_factor: float = 1.0
## Seconds to fully apply an absorption instead of growing instantly.
## New absorptions mid-ramp extend the target smoothly (no jump/restart).
@export var growth_duration: float = 1.5

@export_group("Lensing")
## Radius of the lensing effect mesh (visual only, not gravity).
@export var lensing_radius: float = 30.0:
	set(value):
		lensing_radius = maxf(value, 0.0)
		_apply_lensing_mesh_size()
@export_range(0.0, 0.5, 0.01) var distortion_falloff_start: float = 0.18:
	set(value):
		distortion_falloff_start = clampf(value, 0.0, 0.5)
		_apply_lensing_shader_parameters()
@export_range(0.0, 1.0, 0.01) var chromatic_aberration: float = 0.25:
	set(value):
		chromatic_aberration = clampf(value, 0.0, 1.0)
		_apply_lensing_shader_parameters()

@export_group("Absorption Effect")
## Base particles in the one-shot burst when something falls in, before
## absorption_particles_per_mass adds more for heavier objects.
@export_range(1, 200, 1) var absorption_particle_count: int = 40
## Extra particles per unit of absorbed mass, added on top of
## absorption_particle_count — bigger objects throw more debris.
@export_range(0.0, 10.0, 0.1) var absorption_particles_per_mass: float = 1.0
## Seconds the burst takes to fully fade out.
@export_range(0.1, 5.0, 0.05) var absorption_particle_lifetime: float = 0.9
## Width of the burst cone, in degrees.
@export_range(0.0, 90.0, 0.5) var absorption_cone_spread_deg: float = 10.0
@export var absorption_initial_velocity_min: float = 6.0
@export var absorption_initial_velocity_max: float = 14.0
## Multiplies the absorbed object's own speed and adds it to the initial
## velocity range above — fast impacts throw debris harder.
@export_range(0.0, 3.0, 0.05) var absorption_velocity_multiplier: float = 0.5
## Negative pulls particles inward, toward the hole.
@export var absorption_radial_accel_min: float = -22.0
@export var absorption_radial_accel_max: float = -12.0
## Spins the burst as it's reeled in, giving it a curling look.
@export var absorption_orbit_velocity_min: float = 0.6
@export var absorption_orbit_velocity_max: float = 1.4
@export var absorption_damping_min: float = 0.5
@export var absorption_damping_max: float = 1.5
@export var absorption_particle_scale_min: float = 0.15
@export var absorption_particle_scale_max: float = 0.5
@export var absorption_color: Color = Color(0.85, 0.55, 1.0, 1.0)
## LensingMesh (black_hole.tscn) uses render_priority=1 so its screen-space
## distortion always draws over the black hole's own geometry. Transparent
## draw order is sorted by priority before distance, so this must stay
## higher or the burst gets painted over and disappears.
@export var absorption_render_priority: int = 2

const PARAM_DISTORTION_FALLOFF_START: String = "distortion_falloff_start"
const PARAM_CHROMATIC_ABERRATION: String = "chromatic_aberration"

var _growth_start_radius: float = 0.0
var _growth_start_mass: float = 0.0
var _growth_target_radius: float = 0.0
var _growth_target_mass: float = 0.0
var _growth_elapsed: float = 0.0


func _ready() -> void:
	if not Engine.is_editor_hint() and body_data:
		# Absorption mutates radius/mass and the collision shape, which are
		# otherwise shared between instances — make per-instance copies.
		body_data = body_data.duplicate()
		var collision := $CollisionShape3D as CollisionShape3D
		collision.shape = collision.shape.duplicate()
	if body_data:
		_growth_start_radius = body_data.radius
		_growth_start_mass = body_data.mass
		_growth_target_radius = body_data.radius
		_growth_target_mass = body_data.mass
		_growth_elapsed = growth_duration
	super()
	_apply_lensing_mesh_size()
	_apply_lensing_shader_parameters()


func _physics_process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint() or _growth_elapsed >= growth_duration:
		return
	_growth_elapsed = minf(_growth_elapsed + delta, growth_duration)
	var t := 1.0 if growth_duration <= 0.0 else _growth_elapsed / growth_duration
	_apply_growth(lerpf(_growth_start_radius, _growth_target_radius, t), lerpf(_growth_start_mass, _growth_target_mass, t))


## Swallow the given mass: the hole's radius and gravitational pull grow,
## smoothly, over growth_duration seconds (see _physics_process).
## absorbed_velocity/absorbed_position (world space) drive the absorption
## particle burst, if given — see _spawn_absorption_effect.
func absorb(absorbed_mass: float, absorbed_velocity: Vector3 = Vector3.ZERO, absorbed_position: Vector3 = Vector3.ZERO) -> void:
	if absorbed_mass <= 0.0 or not body_data:
		return
	_growth_start_radius = body_data.radius
	_growth_start_mass = body_data.mass
	_growth_target_radius += radius_growth_per_mass * absorbed_mass
	_growth_target_mass += mass_gain_factor * absorbed_mass
	_growth_elapsed = 0.0
	if growth_duration <= 0.0:
		_growth_elapsed = growth_duration
		_apply_growth(_growth_target_radius, _growth_target_mass)
	if not Engine.is_editor_hint():
		_spawn_absorption_effect(absorbed_velocity, absorbed_position, absorbed_mass)


func _apply_growth(new_radius: float, new_mass: float) -> void:
	var old_radius := body_data.radius
	body_data.radius = new_radius
	body_data.mass = new_mass
	if sim_index >= 0:
		CelestialSim.set_body_mass(sim_index, body_data.mass)
	if old_radius > 0.0:
		lensing_radius *= body_data.radius / old_radius
	_setup_visuals()


## Bursts debris from world_position in a narrow cone along velocity (the
## absorbed object keeps its own momentum at first), then reels it back in:
## a negative radial_accel pulls particles toward this node's local origin
## and orbit_velocity spins them, so the burst curls into the hole like it's
## being caught by its gravity.
func _spawn_absorption_effect(velocity: Vector3, world_position: Vector3, absorbed_mass: float) -> void:
	var direction := velocity
	direction.y = 0.0
	var speed := direction.length()
	if direction.length_squared() < 0.0001:
		# No usable velocity (e.g. a merged-away object at rest): fall back
		# to bursting straight out from the hole through the contact point.
		direction = world_position - global_position
		direction.y = 0.0
		if direction.length_squared() < 0.0001:
			direction = Vector3.FORWARD
	direction = direction.normalized()

	var particles := GPUParticles3D.new()
	particles.name = "AbsorptionEffect"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.one_shot = true
	particles.amount = clampi(
		roundi(absorption_particle_count + absorbed_mass * absorption_particles_per_mass), 1, 400
	)
	particles.lifetime = absorption_particle_lifetime
	particles.explosiveness = 0.85
	particles.randomness = 0.3
	particles.local_coords = true
	particles.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	particles.draw_pass_1 = _build_absorption_mesh()

	add_child(particles)
	particles.position = to_local(world_position)
	# orbit_velocity spins particles in the LOCAL XY plane, but the game
	# lives in the XZ plane — tilt the emitter -90° around X so the two
	# line up, then convert direction into the emitter's (now tilted) local
	# space via its own global basis, not just this node's.
	particles.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	var local_direction := particles.global_transform.basis.inverse() * direction
	particles.process_material = _build_absorption_material(local_direction, speed)

	particles.restart()
	particles.emitting = true
	_free_absorption_effect(particles)


func _build_absorption_material(local_direction: Vector3, absorbed_speed: float) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = local_direction
	material.spread = absorption_cone_spread_deg
	var speed_boost := absorbed_speed * absorption_velocity_multiplier
	material.initial_velocity_min = absorption_initial_velocity_min + speed_boost
	material.initial_velocity_max = absorption_initial_velocity_max + speed_boost
	material.gravity = Vector3.ZERO
	# Negative radial_accel pulls inward, toward this emitter's local origin
	# (the hole itself, since particles are parented here) — orbit_velocity
	# adds the spin, so the two together curl the burst into a spiral.
	material.radial_accel_min = absorption_radial_accel_min
	material.radial_accel_max = absorption_radial_accel_max
	material.orbit_velocity_min = absorption_orbit_velocity_min
	material.orbit_velocity_max = absorption_orbit_velocity_max
	material.damping_min = absorption_damping_min
	material.damping_max = absorption_damping_max
	material.scale_min = absorption_particle_scale_min
	material.scale_max = absorption_particle_scale_max
	material.color = absorption_color
	return material


func _build_absorption_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# White base albedo: vertex_color_use_as_albedo multiplies this by the
	# per-particle color (absorption_color, set on the process material), so
	# absorption_color alone controls the visible tint.
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.render_priority = absorption_render_priority

	var mesh := QuadMesh.new()
	mesh.material = material
	mesh.size = Vector2(0.15, 0.15)
	return mesh


func _free_absorption_effect(particles: GPUParticles3D) -> void:
	await particles.get_tree().create_timer(particles.lifetime + 0.3, true).timeout
	if is_instance_valid(particles):
		particles.queue_free()


func _setup_visuals() -> void:
	# Collision from body_data
	var collision := $CollisionShape3D as CollisionShape3D
	var sphere_shape := collision.shape as SphereShape3D
	sphere_shape.radius = body_data.radius

	# Scale lensing plane to cover distortion area
	_apply_lensing_mesh_size()
	_apply_lensing_shader_parameters()


func _apply_lensing_mesh_size() -> void:
	var lensing_mesh := $LensingMesh as MeshInstance3D
	if not lensing_mesh:
		return

	var plane := lensing_mesh.mesh as PlaneMesh
	if not plane:
		return
	plane.size = Vector2(lensing_radius * 2.0, lensing_radius * 2.0)


func _apply_lensing_shader_parameters() -> void:
	var material := _get_lensing_material()
	if not material:
		return
	material.set_shader_parameter(PARAM_DISTORTION_FALLOFF_START, distortion_falloff_start)
	material.set_shader_parameter(PARAM_CHROMATIC_ABERRATION, chromatic_aberration)


func _get_lensing_material() -> ShaderMaterial:
	var lensing_mesh := get_node_or_null("LensingMesh") as MeshInstance3D
	if not lensing_mesh:
		return null

	var material := lensing_mesh.get_active_material(0) as ShaderMaterial
	if material:
		return material

	var plane := lensing_mesh.mesh as PlaneMesh
	if not plane:
		return null
	return plane.material as ShaderMaterial
