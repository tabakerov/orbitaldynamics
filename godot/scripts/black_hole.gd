@tool
class_name BlackHole
extends CelestialBody

const RingParticleShader = preload("res://resources/shaders/black_hole_ring_particles.gdshader")

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

@export_group("Particle Rendering")
## LensingMesh (black_hole.tscn) uses render_priority=1 so its screen-space
## distortion always draws over the black hole's own geometry. Transparent
## draw order is sorted by priority before distance, so both particle
## systems below (horizon, ring) must stay higher or the lensing plane
## paints over them and they disappear.
@export var particle_render_priority: int = 2

@export_group("Absorption Flare")
## Absorbing something briefly intensifies the accretion ring instead of
## spawning a separate burst: the ring's emitted-particle share jumps to its
## full budget and particle lifetime is multiplied, then both decay back
## linearly over flare_duration seconds.
## Peak particle count = ring_particle_count * this multiplier. The ring's
## GPU buffer is allocated at the peak size up front, because resizing
## GPUParticles3D.amount restarts the system and blinks every particle out.
@export_range(1.0, 8.0, 0.1) var flare_amount_multiplier: float = 3.0
## Ring particle lifetime is multiplied by this at the flare's peak.
@export_range(1.0, 5.0, 0.05) var flare_lifetime_multiplier: float = 1.8
## Seconds for the flare to fully decay back to the ring's normal look.
@export_range(0.05, 10.0, 0.05) var flare_duration: float = 1.2

@export_group("Event Horizon Particles")
## Replaces the old flat black disc: a dense, swirling field of dark
## particles reads as an event horizon without a hard-edged cutout.
@export_range(1, 300, 1) var horizon_particle_count: int = 80
@export_range(0.5, 10.0, 0.1) var horizon_particle_lifetime: float = 3.0
## Radius of the particle field, relative to the hole's physical radius.
@export_range(0.3, 1.5, 0.05) var horizon_radius_multiplier: float = 0.9
@export var horizon_particle_scale_min: float = 0.3
@export var horizon_particle_scale_max: float = 0.8
@export var horizon_orbit_velocity_min: float = 0.4
@export var horizon_orbit_velocity_max: float = 1.0
@export var horizon_color: Color = Color(0.03, 0.02, 0.05, 0.92)

@export_group("Accretion Ring Particles")
## Replaces the old static orange ring glow with fast ember streaks: each
## particle spawns at a random point on the ring moving tangent to it, and
## a short lifetime keeps it a brief streak instead of a full slow circle.
@export_range(1, 400, 1) var ring_particle_count: int = 140
@export_range(0.05, 3.0, 0.05) var ring_particle_lifetime: float = 0.6
## Ring radius, relative to the hole's physical radius.
@export_range(1.0, 4.0, 0.05) var ring_radius_multiplier: float = 1.6
## Ring band thickness, relative to the hole's physical radius.
@export_range(0.02, 1.0, 0.02) var ring_thickness_multiplier: float = 0.35
@export var ring_particle_scale_min: float = 0.12
@export var ring_particle_scale_max: float = 0.35
## Tangential speed range, in world units/second.
@export var ring_particle_speed_min: float = 15.0
@export var ring_particle_speed_max: float = 28.0
@export var ring_color: Color = Color(1.0, 0.45, 0.1, 1.0)

const PARAM_DISTORTION_FALLOFF_START: String = "distortion_falloff_start"
const PARAM_CHROMATIC_ABERRATION: String = "chromatic_aberration"

var _growth_start_radius: float = 0.0
var _growth_start_mass: float = 0.0
var _growth_target_radius: float = 0.0
var _growth_target_mass: float = 0.0
var _growth_elapsed: float = 0.0
var _flare_strength: float = 0.0
var _horizon_particles: GPUParticles3D
var _ring_particles: GPUParticles3D


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
	_setup_horizon_particles()
	_setup_ring_particles()


func _physics_process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	_update_ring_flare(delta)
	if _growth_elapsed >= growth_duration:
		return
	_growth_elapsed = minf(_growth_elapsed + delta, growth_duration)
	var t := 1.0 if growth_duration <= 0.0 else _growth_elapsed / growth_duration
	_apply_growth(lerpf(_growth_start_radius, _growth_target_radius, t), lerpf(_growth_start_mass, _growth_target_mass, t))


## Swallow the given mass: the hole's radius and gravitational pull grow,
## smoothly, over growth_duration seconds (see _physics_process), and the
## accretion ring flares up briefly (see _trigger_ring_flare).
func absorb(absorbed_mass: float) -> void:
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
		_trigger_ring_flare()


func _apply_growth(new_radius: float, new_mass: float) -> void:
	var old_radius := body_data.radius
	body_data.radius = new_radius
	body_data.mass = new_mass
	if sim_index >= 0:
		CelestialSim.set_body_mass(sim_index, body_data.mass)
	if old_radius > 0.0:
		lensing_radius *= body_data.radius / old_radius
	_setup_visuals()


## Kick the accretion ring to full intensity; _update_ring_flare decays it.
func _trigger_ring_flare() -> void:
	_flare_strength = 1.0
	_apply_ring_flare()


func _update_ring_flare(delta: float) -> void:
	if _flare_strength <= 0.0:
		return
	_flare_strength = maxf(_flare_strength - delta / maxf(flare_duration, 0.001), 0.0)
	_apply_ring_flare()


## Intensity is driven through amount_ratio, never amount: resizing
## GPUParticles3D.amount reallocates the buffer and restarts the system,
## blinking every live particle out. Lifetime can be set freely.
func _apply_ring_flare() -> void:
	if not _ring_particles:
		return
	var base_ratio := 1.0 / flare_amount_multiplier
	_ring_particles.amount_ratio = lerpf(base_ratio, 1.0, _flare_strength)
	_ring_particles.lifetime = ring_particle_lifetime * lerpf(1.0, flare_lifetime_multiplier, _flare_strength)


## Continuous swirling disc of dark particles standing in for the old flat
## black event-horizon disc. Ring-shaped emission with inner_radius=0 fills
## the whole disc; orbit_velocity keeps it visibly churning instead of static.
func _setup_horizon_particles() -> void:
	if not body_data or _horizon_particles:
		return
	var particles := GPUParticles3D.new()
	particles.name = "HorizonParticles"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.emitting = true
	particles.amount = horizon_particle_count
	particles.lifetime = horizon_particle_lifetime
	particles.preprocess = horizon_particle_lifetime
	particles.randomness = 0.4
	particles.local_coords = true
	particles.draw_pass_1 = _build_horizon_mesh()
	# orbit_velocity spins particles in the LOCAL XY plane; tilt -90° around X
	# so that plane lines up with the game's XZ ground plane (see the
	# absorption burst above for the same trick).
	particles.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	particles.process_material = _build_horizon_material()
	add_child(particles)
	_horizon_particles = particles
	_apply_horizon_particle_size()


## Continuous ring of glowing ember particles standing in for the old
## static orange accretion-ring glow.
func _setup_ring_particles() -> void:
	if not body_data or _ring_particles:
		return
	var particles := GPUParticles3D.new()
	particles.name = "RingParticles"
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.emitting = true
	# Buffer sized for the absorption flare's peak; amount_ratio scales the
	# actually-emitted share down to ring_particle_count in the normal state
	# (see _apply_ring_flare for why amount itself must never change).
	particles.amount = maxi(ceili(ring_particle_count * flare_amount_multiplier), 1)
	particles.amount_ratio = 1.0 / flare_amount_multiplier
	particles.lifetime = ring_particle_lifetime
	particles.preprocess = ring_particle_lifetime
	particles.randomness = 0.9
	particles.local_coords = true
	particles.draw_pass_1 = _build_ring_mesh()
	particles.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	particles.process_material = _build_ring_material()
	add_child(particles)
	_ring_particles = particles
	_apply_ring_particle_size()


func _build_horizon_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	material.emission_ring_axis = Vector3(0.0, 0.0, 1.0)
	material.emission_ring_height = 0.0
	material.emission_ring_inner_radius = 0.0
	material.initial_velocity_min = 0.0
	material.initial_velocity_max = 0.0
	material.gravity = Vector3.ZERO
	material.orbit_velocity_min = horizon_orbit_velocity_min
	material.orbit_velocity_max = horizon_orbit_velocity_max
	material.scale_min = horizon_particle_scale_min
	material.scale_max = horizon_particle_scale_max
	material.color = horizon_color
	return material


func _build_horizon_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.render_priority = particle_render_priority

	var mesh := QuadMesh.new()
	mesh.material = material
	mesh.size = Vector2(0.4, 0.4)
	return mesh


## Custom particle shader instead of ParticleProcessMaterial: each particle
## spawns on the ring with velocity tangent to it there (see
## black_hole_ring_particles.gdshader) — actual radii/speed/scale are pushed
## in by _apply_ring_particle_size(), called once here and again on growth.
func _build_ring_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RingParticleShader
	material.set_shader_parameter("speed_min", ring_particle_speed_min)
	material.set_shader_parameter("speed_max", ring_particle_speed_max)
	material.set_shader_parameter("scale_min", ring_particle_scale_min)
	material.set_shader_parameter("scale_max", ring_particle_scale_max)
	material.set_shader_parameter("particle_color", ring_color)
	return material


func _build_ring_mesh() -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Additive: bright embers glow instead of just tinting the background.
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.render_priority = particle_render_priority

	var mesh := QuadMesh.new()
	mesh.material = material
	mesh.size = Vector2(0.3, 0.3)
	return mesh


func _apply_horizon_particle_size() -> void:
	if not _horizon_particles or not body_data:
		return
	var material := _horizon_particles.process_material as ParticleProcessMaterial
	if not material:
		return
	var radius := maxf(body_data.radius * horizon_radius_multiplier, 0.01)
	material.emission_ring_radius = radius
	_horizon_particles.visibility_aabb = _particle_visibility_aabb(radius)


func _apply_ring_particle_size() -> void:
	if not _ring_particles or not body_data:
		return
	var material := _ring_particles.process_material as ShaderMaterial
	if not material:
		return
	var outer := maxf(body_data.radius * ring_radius_multiplier, 0.01)
	var thickness := clampf(body_data.radius * ring_thickness_multiplier, 0.0, outer)
	material.set_shader_parameter("ring_outer_radius", outer)
	material.set_shader_parameter("ring_inner_radius", maxf(outer - thickness, 0.0))
	_ring_particles.visibility_aabb = _particle_visibility_aabb(outer)


func _particle_visibility_aabb(radius: float) -> AABB:
	var half := maxf(radius * 2.0 + 10.0, 30.0)
	return AABB(Vector3(-half, -half, -half), Vector3(half * 2.0, half * 2.0, half * 2.0))


func _setup_visuals() -> void:
	# Collision from body_data
	var collision := $CollisionShape3D as CollisionShape3D
	var sphere_shape := collision.shape as SphereShape3D
	sphere_shape.radius = body_data.radius

	# Scale lensing plane to cover distortion area
	_apply_lensing_mesh_size()
	_apply_lensing_shader_parameters()
	_apply_horizon_particle_size()
	_apply_ring_particle_size()


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
