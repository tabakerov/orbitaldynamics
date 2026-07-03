shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float distortion : hint_range(0.0, 0.15) = 0.03;
uniform float edge_fade_start : hint_range(0.2, 0.5) = 0.45;
uniform float distortion_falloff_start : hint_range(0.0, 0.5) = 0.18;
uniform float chromatic_aberration : hint_range(0.0, 1.0) = 0.25;

// The event horizon (dark center) and accretion ring (orange glow) are no
// longer drawn here — see BlackHole's horizon/ring GPUParticles3D systems.
void fragment() {
	vec2 center_offset = UV - vec2(0.5);
	float dist = length(center_offset);
	vec2 dir = center_offset / max(dist, 0.0001);

	// Fade at mesh edges
	float fade = smoothstep(0.5, edge_fade_start, dist);

	// Gravitational lensing — push apparent positions outward
	float warp = distortion / (dist * dist + 0.005);
	float warp_fade = 1.0 - smoothstep(distortion_falloff_start, edge_fade_start, dist);
	warp *= warp_fade;
	vec2 warp_offset = dir * warp * fade;

	// Chromatic aberration is strongest near the center and fades toward the lens edge.
	float aberration_fade = 1.0 - smoothstep(0.0, edge_fade_start, dist);
	float aberration = warp * chromatic_aberration * aberration_fade;
	vec3 col;
	col.r = textureLod(screen_texture, SCREEN_UV + dir * (warp + aberration) * fade, 0.0).r;
	col.g = textureLod(screen_texture, SCREEN_UV + warp_offset, 0.0).g;
	col.b = textureLod(screen_texture, SCREEN_UV + dir * (warp - aberration) * fade, 0.0).b;

	ALBEDO = col;
	ALPHA = fade;
}
