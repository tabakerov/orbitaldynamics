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
@export_range(0.0, 5.0) var wave_speed: float = 0.5

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

## Cloud layer height above surface (multiplier of planet radius).
@export_range(1.001, 1.05) var cloud_height: float = 1.005

## Independent rotation speed for cloud layer (rad/s).
@export_range(0.0, 1.0) var cloud_rotation_speed: float = 0.05

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

## --- Ambient Occlusion ---

## Strength of height-based ambient occlusion. 0 = off.
@export_range(0.0, 1.0) var ao_strength: float = 0.4

## --- Generation ---

## Seed for procedural generation. Different seeds = different continents.
@export var seed: int = 0

## Noise frequency — controls feature size on the surface.
@export_range(0.5, 8.0) var noise_scale: float = 2.0
