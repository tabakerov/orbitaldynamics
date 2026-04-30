@tool
class_name BlackHole
extends CelestialBody

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


func _ready() -> void:
	super()
	_apply_lensing_mesh_size()
	_apply_lensing_shader_parameters()


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
