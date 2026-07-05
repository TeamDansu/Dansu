extends Node3D
class_name GameRail

const CLIP_SHADER := preload("res://resorces/shaders/rail_clip.gdshader")
const DEFAULT_WIDTH := 1.2
const DEFAULT_OUTLINE_SIZE := 0.1
const CAP_SEGMENTS := 10
const SAMPLE_INTERVAL_MS := 16.0
const OUTLINE_WORLD_Y_OFFSET := -0.01
const DEFAULT_FILL_COLOR := Color(0.149, 0.121, 0.278, 1.0)
const DEFAULT_OUTLINE_COLOR := Color(0.439, 0.357, 0.871, 1.0)
const DEFAULT_ACCENT_COLOR := Color(0.561, 0.486, 0.988, 1.0)
const IDLE_BRIGHTNESS := 0.3
const STANDING_BRIGHTNESS := 1
const FILL_DEPTH_CLIP_SCALE := 1.0
const OUTLINE_DEPTH_CLIP_SCALE := 1.0

var rail: Rail

@export var note_container: Node3D
@export var width: float = DEFAULT_WIDTH
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var outline_size := DEFAULT_OUTLINE_SIZE
var outline_mesh_instance: MeshInstance3D
var _fill_material: ShaderMaterial = null
var _outline_material: ShaderMaterial = null

var is_standing := false:
	set(value):
		is_standing = value
		_update_brightness()


static func prebake_for_rails(rails: Array[Rail], rail_width: float = DEFAULT_WIDTH, rail_outline_size: float = DEFAULT_OUTLINE_SIZE) -> void:
	for rail in rails:
		prebake_for_rail(rail, rail_width, rail_outline_size)


static func prebake_for_rail(rail: Rail, rail_width: float = DEFAULT_WIDTH, rail_outline_size: float = DEFAULT_OUTLINE_SIZE) -> void:
	if rail == null or rail.points.size() < 2:
		return

	if rail.cached_fill_mesh != null and rail.cached_outline_mesh != null and is_equal_approx(rail.cached_render_width, rail_width) and is_equal_approx(rail.cached_outline_size, rail_outline_size):
		return

	var path := _sample_curve_points_for_rail(rail)
	rail.cached_fill_mesh = _build_ribbon_mesh(path, rail_width)
	rail.cached_outline_mesh = _build_ribbon_mesh(path, rail_width + (rail_outline_size * 2.0))
	rail.cached_render_width = rail_width
	rail.cached_outline_size = rail_outline_size


func _ready() -> void:
	_ensure_outline_mesh_instance()

	if rail != null and not rail.points.is_empty():
		position.z = GameplayPlayfield.rail_origin_z(rail.start_time, Game.current_time)

	_apply_prebaked_meshes()
	_apply_materials()


func _process(_delta: float) -> void:
	if rail == null or rail.points.is_empty():
		return
	position.z = GameplayPlayfield.rail_origin_z(rail.start_time, Game.current_time)
	_update_material_position()


func _ensure_outline_mesh_instance() -> void:
	outline_mesh_instance = get_node_or_null("OutlineMeshInstance3D") as MeshInstance3D
	if outline_mesh_instance != null:
		return

	outline_mesh_instance = MeshInstance3D.new()
	outline_mesh_instance.name = "OutlineMeshInstance3D"
	outline_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline_mesh_instance.position.y = OUTLINE_WORLD_Y_OFFSET
	add_child(outline_mesh_instance)
	move_child(outline_mesh_instance, 0)


func _apply_prebaked_meshes() -> void:
	if rail == null:
		mesh_instance.mesh = null
		if outline_mesh_instance != null:
			outline_mesh_instance.mesh = null
		return

	prebake_for_rail(rail, width, outline_size)
	mesh_instance.mesh = rail.cached_fill_mesh
	if outline_mesh_instance != null:
		outline_mesh_instance.mesh = rail.cached_outline_mesh


func _apply_materials() -> void:
	_fill_material = _create_material(DEFAULT_FILL_COLOR, DEFAULT_ACCENT_COLOR, 1.0, FILL_DEPTH_CLIP_SCALE, 0.0)
	_outline_material = _create_material(DEFAULT_OUTLINE_COLOR, DEFAULT_ACCENT_COLOR, 0.0, OUTLINE_DEPTH_CLIP_SCALE, 1.0)

	mesh_instance.material_override = _fill_material
	if outline_mesh_instance != null:
		outline_mesh_instance.material_override = _outline_material
		outline_mesh_instance.position.y = OUTLINE_WORLD_Y_OFFSET

	_update_brightness()
	_update_material_position()


func _create_material(color: Color, accent_color: Color, emission_strength: float, depth_clip_scale: float, surface_role: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CLIP_SHADER
	material.set_shader_parameter("min_visible_z", 0.0)
	material.set_shader_parameter("albedo_color", color)
	material.set_shader_parameter("accent_color", accent_color)
	material.set_shader_parameter("brightness", STANDING_BRIGHTNESS)
	material.set_shader_parameter("emission_strength", emission_strength)
	material.set_shader_parameter("depth_clip_scale", depth_clip_scale)
	material.set_shader_parameter("surface_role", surface_role)
	return material


func _update_brightness() -> void:
	if _fill_material != null:
		_fill_material.set_shader_parameter("brightness", STANDING_BRIGHTNESS if is_standing else IDLE_BRIGHTNESS)


func _update_material_position() -> void:
	if _fill_material != null:
		_fill_material.set_shader_parameter("rail_origin_z", position.z)
	if _outline_material != null:
		_outline_material.set_shader_parameter("rail_origin_z", position.z)


static func _sample_curve_points_for_rail(rail: Rail) -> Array[Vector3]:
	var result: Array[Vector3] = []

	if rail == null or rail.points.size() < 2:
		return result

	for i in range(rail.points.size() - 1):
		var a: RailPoint = rail.points[i]
		var b: RailPoint = rail.points[i + 1]

		var t0 := int(a.time)
		var t1 := int(b.time)
		var duration_ms = max(1, t1 - t0)
		var steps = max(4, int(ceil(duration_ms / SAMPLE_INTERVAL_MS)))

		for j in range(steps):
			var alpha := float(j) / float(steps)
			var curved_alpha := rail._apply_curve(alpha, float(a.curve))
			var x := GameplayPlayfield.normalized_x_to_world(lerp(float(a.x), float(b.x), curved_alpha))
			var sampled_time := int(round(lerp(float(t0), float(t1), alpha)))
			var z := GameplayPlayfield.local_z_from_start(rail.start_time, sampled_time)
			result.append(Vector3(x, 0.0, z))

	var last := rail.points[rail.points.size() - 1]
	result.append(
		Vector3(
			GameplayPlayfield.normalized_x_to_world(float(last.x)),
			0.0,
			GameplayPlayfield.local_z_from_start(rail.start_time, int(last.time))
		)
	)
	return result


static func _build_ribbon_mesh(path: Array[Vector3], rail_width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if path.size() < 2:
		return st.commit()

	var half_width := rail_width * 0.5
	var left_points: Array[Vector3] = []
	var right_points: Array[Vector3] = []

	for i in range(path.size()):
		var offset := _get_join_offset(path, i, half_width)
		left_points.append(path[i] - offset)
		right_points.append(path[i] + offset)

	for i in range(path.size() - 1):
		var a := left_points[i]
		var b := right_points[i]
		var c := left_points[i + 1]
		var d := right_points[i + 1]

		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(0, 1)); st.add_vertex(c)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)

		st.set_uv(Vector2(1, 0)); st.add_vertex(b)
		st.set_uv(Vector2(0, 1)); st.add_vertex(c)
		st.set_uv(Vector2(1, 1)); st.add_vertex(d)

	var start_dir := (path[1] - path[0]).normalized()
	var end_dir := (path[path.size() - 1] - path[path.size() - 2]).normalized()
	_append_cap(st, path[0], start_dir, half_width, true)
	_append_cap(st, path[path.size() - 1], end_dir, half_width, false)

	st.generate_normals()
	return st.commit()


static func _append_cap(st: SurfaceTool, center: Vector3, forward: Vector3, radius: float, is_start: bool) -> void:
	if forward.is_zero_approx():
		return

	forward = forward.normalized()
	var side := Vector3.UP.cross(forward).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT

	var prev_point := _get_cap_point(center, side, forward, radius, 0.0, is_start)
	for index in range(1, CAP_SEGMENTS + 1):
		var angle := PI * float(index) / float(CAP_SEGMENTS)
		var next_point := _get_cap_point(center, side, forward, radius, angle, is_start)

		st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(center)
		st.set_uv(Vector2(0, 0)); st.add_vertex(prev_point)
		st.set_uv(Vector2(1, 0)); st.add_vertex(next_point)

		prev_point = next_point


static func _get_cap_point(center: Vector3, side: Vector3, forward: Vector3, radius: float, angle: float, is_start: bool) -> Vector3:
	var offset := Vector3.ZERO
	if is_start:
		offset = (side * cos(angle) - forward * sin(angle)) * radius
	else:
		offset = (-side * cos(angle) + forward * sin(angle)) * radius
	return center + offset


static func _get_join_offset(path: Array[Vector3], index: int, half_width: float) -> Vector3:
	var current := path[index]
	var prev := path[max(index - 1, 0)]
	var nxt := path[min(index + 1, path.size() - 1)]

	var prev_dir := (current - prev).normalized()
	var next_dir := (nxt - current).normalized()
	if prev_dir.is_zero_approx():
		prev_dir = next_dir
	if next_dir.is_zero_approx():
		next_dir = prev_dir
	if prev_dir.is_zero_approx() and next_dir.is_zero_approx():
		return Vector3.RIGHT * half_width

	var prev_side := Vector3.UP.cross(prev_dir).normalized()
	var next_side := Vector3.UP.cross(next_dir).normalized()
	if prev_side.dot(next_side) < 0.0:
		next_side = -next_side

	var miter := (prev_side + next_side).normalized()
	if miter.is_zero_approx():
		return next_side * half_width

	var miter_scale := half_width / maxf(absf(miter.dot(next_side)), 0.35)
	miter_scale = minf(miter_scale, half_width * 2.0)
	return miter * miter_scale
