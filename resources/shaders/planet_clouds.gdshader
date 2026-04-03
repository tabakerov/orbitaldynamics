shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler3D cloud_noise;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.4;
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float noise_scale = 2.0;

varying vec3 v_model_pos;

void vertex() {
	v_model_pos = normalize(VERTEX);
}

void fragment() {
	vec3 sample_pos = v_model_pos * noise_scale * 0.8 * 0.5 + 0.5;
	float n = texture(cloud_noise, sample_pos).r;

	float threshold = 1.0 - cloud_coverage;
	float cloud_mask = smoothstep(threshold - 0.05, threshold + 0.05, n);

	ALBEDO = cloud_color;
	ALPHA = cloud_mask * 0.9;

	if (ALPHA < 0.01) {
		discard;
	}
}
