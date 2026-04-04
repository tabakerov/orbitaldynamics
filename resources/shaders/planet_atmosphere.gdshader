shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never;

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

void fragment() {
	// Ray in model space (sphere centered at origin)
	vec3 ro = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 frag_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 rd = normalize((inverse(MODEL_MATRIX) * vec4(normalize(frag_world - CAMERA_POSITION_WORLD), 0.0)).xyz);

	// Find full atmosphere intersection
	vec2 atmo_hit = ray_sphere(ro, rd, atmosphere_radius);

	vec3 scattered = vec3(0.0);
	float optical_depth = 0.0;

	if (atmo_hit.y > 0.0) {
		float ray_start = max(atmo_hit.x, 0.0);
		float ray_end = atmo_hit.y;

		// Planet body occlusion
		vec2 planet_hit = ray_sphere(ro, rd, planet_radius);
		if (planet_hit.x > 0.0) {
			ray_end = min(ray_end, planet_hit.x);
		}

		vec3 light_dir = normalize((inverse(MODEL_MATRIX) * vec4(sun_direction, 0.0)).xyz);
		float cos_theta = dot(rd, light_dir);

		float step_size = (ray_end - ray_start) / float(atmosphere_steps);
		float scale_height = (atmosphere_radius - planet_radius) * 0.35;

		for (int i = 0; i < atmosphere_steps; i++) {
			float t = ray_start + (float(i) + 0.5) * step_size;
			vec3 sample_point = ro + rd * t;
			float altitude = length(sample_point) - planet_radius;
			float normalized_alt = altitude / (atmosphere_radius - planet_radius);
			float density = exp(-altitude / scale_height) * step_size;

			// Planet self-shadow
			vec2 shadow_hit = ray_sphere(sample_point, light_dir, planet_radius);
			float shadow = (shadow_hit.x > 0.0) ? 0.0 : 1.0;

			// Cloud shadow (optional)
			if (cloud_shadows_enabled && shadow > 0.0 && cloud_coverage > 0.0) {
				vec2 cloud_hit = ray_sphere(sample_point, light_dir, cloud_shell_radius);
				if (cloud_hit.x > 0.0) {
					vec3 cloud_point = sample_point + light_dir * cloud_hit.x;
					vec3 cloud_uv = normalize(cloud_point) * cloud_noise_scale * 0.8 * 0.5 + 0.5;
					float cn = texture(cloud_noise, cloud_uv).r;
					float cloud_threshold = 1.0 - cloud_coverage;
					float cloud_shadow = smoothstep(cloud_threshold - 0.05, cloud_threshold + 0.05, cn);
					shadow *= (1.0 - cloud_shadow * 0.7);
				}
			}

			optical_depth += density;
			float rayleigh = rayleigh_phase(cos_theta) * rayleigh_strength;
			float mie = mie_phase(cos_theta, 0.76) * mie_strength;
			scattered += density * shadow * (atmosphere_color * rayleigh + vec3(mie));
		}
	}

	float alpha = 1.0 - exp(-optical_depth * atmosphere_density * 4.0);
	ALBEDO = scattered / max(optical_depth * atmosphere_density, 0.001);
	ALPHA = alpha;
}
