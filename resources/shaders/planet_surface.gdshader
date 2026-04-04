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

// Atmospheric haze on surface
uniform float atmosphere_haze_density : hint_range(0.0, 1.0) = 0.0;
uniform vec3 atmosphere_haze_color : source_color = vec3(0.3, 0.5, 1.0);

// Noise sampling
uniform float noise_scale = 2.0;

varying float v_height;
varying float v_noise;
varying vec3 v_model_pos;

void vertex() {
	vec3 unit_pos = normalize(VERTEX);
	v_model_pos = unit_pos;
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
		vec3 wave_sample = v_model_pos * noise_scale * 3.0 * 0.5 + 0.5;
		wave_sample.x += TIME * wave_speed * 0.1;
		wave_sample.z += TIME * wave_speed * 0.07;
		float wave = texture(terrain_noise, wave_sample).r;
		col += vec3(wave * 0.1 * wave_intensity);

		// Slight specular for water
		SPECULAR = 0.5;
		ROUGHNESS = 0.2;
	} else {
		// Land — biome selection
		vec3 biome_sample = v_model_pos * noise_scale * 0.7 * 0.5 + 0.5;
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

	// Atmospheric haze — Fresnel: edges get more tinted by atmosphere
	if (atmosphere_haze_density > 0.0) {
		float fresnel = 1.0 - max(dot(NORMAL, VIEW), 0.0);
		float haze = pow(fresnel, 3.0) * atmosphere_haze_density;
		col = mix(col, atmosphere_haze_color, haze);
	}

	ALBEDO = col;
}
