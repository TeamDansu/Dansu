extends Node
class_name EditorInspectorController

const SkinSerializationScript = preload("res://skin/skin_serialization.gd")

@export var editor: Editor
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

var timing_scene := preload("res://scenes/editor/ui/inspector/timing.tscn")
var timing_items: Array[EditorTimingItem] = []
var _syncing_metadata := false
var _skin_file_dialog: FileDialog

func create_dialogs() -> void:
	_skin_file_dialog = FileDialog.new()
	_skin_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_skin_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_skin_file_dialog.filters = PackedStringArray(["*.json ; Skin JSON"])
	_skin_file_dialog.file_selected.connect(_on_skin_file_selected)
	add_child(_skin_file_dialog)

func is_syncing_metadata() -> bool:
	return _syncing_metadata

func refresh_metadata_fields() -> void:
	if editor == null or editor.chart == null:
		return
	_syncing_metadata = true
	title_line_edit.text = editor.chart.title
	artist_line_edit.text = editor.chart.artist
	difficulty_line_edit.text = editor.chart.difficulty
	source_line_edit.text = editor.chart.source
	tags_line_edit.text = editor.chart.tags
	_syncing_metadata = false
	update_skin_file_ui()

func update_skin_file_ui() -> void:
	if skin_file_label == null or editor == null or editor.chart == null:
		return
	skin_file_label.text = editor.chart.file_skin if editor.chart.file_skin != "" else "(no linked skin file)"

func rebuild_timing_ui() -> void:
	if editor == null or editor.chart == null or editor.timeline == null:
		return
	editor.timeline.ensure_timings()
	for item in timing_items:
		if item != null and item != timing_template:
			item.queue_free()
	timing_items.clear()

	for index in range(editor.chart.timings.size()):
		var item: EditorTimingItem
		if index == 0:
			item = timing_template as EditorTimingItem
		else:
			item = timing_scene.instantiate() as EditorTimingItem
			timing_list_container.add_child(item)
		item.bind(editor.chart.timings[index])
		if not item.change_started.is_connected(on_timing_item_change_started):
			item.change_started.connect(on_timing_item_change_started)
		if not item.changed.is_connected(on_timing_item_changed):
			item.changed.connect(on_timing_item_changed)
		if not item.remove_requested.is_connected(on_timing_remove_requested):
			item.remove_requested.connect(on_timing_remove_requested)
		timing_items.append(item)

func update_beat_division_ui() -> void:
	if beat_division_slider == null or editor == null or editor.timeline == null:
		return
	var divisions := editor._get_supported_beat_divisions()
	beat_division_slider.min_value = 0
	beat_division_slider.max_value = divisions.size() - 1
	beat_division_slider.step = 1
	var target_index := divisions.find(editor.timeline.beat_division)
	if target_index == -1:
		target_index = divisions.find(4)
		if target_index == -1:
			target_index = 0
	editor.timeline.beat_division = divisions[target_index]
	beat_division_slider.value = target_index
	beat_division_label.text = "1/%d" % editor.timeline.beat_division

func on_title_changed(new_text: String) -> void:
	if _syncing_metadata or editor == null or editor.chart == null:
		return
	editor.chart.title = new_text
	editor._update_save_button_state()

func on_artist_changed(new_text: String) -> void:
	if _syncing_metadata or editor == null or editor.chart == null:
		return
	editor.chart.artist = new_text

func on_difficulty_changed(new_text: String) -> void:
	if _syncing_metadata or editor == null or editor.chart == null:
		return
	if EditorChartOps.has_duplicate_difficulty(editor.chart, new_text):
		_syncing_metadata = true
		editor.chart.difficulty = ""
		difficulty_line_edit.text = ""
		_syncing_metadata = false
	else:
		editor.chart.difficulty = new_text.strip_edges()
	editor._update_save_button_state()

func on_source_changed(new_text: String) -> void:
	if not _syncing_metadata and editor != null and editor.chart != null:
		editor.chart.source = new_text

func on_tags_changed(new_text: String) -> void:
	if not _syncing_metadata and editor != null and editor.chart != null:
		editor.chart.tags = new_text

func on_beat_division_slider_changed(value: float) -> void:
	if editor == null or editor.timeline == null:
		return
	var divisions := editor._get_supported_beat_divisions()
	var index := clampi(int(round(value)), 0, divisions.size() - 1)
	if editor.timeline.beat_division == divisions[index]:
		return
	editor._push_history_snapshot()
	editor.timeline.beat_division = divisions[index]
	beat_division_label.text = "1/%d" % editor.timeline.beat_division
	editor.refresh_views()

func add_timing() -> void:
	if editor == null or editor.chart == null or editor.timeline == null:
		return
	editor._push_history_snapshot()
	var new_timing := Timing.new()
	new_timing.time = editor.timeline.snap_time(int(round(Game.current_time)))
	new_timing.bpm = 120.0 if editor.chart.timings.is_empty() else editor.chart.timings.back().bpm
	editor.chart.timings.append(new_timing)
	editor.chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	rebuild_timing_ui()
	editor.refresh_views()

func on_timing_item_change_started(_item: EditorTimingItem) -> void:
	if editor != null:
		editor._push_history_snapshot()

func on_timing_item_changed(_item: EditorTimingItem) -> void:
	if editor == null or editor.chart == null:
		return
	editor.chart.timings.sort_custom(func(a, b) -> bool: return a.time < b.time)
	rebuild_timing_ui()
	editor.refresh_views()

func on_timing_remove_requested(item: EditorTimingItem) -> void:
	if editor == null or editor.chart == null:
		return
	if editor.chart.timings.size() <= 1:
		return
	editor._push_history_snapshot()
	editor.chart.timings.erase(item.timing)
	rebuild_timing_ui()
	editor.refresh_views()

func open_skin_browser() -> void:
	if editor == null or editor.chart == null or _skin_file_dialog == null:
		return
	var chart_folder_path := ProjectSettings.globalize_path(editor.chart.folder_path)
	var skins_root_path := SkinSerializationScript.get_chart_skin_root_path(chart_folder_path)
	FileSystem.ensure_dir(skins_root_path)
	_skin_file_dialog.root_subfolder = skins_root_path
	_skin_file_dialog.current_dir = skins_root_path
	if editor.chart.file_skin != "":
		SkinSerializationScript.migrate_chart_skin_layout(editor.chart)
		_skin_file_dialog.current_path = ProjectSettings.globalize_path(editor.chart.skin_path)
	_skin_file_dialog.popup_centered_ratio(0.7)

func _on_skin_file_selected(path: String) -> void:
	if editor == null or editor.chart == null:
		return
	var chart_folder_path := ProjectSettings.globalize_path(editor.chart.folder_path).simplify_path()
	var skins_root_path := SkinSerializationScript.get_chart_skin_root_path(chart_folder_path).simplify_path()
	var selected_path := path.simplify_path()
	if selected_path.get_file() != Chart.CHART_SKIN_JSON_NAME:
		return
	var skin_directory_path := selected_path.get_base_dir().simplify_path()
	if skin_directory_path.get_base_dir() != skins_root_path:
		return
	editor.chart.file_skin = skin_directory_path.get_file()
	update_skin_file_ui()
