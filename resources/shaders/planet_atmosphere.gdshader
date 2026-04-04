shader_type spatial;
render_mode blend_mix, unshaded, cull_front, depth_draw_never;

uniform float planet_radius = 1.0;
uniform float atmosphere_radius = 1.15;
uniform float atmosphere_density : hint_range(0.0, 1.0) = 0.5;
uniform vec3 atmosphere_color : source_color = vec3(0.3, 0.5, 1.0);
uniform float rayleigh_strength : hint_range(0.0, 5.0) = 1.0;
uniform float mie_strength : hint_range(0.0, 2.0) = 0.3;
uniform int atmosphere_steps : hint_range(4, 16) = 8;
uniform vec3 sun_direction = vec3(0.0, -1.0, 0.0);

// Volumetric clouds (integrated into ray-march)
uniform sampler3D cloud_noise;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float cloud_noise_scale = 2.0;
uniform float cloud_shell_radius = 1.005;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float cloud_thickness = 0.02;

varying vec3 v_model_pos;

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

float rayleigh_phase(float cos_theta) {
	return 0.75 * (1.0 + cos_theta * cos_theta);
}

float mie_phase(float cos_theta, float g) {
	float g2 = g * g;
	float denom = 1.0 + g2 - 2.0 * g * cos_theta;
	return (1.0 - g2) / (4.0 * PI * pow(denom, 1.5));
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

	if (atmo_hit.y > 0.0) {
		float ray_start = max(atmo_hit.x, 0.0);
		float ray_end = atmo_hit.y;

		vec2 planet_hit = ray_sphere(ro, rd, planet_radius);
		if (planet_hit.x > 0.0) {
			ray_end = min(ray_end, planet_hit.x);
		}

		vec3 light_dir = normalize((inverse(MODEL_MATRIX) * vec4(sun_direction, 0.0)).xyz);
		float cos_theta = dot(rd, light_dir);
		float step_size = (ray_end - ray_start) / float(atmosphere_steps);
		float scale_height = (atmosphere_radius - planet_radius) * 0.35;
		float atmo_thickness = atmosphere_radius - planet_radius;

		for (int i = 0; i < atmosphere_steps; i++) {
			if (transmittance < 0.01) break;

			float t = ray_start + (float(i) + 0.5) * step_size;
			vec3 sample_point = ro + rd * t;
			float altitude = length(sample_point) - planet_radius;

			// --- Atmosphere density (exponential falloff) ---
			float atmo_dens = exp(-altitude / scale_height) * atmosphere_density;

			// --- Cloud density (at cloud shell altitude) ---
			float cloud_dens = 0.0;
			if (cloud_coverage > 0.0) {
				float cloud_alt = cloud_shell_radius - planet_radius;
				float proximity = 1.0 - clamp(abs(altitude - cloud_alt) / max(cloud_thickness * atmo_thickness, 0.001), 0.0, 1.0);
				if (proximity > 0.0) {
					vec3 cloud_uv = normalize(sample_point) * cloud_noise_scale * 0.8 * 0.5 + 0.5;
					float cn = texture(cloud_noise, cloud_uv).r;
					float threshold = 1.0 - cloud_coverage;
					cloud_dens = smoothstep(threshold - 0.05, threshold + 0.05, cn) * proximity;
				}
			}

			// --- Shadow ---
			vec2 shadow_hit = ray_sphere(sample_point, light_dir, planet_radius);
			float shadow = (shadow_hit.x > 0.0) ? 0.0 : 1.0;

			// --- Scattering (atmosphere + clouds) ---
			float rayleigh = rayleigh_phase(cos_theta) * rayleigh_strength;
			float mie = mie_phase(cos_theta, 0.76) * mie_strength;

			vec3 atmo_scatter = (atmosphere_color * rayleigh + vec3(mie)) * atmo_dens;
			vec3 cloud_scatter = cloud_color * cloud_dens * (0.5 + 0.5 * shadow);

			vec3 in_scatter = (atmo_scatter * shadow + cloud_scatter) * step_size;
			accumulated_light += in_scatter * transmittance;

			// --- Extinction (Beer-Lambert) ---
			float extinction = (atmo_dens * 3.0 + cloud_dens * 8.0) * step_size;
			transmittance *= exp(-extinction);
		}
	}

	float alpha = 1.0 - transmittance;
	ALBEDO = alpha > 0.001 ? accumulated_light / alpha : vec3(0.0);
	ALPHA = alpha;
}
