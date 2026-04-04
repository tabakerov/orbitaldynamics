class_name Planet
extends CelestialBody

@export var visual_data: PlanetVisualData

var _clouds_mesh: MeshInstance3D
var _surface_material: ShaderMaterial
var _clouds_material: ShaderMaterial
var _atmosphere_material: ShaderMaterial
var _sun_light: DirectionalLight3D

const SURFACE_SHADER = preload("res://resources/shaders/planet_surface.gdshader")
const CLOUDS_SHADER = preload("res://resources/shaders/planet_clouds.gdshader")
const ATMOSPHERE_SHADER = preload("res://resources/shaders/planet_atmosphere.gdshader")


func _setup_visuals() -> void:
	print("[Planet] _setup_visuals called. body_data=%s visual_data=%s" % [body_data, visual_data])
	if not body_data or not visual_data:
		print("[Planet] SKIPPING — missing data")
		return

	var r := body_data.radius
	print("[Planet] radius=%s seed=%s" % [r, visual_data.seed])

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
	print("[Planet] Noise textures ready")

	# Surface
	_surface_material = _create_surface_material(terrain_tex, biome_tex, r)
	var surface := $Surface as MeshInstance3D
	var surface_mesh := surface.mesh.duplicate() as SphereMesh
	surface_mesh.radius = r
	surface_mesh.height = r * 2.0
	surface.mesh = surface_mesh
	surface.material_override = _surface_material

	# Clouds
	if visual_data.cloud_coverage > 0.0:
		_clouds_material = _create_clouds_material(cloud_tex)
		_clouds_mesh = $Clouds as MeshInstance3D
		var clouds_mesh_res := _clouds_mesh.mesh.duplicate() as SphereMesh
		var cloud_r := r * 1.005
		clouds_mesh_res.radius = cloud_r
		clouds_mesh_res.height = cloud_r * 2.0
		_clouds_mesh.mesh = clouds_mesh_res
		_clouds_mesh.material_override = _clouds_material
		_clouds_mesh.visible = true
	else:
		($Clouds as MeshInstance3D).visible = false

	# Atmosphere
	if visual_data.atmosphere_density > 0.0:
		_atmosphere_material = _create_atmosphere_material(cloud_tex, r)
		var atmo := $Atmosphere as MeshInstance3D
		var atmo_mesh := atmo.mesh.duplicate() as SphereMesh
		var atmo_r := r * visual_data.atmosphere_radius
		atmo_mesh.radius = atmo_r
		atmo_mesh.height = atmo_r * 2.0
		atmo.mesh = atmo_mesh
		atmo.material_override = _atmosphere_material
		atmo.visible = true
	else:
		($Atmosphere as MeshInstance3D).visible = false

	# Cache sun light reference
	_sun_light = _find_directional_light(get_tree().root)
	print("[Planet] Setup done. surface_mat=%s clouds_vis=%s atmo_vis=%s" % [
		_surface_material != null,
		($Clouds as MeshInstance3D).visible,
		($Atmosphere as MeshInstance3D).visible,
	])


func _process(delta: float) -> void:
	if _clouds_mesh and visual_data and visual_data.cloud_coverage > 0.0:
		_clouds_mesh.rotate_y(visual_data.cloud_rotation_speed * delta)

	if _atmosphere_material:
		var sun_dir := -_sun_light.global_transform.basis.z if _sun_light else Vector3(0.0, -1.0, 0.0)
		_atmosphere_material.set_shader_parameter("sun_direction", sun_dir)


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


func _create_surface_material(terrain_tex: NoiseTexture3D, biome_tex: NoiseTexture3D, r: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SURFACE_SHADER
	mat.set_shader_parameter("terrain_noise", terrain_tex)
	mat.set_shader_parameter("biome_noise", biome_tex)
	mat.set_shader_parameter("sea_level", visual_data.sea_level)
	mat.set_shader_parameter("water_color_shallow", visual_data.water_color_shallow)
	mat.set_shader_parameter("water_color_deep", visual_data.water_color_deep)
	mat.set_shader_parameter("wave_intensity", visual_data.wave_intensity)
	mat.set_shader_parameter("wave_speed", visual_data.wave_speed)
	mat.set_shader_parameter("biome_vegetation", visual_data.biome_vegetation)
	mat.set_shader_parameter("biome_sand", visual_data.biome_sand)
	mat.set_shader_parameter("biome_rock", visual_data.biome_rock)
	mat.set_shader_parameter("color_vegetation", visual_data.color_vegetation)
	mat.set_shader_parameter("color_sand", visual_data.color_sand)
	mat.set_shader_parameter("color_rock", visual_data.color_rock)
	mat.set_shader_parameter("mountain_intensity", visual_data.mountain_intensity)
	mat.set_shader_parameter("max_displacement", r * 0.15)
	mat.set_shader_parameter("snow_level", visual_data.snow_level)
	mat.set_shader_parameter("snow_color", visual_data.snow_color)
	mat.set_shader_parameter("noise_scale", visual_data.noise_scale)
	return mat


func _create_clouds_material(cloud_tex: NoiseTexture3D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = CLOUDS_SHADER
	mat.set_shader_parameter("cloud_noise", cloud_tex)
	mat.set_shader_parameter("cloud_coverage", visual_data.cloud_coverage)
	mat.set_shader_parameter("cloud_color", visual_data.cloud_color)
	mat.set_shader_parameter("noise_scale", visual_data.noise_scale)
	return mat


func _create_atmosphere_material(cloud_tex: NoiseTexture3D, r: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ATMOSPHERE_SHADER
	mat.set_shader_parameter("planet_radius", r)
	mat.set_shader_parameter("atmosphere_radius", r * visual_data.atmosphere_radius)
	mat.set_shader_parameter("atmosphere_density", visual_data.atmosphere_density)
	mat.set_shader_parameter("atmosphere_color", visual_data.atmosphere_color)
	mat.set_shader_parameter("rayleigh_strength", visual_data.atmosphere_rayleigh_strength)
	mat.set_shader_parameter("mie_strength", visual_data.atmosphere_mie_strength)
	mat.set_shader_parameter("atmosphere_steps", visual_data.atmosphere_steps)
	mat.set_shader_parameter("cloud_shadows_enabled", visual_data.cloud_shadows_enabled)
	mat.set_shader_parameter("cloud_noise", cloud_tex)
	mat.set_shader_parameter("cloud_coverage", visual_data.cloud_coverage)
	mat.set_shader_parameter("cloud_noise_scale", visual_data.noise_scale)
	mat.set_shader_parameter("cloud_shell_radius", r * 1.005)
	return mat
