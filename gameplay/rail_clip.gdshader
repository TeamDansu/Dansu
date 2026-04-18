shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float rail_origin_z = 0.0;
uniform float min_visible_z = 0.0;
uniform vec3 albedo_color : source_color = vec3(1.0);

varying float playfield_z;

void vertex() {
	playfield_z = rail_origin_z + VERTEX.z;
}

void fragment() {
	if (playfield_z < min_visible_z) {
		discard;
	}
	ALBEDO = albedo_color;
	EMISSION = albedo_color;
}
