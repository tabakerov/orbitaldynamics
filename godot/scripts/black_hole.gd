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


func _apply_growth(new_radius: float, new_mass: float) -> void:
	var old_radius := body_data.radius
	body_data.radius = new_radius
	body_data.mass = new_mass
	if sim_index >= 0:
		CelestialSim.set_body_mass(sim_index, body_data.mass)
	if old_radius > 0.0:
		lensing_radius *= body_data.radius / old_radius
	_setup_visuals()


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
