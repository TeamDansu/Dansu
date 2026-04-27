shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4 pulse_color : source_color = vec4(0.1, 0.9, 1.0, 1.0);
uniform float origin_x : hint_range(0.0, 1.0) = 0.5;
uniform float judge_y : hint_range(0.0, 1.0) = 0.88;
uniform float progress : hint_range(0.0, 1.0) = 0.0;

uniform float max_radius : hint_range(0.0, 2.0) = 0.75;
uniform float band_width : hint_range(0.001, 0.2) = 0.028;
uniform float softness : hint_range(0.001, 0.2) = 0.03;
uniform float glow_strength : hint_range(0.0, 8.0) = 2.5;
uniform float aspect_ratio = 1.7778;
uniform float vertical_softness : hint_range(0.001, 0.2) = 0.04;

void fragment() {
	vec2 uv = UV;

	// 원형 왜곡 방지
	vec2 p = vec2((uv.x - origin_x) * aspect_ratio, uv.y - judge_y);
	float dist = length(p);

	float radius = progress * max_radius;

	// 메인 파동
	float ring_1 = 1.0 - smoothstep(
		band_width,
		band_width + softness,
		abs(dist - radius)
	);

	// 뒤따라오는 잔파동
	float radius_2 = max(radius - 0.08, 0.0);
	float ring_2 = 1.0 - smoothstep(
		band_width * 1.35,
		band_width * 1.35 + softness,
		abs(dist - radius_2)
	);

	float wave = ring_1 + ring_2 * 0.45;

	// 시간에 따른 페이드아웃
	float time_fade = pow(max(1.0 - progress, 0.0), 0.65);

	// 중심부 약간 밝게
	float core = 1.0 - smoothstep(0.0, 0.12, dist);
	core *= (1.0 - progress) * 0.18;

	float alpha = (wave * time_fade) + core;
	alpha = clamp(alpha, 0.0, 1.0);

	vec3 color = pulse_color.rgb * alpha * glow_strength;
	COLOR = vec4(color, alpha);
}
