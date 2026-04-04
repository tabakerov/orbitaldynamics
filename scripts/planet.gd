@tool
class_name Planet
extends CelestialBody

@export var visual_data: PlanetVisualData

var _clouds_mesh: MeshInstance3D
var _surface_material: ShaderMaterial
var _clouds_material: ShaderMaterial
var _atmosphere_material: ShaderMaterial
var _atmosphere_mesh: MeshInstance3D
var _sun_light: DirectionalLight3D
var _cached_seed: int = -1
var _cached_noise_scale: float = -1.0

const SURFACE_SHADER = preload("res://resources/shaders/planet_surface.gdshader")
const CLOUDS_SHADER = preload("res://resources/shaders/planet_clouds.gdshader")
const ATMOSPHERE_SHADER = preload("res://resources/shaders/planet_atmosphere.gdshader")


func _setup_visuals() -> void:
	if not body_data or not visual_data:
		return

	var r := body_data.radius

	# Collision
	var collision := $CollisionShape3D as CollisionShape3D
	var sphere_shape := collision.shape as SphereShape3D
	sphere_shape.radius = r

	# Noise textures — await generation before using
	var terrain_tex := _create_noise_texture(visual_data.seed, visual_data.noise_scale)
	var biome_tex := _create_noise_texture(visual_data.seed + 1000, visual_data.noise_scale * 2.0)
	var cloud_tex := _create_noise_texture(visual_data.seed + 2000, visual_data.noise_scale * 1.5)
	await terrain_tex.changed
	await biome_tex.changed
	await cloud_tex.changed

	_cached_seed = visual_data.seed
	_cached_noise_scale = visual_data.noise_scale

	# Surface
	_surface_material = ShaderMaterial.new()
	_surface_material.shader = SURFACE_SHADER
	_surface_material.set_shader_parameter("terrain_noise", terrain_tex)
	_surface_material.set_shader_parameter("biome_noise", biome_tex)
	var surface := $Surface as MeshInstance3D
	var surface_mesh := surface.mesh.duplicate() as SphereMesh
	surface_mesh.radius = r
	surface_mesh.height = r * 2.0
	surface.mesh = surface_mesh
	surface.material_override = _surface_material

	# Clouds
	_clouds_material = ShaderMaterial.new()
	_clouds_material.shader = CLOUDS_SHADER
	_clouds_material.set_shader_parameter("cloud_noise", cloud_tex)
	_clouds_mesh = $Clouds as MeshInstance3D
	var clouds_mesh_res := _clouds_mesh.mesh.duplicate() as SphereMesh
	_clouds_mesh.mesh = clouds_mesh_res
	_clouds_mesh.material_override = _clouds_material

	# Atmosphere
	_atmosphere_material = ShaderMaterial.new()
	_atmosphere_material.shader = ATMOSPHERE_SHADER
	_atmosphere_material.set_shader_parameter("cloud_noise", cloud_tex)
	_atmosphere_mesh = $Atmosphere as MeshInstance3D
	var atmo_mesh := _atmosphere_mesh.mesh.duplicate() as SphereMesh
	_atmosphere_mesh.mesh = atmo_mesh
	_atmosphere_mesh.material_override = _atmosphere_material

	# Cache sun light reference
	_sun_light = _find_directional_light(get_tree().root)

	# Push all params
	_update_shader_params()


func _process(delta: float) -> void:
	if not visual_data or not body_data:
		return

	# Rebuild if seed/noise_scale changed
	if visual_data.seed != _cached_seed or visual_data.noise_scale != _cached_noise_scale:
		if _surface_material:
			_setup_visuals()
		return

	# Reactive: push current visual_data to shaders every frame
	_update_shader_params()

	# Cloud rotation
	if _clouds_mesh and visual_data.cloud_coverage > 0.0:
		_clouds_mesh.rotate_y(visual_data.cloud_rotation_speed * delta)

	# Sun direction
	if _atmosphere_material:
		var sun_dir := _sun_light.global_transform.basis.z if _sun_light else Vector3(0.0, 1.0, 0.0)
		_atmosphere_material.set_shader_parameter("sun_direction", sun_dir)


func _update_shader_params() -> void:
	if not visual_data or not body_data:
		return
	var r := body_data.radius

	# Surface
	if _surface_material:
		_surface_material.set_shader_parameter("sea_level", visual_data.sea_level)
		_surface_material.set_shader_parameter("water_color_shallow", visual_data.water_color_shallow)
		_surface_material.set_shader_parameter("water_color_deep", visual_data.water_color_deep)
		_surface_material.set_shader_parameter("wave_intensity", visual_data.wave_intensity)
		_surface_material.set_shader_parameter("wave_speed", visual_data.wave_speed)
		_surface_material.set_shader_parameter("biome_vegetation", visual_data.biome_vegetation)
		_surface_material.set_shader_parameter("biome_sand", visual_data.biome_sand)
		_surface_material.set_shader_parameter("biome_rock", visual_data.biome_rock)
		_surface_material.set_shader_parameter("color_vegetation", visual_data.color_vegetation)
		_surface_material.set_shader_parameter("color_sand", visual_data.color_sand)
		_surface_material.set_shader_parameter("color_rock", visual_data.color_rock)
		_surface_material.set_shader_parameter("mountain_intensity", visual_data.mountain_intensity)
		_surface_material.set_shader_parameter("max_displacement", r * 0.15)
		_surface_material.set_shader_parameter("snow_level", visual_data.snow_level)
		_surface_material.set_shader_parameter("snow_color", visual_data.snow_color)
		_surface_material.set_shader_parameter("noise_scale", visual_data.noise_scale)
		_surface_material.set_shader_parameter("ao_strength", visual_data.ao_strength)
		_surface_material.set_shader_parameter("atmosphere_haze_density", visual_data.atmosphere_density)
		_surface_material.set_shader_parameter("atmosphere_haze_color", visual_data.atmosphere_color)

	# Clouds
	if _clouds_material:
		_clouds_material.set_shader_parameter("cloud_coverage", visual_data.cloud_coverage)
		_clouds_material.set_shader_parameter("cloud_color", visual_data.cloud_color)
		_clouds_material.set_shader_parameter("noise_scale", visual_data.noise_scale)
	if _clouds_mesh:
		_clouds_mesh.visible = visual_data.cloud_coverage > 0.0
		var cloud_r := r * visual_data.cloud_height
		var cmesh := _clouds_mesh.mesh as SphereMesh
		if cmesh and not is_equal_approx(cmesh.radius, cloud_r):
			cmesh.radius = cloud_r
			cmesh.height = cloud_r * 2.0

	# Atmosphere
	if _atmosphere_material:
		var atmo_r := r * visual_data.atmosphere_radius
		_atmosphere_material.set_shader_parameter("planet_radius", r)
		_atmosphere_material.set_shader_parameter("atmosphere_radius", atmo_r)
		_atmosphere_material.set_shader_parameter("atmosphere_density", visual_data.atmosphere_density)
		_atmosphere_material.set_shader_parameter("atmosphere_color", visual_data.atmosphere_color)
		_atmosphere_material.set_shader_parameter("rayleigh_strength", visual_data.atmosphere_rayleigh_strength)
		_atmosphere_material.set_shader_parameter("mie_strength", visual_data.atmosphere_mie_strength)
		_atmosphere_material.set_shader_parameter("atmosphere_steps", visual_data.atmosphere_steps)
		_atmosphere_material.set_shader_parameter("cloud_shadows_enabled", visual_data.cloud_shadows_enabled)
		_atmosphere_material.set_shader_parameter("cloud_coverage", visual_data.cloud_coverage)
		_atmosphere_material.set_shader_parameter("cloud_noise_scale", visual_data.noise_scale)
		_atmosphere_material.set_shader_parameter("cloud_shell_radius", r * visual_data.cloud_height)
	if _atmosphere_mesh:
		_atmosphere_mesh.visible = visual_data.atmosphere_density > 0.0
		var atmo_r := r * visual_data.atmosphere_radius
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
