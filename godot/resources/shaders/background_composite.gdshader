shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_disabled;

// Paints the background SubViewport's frame across the whole screen at the
// far plane, behind all gameplay geometry (see BackgroundLayer).

uniform sampler2D background_texture : source_color, filter_linear;
// Clip-space Z of the far plane. All renderers are reversed-Z since 4.6,
// but clip conventions differ: ~0 on Forward+/Mobile (Vulkan, z in [0,1]),
// ~-1 on gl_compatibility (GL, z in [-1,1]). Set by BackgroundLayer.
uniform float far_clip_z = 0.000001;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, far_clip_z, 1.0);
}

void fragment() {
	ALBEDO = texture(background_texture, SCREEN_UV).rgb;
}
