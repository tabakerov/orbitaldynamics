shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float distortion : hint_range(0.0, 0.15) = 0.03;
uniform float horizon_size : hint_range(0.0, 0.4) = 0.08;
uniform float ring_size : hint_range(0.0, 0.4) = 0.12;
uniform vec4 ring_color : source_color = vec4(1.0, 0.4, 0.05, 1.0);
uniform float ring_intensity : hint_range(0.0, 10.0) = 3.0;
uniform float edge_fade_start : hint_range(0.2, 0.5) = 0.45;

void fragment() {
	vec2 center_offset = UV - vec2(0.5);
	float dist = length(center_offset);
	vec2 dir = center_offset / max(dist, 0.0001);

	// Fade at mesh edges
	float fade = smoothstep(0.5, edge_fade_start, dist);

	// Gravitational lensing — push apparent positions outward
	float warp = distortion / (dist * dist + 0.005);
	vec2 warp_offset = dir * warp * fade;

	// Chromatic aberration near the center
	float aberration = warp * 0.25;
	vec3 col;
	col.r = textureLod(screen_texture, SCREEN_UV + dir * (warp + aberration) * fade, 0.0).r;
	col.g = textureLod(screen_texture, SCREEN_UV + warp_offset, 0.0).g;
	col.b = textureLod(screen_texture, SCREEN_UV + dir * (warp - aberration) * fade, 0.0).b;

	// Event horizon — dark center
	float horizon = smoothstep(horizon_size + 0.02, horizon_size, dist);
	col *= 1.0 - horizon;

	// Accretion ring glow
	float ring_dist = abs(dist - ring_size);
	float ring = exp(-ring_dist * ring_dist / 0.001) * (1.0 - horizon);
	col += ring_color.rgb * ring * ring_intensity;

	// Subtle darkening toward center (gravity dimming)
	float dimming = smoothstep(horizon_size, 0.35, dist);
	col *= mix(0.6, 1.0, dimming);

	ALBEDO = col;
	ALPHA = fade;
}
