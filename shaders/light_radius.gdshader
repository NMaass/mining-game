shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 light_uv = vec2(0.5, 0.38);
uniform float radius_px = 520.0;
uniform float softness_px = 260.0;
uniform float dim_alpha = 0.78;
// Cool deep-terrain cast the headlamp mask fades TOWARD (instead of pure black) so the
// unlit mine reads as atmospheric blue-violet, not muddy black. Data-driven from
// balance.light_dark_tint (see mine.gd _wire_world_guides). Default keeps the old pure
// black so an unconfigured material is harmless. RGB only; the mask alpha is the vignette.
uniform vec4 dark_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 center = light_uv / SCREEN_PIXEL_SIZE;
	float dist = distance(pixel, center);
	float fade = smoothstep(radius_px, radius_px + softness_px, dist);
	COLOR = vec4(dark_tint.rgb, fade * dim_alpha);
}
