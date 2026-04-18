extends Control
class_name Editor

signal selection_changed()
signal hitsounds_changed()

const PIXELS_PER_MS := 1
const TRANSPORT_UI_UPDATE_USEC := 33333
const DEFAULT_HIT_SFX := preload("res://resorces/audio/hitsounds/chop.wav")
const DEFAULT_MOVE_SFX := preload("res://resorces/audio/hitsounds/chop.wav")
const SFX_PLAYER_COUNT := 8
const MAX_HISTORY_STEPS := 128

@export var chart_root: Control
@export var chart_panel: Control
@export var note_pivot: Control
@export var bpm_lines: Control
@export var song_slider: HSlider
@export var current_time_label: Label
@export var save_button: Button
@export var delete_button: Button
@export var hit_button: Button
@export var trace_button: Button
@export var left_button: Button
@export var right_button: Button
@export var spike_button: Button
@export var title_line_edit: LineEdit
@export var artist_line_edit: LineEdit
@export var difficulty_line_edit: LineEdit
@export var source_line_edit: LineEdit
@export var tags_line_edit: LineEdit
@export var beat_division_slider: HSlider
@export var beat_division_label: Label
@export var add_timing_button: Button
@export var timing_list_container: VBoxContainer
@export var timing_template: Node

var timeline: EditorTimeline = null
var selection: ChartEditorSelection = ChartEditorSelection.new()
var chart: Chart = null
var previous_file_path := ""
var audio_player: AudioStreamPlayer
var transport_playing := false
var audio_started := false
var audio_start_target_usec := 0
var audio_start_position_sec := 0.0
var song_finished_usec := 0

var rail_layer: Control
var note_layer: Control
var rail_scene := preload("res://scenes/editor/editor_rail.tscn")
var note_scene := preload("res://scenes/editor/editor_note.tscn")
var timing_scene := preload("res://scenes/editor/ui/inspector/timing.tscn")

var rail_views: Dictionary = {}
var note_views: Dictionary = {}
var timing_items: Array[EditorTimingItem] = []
var point_dragging := false
var note_passthrough := false
var _syncing_metadata := false
var _syncing_song_slider := false
var _view_layout_dirty := true
var _last_panel_size := Vector2.ZERO
var _last_judge_y := INF
var _last_view_time := INF
var _last_selection_rail: Rail = null
var _last_selection_note: Note = null
var _last_selection_point_index := -2
var _last_note_passthrough := false
var _last_transport_ui_usec := 0

var _stream_length_sec := 0.0
var _stream_length_msec := 0.0
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player_index := 0
var _hitsound_streams: Dictionary = {}
var _playback_notes: Array[Note] = []
var _playback_note_index := 0
var _last_sfx_time := -1000000.0
var _playback_release_notes: Array[Note] = []
var _playback_release_note_index := 0
var _last_release_sfx_time := -1000000.0
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _is_restoring_history := false
var _point_drag_history_pending := false

func _ready() -> void:
	Game.current_time = 0.0
	chart = _ensure_chart()
	previous_file_path = chart.file_path
	selection.changed.connect(_on_selection_changed)
	_prepare_audio_player()
	_load_chart_data()
	_configure_chart_input()
	_prepare_layers()
	_connect_ui()
	_refresh_metadata_fields()
	_rebuild_timing_ui()
	_update_slider_range()
	_update_beat_division_ui()
	_refresh_views()
	_update_save_button_state()

func _process(_delta: float) -> void:
	$Label.text = str(Engine.get_frames_per_second())
	_update_transport()
	if point_dragging and selection.has_point() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_selected_point(get_global_mouse_position())
	elif point_dragging:
		point_dragging = false

	var should_passthrough := Input.is_key_pressed(KEY_SHIFT)
	if note_passthrough != should_passthrough:
		note_passthrough = should_passthrough
		for note_view in note_views.values():
			note_view.set_passthrough(note_passthrough)
		_view_layout_dirty = true

	_sync_view_layouts()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		point_dragging = false
		_point_drag_history_pending = false

	if event is InputEventMouseButton:
		if not _is_text_input_focused():
			_handle_mouse_button(event)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if not _is_text_input_focused():
			_handle_key_input(event)

func refresh_views() -> void:
	_refresh_views()

func _ensure_chart() -> Chart:
	if CM.selected_chart != null:
		return CM.selected_chart

	var fallback_chart := Chart.new()
	fallback_chart.uuid = CM.generate_uuid()
	fallback_chart.title = ""
	fallback_chart.artist = ""
	fallback_chart.difficulty = ""
	fallback_chart.chart_set = CM.selected_chartset
	if fallback_chart.chart_set != null:
		fallback_chart.folder_name = fallback_chart.chart_set.folder_name
	return fallback_chart

func _prepare_layers() -> void:
	rail_layer = Control.new()
	rail_layer.name = "RailLayer"
	rail_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	rail_layer.position = Vector2.ZERO
	rail_layer.size = chart_panel.size
	chart_panel.add_child(rail_layer)

	note_layer = Control.new()
	note_layer.name = "NoteLayer"
	note_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	note_layer.position = Vector2.ZERO
	note_layer.size = chart_panel.size
	chart_panel.add_child(note_layer)

func _prepare_audio_player() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.name = "EditorAudioPlayer"
	audio_player.bus = "Music"
	audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(audio_player)

	for index in range(SFX_PLAYER_COUNT):
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.name = "EditorSFXPlayer%d" % index
		sfx_player.bus = "SFX"
		sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(sfx_player)
		_sfx_players.append(sfx_player)

func _configure_chart_input() -> void:
	if chart_root != null:
		chart_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if chart_panel != null:
		chart_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if bpm_lines != null:
		bpm_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if note_pivot != null:
		note_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _connect_ui() -> void:
	if song_slider != null:
		song_slider.value_changed.connect(_on_song_slider_value_changed)
	if save_button != null:
		save_button.pressed.connect(_save_chart)
	if delete_button != null:
		delete_button.pressed.connect(_delete_selected)
	if hit_button != null:
		hit_button.pressed.connect(_create_hit_note)
	if trace_button != null:
		trace_button.pressed.connect(_create_trace_note)
	if left_button != null:
		left_button.pressed.connect(_create_left_note)
	if right_button != null:
		right_button.pressed.connect(_create_right_note)
	if spike_button != null:
		spike_button.pressed.connect(_create_spike_note)
	if title_line_edit != null:
		title_line_edit.text_changed.connect(_on_title_changed)
	if artist_line_edit != null:
		artist_line_edit.text_changed.connect(_on_artist_changed)
	if difficulty_line_edit != null:
		difficulty_line_edit.text_changed.connect(_on_difficulty_changed)
	if source_line_edit != null:
		source_line_edit.text_changed.connect(_on_source_changed)
	if tags_line_edit != null:
		tags_line_edit.text_changed.connect(_on_tags_changed)
	if beat_division_slider != null:
		beat_division_slider.value_changed.connect(_on_beat_division_slider_changed)
	if add_timing_button != null:
		add_timing_button.pressed.connect(_add_timing)

func _load_chart_data() -> void:
	if chart == null:
		return

	chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	if CM.selected_chart != null:
		EditorChartOps.load_selected_chart()
	_load_chart_stream()
	timeline.ensure_timings()

func _load_chart_stream() -> void:
	if audio_player == null:
		return

	_ensure_builtin_hitsounds()

	audio_player.stop()
	audio_player.stream = chart.get_stream() if chart != null else null
	transport_playing = false
	audio_started = false
	audio_start_target_usec = 0
	audio_start_position_sec = 0.0
	song_finished_usec = 0

	if chart != null and audio_player.stream != null:
		_stream_length_sec = audio_player.stream.get_length()
		_stream_length_msec = _stream_length_sec * 1000.0
	else:
		_stream_length_sec = 0.0
		_stream_length_msec = 0.0

	timeline = EditorTimeline.new(chart,_stream_length_sec)
	_rebuild_hitsound_cache()
	_rebuild_playback_notes()
	hitsounds_changed.emit()

func _refresh_metadata_fields() -> void:
	_syncing_metadata = true
	title_line_edit.text = chart.title
	artist_line_edit.text = chart.artist
	difficulty_line_edit.text = chart.difficulty
	source_line_edit.text = chart.source
	tags_line_edit.text = chart.tags
	_syncing_metadata = false

func _rebuild_timing_ui() -> void:
	timeline.ensure_timings()

	for item in timing_items:
		if item != null and item != timing_template:
			item.queue_free()
	timing_items.clear()

	for index in range(chart.timings.size()):
		var item: EditorTimingItem = timing_template as EditorTimingItem
		if index > 0:
			item = timing_scene.instantiate() as EditorTimingItem
			timing_list_container.add_child(item)

		item.bind(chart.timings[index])
		if not item.change_started.is_connected(_on_timing_item_change_started):
			item.change_started.connect(_on_timing_item_change_started)
		if not item.changed.is_connected(_on_timing_item_changed):
			item.changed.connect(_on_timing_item_changed)
		if not item.remove_requested.is_connected(_on_timing_remove_requested):
			item.remove_requested.connect(_on_timing_remove_requested)
		timing_items.append(item)

func _update_slider_range() -> void:
	if song_slider == null:
		return

	song_slider.min_value = timeline.get_min_time()
	song_slider.max_value = timeline.get_max_time()
	song_slider.step = 1.0
	_update_time_ui(true)

func _update_beat_division_ui() -> void:
	if beat_division_slider == null:
		return

	var divisions := _get_supported_beat_divisions()
	beat_division_slider.min_value = 0
	beat_division_slider.max_value = divisions.size() - 1
	beat_division_slider.step = 1

	var target_index := divisions.find(timeline.beat_division)
	if target_index == -1:
		target_index = divisions.find(4)
		if target_index == -1:
			target_index = 0

	timeline.beat_division = divisions[target_index]
	beat_division_slider.value = target_index
	beat_division_label.text = "1/%d" % timeline.beat_division

func _refresh_views() -> void:

	_clear_layers()
	rail_views.clear()
	note_views.clear()

	for rail: Rail in CM.rails:
		if rail == null:
			continue

		var rail_view: EditorRail = rail_scene.instantiate()
		rail_view.rail = rail
		rail_view.editor = self
		rail_layer.add_child(rail_view)
		rail_views[rail] = rail_view

		for note in rail.notes:
			if note == null:
				continue

			var note_view: EditorNote = note_scene.instantiate()
			note_view.note = note
			note_view.rail = rail
			note_view.editor = self
			note_view.set_passthrough(note_passthrough)
			note_layer.add_child(note_view)
			note_views[note] = note_view

	_rebuild_playback_notes()
	_view_layout_dirty = true
	_sync_view_layouts()

func _clear_layers() -> void:

	if rail_layer != null:
		for child in rail_layer.get_children():
			child.queue_free()
	if note_layer != null:
		for child in note_layer.get_children():
			child.queue_free()

func _sync_view_layouts() -> void:
	
	if chart_panel == null or note_pivot == null:
		return

	var panel_size := chart_panel.size
	var judge_y := note_pivot.position.y - chart_panel.position.y
	if rail_layer != null and rail_layer.size != panel_size:
		rail_layer.size = panel_size
	if note_layer != null and note_layer.size != panel_size:
		note_layer.size = panel_size
	var layout_changed := _view_layout_dirty
	layout_changed = layout_changed or panel_size != _last_panel_size
	layout_changed = layout_changed or not is_equal_approx(judge_y, _last_judge_y)
	layout_changed = layout_changed or not is_equal_approx(Game.current_time, _last_view_time)
	layout_changed = layout_changed or selection.selected_rail != _last_selection_rail
	layout_changed = layout_changed or selection.selected_note != _last_selection_note
	layout_changed = layout_changed or selection.selected_point_index != _last_selection_point_index
	layout_changed = layout_changed or note_passthrough != _last_note_passthrough
	if not layout_changed:
		return

	_last_panel_size = panel_size
	_last_judge_y = judge_y
	_last_view_time = Game.current_time
	_last_selection_rail = selection.selected_rail
	_last_selection_note = selection.selected_note
	_last_selection_point_index = selection.selected_point_index
	_last_note_passthrough = note_passthrough
	_view_layout_dirty = false

	for rail_view in rail_views.values():
		rail_view.sync_layout(panel_size, judge_y, PIXELS_PER_MS, Game.current_time)
		rail_view.set_selection_state(selection.selected_rail == rail_view.rail, selection.selected_point_index)

	for note in note_views.keys():
		var note_view: EditorNote = note_views[note]
		note_view.sync_layout(panel_size, judge_y, PIXELS_PER_MS, Game.current_time)
		note_view.set_selected(selection.selected_note == note)
	_update_time_ui(false)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not _is_mouse_inside_chart():
			return
		if Input.is_key_pressed(KEY_ALT):
			_adjust_selected_object(event.button_index == MOUSE_BUTTON_WHEEL_UP)
		else:
			var direction := 1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1
			_set_current_time(timeline.step_time(int(round(Game.current_time)), direction))
		get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not _is_mouse_inside_chart():
		return

	var mouse_position := get_global_mouse_position()
	if Input.is_key_pressed(KEY_SHIFT):
		var point_hit := _find_point_at(mouse_position)
		if not point_hit.is_empty():
			selection.select_point(point_hit["rail"], point_hit["point_index"])
			point_dragging = true
			_point_drag_history_pending = true
			get_viewport().set_input_as_handled()
			return

	if Input.is_key_pressed(KEY_CTRL) and selection.selected_rail != null:
		_add_point_at_mouse(mouse_position)
		get_viewport().set_input_as_handled()
		return

	var note_hit: Dictionary = {} if note_passthrough else _find_note_at(mouse_position)
	if not note_hit.is_empty():
		selection.select_note(note_hit["rail"], note_hit["note"])
		get_viewport().set_input_as_handled()
		return

	var rail_hit: Rail = _find_rail_at(mouse_position)
	if rail_hit != null:
		selection.select_rail(rail_hit)
		get_viewport().set_input_as_handled()
		return

	selection.clear()

func _handle_key_input(event: InputEventKey) -> void:
	if event.ctrl_pressed:
		if event.keycode == KEY_Z:
			if event.shift_pressed:
				_redo_history()
			else:
				_undo_history()
			return
		if event.keycode == KEY_Y:
			_redo_history()
			return

	match event.keycode:
		KEY_R:
			_create_rail()
		KEY_Z:
			_create_hit_note()
		KEY_X:
			_create_trace_note()
		KEY_C:
			_create_spike_note()
		KEY_A:
			_create_left_note()
		KEY_D:
			_create_right_note()
		KEY_DELETE:
			_delete_selected()
		KEY_SPACE:
			_toggle_song_playback()
		KEY_LEFT:
			_push_history_snapshot()
			EditorChartOps.move_rail(selection.selected_rail, -1.0)
			_view_layout_dirty = true
		KEY_RIGHT:
			_push_history_snapshot()
			EditorChartOps.move_rail(selection.selected_rail, 1.0)
			_view_layout_dirty = true
		_:
			return

func _set_current_time(value: float) -> void:
	Game.current_time = timeline.clamp_time(value)
	_update_time_ui(true)
	_view_layout_dirty = true
	if transport_playing:
		_restart_playback_from_current_time()

func _create_rail() -> void:
	_push_history_snapshot()
	var new_rail: Rail = EditorChartOps.create_default_rail(timeline.snap_time(int(round(Game.current_time))))
	CM.rails.append(new_rail)
	selection.select_rail(new_rail)
	_refresh_views()

func _create_hit_note() -> void:
	_create_note(Note.NoteType.HIT, Note.Dir.NONE)

func _create_trace_note() -> void:
	_create_note(Note.NoteType.TRACE, Note.Dir.NONE)

func _create_spike_note() -> void:
	_create_note(Note.NoteType.SPIKE, Note.Dir.NONE)

func _create_left_note() -> void:
	_create_note(Note.NoteType.MOVE, Note.Dir.LEFT)

func _create_right_note() -> void:
	_create_note(Note.NoteType.MOVE, Note.Dir.RIGHT)

func _create_note(note_type: Note.NoteType, dir: int) -> void:
	if selection.selected_rail == null:
		return

	_push_history_snapshot()
	var note_time: int = timeline.snap_time(int(round(Game.current_time)))
	var new_note: Note = EditorChartOps.create_note(note_type, note_time, dir)
	selection.selected_rail.notes.append(new_note)
	selection.selected_rail.sort_notes()
	selection.select_note(selection.selected_rail, new_note)
	_refresh_views()

func _delete_selected() -> void:
	if selection.selected_note == null and not selection.has_point() and selection.selected_rail == null:
		return
	_push_history_snapshot()
	if selection.selected_note != null and selection.selected_rail != null:
		EditorChartOps.remove_note(selection.selected_rail, selection.selected_note)
		selection.clear()
	elif selection.has_point():
		EditorChartOps.remove_point(selection.selected_rail, selection.selected_point_index)
		selection.clear()
	elif selection.selected_rail != null:
		EditorChartOps.remove_rail(selection.selected_rail)
		selection.clear()

	_refresh_views()

func _add_point_at_mouse(global_mouse_position: Vector2) -> void:
	_push_history_snapshot()
	var local_position := chart_panel.get_global_transform_with_canvas().affine_inverse() * global_mouse_position
	var point_time: int = int(timeline.snap_time(_local_y_to_time(local_position.y)))
	var point_x := _snap_point_x(local_position.x / max(1.0, chart_panel.size.x))
	var point_index := EditorChartOps.add_point(selection.selected_rail, point_time, point_x)
	selection.select_point(selection.selected_rail, point_index)
	_refresh_views()

func _adjust_selected_object(is_positive: bool) -> void:
	if selection.selected_note != null:
		_push_history_snapshot()
		var delta := 50 if is_positive else -50
		selection.selected_note.length = max(0, selection.selected_note.length + delta)
		_refresh_views()
		return

	if selection.has_point():
		_push_history_snapshot()
		var selected_point: RailPoint = selection.get_point()
		selected_point.curve = clamp(selected_point.curve + (0.1 if is_positive else -0.1), -1.0, 1.0)
		_refresh_views()

func _find_note_at(global_mouse_position: Vector2):
	for note in note_views.keys():
		var note_view: EditorNote = note_views[note]
		if note_view.is_head_hit(global_mouse_position):
			return {"note": note, "rail": note_view.rail}
	return {}

func _find_rail_at(global_mouse_position: Vector2) -> Rail:
	var closest_rail: Rail = null
	var closest_distance := INF

	for rail in rail_views.keys():
		var rail_view: EditorRail = rail_views[rail]
		var distance: float = rail_view.distance_to_curve(global_mouse_position)
		if distance < 14.0 and distance < closest_distance:
			closest_distance = distance
			closest_rail = rail

	return closest_rail

func _find_point_at(global_mouse_position: Vector2) -> Dictionary:
	var closest_rail: Rail = null
	var closest_point_index := -1
	var closest_distance := INF

	for rail in rail_views.keys():
		var rail_view: EditorRail = rail_views[rail]
		var point_index := rail_view.get_point_hit_index(global_mouse_position)
		if point_index == -1:
			continue

		var local_position := rail_view.get_global_transform_with_canvas().affine_inverse() * global_mouse_position
		var point_position := rail_view._point_to_panel(rail.points[point_index])
		var distance := point_position.distance_to(local_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_rail = rail
			closest_point_index = point_index

	if closest_rail == null:
		return {}

	return {"rail": closest_rail, "point_index": closest_point_index}

func _drag_selected_point(global_mouse_position: Vector2) -> void:
	var local_position := chart_panel.get_global_transform_with_canvas().affine_inverse() * global_mouse_position
	var point: RailPoint = selection.get_point()
	if point == null:
		return

	var next_x := _snap_point_x(local_position.x / max(1.0, chart_panel.size.x))
	var next_time := timeline.snap_time(_local_y_to_time(local_position.y))
	if is_equal_approx(point.x, next_x) and point.time == next_time:
		return
	if _point_drag_history_pending:
		_push_history_snapshot()
		_point_drag_history_pending = false

	point.x = next_x
	point.time = next_time
	selection.selected_rail.sort_points()
	selection.selected_point_index = selection.selected_rail.points.find(point)
	_refresh_views()

func _save_chart() -> void:
	if not EditorChartOps.can_save(chart):
		return

	if EditorChartOps.save_chart(chart, previous_file_path):
		previous_file_path = chart.file_path
		_update_save_button_state()

func _on_song_slider_value_changed(value: float) -> void:
	if _syncing_song_slider:
		return
	_set_current_time(value)

func _on_selection_changed() -> void:
	selection_changed.emit()
	_view_layout_dirty = true
	_sync_view_layouts()

func _on_title_changed(new_text: String) -> void:
	if _syncing_metadata:
		return
	chart.title = new_text
	_update_save_button_state()

func _on_artist_changed(new_text: String) -> void:
	if not _syncing_metadata:
		chart.artist = new_text

func _on_difficulty_changed(new_text: String) -> void:
	if _syncing_metadata:
		return

	if EditorChartOps.has_duplicate_difficulty(chart, new_text):
		_syncing_metadata = true
		chart.difficulty = ""
		difficulty_line_edit.text = ""
		_syncing_metadata = false
	else:
		chart.difficulty = new_text.strip_edges()

	_update_save_button_state()

func _on_source_changed(new_text: String) -> void:
	if not _syncing_metadata:
		chart.source = new_text

func _on_tags_changed(new_text: String) -> void:
	if not _syncing_metadata:
		chart.tags = new_text

func _on_beat_division_slider_changed(value: float) -> void:
	var divisions := _get_supported_beat_divisions()
	var index := clampi(int(round(value)), 0, divisions.size() - 1)
	if timeline.beat_division == divisions[index]:
		return
	_push_history_snapshot()
	timeline.beat_division = divisions[index]
	beat_division_label.text = "1/%d" % timeline.beat_division
	_refresh_views()

func _add_timing() -> void:
	_push_history_snapshot()
	var new_timing := Timing.new()
	new_timing.time = timeline.snap_time(int(round(Game.current_time)))
	new_timing.bpm = 120.0 if chart.timings.is_empty() else chart.timings[chart.timings.size() - 1].bpm
	chart.timings.append(new_timing)
	chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	_rebuild_timing_ui()
	_refresh_views()

func _on_timing_item_changed(_item: EditorTimingItem) -> void:
	chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	_rebuild_timing_ui()
	_refresh_views()

func _on_timing_item_change_started(_item: EditorTimingItem) -> void:
	_push_history_snapshot()

func _on_timing_remove_requested(item: EditorTimingItem) -> void:
	if chart.timings.size() <= 1:
		return

	_push_history_snapshot()
	chart.timings.erase(item.timing)
	_rebuild_timing_ui()
	_refresh_views()

func _update_save_button_state() -> void:
	if save_button != null:
		save_button.disabled = not EditorChartOps.can_save(chart)

func _get_supported_beat_divisions() -> Array[int]:
	return [1, 2, 3, 4, 6, 8, 12, 16]

func _is_mouse_inside_chart() -> bool:
	return chart_panel != null and chart_panel.get_global_rect().has_point(get_global_mouse_position())

func _is_text_input_focused() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit

func _local_y_to_time(local_y: float) -> int:
	var judge_y := note_pivot.position.y - chart_panel.position.y
	return int(round(Game.current_time - ((local_y - judge_y) / PIXELS_PER_MS)))

func _snap_point_x(value: float) -> float:
	return clamp(snapped(value, 0.1), 0.0, 1.0)

func _set_song_slider_value(value: float) -> void:
	if song_slider == null:
		return
	if is_equal_approx(song_slider.value, value):
		return
	_syncing_song_slider = true
	song_slider.value = value
	_syncing_song_slider = false

func _update_time_ui(force: bool) -> void:
	var now_usec := Time.get_ticks_usec()
	if not force and now_usec - _last_transport_ui_usec < TRANSPORT_UI_UPDATE_USEC:
		return
	_last_transport_ui_usec = now_usec
	_set_song_slider_value(Game.current_time)
	if current_time_label != null:
		var label_text := timeline.format_time_label(Game.current_time)
		if current_time_label.text != label_text:
			current_time_label.text = label_text

func _toggle_song_playback() -> void:
	if transport_playing:
		_pause_song_playback()
	else:
		_start_song_playback()

func _start_song_playback() -> void:
	if chart == null or audio_player.stream == null:
		return

	transport_playing = true
	_restart_playback_from_current_time()

func _pause_song_playback() -> void:
	if transport_playing:
		_update_transport()
	transport_playing = false
	if audio_player != null:
		audio_player.stop()
	audio_started = false
	audio_start_target_usec = 0
	song_finished_usec = 0

func _update_transport() -> void:
	if not transport_playing:
		return
	if chart == null or audio_player.stream == null:
		return

	var now_usec := Time.get_ticks_usec()
	var previous_time := Game.current_time
	
	if not audio_started:
		_maybe_start_audio(now_usec)
		Game.current_time = timeline.clamp_time(
			audio_start_position_sec * 1000.0
			+ float(now_usec - audio_start_target_usec) / 1000.0
		)
	elif song_finished_usec > 0:
		Game.current_time = timeline.clamp_time(
			_stream_length_msec + float(now_usec - song_finished_usec) / 1000.0
		)
	else:
		var playback_sec := audio_player.get_playback_position()
		# playback_sec += AudioServer.get_time_since_last_mix()
		playback_sec = clamp(playback_sec, 0.0, _stream_length_sec)
		Game.current_time = timeline.clamp_time(playback_sec * 1000.0)

		if playback_sec >= _stream_length_sec - 0.02 or not audio_player.playing:
			song_finished_usec = now_usec

	_play_note_sfx_between(previous_time, Game.current_time)
	_update_time_ui(false)

	if is_equal_approx(Game.current_time, timeline.get_max_time()):
		transport_playing = false
		if audio_player != null:
			audio_player.stop()
		audio_started = false
		audio_start_target_usec = 0
		song_finished_usec = 0

func _restart_playback_from_current_time() -> void:
	if chart == null or audio_player.stream == null:
		return

	if audio_player != null:
		audio_player.stop()

	var clamped_time := timeline.clamp_time(Game.current_time)
	audio_started = false
	song_finished_usec = 0
	_reset_playback_sfx_cursor(clamped_time)

	if clamped_time < 0.0:
		audio_start_position_sec = 0.0
		audio_start_target_usec = Time.get_ticks_usec() + int(-clamped_time * 1000.0)
		return

	if clamped_time >= _stream_length_msec:
		audio_start_position_sec = _stream_length_sec
		audio_started = true
		song_finished_usec = Time.get_ticks_usec() - int((clamped_time - _stream_length_msec) * 1000.0)
		return

	audio_start_position_sec = clamped_time / 1000.0
	audio_start_target_usec = Time.get_ticks_usec()
	_maybe_start_audio(Time.get_ticks_usec())

func _maybe_start_audio(now_usec: int) -> void:
	if audio_started or audio_player == null or audio_player.stream == null:
		return
	
	var startup_delay_sec := AudioServer.get_time_to_next_mix()
	var play_call_time_usec := audio_start_target_usec - int(startup_delay_sec * 1000000.0)
	if now_usec < play_call_time_usec:
		return

	audio_player.play(audio_start_position_sec)
	audio_started = true

func _rebuild_hitsound_cache() -> void:
	_ensure_builtin_hitsounds()
	_hitsound_streams.clear()
	for hitsound in CM.hitsounds:
		if hitsound == null or hitsound.stream == null:
			continue
		_hitsound_streams[hitsound.id] = hitsound.stream

func _rebuild_playback_notes() -> void:
	_playback_notes.clear()
	_playback_release_notes.clear()
	for rail in CM.rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null:
				_playback_notes.append(note)
				if int(note.length) > 0:
					_playback_release_notes.append(note)
	_playback_notes.sort_custom(func(a: Note, b: Note) -> bool: return a.time < b.time)
	_playback_release_notes.sort_custom(func(a: Note, b: Note) -> bool: return (a.time + a.length) < (b.time + b.length))
	_reset_playback_sfx_cursor(Game.current_time)

func _reset_playback_sfx_cursor(time_ms: float) -> void:
	_playback_note_index = 0
	while _playback_note_index < _playback_notes.size() and _playback_notes[_playback_note_index].time < time_ms:
		_playback_note_index += 1
	_last_sfx_time = time_ms - 0.001
	_playback_release_note_index = 0
	while _playback_release_note_index < _playback_release_notes.size() and (_playback_release_notes[_playback_release_note_index].time + _playback_release_notes[_playback_release_note_index].length) < time_ms:
		_playback_release_note_index += 1
	_last_release_sfx_time = time_ms - 0.001

func _play_note_sfx_between(from_time: float, to_time: float) -> void:
	if to_time < from_time:
		_reset_playback_sfx_cursor(to_time)
		return
	if _playback_notes.is_empty():
		return
	if from_time < _last_sfx_time:
		_reset_playback_sfx_cursor(from_time)
	while _playback_note_index < _playback_notes.size():
		var note := _playback_notes[_playback_note_index]
		if note.time > to_time:
			break
		if note.time > from_time:
			_play_note_sfx(note)
		_playback_note_index += 1
	_last_sfx_time = to_time
	_play_release_sfx_between(from_time, to_time)

func _play_note_sfx(note: Note) -> void:
	var stream := _resolve_note_sfx_stream(note)
	if stream == null or _sfx_players.is_empty():
		return
	var player := _sfx_players[_next_sfx_player_index]
	_next_sfx_player_index = (_next_sfx_player_index + 1) % _sfx_players.size()
	player.stream = stream
	player.play()

func _play_release_sfx_between(from_time: float, to_time: float) -> void:
	if _playback_release_notes.is_empty():
		return
	if from_time < _last_release_sfx_time:
		_reset_playback_sfx_cursor(from_time)
	while _playback_release_note_index < _playback_release_notes.size():
		var note := _playback_release_notes[_playback_release_note_index]
		var release_time := note.time + note.length
		if release_time > to_time:
			break
		if release_time > from_time:
			var stream := _resolve_long_release_sfx_stream()
			if stream != null:
				_play_stream_sfx(stream)
		_playback_release_note_index += 1
	_last_release_sfx_time = to_time

func _play_stream_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player := _sfx_players[_next_sfx_player_index]
	_next_sfx_player_index = (_next_sfx_player_index + 1) % _sfx_players.size()
	player.stream = stream
	player.play()

func _resolve_note_sfx_stream(note: Note) -> AudioStream:
	if note == null:
		return null
	var hitsound_id := int(note.hitsound)
	if hitsound_id < 0 and chart != null:
		hitsound_id = chart.get_default_hitsound_id(chart.get_default_hitsound_slot_for_note(note))
	if hitsound_id >= 0 and _hitsound_streams.has(hitsound_id):
		return _hitsound_streams[hitsound_id]
	if int(note.type) == int(Note.NoteType.MOVE):
		return DEFAULT_MOVE_SFX
	return DEFAULT_HIT_SFX

func _resolve_long_release_sfx_stream() -> AudioStream:
	if chart != null:
		var hitsound_id := chart.get_default_hitsound_id(Chart.DEFAULT_HITSOUND_LONGNOTE_RELEASE)
		if hitsound_id >= 0 and _hitsound_streams.has(hitsound_id):
			return _hitsound_streams[hitsound_id]
	return DEFAULT_HIT_SFX

func get_all_hitsounds() -> Array[HitSound]:
	_ensure_builtin_hitsounds()
	var result: Array[HitSound] = []
	for hitsound in CM.hitsounds:
		if hitsound != null:
			result.append(hitsound)
	result.sort_custom(func(a: HitSound, b: HitSound) -> bool: return a.id < b.id)
	return result

func get_custom_hitsounds() -> Array[HitSound]:
	var result: Array[HitSound] = []
	for hitsound in get_all_hitsounds():
		if hitsound != null and not hitsound.is_builtin():
			result.append(hitsound)
	return result

func get_default_hitsound_id(slot: int) -> int:
	if chart == null:
		return -1
	return chart.get_default_hitsound_id(slot)

func set_default_hitsound_id(slot: int, hitsound_id: int) -> void:
	if chart == null:
		return
	if chart.get_default_hitsound_id(slot) == hitsound_id:
		return
	_push_history_snapshot()
	chart.set_default_hitsound_id(slot, hitsound_id)
	_notify_hitsounds_changed()

func set_selected_note_hitsound_id(hitsound_id: int) -> void:
	if selection.selected_note == null:
		return
	if int(selection.selected_note.hitsound) == hitsound_id:
		return
	_push_history_snapshot()
	selection.selected_note.hitsound = hitsound_id
	_notify_hitsounds_changed()

func add_custom_hitsound_from_file(source_path: String) -> void:
	if chart == null or source_path.is_empty():
		return
	if source_path.get_extension().to_lower() != "wav":
		return
	_ensure_builtin_hitsounds()
	_push_history_snapshot()
	FileSystem.ensure_dir(chart.folder_path)
	var target_name := _make_unique_hitsound_file_name(source_path.get_file())
	var target_path := chart.folder_path.path_join(target_name)
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty():
		return
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_buffer(bytes)
	file.flush()
	var hitsound := HitSound.new()
	hitsound.setup(chart, _next_custom_hitsound_id(), target_name)
	CM.hitsounds.append(hitsound)
	_notify_hitsounds_changed()

func remove_custom_hitsound(hitsound_id: int) -> void:
	var target: HitSound = null
	for hitsound in CM.hitsounds:
		if hitsound != null and hitsound.id == hitsound_id:
			target = hitsound
			break
	if target == null or target.is_builtin():
		return
	_push_history_snapshot()
	CM.hitsounds.erase(target)
	if not target.file_path.is_empty() and FileAccess.file_exists(target.file_path):
		DirAccess.remove_absolute(target.file_path)
	for slot in range(Chart.DEFAULT_HITSOUND_SLOT_COUNT):
		if chart != null and chart.get_default_hitsound_id(slot) == hitsound_id:
			chart.set_default_hitsound_id(slot, -1)
	for rail in CM.rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null and int(note.hitsound) == hitsound_id:
				note.hitsound = -1
	_notify_hitsounds_changed()

func _notify_hitsounds_changed() -> void:
	_rebuild_hitsound_cache()
	hitsounds_changed.emit()
	selection_changed.emit()

func _ensure_builtin_hitsounds() -> void:
	var existing_ids: Dictionary = {}
	var existing_files: Dictionary = {}
	for hitsound in CM.hitsounds:
		if hitsound == null:
			continue
		existing_ids[hitsound.id] = true
		existing_files[hitsound.file_name] = true

	for builtin in HitSound.load_builtin_hitsounds():
		if builtin == null:
			continue
		if existing_ids.has(builtin.id) or existing_files.has(builtin.file_name):
			continue
		CM.hitsounds.append(builtin)

func _next_custom_hitsound_id() -> int:
	var next_id := 0
	for hitsound in CM.hitsounds:
		if hitsound != null:
			next_id = max(next_id, hitsound.id + 1)
	return next_id

func _make_unique_hitsound_file_name(file_name: String) -> String:
	var base_name := file_name.get_basename()
	var extension := file_name.get_extension().to_lower()
	var candidate := "%s.%s" % [base_name, extension]
	var index := 1
	while FileAccess.file_exists(chart.folder_path.path_join(candidate)):
		candidate = "%s_%d.%s" % [base_name, index, extension]
		index += 1
	return candidate

func push_history_snapshot() -> void:
	_push_history_snapshot()

func _push_history_snapshot() -> void:
	if _is_restoring_history:
		return
	var snapshot := EditorHistory.capture(self)
	if not _undo_stack.is_empty() and EditorHistory.same_snapshot(_undo_stack[_undo_stack.size() - 1], snapshot):
		return
	_undo_stack.append(snapshot)
	if _undo_stack.size() > MAX_HISTORY_STEPS:
		_undo_stack.remove_at(0)
	_redo_stack.clear()

func _undo_history() -> void:
	if _undo_stack.is_empty():
		return
	var current_snapshot := EditorHistory.capture(self)
	var target_snapshot = _undo_stack.pop_back()
	_redo_stack.append(current_snapshot)
	_restore_history_snapshot(target_snapshot)

func _redo_history() -> void:
	if _redo_stack.is_empty():
		return
	var current_snapshot := EditorHistory.capture(self)
	var target_snapshot = _redo_stack.pop_back()
	_undo_stack.append(current_snapshot)
	_restore_history_snapshot(target_snapshot)

func _restore_history_snapshot(snapshot: Dictionary) -> void:
	if transport_playing:
		_pause_song_playback()
	_is_restoring_history = true
	EditorHistory.restore(self, snapshot)
	_is_restoring_history = false

func get_pixels_per_ms() -> float:
	return PIXELS_PER_MS

func get_judge_y() -> float:
	return note_pivot.position.y - chart_panel.position.y
