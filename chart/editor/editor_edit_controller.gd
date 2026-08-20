extends Node
class_name EditorEditController

@export var editor: ChartEditor

func handle_mouse_button(event: InputEventMouseButton) -> void:
	if editor == null or not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not editor._is_mouse_inside_chart():
			return
		if Input.is_key_pressed(KEY_CTRL) and Input.is_key_pressed(KEY_SHIFT):
			editor.adjust_editor_zoom(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		elif Input.is_key_pressed(KEY_CTRL):
			adjust_selected_object(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		else:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			set_current_time(editor.timeline.step_time(int(round(Game.current_time)), direction))
		editor.get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not editor._is_mouse_inside_chart():
		return

	var mouse_pos := editor.get_global_mouse_position()

	if Input.is_key_pressed(KEY_SHIFT):
		var point_hit := editor._find_point_at(mouse_pos)
		if not point_hit.is_empty():
			editor.selection.select_point(point_hit["rail"], point_hit["point_index"])
			editor.point_dragging = true
			editor._point_drag_history_pending = true
			editor.get_viewport().set_input_as_handled()
			return

	if Input.is_key_pressed(KEY_CTRL) and editor.selection.selected_rail != null:
		add_point_at_mouse(mouse_pos)
		editor.get_viewport().set_input_as_handled()
		return

	var note_hit: Dictionary = {} if editor.note_passthrough else editor._find_note_at(mouse_pos)
	if not note_hit.is_empty():
		editor.selection.select_note(note_hit["rail"], note_hit["note"])
		editor.get_viewport().set_input_as_handled()
		return

	var rail_hit := editor._find_rail_at(mouse_pos)
	if rail_hit != null:
		editor.selection.select_rail(rail_hit)
		editor.get_viewport().set_input_as_handled()
		return

	editor.selection.clear()

func handle_key_input(event: InputEventKey) -> void:
	if editor == null:
		return

	if event.ctrl_pressed:
		if event.keycode == KEY_Z:
			editor._undo_history()
			return
		if event.keycode == KEY_Y:
			editor._redo_history()
			return

	match event.keycode:
		KEY_R: create_rail()
		KEY_Z: create_hit_note()
		KEY_ESCAPE: editor.exit()
		KEY_X: create_trace_note()
		KEY_C: create_spike_note()
		KEY_H: editor.toggle_note_passthrough()
		KEY_A: create_left_note()
		KEY_D: create_right_note()
		KEY_DELETE: delete_selected()
		KEY_SPACE: editor.transport.toggle()
		KEY_LEFT: move_selected_rail(-1.0)
		KEY_RIGHT: move_selected_rail(1.0)

func set_current_time(value: float) -> void:
	if editor == null or editor.timeline == null:
		return
	Game.current_time = editor.timeline.clamp_time(value)
	editor._update_time_ui(true)
	if editor.view_controller != null:
		editor.view_controller.mark_layout_dirty()
	if editor.transport.playing:
		editor.transport.seek()

func create_rail() -> void:
	if editor == null or editor.timeline == null:
		return
	editor._push_history_snapshot()
	var new_rail := EditorChartOps.create_default_rail(editor.timeline.snap_time(int(round(Game.current_time))))
	CM.ensure_parsed_chart().rails.append(new_rail)
	editor.selection.select_rail(new_rail)
	editor.refresh_views()

func create_hit_note() -> void:
	create_note(Note.NoteType.HIT, Note.Dir.NONE)

func create_trace_note() -> void:
	create_note(Note.NoteType.TRACE, Note.Dir.NONE)

func create_spike_note() -> void:
	create_note(Note.NoteType.SPIKE, Note.Dir.NONE)

func create_left_note() -> void:
	create_note(Note.NoteType.MOVE, Note.Dir.LEFT)

func create_right_note() -> void:
	create_note(Note.NoteType.MOVE, Note.Dir.RIGHT)

func create_note(note_type: Note.NoteType, dir: int) -> void:
	if editor == null or editor.timeline == null or editor.selection.selected_rail == null:
		return
	editor._push_history_snapshot()
	var note_time := editor.timeline.snap_time(int(round(Game.current_time)))
	var parsed_chart := CM.ensure_parsed_chart()
	EditorChartOps.remove_note_placement_conflicts(
		parsed_chart.rails,
		editor.selection.selected_rail,
		note_time,
		note_type
	)
	var new_note := EditorChartOps.create_note(note_type, note_time, dir)
	editor.selection.selected_rail.notes.append(new_note)
	editor.selection.selected_rail.sort_notes()
	editor.selection.select_note(editor.selection.selected_rail, new_note)
	editor.refresh_views()

func delete_selected() -> void:
	if editor == null:
		return
	if editor.selection.selected_note == null and not editor.selection.has_point() and editor.selection.selected_rail == null:
		return
	editor._push_history_snapshot()
	if editor.selection.selected_note != null and editor.selection.selected_rail != null:
		EditorChartOps.remove_note(editor.selection.selected_rail, editor.selection.selected_note)
	elif editor.selection.has_point():
		EditorChartOps.remove_point(editor.selection.selected_rail, editor.selection.selected_point_index)
	elif editor.selection.selected_rail != null:
		EditorChartOps.remove_rail(editor.selection.selected_rail)
	editor.selection.clear()
	editor.refresh_views()

func add_point_at_mouse(global_mouse_pos: Vector2) -> void:
	if editor == null or editor.timeline == null or editor.chart_panel == null:
		return
	editor._push_history_snapshot()
	var local := editor.chart_panel.get_global_transform_with_canvas().affine_inverse() * global_mouse_pos
	var point_time := int(editor.timeline.snap_time(editor._local_y_to_time(local.y)))
	var point_x := editor._snap_point_x(local.x / max(1.0, editor.chart_panel.size.x))
	var point_index := EditorChartOps.add_point(editor.selection.selected_rail, point_time, point_x)
	editor.selection.select_point(editor.selection.selected_rail, point_index)
	editor.refresh_views()

func adjust_selected_object(is_positive: bool) -> void:
	if editor == null:
		return
	if editor.selection.selected_note != null:
		var note := editor.selection.selected_note
		var direction := 1 if is_positive else -1
		var stepped_end_time := editor.timeline.step_time(note.end_time, direction)
		var next_length := maxi(0, stepped_end_time - note.time)
		if next_length == note.length:
			return
		editor._push_history_snapshot()
		note.length = next_length
		if editor.view_controller != null:
			editor.view_controller.refresh_note(note)
		editor.selection_changed.emit()
		return
	if editor.selection.has_point():
		editor._push_history_snapshot()
		var point := editor.selection.get_point()
		point.curve = clamp(point.curve + (0.1 if is_positive else -0.1), -1.0, 1.0)
		if editor.view_controller != null:
			editor.view_controller.mark_layout_dirty()
		editor._sync_view_layouts()

func move_selected_rail(direction: float) -> void:
	if editor == null or editor.selection.selected_rail == null:
		return
	editor._push_history_snapshot()
	EditorChartOps.move_rail(editor.selection.selected_rail, direction)
	if editor.view_controller != null:
		editor.view_controller.mark_layout_dirty()
