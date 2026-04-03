# Procedural Planet Shader Design

## Overview

Configurable procedural shader system for planets that generates stylized surfaces with multiple biomes, vertex-displaced mountains, animated water, volumetric clouds, and ray-marched atmospheric scattering with self-shadowing.

## Architecture: Three-Mesh Approach

Each planet consists of three layered meshes under a single Node3D that extends CelestialBody:

```
Planet (Node3D, planet.gd — extends CelestialBody)
├── Surface    (MeshInstance3D, SphereMesh subdivide_depth=64)
│   → planet_surface.gdshader
├── Clouds     (MeshInstance3D, SphereMesh radius +0.5%)
│   → planet_clouds.gdshader
├── Atmosphere (MeshInstance3D, SphereMesh radius × atmosphere_radius)
│   → planet_atmosphere.gdshader
└── CollisionShape3D (SphereShape3D)
```

**Why three meshes:**
- Atmosphere needs blend_add + cull_front + unshaded — incompatible with surface lighting
- Clouds rotate independently from the planet surface
- Each shader stays focused and maintainable
- Layers can be toggled on/off (e.g. no atmosphere for a moon)

## Visual Style

Stylized/low-poly: clean colors, sharp boundaries between land and water (step/smoothstep transitions), no photorealistic textures.

## Parameters: PlanetVisualData Resource

A `Resource` subclass (like the existing `CelestialBodyData`) holding all visual parameters. The `planet.gd` script reads this resource and sets shader uniforms on all three materials.

### Terrain & Water

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `sea_level` | float | 0.0–1.0 | Noise threshold: below = water, above = land. 0.3 means ~70% water |
| `water_color_shallow` | Color | — | Shallow water near coastlines |
| `water_color_deep` | Color | — | Deep ocean color |
| `wave_intensity` | float | 0.0–1.0 | Amplitude of animated waves |
| `wave_speed` | float | — | Wave animation speed |

### Biomes

Three biome types whose proportions are controlled by normalized weights. A second noise layer (different frequency/seed) generates the biome map. Boundaries use step/smoothstep for a stylized look.

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `biome_vegetation` | float | 0.0–1.0 | Weight of vegetation zones |
| `biome_sand` | float | 0.0–1.0 | Weight of desert/sand zones |
| `biome_rock` | float | 0.0–1.0 | Weight of rocky zones |
| `color_vegetation` | Color | — | Vegetation color (default: green) |
| `color_sand` | Color | — | Sand color (default: yellow) |
| `color_rock` | Color | — | Rock color (default: grey) |

Weights are normalized in the shader: `v / (v + s + r)`.

### Mountains & Snow

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `mountain_intensity` | float | 0.0–1.0 | Vertex displacement magnitude for mountains |
| `snow_level` | float | 0.0–1.0 | Height threshold for snow caps. 0 = no snow |
| `snow_color` | Color | — | Snow color (default: white) |

### Clouds

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `cloud_coverage` | float | 0.0–1.0 | Cloud density. 0 = clear sky |
| `cloud_color` | Color | — | Cloud color (default: white) |
| `cloud_rotation_speed` | float | — | Independent rotation speed for cloud layer |

### Atmosphere

| Parameter | Type | Range | Description |
|-----------|------|-------|-------------|
| `atmosphere_density` | float | 0.0–1.0 | Optical depth multiplier |
| `atmosphere_color` | Color | — | Rayleigh scattering color (blue for Earth-like) |
| `atmosphere_radius` | float | 1.05–1.3 | Atmosphere shell radius relative to planet |
| `atmosphere_rayleigh_strength` | float | 0.0–5.0 | Wavelength-dependent scattering strength |
| `atmosphere_mie_strength` | float | 0.0–2.0 | Forward scattering (halo around sun) |
| `atmosphere_steps` | int | 4–16 | Ray-march step count (quality vs performance) |
| `cloud_shadows_enabled` | bool | — | Enable cloud shadow sampling in atmosphere |

### Generation

| Parameter | Type | Description |
|-----------|------|-------------|
| `seed` | int | Generation seed — determines continent shapes, mountains, clouds |
| `noise_scale` | float | Noise frequency — controls feature size on the surface |

## Shader 1: planet_surface.gdshader

**Type:** `shader_type spatial;` (standard Godot lighting pipeline)

### Noise Strategy

Use `NoiseTexture3D` with `FastNoiseLite` as a uniform sampler. Two instances per planet:
- **Terrain noise** — determines land/water and height
- **Biome noise** — determines biome zones (different frequency)

Sampling by `VERTEX` (model space) ensures the texture is fixed to the mesh surface and rotates with it.

Seed is set on the `FastNoiseLite` resource — no positional offset needed. Different seeds produce entirely different noise patterns.

### Vertex Shader

```
1. Sample terrain noise at VERTEX (model space position)
2. If noise > sea_level:
   - Land: displace vertex outward along normal by (noise - sea_level) * mountain_intensity
3. If noise <= sea_level:
   - Water: vertex stays at base radius
4. Pass noise value and displacement height to fragment via varying
```

### Fragment Shader

**Water** (noise <= sea_level):
- Proximity to coastline: `smoothstep(sea_level - margin, sea_level, noise)`
- Color: `mix(water_color_deep, water_color_shallow, proximity)`
- Animated waves: secondary noise sampled with TIME offset, adds subtle color/normal variation

**Land biome selection** (noise > sea_level):
- Sample biome noise at world position
- Normalize weights: `v_norm = biome_vegetation / (biome_vegetation + biome_sand + biome_rock)`, same for sand and rock
- Map biome noise value to biome type using cumulative thresholds with step transitions
- Apply corresponding biome color

**Mountains:** Where displacement height exceeds a threshold, blend toward `color_rock` regardless of biome.

**Snow:** Where displacement height > `snow_level`, color = `snow_color`. Sharp step boundary.

**Lighting:** Standard Godot pipeline — DIFFUSE_LIGHT and SPECULAR_LIGHT from scene lights. Future: sun object will provide directional light.

## Shader 2: planet_clouds.gdshader

**Type:** `shader_type spatial; render_mode blend_mix, cull_back, depth_draw_opaque;`

### Algorithm

1. Sample the same `NoiseTexture3D` at world position with a different seed/frequency offset
2. Threshold: `cloud_value = noise > (1.0 - cloud_coverage) ? 1.0 : 0.0`
3. `ALPHA = smoothstep` around the threshold for soft cloud edges
4. `ALBEDO = cloud_color`
5. Standard lighting applies — clouds have light/shadow from scene lights

### Rotation

Cloud mesh rotates independently via `planet.gd` script: `clouds_mesh.rotate_y(cloud_rotation_speed * delta)` in `_process`.

## Shader 3: planet_atmosphere.gdshader

**Type:** `shader_type spatial; render_mode blend_add, unshaded, cull_front;`

### Ray-Marching Atmospheric Scattering

`cull_front` renders the inside faces of the atmosphere sphere, making it visible as a glow shell when viewed from outside.

For each fragment:

1. **Ray setup:** Camera ray enters atmosphere sphere. Compute entry and exit points via ray-sphere intersection (analytical, outer radius).
2. **Planet occlusion:** Also compute ray-sphere intersection with inner sphere (planet radius). If hit, the ray ends at the planet surface instead of the far atmosphere boundary.
3. **March** 8–16 steps along the ray segment:
   - At each sample point, compute density from altitude: `density = exp(-altitude / scale_height)`
   - Cast a secondary ray toward the sun (light direction)
   - **Planet shadow:** ray-sphere test with planet body. If intersects, `in_scatter = 0` for this sample (point is in planet's shadow)
   - **Cloud shadow** (optional, `cloud_shadows_enabled`): sample cloud noise at the intersection of the sun-ray with the cloud shell sphere. If cloud present, reduce `in_scatter` proportionally
   - Accumulate `optical_depth` and `scattered_light` using Rayleigh phase function
   - Mie scattering: forward-scattering lobe using Henyey-Greenstein phase function
4. **Output:** `ALBEDO = accumulated_color`, `ALPHA = saturate(optical_depth * atmosphere_density)`

### Light Direction

Currently uses Godot's scene DirectionalLight3D direction. Designed to be swapped to a sun object's position in the future (passed as a uniform `vec3 sun_direction` from `planet.gd`).

## Script: planet.gd

Extends `CelestialBody` (inherits gravity registration, simulation-driven position, stationary flag).

### Responsibilities

- **@export var visual_data: PlanetVisualData** — the resource holding all visual parameters
- **_ready():** Create `ShaderMaterial` instances for each mesh, generate `NoiseTexture3D` resources with seed from `visual_data`, set all uniforms
- **_process(delta):** Rotate cloud mesh by `cloud_rotation_speed * delta`
- **Uniform sync:** When `visual_data` changes in editor, update shader uniforms (tool script or `_validate_property`)

### Noise Texture Setup

```
var terrain_noise = FastNoiseLite.new()
terrain_noise.seed = visual_data.seed
terrain_noise.frequency = 1.0 / visual_data.noise_scale

var biome_noise = FastNoiseLite.new()
biome_noise.seed = visual_data.seed + 1000
biome_noise.frequency = 2.0 / visual_data.noise_scale  # higher frequency for biome zones

# Wrap in NoiseTexture3D for shader sampling
var terrain_tex = NoiseTexture3D.new()
terrain_tex.noise = terrain_noise
# ... set to shader uniform
```

## Performance Considerations

- **Surface mesh:** SphereMesh subdivide_depth=64 yields ~8K vertices — adequate for visible displacement from 60 units above
- **Atmosphere ray-march:** 8 steps default. Atmosphere occupies a small screen area in top-down view. Analytical ray-sphere tests (no loops within the loop)
- **Cloud shadows:** Optional, +1 texture sample per ray-march step. Toggleable via `cloud_shadows_enabled`
- **Draw calls:** 3 per planet. With 2-3 planets per level, this is 6-9 draw calls — negligible
- **NoiseTexture3D:** GPU-sampled, faster than computing noise mathematically in shader

## Integration with Existing Systems

- `Planet` scene replaces `CelestialBody` scene for planets (black holes remain separate)
- `CelestialBodyData` still handles physics (mass, gravity_strength, etc.)
- `PlanetVisualData` is a separate resource for visuals only
- Both resources are exported properties on `planet.gd`
- `CelestialSim` sees Planet as a regular celestial body — no changes needed
