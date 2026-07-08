shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.1098, 0.1020, 0.1765, 1.0);
uniform vec4 accent_color : source_color = vec4(0.4392, 0.3569, 0.8706, 1.0);
uniform vec4 line_color : source_color = vec4(0.5333, 0.4706, 0.9608, 1.0);

uniform float center_glow_strength : hint_range(0.0, 2.0) = 0.42;
uniform float line_strength : hint_range(0.0, 2.0) = 0.75;
uniform float ring_strength : hint_range(0.0, 2.0) = 0.34;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.12;
uniform float emission_strength : hint_range(0.0, 3.0) = 0.7;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise(p) * amp;
		p = p * 2.0 + vec2(4.3, -3.7);
		amp *= 0.5;
	}
	return value;
}

float band(float value, float center, float width, float softness) {
	float dist = abs(value - center);
	return 1.0 - smoothstep(width, width + softness, dist);
}

void fragment() {
	vec2 uv = UV;
	vec2 stage_uv = uv * 2.0 - 1.0;

	vec3 base = base_color.rgb;
	vec3 accent = accent_color.rgb;
	vec3 line = line_color.rgb;

	float near_to_far = 1.0 - uv.y;
	float center_mask = clamp(1.0 - abs(stage_uv.x), 0.0, 1.0);

	float center_glow = pow(center_mask, 2.2) * smoothstep(0.0, 0.82, near_to_far);
	float runway = center_glow * center_glow_strength;

	float line_left = band(stage_uv.x, -0.34, 0.012, 0.015);
	float line_right = band(stage_uv.x, 0.34, 0.012, 0.015);
	float center_line = band(stage_uv.x, 0.0, 0.008, 0.012) * 0.45;
	float lane_lines = (line_left + line_right + center_line) * line_strength;
	lane_lines *= mix(0.55, 1.0, near_to_far);

	vec2 ring_uv = vec2(stage_uv.x * 0.88, (uv.y - 0.14) * 1.9);
	float ring_dist = length(vec2(ring_uv.x, ring_uv.y * 1.35));
	float ring_a = band(ring_dist, 0.92, 0.012, 0.02);
	float ring_b = band(ring_dist, 1.18, 0.016, 0.026) * 0.8;
	float rings = (ring_a + ring_b) * ring_strength;
	rings *= smoothstep(0.18, 0.72, uv.y);

	float panel_noise = fbm(vec2(uv.x * 8.0, uv.y * 18.0));
	float diagonal = sin((uv.y * 24.0 - uv.x * 9.0) + TIME * 0.35) * 0.5 + 0.5;
	float texture_mask = smoothstep(0.58, 0.86, panel_noise) * 0.45 + diagonal * 0.08;
	texture_mask *= texture_strength * smoothstep(0.0, 0.9, near_to_far);

	float edge_fade = 1.0 - smoothstep(0.72, 1.05, abs(stage_uv.x));
	float far_fade = smoothstep(0.0, 0.12, near_to_far);
	float vignette = edge_fade * far_fade;

	vec3 color = base * mix(0.72, 1.0, near_to_far);
	color += accent * runway * 0.34;
	color += line * lane_lines * 0.52;
	color += accent * rings * 0.22;
	color = mix(color, accent * 0.72 + base * 0.28, texture_mask * 0.12);
	color *= mix(0.72, 1.0, vignette);

	float emission = runway * 0.55 + lane_lines * 0.72 + rings * 0.4;
	emission *= emission_strength;

	ALBEDO = color;
	EMISSION = color * emission;
}
