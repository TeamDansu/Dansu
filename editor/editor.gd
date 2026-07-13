extends Control
class_name Editor

signal selection_changed()
signal hitsounds_changed()

const SkinEditorRouterScript = preload("res://skin/skin_editor_router.gd")
const EVENT_EDITOR_SCENE_PATH := "res://scenes/editor/event_editor_scene.tscn"
const PIXELS_PER_MS := 1
const TRANSPORT_UI_UPDATE_USEC := 33333
const MAX_HISTORY_STEPS := 128

@export var chart_root: Control
@export var chart_panel: Control
@export var note_pivot: Control
@export var bpm_lines: Control
@export var song_slider: HSlider
@export var current_time_label: Label
@export var back_button: Button
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
@export var skin_file_label: Label
@export var skin_browser_button: Button
@export var open_skin_editor_button: Button
@export var open_event_editor_button: Button
@export var view_controller: EditorViewController
@export var inspector_controller: EditorInspectorController
@export var save_controller: EditorSaveController
@export var edit_controller: EditorEditController

var timeline: EditorTimeline = null
var selection: ChartEditorSelection = ChartEditorSelection.new()
var chart: Chart = null
var previous_file_path := ""

var transport: EditorTransport = EditorTransport.new()
var hitsound_manager: EditorHitsoundManager = EditorHitsoundManager.new()

var point_dragging := false
var note_passthrough := false
var _syncing_song_slider := false
var _last_transport_ui_usec := 0

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _is_restoring_history := false
var _point_drag_history_pending := false
var _saved_snapshot: Dictionary = {}
var _unsaved_exit_dialog: ConfirmationDialog
var _pending_exit_target := ""

func _ready() -> void:
	if not Game.reopen_editor_without_chart_reload:
		Game.current_time = 0.0
	chart = _ensure_chart()
	previous_file_path = chart.file_path
	selection.changed.connect(_on_selection_changed)

	transport = EditorTransport.new()
	transport.name = "EditorTransport"
	add_child(transport)
	transport.setup()

	hitsound_manager = EditorHitsoundManager.new()
	hitsound_manager.changed.connect(_on_hitsounds_changed)

	_create_dialogs()
	_prepare_layers()
	_configure_chart_input()
	_load_chart_data()
	_connect_ui()
	_refresh_metadata_fields()
	_rebuild_timing_ui()
	_update_slider_range()
	_update_beat_division_ui()
	_refresh_views()
	_update_save_button_state()
	mark_saved_state()
	UIFocusUtils.disable_focus_recursive(self)

func _process(_delta: float) -> void:
	$VBoxContainer/Label.text = str(Engine.get_frames_per_second())
	transport.update()
	_update_time_ui(false)

	if point_dragging and selection.has_point() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_drag_selected_point(get_global_mouse_position())
	elif point_dragging:
		point_dragging = false

	var should_passthrough := Input.is_key_pressed(KEY_SHIFT)
	if note_passthrough != should_passthrough:
		note_passthrough = should_passthrough
		if view_controller != null:
			view_controller.set_note_passthrough(note_passthrough)

	_sync_view_layouts()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _unsaved_exit_dialog != null and _unsaved_exit_dialog.visible:
			return
		exit()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		point_dragging = false
		_point_drag_history_pending = false

	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _is_text_input_focused() and _is_mouse_inside_chart():
			UIFocusUtils.release_text_input_focus(get_viewport())
		if not _is_text_input_focused():
			_handle_mouse_button(event)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if not _is_text_input_focused():
			_handle_key_input(event)

func refresh_views() -> void:
	_refresh_views()

# Init helpers

func _ensure_chart() -> Chart:
	if CM.selected_chart != null:
		return CM.selected_chart
	var fallback := Chart.new()
	fallback.uuid = CM.generate_uuid()
	fallback.title = ""
	fallback.artist = ""
	fallback.difficulty = ""
	fallback.chart_set = CM.selected_chartset
	if fallback.chart_set != null:
		fallback.folder_name = fallback.chart_set.folder_name
	return fallback

func _prepare_layers() -> void:
	if view_controller != null:
		view_controller.prepare_layers()

func _configure_chart_input() -> void:
	if view_controller != null:
		view_controller.configure_chart_input()

func _load_chart_data() -> void:
	if chart == null:
		return
	chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	var skip_reload := Game.reopen_editor_without_chart_reload
	Game.reopen_editor_without_chart_reload = false
	if CM.selected_chart != null and not skip_reload:
		EditorChartOps.load_selected_chart()

	transport.chart = chart
	transport.load_stream()
	timeline = EditorTimeline.new(chart, transport.stream_length_sec)
	transport.timeline = timeline
	transport.hitsound_manager = hitsound_manager
	hitsound_manager.setup(chart, selection)

	timeline.ensure_timings()

func _connect_ui() -> void:
	if song_slider != null:
		song_slider.value_changed.connect(_on_song_slider_value_changed)
	if back_button != null:
		back_button.pressed.connect(exit)
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
	if skin_browser_button != null:
		skin_browser_button.pressed.connect(_on_skin_browser_pressed)
	if open_skin_editor_button != null:
		open_skin_editor_button.pressed.connect(_open_skin_editor)
	if open_event_editor_button != null:
		open_event_editor_button.pressed.connect(_open_event_editor)

func _create_dialogs() -> void:
	if inspector_controller != null:
		inspector_controller.create_dialogs()
	_create_unsaved_exit_dialog()

# — View —

func _refresh_views() -> void:
	if view_controller != null:
		view_controller.refresh_views()
	if bpm_lines != null:
		bpm_lines.queue_redraw()

func _clear_layers() -> void:
	if view_controller != null:
		view_controller.clear_layers()

func _sync_view_layouts() -> void:
	if view_controller != null:
		view_controller.sync_layouts()

# Input

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if edit_controller != null:
		edit_controller.handle_mouse_button(event)


func exit() -> void:
	_request_exit("menu")

func _handle_key_input(event: InputEventKey) -> void:
	if edit_controller != null:
		edit_controller.handle_key_input(event)

# Chart editing

func _set_current_time(value: float) -> void:
	if edit_controller != null:
		edit_controller.set_current_time(value)

func _create_rail() -> void:
	if edit_controller != null:
		edit_controller.create_rail()

func _create_hit_note() -> void:
	if edit_controller != null:
		edit_controller.create_hit_note()

func _create_trace_note() -> void:
	if edit_controller != null:
		edit_controller.create_trace_note()

func _create_spike_note() -> void:
	if edit_controller != null:
		edit_controller.create_spike_note()

func _create_left_note() -> void:
	if edit_controller != null:
		edit_controller.create_left_note()

func _create_right_note() -> void:
	if edit_controller != null:
		edit_controller.create_right_note()

func _create_note(note_type: Note.NoteType, dir: int) -> void:
	if edit_controller != null:
		edit_controller.create_note(note_type, dir)

func _delete_selected() -> void:
	if edit_controller != null:
		edit_controller.delete_selected()

func _add_point_at_mouse(global_mouse_pos: Vector2) -> void:
	if edit_controller != null:
		edit_controller.add_point_at_mouse(global_mouse_pos)

func _adjust_selected_object(is_positive: bool) -> void:
	if edit_controller != null:
		edit_controller.adjust_selected_object(is_positive)

# Hit testing 

func _find_note_at(global_mouse_pos: Vector2) -> Dictionary:
	return view_controller.find_note_at(global_mouse_pos) if view_controller != null else {}

func _find_rail_at(global_mouse_pos: Vector2) -> Rail:
	return view_controller.find_rail_at(global_mouse_pos) if view_controller != null else null

func _find_point_at(global_mouse_pos: Vector2) -> Dictionary:
	return view_controller.find_point_at(global_mouse_pos) if view_controller != null else {}

func _drag_selected_point(global_mouse_pos: Vector2) -> void:
	if view_controller != null:
		view_controller.drag_selected_point(global_mouse_pos)

# Save

func _save_chart() -> bool:
	if save_controller != null:
		return save_controller.save_chart()
	return false

func _open_skin_editor() -> void:
	if chart == null:
		return
	if _has_unsaved_changes():
		_request_exit("skin")
		return
	_open_skin_editor_now()

func _open_skin_editor_now() -> void:
	CM.selected_chart = chart
	SkinEditorRouterScript.open_chart_skin_editor(chart)

func open_new_chart_skin_editor() -> void:
	if chart == null:
		return
	if _has_unsaved_changes():
		_request_exit("new_skin")
		return
	_open_new_chart_skin_editor_now()

func _open_new_chart_skin_editor_now() -> void:
	CM.selected_chart = chart
	SkinEditorRouterScript.open_new_chart_skin_editor(chart)

func _open_event_editor() -> void:
	if chart == null:
		return
	CM.selected_chart = chart
	Game.reopen_editor_without_chart_reload = true
	Transition.transition_to(EVENT_EDITOR_SCENE_PATH, 0.45)

func _on_skin_browser_pressed() -> void:
	if inspector_controller != null:
		inspector_controller.open_skin_browser()

# UI state

func _refresh_metadata_fields() -> void:
	if inspector_controller != null:
		inspector_controller.refresh_metadata_fields()

func _update_skin_file_ui() -> void:
	if inspector_controller != null:
		inspector_controller.update_skin_file_ui()

func _rebuild_timing_ui() -> void:
	if inspector_controller != null:
		inspector_controller.rebuild_timing_ui()

func _update_slider_range() -> void:
	if song_slider == null:
		return
	song_slider.min_value = timeline.get_min_time()
	song_slider.max_value = timeline.get_max_time()
	song_slider.step = 1.0
	_update_time_ui(true)

func _update_beat_division_ui() -> void:
	if inspector_controller != null:
		inspector_controller.update_beat_division_ui()

func _update_save_button_state() -> void:
	if save_controller != null:
		save_controller.update_save_button_state()

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

func _set_song_slider_value(value: float) -> void:
	if song_slider == null or is_equal_approx(song_slider.value, value):
		return
	_syncing_song_slider = true
	song_slider.value = value
	_syncing_song_slider = false

# UI event handlers

func _on_selection_changed() -> void:
	selection_changed.emit()
	if view_controller != null:
		view_controller.mark_layout_dirty()
	_sync_view_layouts()

func _on_hitsounds_changed() -> void:
	hitsounds_changed.emit()
	selection_changed.emit()

func _on_song_slider_value_changed(value: float) -> void:
	if not _syncing_song_slider:
		_set_current_time(value)

func _on_title_changed(new_text: String) -> void:
	if inspector_controller != null:
		inspector_controller.on_title_changed(new_text)

func _on_artist_changed(new_text: String) -> void:
	if inspector_controller != null:
		inspector_controller.on_artist_changed(new_text)

func _on_difficulty_changed(new_text: String) -> void:
	if inspector_controller != null:
		inspector_controller.on_difficulty_changed(new_text)

func _on_source_changed(new_text: String) -> void:
	if inspector_controller != null:
		inspector_controller.on_source_changed(new_text)

func _on_tags_changed(new_text: String) -> void:
	if inspector_controller != null:
		inspector_controller.on_tags_changed(new_text)

func _on_beat_division_slider_changed(value: float) -> void:
	if inspector_controller != null:
		inspector_controller.on_beat_division_slider_changed(value)

func _add_timing() -> void:
	if inspector_controller != null:
		inspector_controller.add_timing()

func _on_timing_item_change_started(_item: EditorTimingItem) -> void:
	if inspector_controller != null:
		inspector_controller.on_timing_item_change_started(_item)

func _on_timing_item_changed(_item: EditorTimingItem) -> void:
	if inspector_controller != null:
		inspector_controller.on_timing_item_changed(_item)

func _on_timing_remove_requested(item: EditorTimingItem) -> void:
	if inspector_controller != null:
		inspector_controller.on_timing_remove_requested(item)

# History

func push_history_snapshot() -> void:
	_push_history_snapshot()

func _push_history_snapshot() -> void:
	if _is_restoring_history:
		return
	var snapshot := EditorHistory.capture(self)
	if not _undo_stack.is_empty() and EditorHistory.same_snapshot(_undo_stack.back(), snapshot):
		return
	_undo_stack.append(snapshot)
	if _undo_stack.size() > MAX_HISTORY_STEPS:
		_undo_stack.remove_at(0)
	_redo_stack.clear()

func _undo_history() -> void:
	if _undo_stack.is_empty():
		return
	var current := EditorHistory.capture(self)
	_redo_stack.append(current)
	_restore_history_snapshot(_undo_stack.pop_back())

func _redo_history() -> void:
	if _redo_stack.is_empty():
		return
	var current := EditorHistory.capture(self)
	_undo_stack.append(current)
	_restore_history_snapshot(_redo_stack.pop_back())

func _restore_history_snapshot(snapshot: Dictionary) -> void:
	if transport.playing:
		transport.pause()
	_is_restoring_history = true
	EditorHistory.restore(self, snapshot)
	_is_restoring_history = false

# Unsaved changes

func mark_saved_state() -> void:
	_saved_snapshot = _capture_saved_state()

func _has_unsaved_changes() -> bool:
	if _saved_snapshot.is_empty():
		return false
	return not EditorHistory.same_snapshot(_saved_snapshot, _capture_saved_state())

func _capture_saved_state() -> Dictionary:
	var snapshot := EditorHistory.capture(self)
	snapshot.erase("selection")
	snapshot.erase("current_time")
	snapshot.erase("beat_division")
	return snapshot

func _create_unsaved_exit_dialog() -> void:
	_unsaved_exit_dialog = ConfirmationDialog.new()
	_unsaved_exit_dialog.title = "Unsaved changes"
	_unsaved_exit_dialog.dialog_text = "Save chart changes before leaving?"
	_unsaved_exit_dialog.ok_button_text = "Save and leave"
	_unsaved_exit_dialog.cancel_button_text = "Cancel"
	_unsaved_exit_dialog.exclusive = true
	_unsaved_exit_dialog.confirmed.connect(_on_unsaved_exit_save_confirmed)
	_unsaved_exit_dialog.custom_action.connect(_on_unsaved_exit_custom_action)
	_unsaved_exit_dialog.add_button("Leave without saving", false, "discard")
	add_child(_unsaved_exit_dialog)

func _request_exit(target: String) -> void:
	if _has_unsaved_changes():
		_show_unsaved_exit_dialog(target)
		return
	_transition_to_pending_target(target)

func _show_unsaved_exit_dialog(target: String) -> void:
	_pending_exit_target = target
	if _unsaved_exit_dialog == null:
		_transition_to_pending_target(target)
		return
	_unsaved_exit_dialog.get_ok_button().disabled = not EditorChartOps.can_save(chart)
	_unsaved_exit_dialog.popup_centered()

func _on_unsaved_exit_save_confirmed() -> void:
	if _save_chart():
		_transition_to_pending_target(_pending_exit_target)

func _on_unsaved_exit_custom_action(action: StringName) -> void:
	if action == &"discard":
		_transition_to_pending_target(_pending_exit_target)

func _transition_to_pending_target(target: String) -> void:
	match target:
		"new_skin":
			_open_new_chart_skin_editor_now()
		"skin":
			_open_skin_editor_now()
		_:
			Transition.return_to_menu(1)

# Hitsound public API

func get_all_hitsounds() -> Array[HitSound]:
	return hitsound_manager.get_all_hitsounds()

func get_custom_hitsounds() -> Array[HitSound]:
	return hitsound_manager.get_custom_hitsounds()

func get_default_hitsound_id(slot: int) -> int:
	return hitsound_manager.get_default_hitsound_id(slot)

func set_default_hitsound_id(slot: int, hitsound_id: int) -> void:
	if hitsound_manager.get_default_hitsound_id(slot) == hitsound_id:
		return
	_push_history_snapshot()
	hitsound_manager.set_default_hitsound_id(slot, hitsound_id)

func set_selected_note_hitsound_id(hitsound_id: int) -> void:
	if selection.selected_note == null or int(selection.selected_note.hitsound) == hitsound_id:
		return
	_push_history_snapshot()
	hitsound_manager.set_selected_note_hitsound_id(hitsound_id)

func add_custom_hitsound_from_file(source_path: String) -> void:
	_push_history_snapshot()
	hitsound_manager.add_custom_hitsound_from_file(source_path)

func remove_custom_hitsound(hitsound_id: int) -> void:
	_push_history_snapshot()
	hitsound_manager.remove_custom_hitsound(hitsound_id)

# Utilities

func get_pixels_per_ms() -> float:
	return PIXELS_PER_MS

func get_judge_y() -> float:
	return note_pivot.position.y - chart_panel.position.y

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
