shader_type canvas_item;
render_mode unshaded;

uniform vec4 transition_color : source_color = vec4(0.02, 0.018, 0.035, 1.0);

uniform float progress : hint_range(0.0, 1.0) = 0.0;

// 팔 형태
uniform float arm_width = 0.48;
uniform float arm_softness = 0.16;

// 소용돌이
uniform float twist = 3.2;
uniform float rotation = 1.4;

// 액체감
uniform float liquid_scale = 3.0;
uniform float liquid_strength = 0.22;
uniform float flow_speed = 1.4;

// 진행 범위
uniform float outer_radius = 1.65;
uniform float inner_radius = 0.02;

// 머리/꼬리 부드러움
uniform float head_softness = 0.12;
uniform float tail_softness = 0.08;

// 시작 시 끝부분에 남는 두께
uniform float initial_length = 0.08;

float hash(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 37.13);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;

	for (int i = 0; i < 5; i++) {
		v += noise(p) * a;
		p *= 2.0;
		a *= 0.5;
	}

	return v;
}

float angle_diff(float a, float b) {
	float d = mod(a - b + PI, TAU) - PI;
	return abs(d);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * 2.0 - 1.0;

	// 화면 비율 보정
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	p.x /= aspect;

	float r = length(p);
	float a = atan(p.y, p.x);

	// progress가 올라갈수록 끝에서 중앙 쪽으로 head가 전진
	float head_radius = mix(outer_radius - initial_length, inner_radius, progress);

	// tail은 항상 화면 바깥쪽에 고정
	float tail_radius = outer_radius;

	// r이 head_radius ~ tail_radius 사이일 때만 보이게 함
	// 즉, 중앙 쪽은 아직 안 보이고 바깥에서부터 길어진다.
	float behind_head = smoothstep(
		head_radius - head_softness,
		head_radius + head_softness,
		r
	);

	float before_tail = 1.0 - smoothstep(
		tail_radius - tail_softness,
		tail_radius + tail_softness,
		r
	);

	float length_mask = behind_head * before_tail;

	// 소용돌이 중심선
	float spiral_angle = a + r * twist - progress * rotation;

	vec2 liquid_pos = vec2(cos(a), sin(a)) * r;
	float n = fbm(liquid_pos * liquid_scale + vec2(progress * flow_speed, -progress * flow_speed * 0.7));
	float liquid = (n - 0.5) * liquid_strength;

	float mask = 0.0;

	// 네 모서리 방향: 45도, 135도, 225도, 315도
	for (int i = 0; i < 4; i++) {
		float arm_angle = float(i) * PI * 0.5 + PI * 0.25;

		float d = angle_diff(spiral_angle + liquid, arm_angle);

		float arm = 1.0 - smoothstep(
			arm_width,
			arm_width + arm_softness,
			d
		);

		mask = max(mask, arm);
	}

	mask *= length_mask;

	// progress 1 근처에서 화면 전부 덮고 싶으면 유지
	// 싫으면 이 2줄 삭제
	float final_fill = smoothstep(0.88, 1.0, progress);
	mask = max(mask, final_fill);

	COLOR = vec4(transition_color.rgb, transition_color.a * mask);
}