shader_type sky;

uniform vec4 base_color : source_color = vec4(0.1098, 0.1020, 0.1765, 1.0);
uniform vec4 detail_color : source_color = vec4(0.168, 0.149, 0.278, 1.0);

uniform float scale_a : hint_range(0.5, 16.0) = 4.2;
uniform float scale_b : hint_range(0.5, 16.0) = 2.2;
uniform float move_speed : hint_range(0.0, 2.0) = 0.08;
uniform float pattern_strength : hint_range(0.0, 1.0) = 0.92;
uniform float softness : hint_range(0.001, 0.2) = 0.018;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sd_diamond(vec2 p, float r) {
	p = abs(p);
	return p.x + p.y - r;
}

float shape_distance(vec2 p, float seed, float pulse) {
	if (seed < 0.33) {
		return sd_circle(p, 0.22 + pulse * 0.03);
	}
	if (seed < 0.66) {
		return sd_box(p, vec2(0.2 + pulse * 0.025));
	}
	return sd_diamond(p, 0.34 + pulse * 0.035);
}

float layer_mask(vec2 uv, float scale, vec2 velocity, float time_offset) {
	vec2 grid_uv = uv * scale + velocity * TIME;
	vec2 cell = floor(grid_uv);
	vec2 local = fract(grid_uv) - 0.5;

	float seed = hash(cell + vec2(time_offset, time_offset * 0.37));
	float pulse = sin(TIME * (0.55 + seed * 0.75) + seed * 6.28318) * 0.5 + 0.5;
	float angle = (seed - 0.5) * 1.2 + TIME * (0.08 + seed * 0.12);
	local *= rot(angle);

	float dist = shape_distance(local, seed, pulse);
	return 1.0 - smoothstep(0.0, softness, dist);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec2 uv = vec2(dir.x, dir.y) * 0.92;

	float mask_a = layer_mask(uv, scale_a, vec2(-move_speed, move_speed * 0.58), 1.0);
	float mask_b = layer_mask(uv, scale_b, vec2(move_speed * 0.42, -move_speed * 0.24), 9.0) * 0.7;
	float pattern = clamp(mask_a + mask_b, 0.0, 1.0) * pattern_strength;

	COLOR = mix(base_color.rgb, detail_color.rgb, pattern);
}
