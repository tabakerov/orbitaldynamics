shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled;

// Paints the background SubViewport's frame across the whole screen at the
// far plane, behind all gameplay geometry (see BackgroundLayer).

uniform sampler2D background_texture : source_color, filter_linear;
// Clip-space Z of the far plane: ~0 on reversed-Z renderers
// (Forward+/Mobile), ~1 on gl_compatibility. Set by BackgroundLayer.
uniform float far_clip_z = 0.000001;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, far_clip_z, 1.0);
}

void fragment() {
	ALBEDO = texture(background_texture, SCREEN_UV).rgb;
}
