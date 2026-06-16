shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec2 light_uv = vec2(0.5, 0.38);
uniform float radius_px = 520.0;
uniform float softness_px = 260.0;
uniform float dim_alpha = 0.78;

void fragment() {
	vec2 pixel = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 center = light_uv / SCREEN_PIXEL_SIZE;
	float dist = distance(pixel, center);
	float fade = smoothstep(radius_px, radius_px + softness_px, dist);
	COLOR = vec4(0.0, 0.0, 0.0, fade * dim_alpha);
}
