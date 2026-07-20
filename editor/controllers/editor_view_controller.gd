extends Node
class_name EditorViewController

const PIXELS_PER_MS := 1.0
@export var editor: Editor
@export var chart_root: Control
@export var chart_panel: Control
@export var note_pivot: Control
@export var bpm_lines: Control

var rail_layer: Control
var note_layer: Control

var rail_scene := preload("res://scenes/editor/editor_rail.tscn")
var note_scene := preload("res://scenes/editor/editor_note.tscn")

var rail_views: Dictionary = {}
var note_views: Dictionary = {}
var _layout_dirty := true
var _last_panel_size := Vector2(-1.0, -1.0)
var _last_judge_y := INF
var _last_current_time := INF

func prepare_layers() -> void:
	if chart_panel == null:
		return
	if rail_layer == null:
		rail_layer = Control.new()
		rail_layer.name = "RailLayer"
		rail_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rail_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		rail_layer.position = Vector2.ZERO
		rail_layer.size = chart_panel.size
		chart_panel.add_child(rail_layer)
	if note_layer == null:
		note_layer = Control.new()
		note_layer.name = "NoteLayer"
		note_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		note_layer.position = Vector2.ZERO
		note_layer.size = chart_panel.size
		chart_panel.add_child(note_layer)

func configure_chart_input() -> void:
	for node in [chart_root, chart_panel, bpm_lines, note_pivot]:
		if node != null:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func mark_layout_dirty() -> void:
	_layout_dirty = true

func refresh_views() -> void:
	clear_layers()
	rail_views.clear()
	note_views.clear()
	_layout_dirty = true

	if editor == null or editor.transport == null or CM.parsed_chart == null:
		if editor != null and editor.transport != null:
			editor.transport.rebuild_playback_notes()
		sync_layouts()
		return

	for rail: Rail in CM.parsed_chart.rails:
		if rail == null:
			continue
		var rail_view: EditorRail = rail_scene.instantiate()
		rail_view.rail = rail
		rail_view.editor = editor
		rail_layer.add_child(rail_view)
		rail_views[rail] = rail_view

		for note in rail.notes:
			if note == null:
				continue
			var note_view: EditorNote = note_scene.instantiate()
			note_view.note = note
			note_view.rail = rail
			note_view.editor = editor
			note_view.set_passthrough(editor.note_passthrough)
			note_layer.add_child(note_view)
			note_views[note] = note_view

	editor.transport.rebuild_playback_notes()
	sync_layouts()

func clear_layers() -> void:
	if rail_layer != null:
		for child in rail_layer.get_children():
			child.queue_free()
	if note_layer != null:
		for child in note_layer.get_children():
			child.queue_free()

func sync_layouts() -> void:
	if editor == null or chart_panel == null or note_pivot == null:
		return

	var panel_size := chart_panel.size
	var judge_y := note_pivot.position.y - chart_panel.position.y
	var current_time := Game.current_time

	if not _layout_dirty \
	and _last_panel_size == panel_size \
	and is_equal_approx(_last_judge_y, judge_y) \
	and is_equal_approx(_last_current_time, current_time):
		return

	_layout_dirty = false
	_last_panel_size = panel_size
	_last_judge_y = judge_y
	_last_current_time = current_time

	if rail_layer != null and rail_layer.size != panel_size:
		rail_layer.size = panel_size
	if note_layer != null and note_layer.size != panel_size:
		note_layer.size = panel_size

	for rail_view in rail_views.values():
		rail_view.sync_layout(panel_size, judge_y, PIXELS_PER_MS, current_time)
		rail_view.set_selection_state(editor.selection.selected_rail == rail_view.rail, editor.selection.selected_point_index)

	for note in note_views.keys():
		var note_view: EditorNote = note_views[note]
		note_view.sync_layout(panel_size, judge_y, PIXELS_PER_MS, current_time)
		note_view.set_selected(editor.selection.selected_note == note)

	editor._update_time_ui(false)

func set_note_passthrough(enabled: bool) -> void:
	for note_view in note_views.values():
		note_view.set_passthrough(enabled)

func find_note_at(global_mouse_pos: Vector2) -> Dictionary:
	for note in note_views.keys():
		var note_view: EditorNote = note_views[note]
		if note_view.is_head_hit(global_mouse_pos):
			return {"note": note, "rail": note_view.rail}
	return {}

func find_rail_at(global_mouse_pos: Vector2) -> Rail:
	var closest_rail: Rail = null
	var closest_distance := INF
	for rail in rail_views.keys():
		var dist: float = rail_views[rail].distance_to_curve(global_mouse_pos)
		if dist < 14.0 and dist < closest_distance:
			closest_distance = dist
			closest_rail = rail
	return closest_rail

func find_point_at(global_mouse_pos: Vector2) -> Dictionary:
	var closest_rail: Rail = null
	var closest_index := -1
	var closest_distance := INF
	for rail in rail_views.keys():
		var rail_view: EditorRail = rail_views[rail]
		var point_index := rail_view.get_point_hit_index(global_mouse_pos)
		if point_index == -1:
			continue
		var local := rail_view.get_global_transform_with_canvas().affine_inverse() * global_mouse_pos
		var dist := rail_view._point_to_panel(rail.points[point_index]).distance_to(local)
		if dist < closest_distance:
			closest_distance = dist
			closest_rail = rail
			closest_index = point_index
	if closest_rail == null:
		return {}
	return {"rail": closest_rail, "point_index": closest_index}

func drag_selected_point(global_mouse_pos: Vector2) -> void:
	if editor == null or chart_panel == null:
		return
	var point := editor.selection.get_point()
	if point == null:
		return
	var local := chart_panel.get_global_transform_with_canvas().affine_inverse() * global_mouse_pos
	var next_x = clamp(snapped(local.x / max(1.0, chart_panel.size.x), 0.05), 0.0, 1.0)
	var next_time := editor.timeline.snap_time(editor._local_y_to_time(local.y))
	if is_equal_approx(point.x, next_x) and point.time == next_time:
		return
	if editor._point_drag_history_pending:
		editor._push_history_snapshot()
		editor._point_drag_history_pending = false
	point.x = next_x
	point.time = next_time
	editor.selection.selected_rail.sort_points()
	editor.selection.selected_point_index = editor.selection.selected_rail.points.find(point)
	mark_layout_dirty()
	sync_layouts()
