shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never;

// Atmosphere
uniform float planet_radius = 1.0;
uniform float atmosphere_radius = 1.15;
uniform float atmosphere_density : hint_range(0.0, 1.0) = 0.5;
uniform vec3 atmosphere_color : source_color = vec3(0.3, 0.5, 1.0);
uniform float rayleigh_strength : hint_range(0.0, 5.0) = 1.0;
uniform float mie_strength : hint_range(0.0, 2.0) = 0.3;
uniform float atmosphere_falloff : hint_range(0.05, 1.0) = 0.35;
uniform int atmosphere_steps : hint_range(4, 128) = 8;
uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0);

// Clouds
uniform sampler3D cloud_noise;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_noise_scale = 2.0;
uniform float cloud_lower_radius = 1.003;
uniform float cloud_upper_radius = 1.02;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);

// Surface
uniform sampler3D terrain_noise;
uniform sampler3D biome_noise;
uniform float sea_level : hint_range(0.0, 1.0) = 0.4;
uniform vec3 water_color_shallow : source_color = vec3(0.3, 0.6, 0.8);
uniform vec3 water_color_deep : source_color = vec3(0.05, 0.1, 0.3);
uniform float wave_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float wave_speed = 0.5;
uniform float biome_vegetation : hint_range(0.0, 1.0) = 0.5;
uniform float biome_sand : hint_range(0.0, 1.0) = 0.3;
uniform float biome_rock : hint_range(0.0, 1.0) = 0.2;
uniform vec3 color_vegetation : source_color = vec3(0.2, 0.55, 0.15);
uniform vec3 color_sand : source_color = vec3(0.85, 0.75, 0.45);
uniform vec3 color_rock : source_color = vec3(0.45, 0.42, 0.4);
uniform float mountain_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float mountain_noise_scale : hint_range(0.5, 16.0) = 4.0;
uniform float snow_level : hint_range(0.0, 1.0) = 0.7;
uniform vec3 snow_color : source_color = vec3(0.95, 0.95, 0.98);
uniform float noise_scale = 2.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.4;

varying vec3 v_model_pos;

vec2 ray_sphere(vec3 ro, vec3 rd, float radius) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - radius * radius;
	float discriminant = b * b - c;
	if (discriminant < 0.0) return vec2(-1.0);
	float sq = sqrt(discriminant);
	return vec2(-b - sq, -b + sq);
}

float rayleigh_phase(float cos_theta) {
	return 0.75 * (1.0 + cos_theta * cos_theta);
}

float mie_phase(float cos_theta, float g) {
	float g2 = g * g;
	float denom = 1.0 + g2 - 2.0 * g * cos_theta;
	return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
}

vec3 compute_surface(vec3 hit_point, vec3 light_dir) {
	vec3 unit = normalize(hit_point);
	vec3 sample_pos = unit * noise_scale * 0.5 + 0.5;
	float n = texture(terrain_noise, sample_pos).r;

	vec3 col;

	if (n <= sea_level) {
		float coast_proximity = smoothstep(sea_level - 0.08, sea_level, n);
		col = mix(water_color_deep, water_color_shallow, coast_proximity);
		// Waves
		vec3 wave_sample = unit * noise_scale * 3.0 * 0.5 + 0.5;
		wave_sample.x += TIME * wave_speed * 0.1;
		wave_sample.z += TIME * wave_speed * 0.07;
		float wave = texture(terrain_noise, wave_sample).r;
		col += vec3(wave * 0.1 * wave_intensity);
	} else {
		float land_height = (n - sea_level) / (1.0 - sea_level);
		// Mountain detail
		float mtn_detail = texture(terrain_noise, unit * mountain_noise_scale * 0.5 + 0.5).r;
		float height = land_height * (0.6 + 0.4 * mtn_detail);

		// Biome selection
		float bn = texture(biome_noise, unit * noise_scale * 0.7 * 0.5 + 0.5).r;
		float total_weight = biome_vegetation + biome_sand + biome_rock;
		float w_veg = biome_vegetation / max(total_weight, 0.001);
		float w_sand = biome_sand / max(total_weight, 0.001);

		if (bn < w_veg) {
			col = color_vegetation;
		} else if (bn < w_veg + w_sand) {
			col = color_sand;
		} else {
			col = color_rock;
		}

		// Mountains → rock
		col = mix(col, color_rock, smoothstep(0.5, 0.8, height));
		// Snow
		col = mix(col, snow_color, step(snow_level, height));

		// AO: broad vs local height
		float n_broad = texture(terrain_noise, unit * noise_scale * 0.25 + 0.5).r;
		float ao = clamp(0.5 + (n - n_broad) * 2.0, 0.0, 1.0);
		float coastal_ao = smoothstep(0.0, 0.15, land_height);
		ao *= mix(1.0 - ao_strength * 0.5, 1.0, coastal_ao);
		col *= mix(1.0, ao, ao_strength);
	}

	// Compute normal from noise gradient for lighting
	float eps = 0.002;
	float h_c = texture(terrain_noise, unit * noise_scale * 0.5 + 0.5).r;
	vec3 tangent = normalize(cross(unit, vec3(0.0, 1.0, 0.001)));
	vec3 bitangent = normalize(cross(unit, tangent));
	float h_t = texture(terrain_noise, normalize(hit_point + tangent * eps) * noise_scale * 0.5 + 0.5).r;
	float h_b = texture(terrain_noise, normalize(hit_point + bitangent * eps) * noise_scale * 0.5 + 0.5).r;
	vec3 surface_normal = normalize(unit + (h_c - h_t) * tangent * mountain_intensity * 8.0
	                                     + (h_c - h_b) * bitangent * mountain_intensity * 8.0);

	// Lighting
	float ndotl = max(dot(surface_normal, light_dir), 0.0);
	col *= 0.12 + 0.88 * ndotl;

	return col;
}

void vertex() {
	v_model_pos = VERTEX;
}

void fragment() {
	vec3 ro = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 rd = normalize(v_model_pos - ro);

	vec2 atmo_hit = ray_sphere(ro, rd, atmosphere_radius);

	vec3 accumulated_light = vec3(0.0);
	float transmittance = 1.0;

	vec2 planet_hit = ray_sphere(ro, rd, planet_radius);

	if (atmo_hit.y > 0.0) {
		float ray_start = max(atmo_hit.x, 0.0);
		float ray_end = atmo_hit.y;

		if (planet_hit.x > 0.0) {
			ray_end = min(ray_end, planet_hit.x);
		}

		vec3 light_dir = normalize((inverse(MODEL_MATRIX) * vec4(sun_direction, 0.0)).xyz);
		float cos_theta = dot(rd, light_dir);
		float step_size = (ray_end - ray_start) / float(atmosphere_steps);
		float scale_height = (atmosphere_radius - planet_radius) * atmosphere_falloff;

		for (int i = 0; i < atmosphere_steps; i++) {
			if (transmittance < 0.01) break;

			float t = ray_start + (float(i) + 0.5) * step_size;
			vec3 sample_point = ro + rd * t;
			float altitude = length(sample_point) - planet_radius;

			// Atmosphere density
			float atmo_dens = exp(-altitude / scale_height) * atmosphere_density;

			// Cloud density
			float cloud_dens = 0.0;
			if (cloud_coverage > 0.0) {
				float sample_r = length(sample_point);
				if (sample_r >= cloud_lower_radius && sample_r <= cloud_upper_radius) {
					float cloud_band = cloud_upper_radius - cloud_lower_radius;
					float band_pos = (sample_r - cloud_lower_radius) / max(cloud_band, 0.001);
					float edge_fade = smoothstep(0.0, 0.2, band_pos) * smoothstep(1.0, 0.8, band_pos);
					vec3 cloud_uv = normalize(sample_point) * cloud_noise_scale * 0.8 * 0.5 + 0.5;
					float cn = texture(cloud_noise, cloud_uv).r;
					cloud_dens = smoothstep(1.0 - cloud_coverage - 0.05, 1.0 - cloud_coverage + 0.05, cn) * edge_fade;
				}
			}

			// Shadow
			vec2 shadow_hit = ray_sphere(sample_point, light_dir, planet_radius);
			float shadow = (shadow_hit.x > 0.0) ? 0.0 : 1.0;

			// Scattering
			float rayleigh = rayleigh_phase(cos_theta) * rayleigh_strength;
			float mie = mie_phase(cos_theta, 0.76) * mie_strength;
			vec3 atmo_scatter = (atmosphere_color * rayleigh + vec3(mie)) * atmo_dens;
			vec3 cloud_scatter = cloud_color * cloud_dens * (0.5 + 0.5 * shadow);
			accumulated_light += (atmo_scatter * shadow + cloud_scatter) * step_size * transmittance;

			// Extinction
			float extinction = (atmo_dens * 3.0 + cloud_dens * 8.0) * step_size;
			transmittance *= exp(-extinction);
		}

		// Surface rendering at ray-planet intersection
		if (planet_hit.x > 0.0 && transmittance > 0.01) {
			vec3 hit = ro + rd * planet_hit.x;
			vec3 light_dir2 = normalize((inverse(MODEL_MATRIX) * vec4(sun_direction, 0.0)).xyz);
			vec3 surface_col = compute_surface(hit, light_dir2);
			accumulated_light += surface_col * transmittance;
			transmittance = 0.0;
		}
	}

	float alpha = 1.0 - transmittance;
	ALBEDO = alpha > 0.001 ? accumulated_light / alpha : vec3(0.0);
	ALPHA = alpha;
}
