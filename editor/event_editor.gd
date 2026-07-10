extends Control
class_name EventEditor

const MAP_EDITOR_SCENE_PATH := "res://scenes/editor/editor_scene.tscn"
const MAX_HISTORY_STEPS := 128
const UIFocusUtils = preload("res://global/ui_focus_utils.gd")

@export var chart_root: Control
@export var event_controller: EditorEventController
@export var back_button: Button
@export var save_button: Button
@export var play_button: Button
@export var chart_name_label: Label
@export var time_label: Label
@export var status_label: Label
@export var preview: Control

var chart: Chart = null
var timeline: EditorTimeline = null
var selection := ChartEditorSelection.new()
var transport := EditorTransport.new()

var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _restoring := false

func _ready() -> void:
	chart = CM.selected_chart
	if chart == null:
		Transition.return_to_menu(0.2)
		return
	_ensure_parsed_chart()
	_setup_transport()
	_connect_ui()
	if event_controller != null:
		event_controller.setup()
	if chart_name_label != null:
		chart_name_label.text = "%s  ·  %s" % [chart.title, chart.difficulty]
	_update_toolbar()
	UIFocusUtils.disable_focus_recursive(self)

func _process(_delta: float) -> void:
	transport.update()
	_update_toolbar()
	if preview != null:
		preview.queue_redraw()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.ctrl_pressed and event.keycode == KEY_Z:
		_undo_history()
		return
	if event.ctrl_pressed and event.keycode == KEY_Y:
		_redo_history()
		return
	match event.keycode:
		KEY_SPACE: transport.toggle()
		KEY_DELETE:
			if event_controller != null:
				event_controller.delete_selection()
		KEY_ESCAPE: _return_to_chart()

func _ensure_parsed_chart() -> void:
	if CM.parsed_chart != null and CM.parsed_chart.chart == chart:
		return
	var result := Parser.new().parse_object(chart)
	CM.parsed_chart = result.parsed_chart if result.success else ParsedChart.new(chart)

func _setup_transport() -> void:
	transport = EditorTransport.new()
	transport.name = "EventEditorTransport"
	add_child(transport)
	transport.setup()
	transport.chart = chart
	transport.load_stream()
	timeline = EditorTimeline.new(chart, transport.stream_length_sec)
	timeline.ensure_timings()
	transport.timeline = timeline

func _connect_ui() -> void:
	if back_button != null:
		back_button.pressed.connect(_return_to_chart)
	if save_button != null:
		save_button.pressed.connect(_save_chart)
	if play_button != null:
		play_button.pressed.connect(transport.toggle)

func _set_current_time(value: float) -> void:
	if timeline == null:
		return
	Game.current_time = timeline.clamp_time(value)
	if transport.playing:
		transport.seek()
	_update_toolbar()

func _push_history_snapshot() -> void:
	if _restoring or CM.parsed_chart == null:
		return
	var snapshot := _capture_snapshot()
	if not _undo_stack.is_empty() and EditorHistory.same_snapshot(_undo_stack.back(), snapshot):
		return
	_undo_stack.append(snapshot)
	if _undo_stack.size() > MAX_HISTORY_STEPS:
		_undo_stack.remove_at(0)
	_redo_stack.clear()

func _capture_snapshot() -> Dictionary:
	var event_index := -1
	if selection.selected_event != null:
		event_index = CM.parsed_chart.events.find(selection.selected_event)
	return {
		"events": EditorHistory.capture_events_data(CM.parsed_chart.events),
		"event_index": event_index,
		"frame_index": selection.selected_event_frame_index,
		"current_time": Game.current_time,
	}

func _undo_history() -> void:
	if _undo_stack.is_empty():
		return
	_redo_stack.append(_capture_snapshot())
	_restore_snapshot(_undo_stack.pop_back())

func _redo_history() -> void:
	if _redo_stack.is_empty():
		return
	_undo_stack.append(_capture_snapshot())
	_restore_snapshot(_redo_stack.pop_back())

func _restore_snapshot(snapshot: Dictionary) -> void:
	if transport.playing:
		transport.pause()
	_restoring = true
	CM.parsed_chart.events = EditorHistory.restore_events_data(snapshot.get("events", []))
	CM.parsed_chart.sort_events()
	var event_index := int(snapshot.get("event_index", -1))
	if event_index >= 0 and event_index < CM.parsed_chart.events.size():
		selection.select_event(CM.parsed_chart.events[event_index], int(snapshot.get("frame_index", -1)))
	else:
		selection.clear()
	Game.current_time = timeline.clamp_time(float(snapshot.get("current_time", Game.current_time)))
	_restoring = false
	if event_controller != null:
		event_controller.on_history_restored()

func _save_chart() -> void:
	if CM.parsed_chart == null:
		return
	CM.parsed_chart.chart = chart
	var success := ChartWriter.new().write_chart(CM.parsed_chart)
	if status_label != null:
		status_label.text = "Chart saved" if success else "Save failed"
		status_label.add_theme_color_override("font_color", Color("75d5a4") if success else Color("ff7c86"))

func _return_to_chart() -> void:
	if transport.playing:
		transport.pause()
	Game.reopen_editor_without_chart_reload = true
	Transition.transition_to(MAP_EDITOR_SCENE_PATH, 0.45)

func _update_toolbar() -> void:
	if play_button != null:
		play_button.text = "Pause" if transport.playing else "Play"
	if time_label != null and timeline != null:
		time_label.text = timeline.format_time_label(Game.current_time)
