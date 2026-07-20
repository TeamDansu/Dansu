shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float rail_origin_z = 0.0;
uniform float min_visible_z = 0.0;
uniform float clip_fade_length : hint_range(0.1, 8.0) = 2.5;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec4 accent_color : source_color = vec4(0.561, 0.486, 0.988, 1.0);
uniform float brightness : hint_range(0.0, 1.0) = 1.0;
uniform float emission_strength : hint_range(0.0, 4.0) = 1.0;
uniform float depth_clip_scale : hint_range(0.9, 1.1) = 1.0;
uniform float surface_role : hint_range(0.0, 1.0) = 0.0;

varying float playfield_z;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void vertex() {
	playfield_z = rail_origin_z + VERTEX.z;
	Z_CLIP_SCALE = depth_clip_scale;
}

void fragment() {
	if (playfield_z < min_visible_z) {
		discard;
	}
	float clip_coverage = smoothstep(min_visible_z, min_visible_z + clip_fade_length, playfield_z);
	float clip_dither = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (clip_coverage < clip_dither) {
		discard;
	}

	float center_mask = 1.0 - abs(UV.x * 2.0 - 1.0);
	center_mask = clamp(center_mask, 0.0, 1.0);
	float core_mask = smoothstep(0.18, 0.92, center_mask);
	float core_glow = pow(center_mask, 3.4);
	float edge_mask = smoothstep(0.56, 0.98, 1.0 - center_mask);

	vec3 base_color = albedo_color.rgb;
	vec3 highlight_color = mix(base_color, accent_color.rgb, 0.68);
	vec3 shadow_color = base_color * 0.58;

	float active_strength = mix(0.34, 1.0, brightness);
	float soft_sweep = sin(playfield_z * 0.058 - TIME * 2.15) * 0.5 + 0.5;
	soft_sweep = smoothstep(0.80, 0.99, soft_sweep) * core_glow;

	float pulse = sin(playfield_z * 0.028 + TIME * 1.15) * 0.5 + 0.5;
	float grain = hash(floor(playfield_z * 0.045) + floor(UV.x * 14.0) * 13.0);
	float breakup = mix(0.975, 1.025, grain * 0.5 + pulse * 0.5);

	vec3 body_color = mix(shadow_color, base_color, 0.78);
	body_color = mix(body_color, highlight_color, core_mask * 0.075);
	body_color += highlight_color * soft_sweep * (0.045 + active_strength * 0.065);
	body_color *= breakup;

	vec3 fill_color = body_color;
	fill_color += highlight_color * core_glow * active_strength * 0.055;

	vec3 outline_color = mix(base_color * 0.92, highlight_color, 0.62);
	outline_color += highlight_color * edge_mask * 0.018;

	vec3 final_color = mix(fill_color * active_strength, outline_color, surface_role);
	float final_emission = mix((0.07 + core_glow * 0.22 + soft_sweep * 0.26) * emission_strength * active_strength, 0.018, surface_role);

	ALBEDO = final_color;
	EMISSION = final_color * final_emission;
}
