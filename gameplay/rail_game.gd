extends Node3D
class_name GameRail

const CLIP_SHADER := preload("res://gameplay/rail_clip.gdshader")

var rail: Rail

@export var note_container: Node3D
@export var width: float = 1.5
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var _clip_material: ShaderMaterial = null

func _ready() -> void:
	if rail != null and not rail.points.is_empty():
		position.z = GameplayPlayfield.rail_origin_z(rail.start_time, Game.current_time)
	rebuild_mesh()

func _process(_delta: float) -> void:
	if rail == null or rail.points.is_empty():
		return
	position.z = GameplayPlayfield.rail_origin_z(rail.start_time, Game.current_time)
	_update_clip_material()

func rebuild_mesh() -> void:
	var path := _sample_curve_points()
	var mesh := _build_ribbon_mesh(path, width)
	mesh_instance.mesh = mesh
	_apply_clip_material()

func _sample_curve_points() -> Array[Vector3]:
	var result: Array[Vector3] = []

	if rail == null or rail.points.size() < 2:
		return result

	for i in range(rail.points.size() - 1):
		var a: RailPoint = rail.points[i]
		var b: RailPoint = rail.points[i + 1]

		var t0 := int(a.time)
		var t1 := int(b.time)
		var duration_ms = max(1, t1 - t0)
		var steps = max(4, int(ceil(duration_ms / 16.0)))

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

func _build_ribbon_mesh(path: Array[Vector3], rail_width: float) -> ArrayMesh:
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

		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)

		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(d)

	st.generate_normals()
	return st.commit()

func _get_join_offset(path: Array[Vector3], index: int, half_width: float) -> Vector3:
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

func _apply_clip_material() -> void:
	_clip_material = ShaderMaterial.new()
	_clip_material.shader = CLIP_SHADER
	_clip_material.set_shader_parameter("min_visible_z", 0.0)
	_clip_material.set_shader_parameter("albedo_color", Vector3.ONE)
	mesh_instance.material_override = _clip_material
	_update_clip_material()

func _update_clip_material() -> void:
	if _clip_material == null:
		return
	_clip_material.set_shader_parameter("rail_origin_z", position.z)
