extends RefCounted
class_name Rail

var id := -1
var points: Array[RailPoint] = []
var notes: Array[Note] = []
var cached_fill_mesh: ArrayMesh = null
var cached_outline_mesh: ArrayMesh = null
var cached_render_width := -1.0
var cached_outline_size := -1.0

func _init() -> void:
	points = []
	notes = []

var start_time: int:
	get:
		return points[0].time if not points.is_empty() else 0
	set(value):
		if not points.is_empty():
			points[0].time = value

var end_time: int:
	get:
		return int(points[points.size() - 1].time) if not points.is_empty() else 0
	set(value):
		if not points.is_empty():
			points[points.size() - 1].time = value

func sort_points() -> void:
	points.sort_custom(func(a, b) -> bool: return a.time < b.time)

func sort_notes() -> void:
	notes.sort_custom(func(a, b) -> bool: return a.time < b.time)

func clear_render_cache() -> void:
	cached_fill_mesh = null
	cached_outline_mesh = null
	cached_render_width = -1.0
	cached_outline_size = -1.0

func _apply_curve(t: float, curve: float) -> float:
	curve = clamp(curve, -1.0, 1.0)
	if abs(curve) < 0.001:
		return t
	if curve > 0.0:
		return pow(t, 1.0 + curve * 2.0)
	return 1.0 - pow(1.0 - t, 1.0 + abs(curve) * 2.0)

func _get_rail_x_at_time(time_ms: int) -> float:
	if points.is_empty():
		return 0.0
	if points.size() == 1:
		return float(points[0].x)
	if time_ms <= int(points[0].time):
		return float(points[0].x)

	var last_index := points.size() - 1
	if time_ms >= int(points[last_index].time):
		return float(points[last_index].x)

	for i in range(points.size() - 1):
		var a = points[i]
		var b = points[i + 1]
		var t0 := int(a.time)
		var t1 := int(b.time)
		if time_ms < t0 or time_ms > t1:
			continue

		var x0 := float(a.x)
		var x1 := float(b.x)
		if t1 == t0:
			return x1

		var alpha := float(time_ms - t0) / float(t1 - t0)
		alpha = clamp(alpha, 0.0, 1.0)
		alpha = _apply_curve(alpha, float(a.curve))
		return lerp(x0, x1, alpha)

	return 0.0
