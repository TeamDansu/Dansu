shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float rail_origin_z = 0.0;
uniform float min_visible_z = 0.0;
uniform vec3 albedo_color : source_color = vec3(1.0);
uniform float outline_width : hint_range(0.0, 0.5) = 0.08;
uniform float brightness : hint_range(0.0, 1.0) = 1.0;

varying float playfield_z;

void vertex() {
	playfield_z = rail_origin_z + VERTEX.z;
}

void fragment() {
	if (playfield_z < min_visible_z) {
		discard;
	}
	vec3 color = albedo_color * brightness;
	if (UV.x < outline_width || UV.x > 1.0 - outline_width) {
		ALBEDO = vec3(0.0);
		EMISSION = vec3(0.0);
	} else {
		ALBEDO = color;
		EMISSION = color;
	}
}
