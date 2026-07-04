@tool
class_name Planet
extends CelestialBody

@export var visual_data: PlanetVisualData

var _atmosphere_material: ShaderMaterial
var _atmosphere_mesh: MeshInstance3D
var _sun_light: DirectionalLight3D
var _cached_seed: int = -1
var _cached_noise_scale: float = -1.0

const ATMOSPHERE_SHADER = preload("res://resources/shaders/planet_atmosphere.gdshader")


func _setup_visuals() -> void:
	if not body_data or not visual_data:
		return

	var r := body_data.radius

	# Collision
	var collision := $CollisionShape3D as CollisionShape3D
	var sphere_shape := collision.shape as SphereShape3D
	sphere_shape.radius = r

	# Hide surface and cloud meshes — everything renders in atmosphere shader
	($Surface as MeshInstance3D).visible = false
	($Clouds as MeshInstance3D).visible = false

	# Noise textures — await generation before using
	var terrain_tex := _create_noise_texture(visual_data.seed, visual_data.noise_scale)
	var biome_tex := _create_noise_texture(visual_data.seed + 1000, visual_data.noise_scale * 2.0)
	var cloud_tex := _create_noise_texture(visual_data.seed + 2000, visual_data.noise_scale * 1.5)
	await terrain_tex.changed
	await biome_tex.changed
	await cloud_tex.changed
	# The awaits can outlive this node's stay in the tree (e.g. editor scans
	# loading and dropping the scene) — bail out instead of touching a null tree.
	if not is_inside_tree():
		return

	_cached_seed = visual_data.seed
	_cached_noise_scale = visual_data.noise_scale

	# Unified volumetric renderer (atmosphere + clouds + surface)
	_atmosphere_material = ShaderMaterial.new()
	_atmosphere_material.shader = ATMOSPHERE_SHADER
	_atmosphere_material.set_shader_parameter("terrain_noise", terrain_tex)
	_atmosphere_material.set_shader_parameter("biome_noise", biome_tex)
	_atmosphere_material.set_shader_parameter("cloud_noise", cloud_tex)
	_atmosphere_mesh = $Atmosphere as MeshInstance3D
	var atmo_mesh := _atmosphere_mesh.mesh.duplicate() as SphereMesh
	_atmosphere_mesh.mesh = atmo_mesh
	_atmosphere_mesh.material_override = _atmosphere_material
	_atmosphere_mesh.visible = true

	# Cache sun light reference
	_sun_light = _find_directional_light(get_tree().root)

	# Push all params
	_update_shader_params()


func _process(delta: float) -> void:
	if not visual_data or not body_data:
		return

	# Rebuild if seed/noise_scale changed
	if visual_data.seed != _cached_seed or visual_data.noise_scale != _cached_noise_scale:
		if _atmosphere_material:
			_setup_visuals()
		return

	# Reactive: push current visual_data to shaders every frame
	_update_shader_params()

	# Sun direction
	if _atmosphere_material:
		var sun_dir := _sun_light.global_transform.basis.z if _sun_light else Vector3(0.0, 1.0, 0.0)
		_atmosphere_material.set_shader_parameter("sun_direction", sun_dir)


func _update_shader_params() -> void:
	if not visual_data or not body_data or not _atmosphere_material:
		return
	var r := body_data.radius
	var atmo_r := r * visual_data.atmosphere_radius

	# All uniforms go to the unified atmosphere shader
	var m := _atmosphere_material

	# Atmosphere
	m.set_shader_parameter("planet_radius", r)
	m.set_shader_parameter("atmosphere_radius", atmo_r)
	m.set_shader_parameter("atmosphere_density", visual_data.atmosphere_density)
	m.set_shader_parameter("atmosphere_color", visual_data.atmosphere_color)
	m.set_shader_parameter("rayleigh_strength", visual_data.atmosphere_rayleigh_strength)
	m.set_shader_parameter("mie_strength", visual_data.atmosphere_mie_strength)
	m.set_shader_parameter("atmosphere_falloff", visual_data.atmosphere_falloff)
	m.set_shader_parameter("atmosphere_steps", visual_data.atmosphere_steps)

	# Clouds
	m.set_shader_parameter("cloud_coverage_lower", visual_data.cloud_coverage_lower)
	m.set_shader_parameter("cloud_coverage_upper", visual_data.cloud_coverage_upper)
	m.set_shader_parameter("cloud_color", visual_data.cloud_color)
	m.set_shader_parameter("cloud_noise_scale", visual_data.noise_scale)
	m.set_shader_parameter("cloud_lower_radius", r * visual_data.cloud_lower)
	m.set_shader_parameter("cloud_upper_radius", r * visual_data.cloud_upper)

	# Surface
	m.set_shader_parameter("sea_level", visual_data.sea_level)
	m.set_shader_parameter("water_color_shallow", visual_data.water_color_shallow)
	m.set_shader_parameter("water_color_deep", visual_data.water_color_deep)
	m.set_shader_parameter("wave_intensity", visual_data.wave_intensity)
	m.set_shader_parameter("wave_speed", visual_data.wave_speed)
	m.set_shader_parameter("biome_vegetation", visual_data.biome_vegetation)
	m.set_shader_parameter("biome_sand", visual_data.biome_sand)
	m.set_shader_parameter("biome_rock", visual_data.biome_rock)
	m.set_shader_parameter("color_vegetation", visual_data.color_vegetation)
	m.set_shader_parameter("color_sand", visual_data.color_sand)
	m.set_shader_parameter("color_rock", visual_data.color_rock)
	m.set_shader_parameter("mountain_intensity", visual_data.mountain_intensity)
	m.set_shader_parameter("mountain_noise_scale", visual_data.mountain_noise_scale)
	m.set_shader_parameter("snow_level", visual_data.snow_level)
	m.set_shader_parameter("snow_color", visual_data.snow_color)
	m.set_shader_parameter("noise_scale", visual_data.noise_scale)
	m.set_shader_parameter("max_displacement", r * 0.15)
	m.set_shader_parameter("ao_strength", visual_data.ao_strength)

	# Resize atmosphere mesh
	if _atmosphere_mesh:
		var amesh := _atmosphere_mesh.mesh as SphereMesh
		if amesh and not is_equal_approx(amesh.radius, atmo_r):
			amesh.radius = atmo_r
			amesh.height = atmo_r * 2.0


func _find_directional_light(node: Node) -> DirectionalLight3D:
	if node is DirectionalLight3D:
		return node
	for child in node.get_children():
		var found := _find_directional_light(child)
		if found:
			return found
	return null


func _create_noise_texture(noise_seed: int, frequency: float) -> NoiseTexture3D:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.frequency = frequency * 0.1
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4

	var tex := NoiseTexture3D.new()
	tex.noise = noise
	tex.width = 64
	tex.height = 64
	tex.depth = 64
	return tex
