extends Control
class_name EditorBPMLines

@export var editor: Editor
@export var chart_panel: Control

var _last_position := Vector2(INF, INF)
var _last_size := Vector2.ZERO
var _last_time := INF
var _last_pixels_per_ms := INF

func _process(_delta: float) -> void:
	if chart_panel == null:
		return

	var next_position := Vector2.ZERO if get_parent() == chart_panel else chart_panel.position
	var next_size := chart_panel.size
	var next_time := Game.current_time
	var next_pixels_per_ms := editor.get_pixels_per_ms() if editor != null else 0.0
	if position == next_position and size == next_size and is_equal_approx(_last_time, next_time) and is_equal_approx(_last_pixels_per_ms, next_pixels_per_ms):
		return

	position = next_position
	size = next_size
	_last_position = next_position
	_last_size = next_size
	_last_time = next_time
	_last_pixels_per_ms = next_pixels_per_ms
	queue_redraw()

func _draw() -> void:
	if editor == null or editor.timeline == null:
		return

	var pixels_per_ms = editor.get_pixels_per_ms()
	var judge_y = editor.get_judge_y()
	var visible_top := int(round(Game.current_time + (judge_y / pixels_per_ms)))
	var visible_bottom := int(round(Game.current_time - ((size.y - judge_y) / pixels_per_ms)))

	var center_time: int = int(editor.timeline.snap_time(int(round(Game.current_time))))
	if center_time >= visible_bottom and center_time <= visible_top:
		_draw_grid_line(center_time, judge_y)
	_draw_from_time(editor.timeline.step_time(center_time, 1), 1, visible_bottom, visible_top, judge_y)
	_draw_from_time(editor.timeline.step_time(center_time, -1), -1, visible_bottom, visible_top, judge_y)

func _draw_from_time(start_time: int, direction: int, visible_bottom: int, visible_top: int, judge_y: float) -> void:
	var visited: Dictionary = {}
	var current_time := start_time

	while not visited.has(current_time):
		visited[current_time] = true
		if current_time >= visible_bottom and current_time <= visible_top:
			_draw_grid_line(current_time, judge_y)
		elif direction > 0 and current_time > visible_top:
			break
		elif direction < 0 and current_time < visible_bottom:
			break

		current_time = editor.timeline.step_time(current_time, direction)

func _draw_grid_line(time_value: int, judge_y: float) -> void:
	var denominator: int = int(editor.timeline.get_division_denominator(time_value))
	var color := Color(0.4, 0.4, 0.4, 0.45)
	var thickness := 1.0

	match denominator:
		1:
			color = Color(1, 1, 1, 0.9)
			thickness = 2.0
		2:
			color = Color(0.25, 0.6, 1.0, 0.8)
		3:
			color = Color(1.0, 0.85, 0.2, 0.75)
		4:
			color = Color(1.0, 0.3, 0.3, 0.75)
		6:
			color = Color(0.9, 0.6, 0.1, 0.75)

	var y: float = judge_y + (Game.current_time - time_value) * editor.get_pixels_per_ms()
	draw_line(Vector2(0, y), Vector2(size.x, y), color, thickness, true)
