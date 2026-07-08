extends Node
class_name ChartManager

const SkinSerializationScript = preload("res://skin/skin_serialization.gd")

signal chartset_loaded(_set)
signal progress_changed(ratio: float) # 0.0 ~ 1.0
signal loading_finished()
signal chart_reload()
signal chart_update(chart_set)
signal chart_selected(chart: Chart)
signal chartset_selected(chart_set: ChartSet)
signal chart_loaded()

const SONG_PATH = "user://charts/"

var selected_chart : Chart = null
var selected_chartset : ChartSet = null
var chartsets : Array[ChartSet] = []
var parsed_chart : ParsedChart

var all_folders: PackedStringArray = []
var unloaded_folders: PackedStringArray = []
var loaded_folders: PackedStringArray = []
var lastSelectedDiff := 0

var _threads: Array[Thread] = []
var _folders_to_load: PackedStringArray = []
var _loaded_count: int = 0
var _stop := false
var _mutex := Mutex.new()
var _finish_queued := false

func clear():
	parsed_chart = null

func parse_selected_chart() -> bool:
	if not selected_chart:
		Notification.notice("no chart selected",Notification.Type.WARNING)
		return false
	var parser: Parser = Parser.new()
	var result := parser.parse_object(selected_chart)
	if not result.success:
		parsed_chart = null
		return false
	parsed_chart = result.parsed_chart
	return true

func ensure_parsed_chart() -> ParsedChart:
	if parsed_chart == null:
		parsed_chart = ParsedChart.new(selected_chart)
	return parsed_chart

func select_chart(chart: Chart):
	selected_chart = chart
	emit_signal("chart_selected",chart)

func select_chartset(chartset: ChartSet):
	selected_chartset = chartset
	emit_signal("chartset_selected",chartset)

func _load(is_reload: bool) -> void:
	FileSystem.ensure_dir(SONG_PATH)

	all_folders = DirAccess.get_directories_at(SONG_PATH)

	if is_reload:
		for folder in all_folders:
			if not loaded_folders.has(folder):
				unloaded_folders.append(folder)
	else:
		unloaded_folders = all_folders
	start_loading(unloaded_folders)
	_emit_reload()

func start_loading(folders_in: Array[String]) -> void:
	stop()
	_finish_queued = false
	_folders_to_load = folders_in.duplicate()
	_loaded_count = 0
	_stop = false
	var thread_count = Config.chart_load_threads
	_threads.clear()
	for i in range(thread_count):
		var t := Thread.new()
		_threads.append(t)
		t.start(Callable(self, "_thread_func"))

func stop() -> void:
	_stop = true
	for t in _threads:
		if t.is_started():
			t.wait_to_finish()
	_threads.clear()

func _thread_func() -> void:
	while true:
		if _stop:
			return
		var folder: String = ""
		_mutex.lock()
		if _folders_to_load.size() > 0:
			folder = _folders_to_load[0]
			_folders_to_load.remove_at(0)
			loaded_folders.append(folder)
		_mutex.unlock()
		if folder == "":
			return

		var new_set := ChartSet.new()
		new_set.folder_name = folder.get_file()
		for file_name in _get_chart_files_in_path(folder):
			var new_chart = Chart.new()
			new_chart.folder_name = new_set.folder_name
			new_chart.file_name = file_name
			Parser.parse_meta(new_chart)
			new_chart.chart_set = new_set
			new_set.charts.append(new_chart)
		SkinSerializationScript.migrate_chartset_skin_layout(new_set.charts)
		if new_set.charts.size() > 0:
			call_deferred("_emit_loaded", new_set)
		else:
			push_error("FILE : failed to parse : %s" %folder)
		_mutex.lock()
		_loaded_count += 1
		var progress := float(_loaded_count) / float(max(1, _loaded_count + _folders_to_load.size()))
		call_deferred("_emit_progress", progress)
		if _folders_to_load.is_empty() and not _finish_queued:
			_finish_queued = true
			call_deferred("_emit_finished")
		_mutex.unlock()

func _get_chart_files_in_path(path: String) -> Array:
	var result = []
	var dir = DirAccess.open(CM.SONG_PATH.path_join(path))
	if not dir:
		return result
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(Config.FILE_EXTENSION):
			result.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return result

func _emit_loaded(_set: ChartSet) -> void:
	chartsets.append(_set)
	emit_signal("chartset_loaded", _set)

func _emit_progress(ratio: float) -> void:
	emit_signal("progress_changed", ratio)

func _emit_finished() -> void:
	emit_signal("loading_finished")
	if chartsets.size() > 0:
		selected_chartset = chartsets[0]
		emit_signal("chart_loaded")

func _emit_reload() -> void:
	emit_signal("chart_reload")

func _emit_update() -> void:
	emit_signal("chart_update",chartsets)
