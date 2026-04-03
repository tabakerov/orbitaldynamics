# Procedural Planet Shader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a configurable procedural planet shader system with three layers (surface, clouds, atmosphere) that generates unique stylized planets from parametric data.

**Architecture:** Three-mesh approach per planet — Surface (land/water/biomes/mountains via vertex displacement), Clouds (separate mesh with independent rotation), Atmosphere (ray-marched scattering with planet self-shadowing). All parameters stored in a PlanetVisualData Resource, applied via planet.gd which extends the existing CelestialBody.

**Tech Stack:** Godot 4.6, GDShader (GLSL-like), FastNoiseLite + NoiseTexture3D, GDScript

**Spec:** `docs/superpowers/specs/2026-04-03-procedural-planet-shader-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `scripts/planet_visual_data.gd` | Create | Resource holding all visual parameters |
| `resources/shaders/planet_surface.gdshader` | Create | Surface shader: land/water/biomes/mountains/snow/waves |
| `resources/shaders/planet_clouds.gdshader` | Create | Cloud shader: procedural cloud layer |
| `resources/shaders/planet_atmosphere.gdshader` | Create | Atmosphere shader: ray-marched scattering |
| `scripts/planet.gd` | Create | Planet script extending CelestialBody |
| `scenes/planet.tscn` | Create | Planet scene with 3 meshes + collision |
| `resources/planet_earth.tres` | Create | Earth-like preset |
| `resources/planet_desert.tres` | Create | Desert planet preset |
| `scenes/levels/level_01.tscn` | Modify | Replace CelestialBody instances with Planet |
| `tests/test_planet_visual_data.gd` | Create | Tests for resource defaults and validation |

---

### Task 1: PlanetVisualData Resource

**Files:**
- Create: `scripts/planet_visual_data.gd`
- Create: `tests/test_planet_visual_data.gd`

- [ ] **Step 1: Write the failing test**

Create `tests/test_planet_visual_data.gd`:

```gdscript
extends SceneTree

const PVD = preload("res://scripts/planet_visual_data.gd")


func _init() -> void:
	_test_defaults()
	_test_biome_weights_nonzero()
	print("All PlanetVisualData tests passed!")
	quit()


func _test_defaults() -> void:
	var data := PVD.new()
	assert(data.sea_level >= 0.0 and data.sea_level <= 1.0, "sea_level should be in [0,1]")
	assert(data.mountain_intensity >= 0.0, "mountain_intensity should be non-negative")
	assert(data.cloud_coverage >= 0.0 and data.cloud_coverage <= 1.0, "cloud_coverage in [0,1]")
	assert(data.atmosphere_density >= 0.0, "atmosphere_density should be non-negative")
	assert(data.atmosphere_radius >= 1.0, "atmosphere_radius must be >= 1.0")
	assert(data.atmosphere_steps >= 1, "atmosphere_steps must be >= 1")
	assert(data.noise_scale > 0.0, "noise_scale must be positive")
	print("  PASS: defaults valid")


func _test_biome_weights_nonzero() -> void:
	var data := PVD.new()
	var total := data.biome_vegetation + data.biome_sand + data.biome_rock
	assert(total > 0.0, "At least one biome weight must be > 0")
	print("  PASS: biome weights nonzero")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /var/home/az/Gamedev/orbital-dynamics && godot --headless --script tests/test_planet_visual_data.gd`

Expected: Fail — `PVD` cannot be preloaded (file doesn't exist).

- [ ] **Step 3: Write the PlanetVisualData resource**

Create `scripts/planet_visual_data.gd`:

```gdscript
class_name PlanetVisualData
extends Resource

## --- Terrain & Water ---

## Noise threshold: below = water, above = land. 0.3 means ~70% water.
@export_range(0.0, 1.0) var sea_level: float = 0.4

## Shallow water color near coastlines.
@export var water_color_shallow: Color = Color(0.3, 0.6, 0.8)

## Deep ocean color.
@export var water_color_deep: Color = Color(0.05, 0.1, 0.3)

## Amplitude of animated waves.
@export_range(0.0, 1.0) var wave_intensity: float = 0.3

## Wave animation speed.
@export var wave_speed: float = 0.5

## --- Biomes ---

## Weight of vegetation zones on land.
@export_range(0.0, 1.0) var biome_vegetation: float = 0.5

## Weight of desert/sand zones on land.
@export_range(0.0, 1.0) var biome_sand: float = 0.3

## Weight of rocky zones on land.
@export_range(0.0, 1.0) var biome_rock: float = 0.2

## Vegetation color.
@export var color_vegetation: Color = Color(0.2, 0.55, 0.15)

## Sand color.
@export var color_sand: Color = Color(0.85, 0.75, 0.45)

## Rock color.
@export var color_rock: Color = Color(0.45, 0.42, 0.4)

## --- Mountains & Snow ---

## Vertex displacement magnitude. 0 = flat, 1 = maximum height.
@export_range(0.0, 1.0) var mountain_intensity: float = 0.3

## Height threshold for snow caps. 0 = no snow.
@export_range(0.0, 1.0) var snow_level: float = 0.7

## Snow color.
@export var snow_color: Color = Color(0.95, 0.95, 0.98)

## --- Clouds ---

## Cloud density. 0 = clear sky.
@export_range(0.0, 1.0) var cloud_coverage: float = 0.4

## Cloud color.
@export var cloud_color: Color = Color(1.0, 1.0, 1.0)

## Independent rotation speed for cloud layer (rad/s).
@export var cloud_rotation_speed: float = 0.05

## --- Atmosphere ---

## Optical depth multiplier. 0 = no atmosphere.
@export_range(0.0, 1.0) var atmosphere_density: float = 0.5

## Rayleigh scattering color.
@export var atmosphere_color: Color = Color(0.3, 0.5, 1.0)

## Atmosphere shell radius relative to planet (1.0 = no atmosphere shell).
@export_range(1.0, 1.5) var atmosphere_radius: float = 1.15

## Rayleigh scattering strength.
@export_range(0.0, 5.0) var atmosphere_rayleigh_strength: float = 1.0

## Mie forward-scattering strength.
@export_range(0.0, 2.0) var atmosphere_mie_strength: float = 0.3

## Ray-march step count (quality vs performance).
@export_range(4, 16) var atmosphere_steps: int = 8

## Enable cloud shadow sampling in atmosphere ray-march.
@export var cloud_shadows_enabled: bool = false

## --- Generation ---

## Seed for procedural generation. Different seeds = different continents.
@export var seed: int = 0

## Noise frequency — controls feature size on the surface.
@export_range(0.5, 8.0) var noise_scale: float = 2.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /var/home/az/Gamedev/orbital-dynamics && godot --headless --script tests/test_planet_visual_data.gd`

Expected: `All PlanetVisualData tests passed!`

- [ ] **Step 5: Commit**

```bash
git add scripts/planet_visual_data.gd tests/test_planet_visual_data.gd
git commit -m "feat: add PlanetVisualData resource with all visual parameters"
```

---

### Task 2: Surface Shader — Basic Land/Water

**Files:**
- Create: `resources/shaders/planet_surface.gdshader`

- [ ] **Step 1: Create the surface shader with land/water coloring**

Create `resources/shaders/planet_surface.gdshader`:

```glsl
shader_type spatial;

uniform sampler3D terrain_noise;
uniform sampler3D biome_noise;

// Terrain & Water
uniform float sea_level : hint_range(0.0, 1.0) = 0.4;
uniform vec3 water_color_shallow : source_color = vec3(0.3, 0.6, 0.8);
uniform vec3 water_color_deep : source_color = vec3(0.05, 0.1, 0.3);
uniform float wave_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float wave_speed = 0.5;

// Biomes
uniform float biome_vegetation : hint_range(0.0, 1.0) = 0.5;
uniform float biome_sand : hint_range(0.0, 1.0) = 0.3;
uniform float biome_rock : hint_range(0.0, 1.0) = 0.2;
uniform vec3 color_vegetation : source_color = vec3(0.2, 0.55, 0.15);
uniform vec3 color_sand : source_color = vec3(0.85, 0.75, 0.45);
uniform vec3 color_rock : source_color = vec3(0.45, 0.42, 0.4);

// Mountains & Snow
uniform float mountain_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float max_displacement = 0.5;
uniform float snow_level : hint_range(0.0, 1.0) = 0.7;
uniform vec3 snow_color : source_color = vec3(0.95, 0.95, 0.98);

// Noise sampling
uniform float noise_scale = 2.0;

varying float v_height;
varying float v_noise;

void vertex() {
	vec3 unit_pos = normalize(VERTEX);
	vec3 sample_pos = unit_pos * noise_scale * 0.5 + 0.5;
	float n = texture(terrain_noise, sample_pos).r;

	v_noise = n;

	if (n > sea_level) {
		float land_height = (n - sea_level) / (1.0 - sea_level);
		VERTEX += NORMAL * land_height * mountain_intensity * max_displacement;
		v_height = land_height;
	} else {
		v_height = 0.0;
	}
}

void fragment() {
	vec3 col;

	if (v_noise <= sea_level) {
		// Water
		float coast_proximity = smoothstep(sea_level - 0.08, sea_level, v_noise);
		col = mix(water_color_deep, water_color_shallow, coast_proximity);

		// Animated waves
		vec3 wave_sample = normalize(VERTEX) * noise_scale * 3.0 * 0.5 + 0.5;
		wave_sample.x += TIME * wave_speed * 0.1;
		wave_sample.z += TIME * wave_speed * 0.07;
		float wave = texture(terrain_noise, wave_sample).r;
		col += vec3(wave * 0.1 * wave_intensity);

		// Slight specular for water
		SPECULAR = 0.5;
		ROUGHNESS = 0.2;
	} else {
		// Land — biome selection
		vec3 biome_sample = normalize(VERTEX) * noise_scale * 0.7 * 0.5 + 0.5;
		float bn = texture(biome_noise, biome_sample).r;

		// Normalize weights
		float total_weight = biome_vegetation + biome_sand + biome_rock;
		float w_veg = biome_vegetation / max(total_weight, 0.001);
		float w_sand = biome_sand / max(total_weight, 0.001);

		// Map noise to biome via cumulative thresholds
		if (bn < w_veg) {
			col = color_vegetation;
		} else if (bn < w_veg + w_sand) {
			col = color_sand;
		} else {
			col = color_rock;
		}

		// Mountains override — high areas tend to rock
		float mountain_blend = smoothstep(0.5, 0.8, v_height);
		col = mix(col, color_rock, mountain_blend);

		// Snow caps
		float snow_mask = step(snow_level, v_height);
		col = mix(col, snow_color, snow_mask);

		ROUGHNESS = 0.8;
		SPECULAR = 0.1;
	}

	ALBEDO = col;
}
```

- [ ] **Step 2: Commit**

```bash
git add resources/shaders/planet_surface.gdshader
git commit -m "feat: add planet surface shader with land/water/biomes/mountains/snow"
```

---

### Task 3: Cloud Shader

**Files:**
- Create: `resources/shaders/planet_clouds.gdshader`

- [ ] **Step 1: Create the cloud shader**

Create `resources/shaders/planet_clouds.gdshader`:

```glsl
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler3D cloud_noise;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.4;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float noise_scale = 2.0;

void fragment() {
	vec3 sample_pos = normalize(VERTEX) * noise_scale * 0.8 * 0.5 + 0.5;
	float n = texture(cloud_noise, sample_pos).r;

	float threshold = 1.0 - cloud_coverage;
	float cloud_mask = smoothstep(threshold - 0.05, threshold + 0.05, n);

	ALBEDO = cloud_color;
	ALPHA = cloud_mask * 0.9;

	if (ALPHA < 0.01) {
		discard;
	}
}
```

- [ ] **Step 2: Commit**

```bash
git add resources/shaders/planet_clouds.gdshader
git commit -m "feat: add planet cloud shader with procedural coverage"
```

---

### Task 4: Atmosphere Shader

**Files:**
- Create: `resources/shaders/planet_atmosphere.gdshader`

- [ ] **Step 1: Create the atmosphere shader with ray-marching**

Create `resources/shaders/planet_atmosphere.gdshader`:

```glsl
shader_type spatial;
render_mode blend_add, unshaded, cull_front;

uniform float planet_radius = 1.0;
uniform float atmosphere_radius = 1.15;
uniform float atmosphere_density : hint_range(0.0, 1.0) = 0.5;
uniform vec3 atmosphere_color : source_color = vec3(0.3, 0.5, 1.0);
uniform float rayleigh_strength : hint_range(0.0, 5.0) = 1.0;
uniform float mie_strength : hint_range(0.0, 2.0) = 0.3;
uniform int atmosphere_steps : hint_range(4, 16) = 8;

uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0);

// Optional cloud shadow sampling
uniform bool cloud_shadows_enabled = false;
uniform sampler3D cloud_noise;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_noise_scale = 2.0;
uniform float cloud_shell_radius = 1.005;

// Ray-sphere intersection. Returns (near, far) distances or (-1, -1) if no hit.
vec2 ray_sphere(vec3 ro, vec3 rd, float radius) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - radius * radius;
	float discriminant = b * b - c;
	if (discriminant < 0.0) {
		return vec2(-1.0);
	}
	float sq = sqrt(discriminant);
	return vec2(-b - sq, -b + sq);
}

// Rayleigh phase function
float rayleigh_phase(float cos_theta) {
	return 0.75 * (1.0 + cos_theta * cos_theta);
}

// Henyey-Greenstein phase function for Mie scattering
float mie_phase(float cos_theta, float g) {
	float g2 = g * g;
	float denom = 1.0 + g2 - 2.0 * g * cos_theta;
	return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
}

void fragment() {
	// Ray origin and direction in model space
	vec3 ro = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize((inverse(MODEL_MATRIX) * vec4(normalize(world_pos - CAMERA_POSITION_WORLD), 0.0)).xyz);

	// Atmosphere shell intersection
	vec2 atmo_hit = ray_sphere(ro, rd, atmosphere_radius);
	if (atmo_hit.x < 0.0 && atmo_hit.y < 0.0) {
		ALPHA = 0.0;
		return;
	}

	float ray_start = max(atmo_hit.x, 0.0);
	float ray_end = atmo_hit.y;

	// Planet body intersection — ray ends at planet surface
	vec2 planet_hit = ray_sphere(ro, rd, planet_radius);
	if (planet_hit.x > 0.0) {
		ray_end = min(ray_end, planet_hit.x);
	}

	// Light direction in model space
	vec3 light_dir = normalize((inverse(MODEL_MATRIX) * vec4(sun_direction, 0.0)).xyz);
	float cos_theta = dot(rd, light_dir);

	float step_size = (ray_end - ray_start) / float(atmosphere_steps);
	float optical_depth = 0.0;
	vec3 scattered = vec3(0.0);

	float scale_height = (atmosphere_radius - planet_radius) * 0.4;

	for (int i = 0; i < atmosphere_steps; i++) {
		float t = ray_start + (float(i) + 0.5) * step_size;
		vec3 sample_point = ro + rd * t;
		float altitude = length(sample_point) - planet_radius;
		float density = exp(-altitude / scale_height) * step_size;

		// Planet self-shadow: check if sun ray from this point hits the planet
		vec2 shadow_hit = ray_sphere(sample_point, light_dir, planet_radius);
		float shadow = (shadow_hit.x > 0.0) ? 0.0 : 1.0;

		// Cloud shadow (optional)
		if (cloud_shadows_enabled && shadow > 0.0 && cloud_coverage > 0.0) {
			// Find where sun ray intersects cloud shell
			vec2 cloud_hit = ray_sphere(sample_point, light_dir, cloud_shell_radius);
			if (cloud_hit.x > 0.0) {
				vec3 cloud_point = sample_point + light_dir * cloud_hit.x;
				vec3 cloud_uv = cloud_point * cloud_noise_scale * 0.8 * 0.5 + 0.5;
				float cn = texture(cloud_noise, cloud_uv).r;
				float cloud_threshold = 1.0 - cloud_coverage;
				float cloud_shadow = smoothstep(cloud_threshold - 0.05, cloud_threshold + 0.05, cn);
				shadow *= (1.0 - cloud_shadow * 0.7);
			}
		}

		// Accumulate
		optical_depth += density;

		float rayleigh = rayleigh_phase(cos_theta) * rayleigh_strength;
		float mie = mie_phase(cos_theta, 0.76) * mie_strength;
		scattered += density * shadow * (atmosphere_color * rayleigh + vec3(mie));
	}

	ALBEDO = scattered;
	ALPHA = clamp(optical_depth * atmosphere_density, 0.0, 1.0);
}
```

- [ ] **Step 2: Commit**

```bash
git add resources/shaders/planet_atmosphere.gdshader
git commit -m "feat: add ray-marched atmosphere shader with self-shadow and cloud shadows"
```

---

### Task 5: Planet Script

**Files:**
- Create: `scripts/planet.gd`

- [ ] **Step 1: Create planet.gd extending CelestialBody**

Create `scripts/planet.gd`:

```gdscript
class_name Planet
extends CelestialBody

@export var visual_data: PlanetVisualData

var _clouds_mesh: MeshInstance3D
var _surface_material: ShaderMaterial
var _clouds_material: ShaderMaterial
var _atmosphere_material: ShaderMaterial

const SURFACE_SHADER = preload("res://resources/shaders/planet_surface.gdshader")
const CLOUDS_SHADER = preload("res://resources/shaders/planet_clouds.gdshader")
const ATMOSPHERE_SHADER = preload("res://resources/shaders/planet_atmosphere.gdshader")


func _setup_visuals() -> void:
	if not body_data:
		return

	var r := body_data.radius

	# Collision
	var collision := $CollisionShape3D as CollisionShape3D
	var sphere_shape := collision.shape as SphereShape3D
	sphere_shape.radius = r

	# Noise textures
	var terrain_tex := _create_noise_texture(visual_data.seed, visual_data.noise_scale)
	var biome_tex := _create_noise_texture(visual_data.seed + 1000, visual_data.noise_scale * 2.0)
	var cloud_tex := _create_noise_texture(visual_data.seed + 2000, visual_data.noise_scale * 1.5)

	# Surface
	_surface_material = _create_surface_material(terrain_tex, biome_tex, r)
	var surface := $Surface as MeshInstance3D
	var surface_mesh := surface.mesh as SphereMesh
	surface_mesh.radius = r
	surface_mesh.height = r * 2.0
	surface.material_override = _surface_material

	# Clouds
	if visual_data.cloud_coverage > 0.0:
		_clouds_material = _create_clouds_material(cloud_tex)
		_clouds_mesh = $Clouds as MeshInstance3D
		var clouds_mesh_res := _clouds_mesh.mesh as SphereMesh
		var cloud_r := r * 1.005
		clouds_mesh_res.radius = cloud_r
		clouds_mesh_res.height = cloud_r * 2.0
		_clouds_mesh.material_override = _clouds_material
		_clouds_mesh.visible = true
	else:
		($Clouds as MeshInstance3D).visible = false

	# Atmosphere
	if visual_data.atmosphere_density > 0.0:
		_atmosphere_material = _create_atmosphere_material(cloud_tex, r)
		var atmo := $Atmosphere as MeshInstance3D
		var atmo_mesh := atmo.mesh as SphereMesh
		var atmo_r := r * visual_data.atmosphere_radius
		atmo_mesh.radius = atmo_r
		atmo_mesh.height = atmo_r * 2.0
		atmo.material_override = _atmosphere_material
		atmo.visible = true
	else:
		($Atmosphere as MeshInstance3D).visible = false


func _process(delta: float) -> void:
	if _clouds_mesh and visual_data and visual_data.cloud_coverage > 0.0:
		_clouds_mesh.rotate_y(visual_data.cloud_rotation_speed * delta)

	if _atmosphere_material:
		var sun_dir := _get_sun_direction()
		_atmosphere_material.set_shader_parameter("sun_direction", sun_dir)


func _get_sun_direction() -> Vector3:
	# Find DirectionalLight3D in the scene for sun direction
	var light := _find_directional_light(get_tree().root)
	if light:
		return -light.global_transform.basis.z
	return Vector3(0.0, -1.0, 0.0)


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
	tex.width = 128
	tex.height = 128
	tex.depth = 128
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
```

- [ ] **Step 2: Commit**

```bash
git add scripts/planet.gd
git commit -m "feat: add planet script with noise texture setup and shader material creation"
```

---

### Task 6: Planet Scene

**Files:**
- Create: `scenes/planet.tscn`

- [ ] **Step 1: Create the planet scene**

Create `scenes/planet.tscn`:

```
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scripts/planet.gd" id="1"]

[sub_resource type="SphereShape3D" id="collision"]
radius = 3.0

[sub_resource type="SphereMesh" id="surface_mesh"]
radius = 3.0
height = 6.0
radial_segments = 128
rings = 64

[sub_resource type="SphereMesh" id="cloud_mesh"]
radius = 3.015
height = 6.03
radial_segments = 64
rings = 32

[sub_resource type="SphereMesh" id="atmo_mesh"]
radius = 3.45
height = 6.9
radial_segments = 32
rings = 16

[node name="Planet" type="AnimatableBody3D"]
script = ExtResource("1")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("collision")

[node name="Surface" type="MeshInstance3D" parent="."]
mesh = SubResource("surface_mesh")

[node name="Clouds" type="MeshInstance3D" parent="."]
mesh = SubResource("cloud_mesh")
visible = false

[node name="Atmosphere" type="MeshInstance3D" parent="."]
mesh = SubResource("atmo_mesh")
visible = false
```

- [ ] **Step 2: Commit**

```bash
git add scenes/planet.tscn
git commit -m "feat: add planet scene with surface, clouds, and atmosphere meshes"
```

---

### Task 7: Example Presets

**Files:**
- Create: `resources/planet_earth.tres`
- Create: `resources/planet_desert.tres`

- [ ] **Step 1: Create earth-like preset**

Create `resources/planet_earth.tres`:

```
[gd_resource type="Resource" script_class="PlanetVisualData" format=3]

[ext_resource type="Script" path="res://scripts/planet_visual_data.gd" id="1"]

[resource]
script = ExtResource("1")
sea_level = 0.45
water_color_shallow = Color(0.3, 0.6, 0.8, 1)
water_color_deep = Color(0.05, 0.1, 0.3, 1)
wave_intensity = 0.3
wave_speed = 0.5
biome_vegetation = 0.6
biome_sand = 0.2
biome_rock = 0.2
color_vegetation = Color(0.2, 0.55, 0.15, 1)
color_sand = Color(0.85, 0.75, 0.45, 1)
color_rock = Color(0.45, 0.42, 0.4, 1)
mountain_intensity = 0.3
snow_level = 0.7
snow_color = Color(0.95, 0.95, 0.98, 1)
cloud_coverage = 0.4
cloud_color = Color(1, 1, 1, 1)
cloud_rotation_speed = 0.05
atmosphere_density = 0.5
atmosphere_color = Color(0.3, 0.5, 1, 1)
atmosphere_radius = 1.15
atmosphere_rayleigh_strength = 1.0
atmosphere_mie_strength = 0.3
atmosphere_steps = 8
cloud_shadows_enabled = false
seed = 42
noise_scale = 2.0
```

- [ ] **Step 2: Create desert planet preset**

Create `resources/planet_desert.tres`:

```
[gd_resource type="Resource" script_class="PlanetVisualData" format=3]

[ext_resource type="Script" path="res://scripts/planet_visual_data.gd" id="1"]

[resource]
script = ExtResource("1")
sea_level = 0.15
water_color_shallow = Color(0.2, 0.4, 0.5, 1)
water_color_deep = Color(0.05, 0.15, 0.25, 1)
wave_intensity = 0.1
wave_speed = 0.3
biome_vegetation = 0.05
biome_sand = 0.8
biome_rock = 0.15
color_vegetation = Color(0.35, 0.45, 0.1, 1)
color_sand = Color(0.9, 0.7, 0.35, 1)
color_rock = Color(0.55, 0.45, 0.35, 1)
mountain_intensity = 0.5
snow_level = 0.95
snow_color = Color(0.95, 0.95, 0.98, 1)
cloud_coverage = 0.1
cloud_color = Color(1, 0.95, 0.85, 1)
cloud_rotation_speed = 0.03
atmosphere_density = 0.3
atmosphere_color = Color(0.8, 0.55, 0.3, 1)
atmosphere_radius = 1.08
atmosphere_rayleigh_strength = 0.5
atmosphere_mie_strength = 0.5
atmosphere_steps = 8
cloud_shadows_enabled = false
seed = 137
noise_scale = 2.5
```

- [ ] **Step 3: Commit**

```bash
git add resources/planet_earth.tres resources/planet_desert.tres
git commit -m "feat: add earth-like and desert planet visual presets"
```

---

### Task 8: Level Integration

**Files:**
- Modify: `scenes/levels/level_01.tscn`

- [ ] **Step 1: Update level_01 to use Planet scenes**

In `scenes/levels/level_01.tscn`, make these exact changes:

Replace the celestial_body ext_resource (line 3 of the file):
```
# OLD:
[ext_resource type="PackedScene" path="res://scenes/celestial_body.tscn" id="2"]
# NEW:
[ext_resource type="PackedScene" path="res://scenes/planet.tscn" id="2"]
```

Add two new ext_resources for visual presets (after existing ext_resources):
```
[ext_resource type="Resource" path="res://resources/planet_earth.tres" id="11_earth"]
[ext_resource type="Resource" path="res://resources/planet_desert.tres" id="12_desert"]
```

Add `visual_data` to both Planet nodes (after existing properties on each):
```
# On the [node name="Planet" ...] block, add:
visual_data = ExtResource("11_earth")

# On the [node name="Planet2" ...] block, add:
visual_data = ExtResource("12_desert")
```

All other properties (transform, body_data, initial_velocity) stay unchanged.

- [ ] **Step 2: Run the game to visually verify planets render correctly**

Run: `cd /var/home/az/Gamedev/orbital-dynamics && godot`

Open Level 01 and verify:
- Both planets show procedural surfaces (land/water with colors)
- Mountains displace vertices visibly
- Clouds appear as a semi-transparent layer
- Atmosphere glows around planet edges
- Planets still move correctly in orbital simulation
- Ship still interacts with planet gravity normally
- Collision still works

- [ ] **Step 3: Commit**

```bash
git add scenes/levels/level_01.tscn
git commit -m "feat: replace CelestialBody with Planet in level_01"
```

---

### Task 9: Visual Polish & Iteration

**Files:**
- Modify: `resources/shaders/planet_surface.gdshader` (potential adjustments)
- Modify: `resources/shaders/planet_atmosphere.gdshader` (potential adjustments)
- Modify: `resources/shaders/planet_clouds.gdshader` (potential adjustments)

- [ ] **Step 1: Run the game and evaluate visual results**

Run the game and evaluate:
1. Are land/water boundaries sharp enough for the stylized look?
2. Is vertex displacement visible from the camera height?
3. Is the atmosphere glow visible and convincing?
4. Do cloud shadows work if enabled?
5. Are wave animations subtle enough?

- [ ] **Step 2: Adjust shader parameters based on visual testing**

Tweak default uniform values, smoothstep margins, displacement scale, atmosphere step count, etc. based on what looks good at the game's camera distance (~60 units above).

Common adjustments:
- `max_displacement` in surface shader may need scaling relative to planet radius
- `scale_height` in atmosphere shader may need tuning
- Smoothstep margins in biome boundaries may need widening/narrowing
- Noise frequency for wave animation may need adjustment

- [ ] **Step 3: Run all tests**

Run: `cd /var/home/az/Gamedev/orbital-dynamics && godot --headless --script tests/test_planet_visual_data.gd && godot --headless --script tests/test_celestial_sim.gd`

Expected: Both test suites pass.

- [ ] **Step 4: Commit final adjustments**

```bash
git add -A
git commit -m "chore: tune planet shader parameters for visual polish"
```
