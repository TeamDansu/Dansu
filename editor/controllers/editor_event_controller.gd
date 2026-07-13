extends Node
class_name EditorEventController

const UIFocusUtils = preload("res://global/ui_focus_utils.gd")
const CURRENT_TIME_SENTINEL := -9223372036854775807
const EASE_OPTIONS := [
	"", "linear",
	"in_sine", "out_sine", "in_out_sine",
	"in_quad", "out_quad", "in_out_quad",
	"in_cubic", "out_cubic", "in_out_cubic",
	"in_back", "out_back", "in_out_back",
]
const OVERLAY_LANE_START := 3
const FIXED_LANE_NAMES := ["CAMERA", "THEME", "SKIN"]
const CAMERA_COLOR := Color("46b8ff")
const THEME_COLOR := Color("5ed39a")
const SKIN_COLOR := Color("ef6f8f")
const OVERLAY_COLOR := Color("ffb547")
const SPRITE_IMPORT_FILTERS : Array = ["*.png,*.jpg,*.jpeg,*.webp,*.svg ; Image Files"]

@export var editor: Node
@export var event_dock: Control
@export var timeline_view: EditorEventTimeline
@export var add_overlay_button: Button
@export var zoom_slider: HSlider
@export var follow_button: Button
@export var collapse_button: Button
@export var inspector_content: VBoxContainer
@export var expanded_dock_top := 0.695
@export var collapsed_dock_top := 0.895
@export var expanded_stage_bottom := 0.68
@export var collapsed_stage_bottom := 0.88

var _setup_complete := false
var _syncing := false
var _collapsed := false
var _overlay_layer_count := 1
var _active_overlay_layer := 0
var _resource_import_dialog: FileDialog
var _pending_resource_kind := ""
var _pending_resource_event: ChartEvent = null
var _pending_resource_frame: ChartEventFrame = null

func setup() -> void:
	if _setup_complete or editor == null:
		return
	_setup_complete = true
	_create_resource_import_dialog()
	if timeline_view != null:
		timeline_view.controller = self
	if add_overlay_button != null:
		add_overlay_button.pressed.connect(add_overlay_layer)
	if zoom_slider != null:
		zoom_slider.value_changed.connect(_on_zoom_changed)
	if follow_button != null:
		follow_button.toggled.connect(_on_follow_toggled)
	if collapse_button != null:
		collapse_button.pressed.connect(_toggle_collapsed)
	editor.selection.changed.connect(_on_selection_changed)
	_sync_overlay_layers_from_events()
	_apply_dock_layout()
	refresh_inspector()
	refresh_timeline()

func get_events() -> Array[ChartEvent]:
	if CM.parsed_chart == null:
		return []
	return CM.parsed_chart.events

func get_frames(event: ChartEvent) -> Array:
	if event is CameraEvent:
		return (event as CameraEvent).frames
	if event is OverlayEvent:
		return (event as OverlayEvent).frames
	if event is ThemeEvent:
		return (event as ThemeEvent).frames
	return []

func get_event_lane(event: ChartEvent) -> int:
	if event is CameraEvent:
		return 0
	if event is ThemeEvent:
		return 1
	if event is SkinEvent:
		return 2
	if event is OverlayEvent:
		return OVERLAY_LANE_START + maxi(0, (event as OverlayEvent).layer)
	return -1

func get_lane_count() -> int:
	return OVERLAY_LANE_START + _overlay_layer_count

func get_lane_name(lane: int) -> String:
	if lane >= 0 and lane < FIXED_LANE_NAMES.size():
		return FIXED_LANE_NAMES[lane]
	if lane >= OVERLAY_LANE_START:
		return "OVERLAY %d" % (lane - OVERLAY_LANE_START + 1)
	return ""

func get_lane_color(lane: int) -> Color:
	match lane:
		0:
			return CAMERA_COLOR
		1:
			return THEME_COLOR
		2:
			return SKIN_COLOR
		_:
			var layer := maxi(0, lane - OVERLAY_LANE_START)
			return OVERLAY_COLOR.lightened(minf(0.2, layer * 0.035))

func is_overlay_lane(lane: int) -> bool:
	return lane >= OVERLAY_LANE_START and lane < get_lane_count()

func is_active_overlay_lane(lane: int) -> bool:
	return lane == OVERLAY_LANE_START + _active_overlay_layer

func select_overlay_lane(lane: int, clear_event_selection: bool = true) -> void:
	if not is_overlay_lane(lane):
		return
	_active_overlay_layer = lane - OVERLAY_LANE_START
	if clear_event_selection and editor != null:
		editor.selection.clear()
	if timeline_view != null:
		timeline_view.ensure_lane_visible(lane)
	refresh_timeline()

func add_overlay_layer() -> void:
	_overlay_layer_count += 1
	select_overlay_lane(get_lane_count() - 1)

func create_overlay_event(requested_time: int = CURRENT_TIME_SENTINEL) -> void:
	create_event_for_lane(OVERLAY_LANE_START + _active_overlay_layer, requested_time)

func create_event_for_lane(lane: int, requested_time: int = CURRENT_TIME_SENTINEL) -> void:
	if editor == null or editor.timeline == null or lane < 0 or lane >= get_lane_count():
		return
	var raw_time := int(round(Game.current_time)) if requested_time == CURRENT_TIME_SENTINEL else requested_time
	var start_time: int = editor.timeline.snap_time(raw_time)
	var duration := maxi(250, int(round(editor.timeline.get_snap_interval_ms(start_time) * 4.0)))
	var event: ChartEvent = null
	match lane:
		0:
			var camera := CameraEvent.new()
			camera.frames.append(_create_default_frame(camera))
			event = camera
		1:
			var theme := ThemeEvent.new()
			theme.frames.append(_create_default_frame(theme))
			event = theme
		2:
			var skin := SkinEvent.new()
			skin.duration = 0
			event = skin
		_:
			var overlay := OverlayEvent.new()
			overlay.layer = lane - OVERLAY_LANE_START
			overlay.frames.append(_create_default_frame(overlay))
			event = overlay
	if event == null:
		return

	editor._push_history_snapshot()
	event.time = start_time
	event.duration = 0 if event is SkinEvent else duration
	event.id = _make_unique_id(_get_event_type_name(event).to_lower())
	CM.ensure_parsed_chart().events.append(event)
	CM.parsed_chart.sort_events()
	select_event(event, 0 if not get_frames(event).is_empty() else -1)
	refresh_timeline()

func select_event(event: ChartEvent, frame_index: int = -1, switch_tab: bool = true) -> void:
	if editor == null:
		return
	if event is OverlayEvent:
		_active_overlay_layer = maxi(0, (event as OverlayEvent).layer)
		_overlay_layer_count = maxi(_overlay_layer_count, _active_overlay_layer + 1)
	var frames := get_frames(event)
	var safe_index := frame_index
	if safe_index < 0 or safe_index >= frames.size():
		safe_index = -1
	editor.selection.select_event(event, safe_index)

func move_event_to_time(event: ChartEvent, requested_time: int) -> void:
	if event == null or editor == null or editor.timeline == null:
		return
	var snapped_time: int = editor.timeline.snap_time(requested_time)
	var max_start: int = editor.timeline.get_max_time() - event.duration
	event.time = clampi(snapped_time, editor.timeline.get_min_time(), maxi(editor.timeline.get_min_time(), max_start))
	CM.ensure_parsed_chart().sort_events()
	refresh_timeline()

func move_frame_to_absolute_time(event: ChartEvent, frame: ChartEventFrame, requested_time: int) -> void:
	if event == null or frame == null or editor == null or editor.timeline == null:
		return
	var snapped_absolute: int = editor.timeline.snap_time(requested_time)
	frame.time = clampi(snapped_absolute - event.time, 0, maxi(0, event.duration))
	event.sort_frames()
	editor.selection.selected_event = event
	editor.selection.selected_event_frame_index = get_frames(event).find(frame)
	refresh_timeline()

func resize_event_to_end(event: ChartEvent, requested_end_time: int) -> void:
	if event == null or event is SkinEvent or editor == null or editor.timeline == null:
		return
	var snapped_end: int = editor.timeline.snap_time(requested_end_time)
	event.duration = clampi(snapped_end - event.time, 0, editor.timeline.get_max_time() - event.time)
	var selected_frame := _get_selected_frame()
	for frame in get_frames(event):
		frame.time = mini(frame.time, event.duration)
	_mark_changed(event, selected_frame)

func add_frame() -> void:
	add_frame_to_event(_get_selected_event())

func add_frame_to_event(event: ChartEvent, requested_absolute_time: int = CURRENT_TIME_SENTINEL) -> void:
	if event == null or event is SkinEvent or editor == null or editor.timeline == null:
		return
	var frames := get_frames(event)
	var raw_time := int(round(Game.current_time)) if requested_absolute_time == CURRENT_TIME_SENTINEL else requested_absolute_time
	var target_time := clampi(editor.timeline.snap_time(raw_time) - event.time, 0, event.duration)
	var source: ChartEventFrame = null
	if _get_selected_event() == event:
		source = _get_selected_frame()
	if source == null and not frames.is_empty():
		source = frames[0]
	var frame := _clone_frame(source, event) if source != null else _create_default_frame(event)
	frame.time = target_time
	editor._push_history_snapshot()
	frames.append(frame)
	event.sort_frames()
	select_event(event, get_frames(event).find(frame))
	refresh_timeline()

func duplicate_frame() -> void:
	var event := _get_selected_event()
	var source := _get_selected_frame()
	if event == null or source == null:
		return
	var frame := _clone_frame(source, event)
	var step := int(round(editor.timeline.get_snap_interval_ms(event.time + source.time)))
	frame.time = clampi(source.time + maxi(1, step), 0, event.duration)
	editor._push_history_snapshot()
	get_frames(event).append(frame)
	event.sort_frames()
	select_event(event, get_frames(event).find(frame))
	refresh_timeline()

func delete_selection() -> bool:
	var event := _get_selected_event()
	if event == null:
		return false
	var frame := _get_selected_frame()
	editor._push_history_snapshot()
	if frame != null:
		get_frames(event).erase(frame)
		select_event(event)
	else:
		CM.ensure_parsed_chart().events.erase(event)
		editor.selection.clear()
	refresh_timeline()
	refresh_inspector()
	return true

func refresh_timeline() -> void:
	if timeline_view != null:
		timeline_view.queue_redraw()

func refresh_inspector() -> void:
	if inspector_content == null:
		return
	_syncing = true
	for child in inspector_content.get_children():
		child.queue_free()

	var event := _get_selected_event()
	if event == null:
		_add_title("EVENTS")
		UIFocusUtils.disable_focus_recursive(inspector_content)
		_syncing = false
		return

	var lane := get_event_lane(event)
	_add_title("%s EVENT" % _get_event_type_name(event).to_upper())
	_add_readonly_badge("CLIP" if not event is SkinEvent else "TRIGGER", get_lane_color(lane))
	_add_line_row("ID", event.id, _on_event_id_committed.bind(event))
	_add_number_row("Start (ms)", event.time, editor.timeline.get_min_time(), editor.timeline.get_max_time(), 1.0, _on_event_time_changed.bind(event))
	if not event is SkinEvent:
		_add_number_row("Duration", event.duration, 0.0, editor.timeline.get_max_time(), 1.0, _on_event_duration_changed.bind(event))
	if event is OverlayEvent:
		_add_number_row("Layer", (event as OverlayEvent).layer, 0.0, 1000.0, 1.0, _on_overlay_layer_changed.bind(event as OverlayEvent))
		_add_overlay_anchor_row((event as OverlayEvent).anchor, _on_overlay_anchor_changed.bind(event as OverlayEvent))

	if event is SkinEvent:
		_add_separator("RESOURCE")
		_add_resource_row("Skin JSON", (event as SkinEvent).skin_json, "skin", event, null)
		_add_resource_folder_button()
		_add_destructive_button("Delete skin trigger", _delete_event.bind(event))
		UIFocusUtils.disable_focus_recursive(inspector_content)
		_syncing = false
		return

	_add_separator("KEYFRAMES")
	_add_frame_toolbar(event)
	var frame := _get_selected_frame()
	if frame != null:
		_add_number_row("Offset (ms)", frame.time, 0.0, event.duration, 1.0, _on_frame_time_changed.bind(event, frame))
		if frame is CameraEventFrame:
			_build_camera_frame_inspector(event as CameraEvent, frame as CameraEventFrame)
		elif frame is OverlayEventFrame:
			_build_overlay_frame_inspector(event as OverlayEvent, frame as OverlayEventFrame)
		elif frame is ThemeEventFrame:
			_build_theme_frame_inspector(event as ThemeEvent, frame as ThemeEventFrame)
	_add_separator("CLIP")
	_add_destructive_button("Delete event", _delete_event.bind(event))
	UIFocusUtils.disable_focus_recursive(inspector_content)
	_syncing = false

func on_history_restored() -> void:
	_sync_overlay_layers_from_events()
	refresh_inspector()
	refresh_timeline()

func sync_zoom_control(value: float) -> void:
	if zoom_slider == null or is_equal_approx(zoom_slider.value, value):
		return
	_syncing = true
	zoom_slider.value = value
	_syncing = false

func _build_camera_frame_inspector(event: CameraEvent, frame: CameraEventFrame) -> void:
	_add_separator("CAMERA")
	_add_check_row("Follow character", frame.follow_character, _on_camera_follow_changed.bind(event, frame))
	_add_number_row("Position X", frame.position.x, -10000.0, 10000.0, 1.0, _on_camera_vector_changed.bind(event, frame, true))
	_add_number_row("Position Y", frame.position.y, -10000.0, 10000.0, 1.0, _on_camera_vector_changed.bind(event, frame, false))
	_add_number_row("Zoom", frame.zoom, 0.01, 20.0, 0.01, _on_camera_zoom_changed.bind(event, frame))
	_add_ease_row(frame.ease, _on_frame_ease_changed.bind(event, frame))

func _build_overlay_frame_inspector(event: OverlayEvent, frame: OverlayEventFrame) -> void:
	_add_separator("OVERLAY")
	_add_resource_row("Sprite", frame.sprite, "sprite", event, frame)
	_add_number_row("Position X", frame.position.x, -10000.0, 10000.0, 1.0, _on_overlay_position_changed.bind(event, frame, true))
	_add_number_row("Position Y", frame.position.y, -10000.0, 10000.0, 1.0, _on_overlay_position_changed.bind(event, frame, false))
	_add_number_row("Scale X", frame.scale.x, -20.0, 20.0, 0.01, _on_overlay_scale_changed.bind(event, frame, true))
	_add_number_row("Scale Y", frame.scale.y, -20.0, 20.0, 0.01, _on_overlay_scale_changed.bind(event, frame, false))
	_add_number_row("Rotation", frame.rotation, -3600.0, 3600.0, 0.1, _on_overlay_rotation_changed.bind(event, frame))
	_add_check_row("Override opacity", frame.has_opacity, _on_overlay_opacity_enabled.bind(event, frame))
	if frame.has_opacity:
		_add_number_row("Opacity", frame.opacity, 0.0, 1.0, 0.01, _on_overlay_opacity_changed.bind(event, frame))
	_add_ease_row(frame.ease, _on_frame_ease_changed.bind(event, frame))
	_add_resource_folder_button()

func _build_theme_frame_inspector(event: ThemeEvent, frame: ThemeEventFrame) -> void:
	_add_separator("THEME")
	_add_color_row("Background A", frame.bg_color, _on_theme_color_changed.bind(event, frame, 0))
	_add_color_row("Background B", frame.bg_color_2, _on_theme_color_changed.bind(event, frame, 1))
	_add_color_row("Rail", frame.rail_color, _on_theme_color_changed.bind(event, frame, 2))
	_add_ease_row(frame.ease, _on_frame_ease_changed.bind(event, frame))

func _add_frame_toolbar(event: ChartEvent) -> void:
	var frames := get_frames(event)
	var row := HBoxContainer.new()
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_item("No frame selected", -1)
	for index in range(frames.size()):
		selector.add_item("%02d  +%d ms" % [index + 1, int(frames[index].time)], index)
	selector.select(editor.selection.selected_event_frame_index + 1)
	selector.item_selected.connect(_on_frame_selector_changed.bind(event, selector))
	var add_button := Button.new()
	add_button.text = "+"
	add_button.pressed.connect(add_frame)
	var duplicate_button := Button.new()
	duplicate_button.text = "Duplicate"
	duplicate_button.disabled = _get_selected_frame() == null
	duplicate_button.pressed.connect(duplicate_frame)
	var delete_button := Button.new()
	delete_button.text = "−"
	delete_button.disabled = _get_selected_frame() == null
	delete_button.pressed.connect(_delete_selected_frame)
	row.add_child(selector)
	row.add_child(add_button)
	row.add_child(duplicate_button)
	row.add_child(delete_button)
	inspector_content.add_child(row)

func _add_title(text_value: String) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("edf2fa"))
	inspector_content.add_child(label)

func _add_readonly_badge(text_value: String, color: Color) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 11)
	inspector_content.add_child(label)

func _add_separator(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color("768296"))
	inspector_content.add_child(label)
	inspector_content.add_child(HSeparator.new())

func _add_line_row(label_text: String, value: String, callback: Callable) -> void:
	var row := _make_row(label_text)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(text: String) -> void: callback.call(text))
	edit.focus_exited.connect(func() -> void: callback.call(edit.text))
	row.add_child(edit)

func _add_number_row(label_text: String, value: float, min_value: float, max_value: float, step: float, callback: Callable) -> void:
	var row := _make_row(label_text)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(next_value: float) -> void: callback.call(next_value))
	row.add_child(spin)

func _add_check_row(label_text: String, value: bool, callback: Callable) -> void:
	var row := _make_row(label_text)
	var check := CheckBox.new()
	check.button_pressed = value
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check.toggled.connect(func(enabled: bool) -> void: callback.call(enabled))
	row.add_child(check)

func _add_color_row(label_text: String, value: Color, callback: Callable) -> void:
	var row := _make_row(label_text)
	var picker := ColorPickerButton.new()
	picker.color = value
	picker.edit_alpha = true
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.color_changed.connect(func(next_color: Color) -> void: callback.call(next_color))
	row.add_child(picker)

func _add_ease_row(value: String, callback: Callable) -> void:
	var row := _make_row("Ease")
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var values := EASE_OPTIONS.duplicate()
	if not value.is_empty() and not values.has(value):
		values.append(value)
	for ease_name in values:
		option.add_item("Default (linear)" if ease_name.is_empty() else ease_name)
	option.select(maxi(0, values.find(value)))
	option.item_selected.connect(func(index: int) -> void: callback.call(values[index]))
	row.add_child(option)

func _add_overlay_anchor_row(value: String, callback: Callable) -> void:
	var row := _make_row("Anchor")
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in OverlayEventFrame.ANCHOR_PRESETS:
		option.add_item(preset.replace("_", " ").capitalize())
	option.select(maxi(0, OverlayEventFrame.ANCHOR_PRESETS.find(value)))
	option.item_selected.connect(func(index: int) -> void: callback.call(OverlayEventFrame.ANCHOR_PRESETS[index]))
	row.add_child(option)

func _add_resource_row(label_text: String, current: String, kind: String, event: ChartEvent, frame: ChartEventFrame) -> void:
	var row := _make_row(label_text)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var references := _get_resource_references(kind)
	if current.is_empty():
		references.insert(0, "")
	elif not references.has(current):
		references.insert(0, current)
	for reference in references:
		option.add_item("<none>" if reference.is_empty() else reference)
	option.select(maxi(0, references.find(current)))
	option.item_selected.connect(_on_resource_selected.bind(references, event, frame, kind))
	row.add_child(option)
	if _can_import_resource(kind):
		var import_button := Button.new()
		import_button.text = "Import"
		import_button.pressed.connect(_open_resource_import_dialog.bind(kind, event, frame))
		row.add_child(import_button)

func _add_resource_folder_button() -> void:
	var button := Button.new()
	button.text = "Open eventres folder"
	button.pressed.connect(_open_event_resource_folder)
	inspector_content.add_child(button)

func _add_destructive_button(text_value: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.add_theme_color_override("font_color", Color("ff8992"))
	button.pressed.connect(func() -> void: callback.call())
	inspector_content.add_child(button)

func _make_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 108.0
	label.add_theme_color_override("font_color", Color("aab2c0"))
	row.add_child(label)
	inspector_content.add_child(row)
	return row

func _get_resource_references(kind: String) -> Array[String]:
	var result: Array[String] = []
	var extensions = EventResourceRef.SPRITE_EXTENSIONS if kind == "sprite" else PackedStringArray(["json"])
	if editor != null and editor.chart != null:
		var chart_path: String = editor.chart.folder_path.path_join(EventResourceRef.CHART_DIRECTORY_NAME)
		if DirAccess.dir_exists_absolute(chart_path):
			for file_name in DirAccess.get_files_at(chart_path):
				if file_name.get_extension().to_lower() in extensions and EventResourceRef.is_valid(file_name):
					result.append(file_name)
	var builtin_path := EventResourceRef.BUILTIN_SPRITE_BASE_PATH if kind == "sprite" else EventResourceRef.BUILTIN_SKIN_BASE_PATH
	if DirAccess.dir_exists_absolute(builtin_path):
		for file_name in DirAccess.get_files_at(builtin_path):
			if file_name.get_extension().to_lower() in extensions:
				result.append(EventResourceRef.BUILTIN_PREFIX + file_name)
	result.sort()
	return result

func _get_selected_event() -> ChartEvent:
	return editor.selection.selected_event if editor != null else null

func _get_selected_frame() -> ChartEventFrame:
	var event := _get_selected_event()
	if event == null:
		return null
	var frames := get_frames(event)
	var index: int = editor.selection.selected_event_frame_index
	return frames[index] if index >= 0 and index < frames.size() else null

func _create_default_frame(event: ChartEvent) -> ChartEventFrame:
	if event is CameraEvent:
		return CameraEventFrame.new()
	if event is OverlayEvent:
		var overlay_frame := OverlayEventFrame.new()
		overlay_frame.has_opacity = true
		return overlay_frame
	if event is ThemeEvent:
		var theme_frame := ThemeEventFrame.new()
		theme_frame.bg_color = Color("101018")
		theme_frame.bg_color_2 = Color("191927")
		theme_frame.rail_color = Color.WHITE
		return theme_frame
	return null

func _clone_frame(source: ChartEventFrame, event: ChartEvent) -> ChartEventFrame:
	if source is CameraEventFrame and event is CameraEvent:
		var camera := CameraEventFrame.new()
		camera.ease = source.ease
		camera.follow_character = source.follow_character
		camera.position = source.position
		camera.zoom = source.zoom
		return camera
	if source is OverlayEventFrame and event is OverlayEvent:
		var overlay := OverlayEventFrame.new()
		overlay.ease = source.ease
		overlay.position = source.position
		overlay.scale = source.scale
		overlay.rotation = source.rotation
		overlay.sprite = source.sprite
		overlay.opacity = source.opacity
		overlay.has_opacity = source.has_opacity
		return overlay
	if source is ThemeEventFrame and event is ThemeEvent:
		var theme := ThemeEventFrame.new()
		theme.ease = source.ease
		theme.bg_color = source.bg_color
		theme.bg_color_2 = source.bg_color_2
		theme.rail_color = source.rail_color
		return theme
	return _create_default_frame(event)

func _make_unique_id(prefix: String) -> String:
	var used: Dictionary = {}
	for event in get_events():
		if event != null:
			used[event.id] = true
	var index := 1
	var candidate := "%s_%d" % [prefix, index]
	while used.has(candidate):
		index += 1
		candidate = "%s_%d" % [prefix, index]
	return candidate

func _on_selection_changed() -> void:
	var event := _get_selected_event()
	if event is OverlayEvent:
		_active_overlay_layer = maxi(0, (event as OverlayEvent).layer)
		_overlay_layer_count = maxi(_overlay_layer_count, _active_overlay_layer + 1)
	refresh_inspector()
	refresh_timeline()

func _on_zoom_changed(value: float) -> void:
	if not _syncing and timeline_view != null:
		timeline_view.set_zoom(value)

func _on_follow_toggled(enabled: bool) -> void:
	if timeline_view != null:
		timeline_view.set_follow_playhead(enabled)

func _toggle_collapsed() -> void:
	_collapsed = not _collapsed
	_apply_dock_layout()

func _apply_dock_layout() -> void:
	if event_dock == null or editor == null or editor.chart_root == null:
		return
	if timeline_view != null:
		timeline_view.visible = not _collapsed
	event_dock.anchor_top = collapsed_dock_top if _collapsed else expanded_dock_top
	editor.chart_root.anchor_bottom = collapsed_stage_bottom if _collapsed else expanded_stage_bottom
	if collapse_button != null:
		collapse_button.text = "Expand" if _collapsed else "Collapse"

func _mark_changed(event: ChartEvent, frame: ChartEventFrame = null) -> void:
	if event != null:
		event.sort_frames()
	CM.ensure_parsed_chart().sort_events()
	if frame != null:
		editor.selection.selected_event_frame_index = get_frames(event).find(frame)
	refresh_timeline()

func _on_event_id_committed(value: String, event: ChartEvent) -> void:
	var next_value := value.strip_edges().replace(",", "_")
	if _syncing or next_value.is_empty() or event.id == next_value:
		return
	editor._push_history_snapshot()
	event.id = next_value
	_mark_changed(event)

func _on_event_time_changed(value: float, event: ChartEvent) -> void:
	if _syncing or event.time == int(round(value)):
		return
	editor._push_history_snapshot()
	move_event_to_time(event, int(round(value)))

func _on_event_duration_changed(value: float, event: ChartEvent) -> void:
	var next_value := maxi(0, int(round(value)))
	if _syncing or event.duration == next_value:
		return
	editor._push_history_snapshot()
	event.duration = next_value
	for frame in get_frames(event):
		frame.time = mini(frame.time, event.duration)
	_mark_changed(event)

func _on_frame_selector_changed(index: int, event: ChartEvent, selector: OptionButton) -> void:
	if _syncing:
		return
	select_event(event, selector.get_item_id(index))

func _on_frame_time_changed(value: float, event: ChartEvent, frame: ChartEventFrame) -> void:
	var next_value := clampi(int(round(value)), 0, event.duration)
	if _syncing or frame.time == next_value:
		return
	editor._push_history_snapshot()
	frame.time = next_value
	_mark_changed(event, frame)

func _on_frame_ease_changed(value: String, event: ChartEvent, frame: ChartEventFrame) -> void:
	if _syncing or frame.ease == value:
		return
	editor._push_history_snapshot()
	frame.ease = value
	_mark_changed(event, frame)

func _on_camera_follow_changed(value: bool, event: CameraEvent, frame: CameraEventFrame) -> void:
	if _syncing or frame.follow_character == value:
		return
	editor._push_history_snapshot()
	frame.follow_character = value
	_mark_changed(event, frame)

func _on_camera_vector_changed(value: float, event: CameraEvent, frame: CameraEventFrame, change_x: bool) -> void:
	var next := frame.position
	if change_x:
		next.x = value
	else:
		next.y = value
	if _syncing or next == frame.position:
		return
	editor._push_history_snapshot()
	frame.position = next
	_mark_changed(event, frame)

func _on_camera_zoom_changed(value: float, event: CameraEvent, frame: CameraEventFrame) -> void:
	if _syncing or is_equal_approx(frame.zoom, value):
		return
	editor._push_history_snapshot()
	frame.zoom = value
	_mark_changed(event, frame)

func _on_overlay_position_changed(value: float, event: OverlayEvent, frame: OverlayEventFrame, change_x: bool) -> void:
	var next := frame.position
	if change_x:
		next.x = value
	else:
		next.y = value
	if _syncing or next == frame.position:
		return
	editor._push_history_snapshot()
	frame.position = next
	_mark_changed(event, frame)

func _on_overlay_anchor_changed(value: String, event: OverlayEvent) -> void:
	if _syncing or not OverlayEventFrame.is_valid_anchor(value) or value == event.anchor:
		return
	editor._push_history_snapshot()
	event.anchor = value
	_mark_changed(event)

func _on_overlay_layer_changed(value: float, event: OverlayEvent) -> void:
	var next_value := maxi(0, int(round(value)))
	if _syncing or event.layer == next_value:
		return
	editor._push_history_snapshot()
	event.layer = next_value
	_active_overlay_layer = next_value
	_overlay_layer_count = maxi(_overlay_layer_count, next_value + 1)
	if timeline_view != null:
		timeline_view.ensure_lane_visible(get_event_lane(event))
	_mark_changed(event)

func _on_overlay_scale_changed(value: float, event: OverlayEvent, frame: OverlayEventFrame, change_x: bool) -> void:
	var next := frame.scale
	if change_x:
		next.x = value
	else:
		next.y = value
	if _syncing or next == frame.scale:
		return
	editor._push_history_snapshot()
	frame.scale = next
	_mark_changed(event, frame)

func _on_overlay_rotation_changed(value: float, event: OverlayEvent, frame: OverlayEventFrame) -> void:
	if _syncing or is_equal_approx(frame.rotation, value):
		return
	editor._push_history_snapshot()
	frame.rotation = value
	_mark_changed(event, frame)

func _on_overlay_opacity_enabled(value: bool, event: OverlayEvent, frame: OverlayEventFrame) -> void:
	if _syncing or frame.has_opacity == value:
		return
	editor._push_history_snapshot()
	frame.has_opacity = value
	_mark_changed(event, frame)
	refresh_inspector()

func _on_overlay_opacity_changed(value: float, event: OverlayEvent, frame: OverlayEventFrame) -> void:
	if _syncing or is_equal_approx(frame.opacity, value):
		return
	editor._push_history_snapshot()
	frame.opacity = value
	_mark_changed(event, frame)

func _on_theme_color_changed(value: Color, event: ThemeEvent, frame: ThemeEventFrame, color_index: int) -> void:
	var previous := frame.bg_color if color_index == 0 else frame.bg_color_2 if color_index == 1 else frame.rail_color
	if _syncing or previous == value:
		return
	editor._push_history_snapshot()
	match color_index:
		0: frame.bg_color = value
		1: frame.bg_color_2 = value
		2: frame.rail_color = value
	_mark_changed(event, frame)

func _on_resource_selected(index: int, references: Array[String], event: ChartEvent, frame: ChartEventFrame, kind: String) -> void:
	if _syncing or index < 0 or index >= references.size():
		return
	var value := references[index]
	if kind == "sprite" and frame is OverlayEventFrame:
		if frame.sprite == value:
			return
		editor._push_history_snapshot()
		(frame as OverlayEventFrame).sprite = value
	elif kind == "skin" and event is SkinEvent:
		if (event as SkinEvent).skin_json == value:
			return
		editor._push_history_snapshot()
		(event as SkinEvent).skin_json = value
	_mark_changed(event, frame)

func _delete_selected_frame() -> void:
	if _get_selected_frame() != null:
		delete_selection()

func _delete_event(event: ChartEvent) -> void:
	if event == null:
		return
	editor._push_history_snapshot()
	CM.ensure_parsed_chart().events.erase(event)
	editor.selection.clear()
	refresh_timeline()

func _open_event_resource_folder() -> void:
	if editor == null or editor.chart == null:
		return
	var path: String = editor.chart.folder_path.path_join(EventResourceRef.CHART_DIRECTORY_NAME)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	OS.shell_open(ProjectSettings.globalize_path(path))

func _create_resource_import_dialog() -> void:
	_resource_import_dialog = FileDialog.new()
	_resource_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_resource_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_resource_import_dialog.use_native_dialog = true
	_resource_import_dialog.file_selected.connect(_on_resource_import_file_selected)
	add_child(_resource_import_dialog)
	UIFocusUtils.disable_focus_recursive(_resource_import_dialog)

func _can_import_resource(kind: String) -> bool:
	return kind == "sprite"

func _open_resource_import_dialog(kind: String, event: ChartEvent, frame: ChartEventFrame) -> void:
	if editor == null or editor.chart == null or _resource_import_dialog == null or not _can_import_resource(kind):
		return
	_pending_resource_kind = kind
	_pending_resource_event = event
	_pending_resource_frame = frame
	var target_directory: String = editor.chart.folder_path.path_join(EventResourceRef.CHART_DIRECTORY_NAME)
	FileSystem.ensure_dir(target_directory)
	_resource_import_dialog.filters = _get_resource_import_filters(kind)
	_resource_import_dialog.current_dir = ProjectSettings.globalize_path(target_directory)
	_resource_import_dialog.popup_centered_ratio(0.7)

func _get_resource_import_filters(kind: String) -> PackedStringArray:
	if kind == "sprite":
		return SPRITE_IMPORT_FILTERS
	return PackedStringArray()

func _on_resource_import_file_selected(path: String) -> void:
	if editor == null or editor.chart == null:
		_clear_resource_import_state()
		return

	var event := _pending_resource_event
	var frame := _pending_resource_frame
	var kind := _pending_resource_kind
	var imported_reference := _import_resource_reference(kind, path)
	_clear_resource_import_state()
	if imported_reference.is_empty():
		return

	if kind == "sprite" and event is OverlayEvent and frame is OverlayEventFrame:
		var overlay_frame := frame as OverlayEventFrame
		if overlay_frame.sprite == imported_reference:
			refresh_inspector()
			return
		editor._push_history_snapshot()
		overlay_frame.sprite = imported_reference
		_mark_changed(event, overlay_frame)
		refresh_inspector()

func _import_resource_reference(kind: String, path: String) -> String:
	if kind == "sprite":
		return EventResourceRef.import_sprite(editor.chart, path)
	return ""

func _clear_resource_import_state() -> void:
	_pending_resource_kind = ""
	_pending_resource_event = null
	_pending_resource_frame = null

func _get_event_type_name(event: ChartEvent) -> String:
	if event is CameraEvent:
		return "Camera"
	if event is ThemeEvent:
		return "Theme"
	if event is SkinEvent:
		return "Skin"
	if event is OverlayEvent:
		return "Overlay"
	return "Event"

func _sync_overlay_layers_from_events() -> void:
	var required_layers := 1
	for event in get_events():
		if event is OverlayEvent:
			required_layers = maxi(required_layers, maxi(0, (event as OverlayEvent).layer) + 1)
	_overlay_layer_count = maxi(_overlay_layer_count, required_layers)
	_active_overlay_layer = mini(_active_overlay_layer, _overlay_layer_count - 1)
