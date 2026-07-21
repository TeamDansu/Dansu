extends Node
class_name ChartManager

signal chartset_loaded(_set)
signal progress_changed(ratio: float)
signal loading_finished()
signal database_sync_finished(success: bool)
signal chart_reload()
signal chart_update(chart_set)
signal chart_selected(chart: Chart)
signal chartset_selected(chart_set: ChartSet)
signal chart_loaded()

const SONG_PATH := "user://charts/"
const LEGACY_CHARTSET_MANIFEST_FILE := "chartset.json"

var selected_chart: Chart = null
var selected_chartset: ChartSet = null
var chartsets: Array[ChartSet] = []
var parsed_chart: ParsedChart = null

var chartsets_by_db_id: Dictionary = {}
var charts_by_db_id: Dictionary = {}
var chartsets_by_uuid: Dictionary = {}
var charts_by_uuid: Dictionary = {}

var all_folders: PackedStringArray = []
var unloaded_folders: PackedStringArray = []
var loaded_folders: PackedStringArray = []
var lastSelectedDiff := 0

var _database: DansuDB = null
var _threads: Array[Thread] = []
var _folders_to_load: PackedStringArray = []
var _charts_by_path: Dictionary = {}
var _scan_generation := -1
var _scan_total_count := 0
var _scan_completed_count := 0
var _active_worker_count := 0
var _stop := false
var _scan_failed := false
var _finish_queued := false
var _mutex := Mutex.new()
var _new_chartset_ids: Dictionary = {}
var _allowed_chart_paths: Dictionary = {}
var _scan_chartsets_by_folder: Dictionary = {}
var _pending_discard_paths: PackedStringArray = []


func _exit_tree() -> void:
	stop()


func clear() -> void:
	parsed_chart = null


func parse_selected_chart() -> bool:
	if selected_chart == null:
		Notification.notice("no chart selected", Notification.Type.WARNING)
		return false
	if not validate_chart_file(selected_chart):
		Notification.notice("chart file is missing", Notification.Type.WARNING)
		parsed_chart = null
		return false

	selected_chart.filehash = FileAccess.get_sha256(selected_chart.file_path)
	var result := Parser.new().parse_object(selected_chart)
	if not result.success:
		selected_chart.availability = Chart.Availability.INVALID
		parsed_chart = null
		return false

	selected_chart.availability = Chart.Availability.AVAILABLE
	parsed_chart = result.parsed_chart
	return true


func ensure_parsed_chart() -> ParsedChart:
	if parsed_chart == null or parsed_chart.chart != selected_chart:
		parsed_chart = ParsedChart.new(selected_chart)
	return parsed_chart


func select_chart(chart: Chart) -> void:
	if selected_chart != chart:
		parsed_chart = null
	selected_chart = chart
	if chart != null:
		validate_chart_file(chart)
	chart_selected.emit(chart)


func select_chartset(chartset: ChartSet) -> void:
	selected_chartset = chartset
	chartset_selected.emit(chartset)


func validate_chart_file(chart: Chart) -> bool:
	if chart == null:
		return false

	var previous := chart.availability
	var exists := FileAccess.file_exists(chart.file_path)
	chart.availability = Chart.Availability.AVAILABLE if exists else Chart.Availability.MISSING

	if _database != null and chart.db_id > 0:
		if not exists or previous == Chart.Availability.MISSING:
			if not _database.set_chart_present(chart.db_id, exists):
				push_warning("[database] failed to update chart presence: %s" % _database.get_last_error_message())
	return exists


func make_unique_chartset_folder_name(preferred_name: String = "new_chartset") -> String:
	var base_name := preferred_name.strip_edges().validate_filename()
	if base_name.is_empty():
		base_name = "new_chartset"

	var candidate := base_name
	var suffix := 2
	while _chartset_folder_exists(candidate):
		candidate = "%s_%d" % [base_name, suffix]
		suffix += 1
	return candidate


func register_saved_chart(chart: Chart) -> void:
	if chart == null or chart.chart_set == null:
		return

	_index_saved_chart(chart, true)
	if not chartsets.has(chart.chart_set):
		chartsets.append(chart.chart_set)
	if not chart.chart_set.charts.has(chart):
		chart.chart_set.charts.append(chart)

	select_chartset(chart.chart_set)
	select_chart(chart)
	_emit_update()


func recalculate_all_ratings() -> Dictionary:
	var total := 0
	var updated := 0
	var failed := 0
	var parser := Parser.new()
	var writer := ChartWriter.new()

	for chart_set: ChartSet in chartsets:
		if chart_set == null:
			continue
		for chart: Chart in chart_set.charts:
			if chart == null:
				continue
			total += 1

			var parse_result := parser.parse_object(chart)
			if not parse_result.success or parse_result.parsed_chart == null:
				failed += 1
				continue

			var parsed: ParsedChart = parse_result.parsed_chart
			chart.rating = Rating.calculate_rating(parsed)
			chart.rating_calculated = true
			if not writer.write_chart(parsed):
				failed += 1
				continue

			chart.build_search_string()
			if not _index_saved_chart(chart):
				failed += 1
				continue
			updated += 1

	if updated > 0:
		_emit_update()

	return {
		"total": total,
		"updated": updated,
		"failed": failed,
	}


func _load(_is_reload: bool) -> void:
	FileSystem.ensure_dir(SONG_PATH)
	_database = DB.connection if DB != null else null
	if _database == null:
		push_error("[database] DansuDB is unavailable")
		call_deferred("_emit_initial_ready")
		return
	if not _database.prepare_rating_cache(Rating.CACHE_VERSION):
		push_error("[database] failed to prepare rating cache: %s" % _database.get_last_error_message())
		call_deferred("_emit_initial_ready")
		return

	_refresh_library_from_database(false)
	_emit_reload()
	_emit_initial_ready()
	_start_background_sync()


func _refresh_library_from_database(filesystem_validated: bool) -> bool:
	if _database == null:
		return false

	var previous_chart_id := selected_chart.db_id if selected_chart != null else -1
	var previous_set_id := selected_chartset.db_id if selected_chartset != null else -1
	_new_chartset_ids.clear()
	var loaded_chartsets := _database.load_chart_library(
		_get_or_create_chartset,
		_get_or_create_chart,
		_create_timing,
		true,
		filesystem_validated
	)
	if _database.get_last_error_code() != 0:
		push_error("[database] failed to load chart library: %s" % _database.get_last_error_message())
		return false

	var next_chartsets: Array[ChartSet] = []
	var active_set_ids: Dictionary = {}
	var active_chart_ids: Dictionary = {}
	chartsets_by_uuid.clear()
	charts_by_uuid.clear()
	for chartset_value in loaded_chartsets:
		var chart_set := chartset_value as ChartSet
		if chart_set == null:
			continue
		active_set_ids[chart_set.db_id] = true
		chartsets_by_uuid[chart_set.uuid] = chart_set
		next_chartsets.append(chart_set)
		if _new_chartset_ids.has(chart_set.db_id):
			chartset_loaded.emit(chart_set)
		for chart in chart_set.charts:
			active_chart_ids[chart.db_id] = true
			charts_by_uuid[chart.uuid] = chart

	chartsets = next_chartsets
	selected_chartset = chartsets_by_db_id.get(previous_set_id) if active_set_ids.has(previous_set_id) else null
	selected_chart = charts_by_db_id.get(previous_chart_id) if active_chart_ids.has(previous_chart_id) else null
	if selected_chart == null:
		parsed_chart = null
	return true


func _get_or_create_chartset(db_id: int) -> ChartSet:
	var chart_set := chartsets_by_db_id.get(db_id) as ChartSet
	if chart_set == null:
		chart_set = ChartSet.new()
		chartsets_by_db_id[db_id] = chart_set
		_new_chartset_ids[db_id] = true
	return chart_set


func _get_or_create_chart(db_id: int) -> Chart:
	var chart := charts_by_db_id.get(db_id) as Chart
	if chart == null:
		chart = Chart.new()
		charts_by_db_id[db_id] = chart
	return chart


func _create_timing() -> Timing:
	return Timing.new()


func _start_background_sync() -> void:
	stop()
	all_folders = DirAccess.get_directories_at(SONG_PATH)
	all_folders.sort()
	all_folders = _prepare_scan_sources(all_folders)
	unloaded_folders = all_folders.duplicate()
	loaded_folders.clear()
	_folders_to_load = all_folders.duplicate()
	_charts_by_path.clear()
	for chart_set in chartsets:
		for chart in chart_set.charts:
			_charts_by_path[_path_key(chart.folder_name, chart.file_name)] = chart

	_scan_generation = _database.begin_chart_scan()
	if _scan_generation <= 0:
		push_error("[database] failed to begin chart scan: %s" % _database.get_last_error_message())
		database_sync_finished.emit(false)
		return

	_scan_total_count = _folders_to_load.size()
	_scan_completed_count = 0
	_scan_failed = false
	_finish_queued = false
	_stop = false
	_threads.clear()

	if _folders_to_load.is_empty():
		call_deferred("_finish_background_sync")
		return

	var thread_count := clampi(Config.chart_load_threads, 1, _folders_to_load.size())
	_active_worker_count = thread_count
	for _index in range(thread_count):
		var thread := Thread.new()
		_threads.append(thread)
		thread.start(Callable(self, "_scan_worker"))


func stop() -> void:
	_stop = true
	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()
	_active_worker_count = 0


func _scan_worker() -> void:
	while true:
		var folder := ""
		_mutex.lock()
		if not _stop and not _folders_to_load.is_empty():
			folder = _folders_to_load[0]
			_folders_to_load.remove_at(0)
		_mutex.unlock()

		if folder.is_empty():
			break
		_scan_folder(folder)

		_mutex.lock()
		loaded_folders.append(folder)
		_scan_completed_count += 1
		var progress := float(_scan_completed_count) / float(maxi(_scan_total_count, 1))
		_mutex.unlock()
		call_deferred("_emit_progress", progress)

	_mutex.lock()
	_active_worker_count -= 1
	var should_finish := _active_worker_count == 0 and not _stop and not _finish_queued
	if should_finish:
		_finish_queued = true
	_mutex.unlock()
	if should_finish:
		call_deferred("_finish_background_sync")


func _scan_folder(folder: String) -> void:
	var chart_set := _scan_chartsets_by_folder.get(folder) as ChartSet
	if chart_set == null:
		_mark_scan_failed("failed to resolve chart set UUID '%s'" % folder)
		return

	var set_id := _database.upsert_chart_set(chart_set, _scan_generation)
	if set_id <= 0:
		_mark_scan_failed("failed to index chart set '%s'" % folder)
		return

	chart_set.db_id = set_id
	for file_name in _get_chart_files_in_path(folder):
		if _stop:
			return
		if not _allowed_chart_paths.has(_path_key(folder, file_name)):
			continue
		var path := SONG_PATH.path_join(folder).path_join(file_name)
		var modified_time := int(FileAccess.get_modified_time(path))
		var file_size := _get_file_size(path)
		var cached := _charts_by_path.get(_path_key(folder, file_name)) as Chart

		if cached != null and cached.rating_calculated and cached.file_modified_time == modified_time and cached.file_size == file_size:
			if not _database.touch_chart(cached.db_id, modified_time, file_size, _scan_generation):
				_mark_scan_failed("failed to touch cached chart '%s'" % path)
			continue

		var chart := Chart.new()
		chart.chart_set = chart_set
		chart.folder_name = folder
		chart.file_name = file_name
		if not Parser.parse_meta(chart):
			push_warning("[charts] invalid chart metadata: %s" % path)
			continue
		if not _calculate_chart_rating(chart):
			push_warning("[charts] failed to calculate rating: %s" % path)
			continue
		chart.file_modified_time = modified_time
		chart.file_size = file_size
		chart.filehash = FileAccess.get_sha256(path)

		var chart_id := _database.upsert_chart(chart, _scan_generation)
		if chart_id <= 0:
			_mark_scan_failed("failed to index chart '%s'" % path)
			return


func _finish_background_sync() -> void:
	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()

	var success := not _scan_failed and not _stop
	if success:
		success = _database.finish_chart_scan(_scan_generation)
		if not success:
			push_error("[database] failed to finish chart scan: %s" % _database.get_last_error_message())

	if success:
		_commit_pending_discards()
		_refresh_library_from_database(true)
		_emit_update()
	_emit_progress(1.0)
	database_sync_finished.emit(success)


func _mark_scan_failed(context: String) -> void:
	_mutex.lock()
	_scan_failed = true
	_mutex.unlock()
	push_error("[database] %s: %s" % [context, _database.get_last_error_message()])


func _index_saved_chart(chart: Chart, force_rating: bool = false) -> bool:
	if _database == null or chart == null or chart.chart_set == null:
		return false
	if not FileAccess.file_exists(chart.file_path):
		return false

	var chart_set := chart.chart_set
	if chart_set.uuid.is_empty():
		chart_set.build_uuid()
	var set_id := _database.upsert_chart_set(chart_set)
	if set_id <= 0:
		push_error("[database] failed to save chart set: %s" % _database.get_last_error_message())
		return false

	var previous_id := chart.db_id
	chart_set.db_id = set_id
	if not _calculate_chart_rating(chart, force_rating):
		push_error("[rating] failed to calculate chart rating: %s" % chart.file_path)
		return false
	chart.file_modified_time = int(FileAccess.get_modified_time(chart.file_path))
	chart.file_size = _get_file_size(chart.file_path)
	chart.filehash = FileAccess.get_sha256(chart.file_path)
	var chart_id := _database.upsert_chart(chart)
	if chart_id <= 0:
		push_error("[database] failed to save chart: %s" % _database.get_last_error_message())
		return false

	if previous_id > 0 and previous_id != chart_id:
		_database.set_chart_present(previous_id, false)
	chart.db_id = chart_id
	chart.availability = Chart.Availability.AVAILABLE
	chartsets_by_db_id[set_id] = chart_set
	charts_by_db_id[chart_id] = chart
	chartsets_by_uuid[chart_set.uuid] = chart_set
	charts_by_uuid[chart.uuid] = chart
	return true


func _calculate_chart_rating(chart: Chart, force: bool = false) -> bool:
	if chart == null:
		return false
	if chart.rating_calculated and not force:
		return true

	var rating_source: ParsedChart = null
	if parsed_chart != null and parsed_chart.chart == chart:
		rating_source = parsed_chart
	else:
		var parse_result := Parser.new().parse_object(chart)
		if not parse_result.success or parse_result.parsed_chart == null:
			return false
		rating_source = parse_result.parsed_chart

	chart.rating = Rating.calculate_rating(rating_source)
	chart.rating_calculated = true
	return true


func _prepare_scan_sources(folders: PackedStringArray) -> PackedStringArray:
	_allowed_chart_paths.clear()
	_scan_chartsets_by_folder.clear()
	_pending_discard_paths.clear()
	var sets_by_uuid: Dictionary = {}

	for folder in folders:
		var chart_files := _get_chart_files_in_path(folder)
		if chart_files.is_empty():
			continue

		var discovered_uuids: Dictionary = {}
		var missing_uuid_paths: PackedStringArray = []
		for file_name in chart_files:
			var candidate_set := ChartSet.new()
			candidate_set.folder_name = folder
			var candidate_chart := Chart.new()
			candidate_chart.chart_set = candidate_set
			candidate_chart.folder_name = folder
			candidate_chart.file_name = file_name
			if not Parser.parse_meta(candidate_chart):
				continue
			if candidate_set.uuid.is_empty():
				missing_uuid_paths.append(candidate_chart.file_path)
			else:
				discovered_uuids[candidate_set.uuid] = true

		if discovered_uuids.size() > 1:
			push_error("[charts] conflicting chartset_uuid values in folder: %s" % folder)
			continue

		var chart_set := ChartSet.new()
		chart_set.folder_name = folder
		if discovered_uuids.size() == 1:
			chart_set.uuid = str(discovered_uuids.keys()[0])
		else:
			chart_set.uuid = _find_registered_chartset_uuid(folder)
			if chart_set.uuid.is_empty():
				chart_set.uuid = _read_legacy_chartset_uuid(folder)
			if chart_set.uuid.is_empty():
				chart_set.build_uuid()

		for path in missing_uuid_paths:
			if not _inject_chartset_uuid(path, chart_set.uuid):
				push_error("[charts] failed to write chartset_uuid: %s" % path)
				chart_set = null
				break
		if chart_set == null:
			continue

		var legacy_manifest_path := SONG_PATH.path_join(folder).path_join(LEGACY_CHARTSET_MANIFEST_FILE)
		if FileAccess.file_exists(legacy_manifest_path):
			_pending_discard_paths.append(legacy_manifest_path)
		_scan_chartsets_by_folder[folder] = chart_set
		if not sets_by_uuid.has(chart_set.uuid):
			sets_by_uuid[chart_set.uuid] = []
		sets_by_uuid[chart_set.uuid].append(folder)

	var winning_folders: PackedStringArray = []
	for uuid_value in sets_by_uuid:
		var candidates: Array = sets_by_uuid[uuid_value]
		var registered := chartsets_by_uuid.get(uuid_value) as ChartSet
		var registered_folder := registered.folder_name if registered != null else ""
		var winner := _choose_newest_path(candidates, registered_folder, true)
		winning_folders.append(winner)
		for candidate in candidates:
			if candidate != winner:
				_pending_discard_paths.append(SONG_PATH.path_join(str(candidate)))

	winning_folders.sort()
	var charts_by_uuid_for_scan: Dictionary = {}
	for folder in winning_folders:
		for file_name in _get_chart_files_in_path(folder):
			var chart := Chart.new()
			chart.chart_set = _scan_chartsets_by_folder[folder]
			chart.folder_name = folder
			chart.file_name = file_name
			if not Parser.parse_meta(chart):
				push_warning("[charts] invalid chart metadata: %s" % chart.file_path)
				continue
			if chart.uuid.is_empty():
				push_warning("[charts] chart UUID is required: %s" % chart.file_path)
				continue
			if not charts_by_uuid_for_scan.has(chart.uuid):
				charts_by_uuid_for_scan[chart.uuid] = []
			charts_by_uuid_for_scan[chart.uuid].append(chart.file_path)

	for uuid_value in charts_by_uuid_for_scan:
		var candidates: Array = charts_by_uuid_for_scan[uuid_value]
		var registered := charts_by_uuid.get(uuid_value) as Chart
		var registered_path := registered.file_path if registered != null else ""
		var winner := _choose_newest_path(candidates, registered_path, false)
		_allowed_chart_paths[_path_key_from_path(winner)] = true
		for candidate in candidates:
			if candidate != winner:
				_pending_discard_paths.append(str(candidate))

	return winning_folders


func _find_registered_chartset_uuid(folder_name: String) -> String:
	for chart_set in chartsets:
		if chart_set != null and chart_set.folder_name == folder_name:
			return chart_set.uuid
	return ""


func _read_legacy_chartset_uuid(folder_name: String) -> String:
	var path := SONG_PATH.path_join(folder_name).path_join(LEGACY_CHARTSET_MANIFEST_FILE)
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var data = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		return str(data.get("uuid", "")).strip_edges()
	return ""


func _inject_chartset_uuid(path: String, chartset_uuid: String) -> bool:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return false
	var lines := source.get_as_text().split("\n", true)
	var insert_index := -1
	for index in range(lines.size()):
		var stripped := lines[index].strip_edges()
		if stripped.to_lower().begins_with("chartset_uuid:"):
			lines[index] = "chartset_uuid: %s" % chartset_uuid
			insert_index = -2
			break
		if stripped.to_lower().begins_with("uuid:"):
			insert_index = index + 1
	if insert_index >= 0:
		lines.insert(insert_index, "chartset_uuid: %s" % chartset_uuid)
	elif insert_index == -1:
		return false

	var target := FileAccess.open(path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_string("\n".join(lines))
	target.flush()
	return true


func _choose_newest_path(candidates: Array, registered_path: String, is_directory: bool) -> String:
	var pool := candidates.duplicate()
	if not registered_path.is_empty() and candidates.size() > 1:
		var new_candidates := candidates.filter(func(path): return str(path) != registered_path)
		if not new_candidates.is_empty():
			pool = new_candidates

	pool.sort_custom(func(a, b):
		var modified_a := _get_chartset_modified_time(str(a)) if is_directory else int(FileAccess.get_modified_time(str(a)))
		var modified_b := _get_chartset_modified_time(str(b)) if is_directory else int(FileAccess.get_modified_time(str(b)))
		if modified_a == modified_b:
			return str(a).naturalnocasecmp_to(str(b)) < 0
		return modified_a > modified_b
	)
	return str(pool[0])


func _get_chartset_modified_time(folder_name: String) -> int:
	var newest := 0
	for file_name in _get_chart_files_in_path(folder_name):
		newest = maxi(newest, int(FileAccess.get_modified_time(SONG_PATH.path_join(folder_name).path_join(file_name))))
	return newest


func _commit_pending_discards() -> void:
	for path in _pending_discard_paths:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(absolute_path):
			var error := OS.move_to_trash(absolute_path)
			if error != OK:
				push_warning("[charts] failed to discard duplicate UUID path: %s" % path)
	_pending_discard_paths.clear()


func _path_key_from_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	var root := SONG_PATH.replace("\\", "/")
	if normalized.begins_with(root):
		normalized = normalized.trim_prefix(root)
	return normalized.to_lower()

func _get_chart_files_in_path(folder: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(SONG_PATH.path_join(folder))
	if directory == null:
		return result
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.ends_with(Config.FILE_EXTENSION):
			result.append(file_name)
		file_name = directory.get_next()
	directory.list_dir_end()
	return result


func _get_file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	return file.get_length()


func _path_key(folder_name: String, file_name: String) -> String:
	return folder_name.path_join(file_name).replace("\\", "/").to_lower()


func _emit_progress(ratio: float) -> void:
	progress_changed.emit(ratio)


func _emit_initial_ready() -> void:
	loading_finished.emit()
	if not chartsets.is_empty():
		if selected_chartset == null:
			selected_chartset = chartsets[0]
		chart_loaded.emit()


func _emit_reload() -> void:
	chart_reload.emit()


func _emit_update() -> void:
	chart_update.emit(chartsets)


func _chartset_folder_exists(folder_name: String) -> bool:
	var normalized := folder_name.strip_edges()
	if normalized.is_empty():
		return true

	for chartset in chartsets:
		if chartset != null and chartset.folder_name == normalized:
			return true

	var absolute_path := ProjectSettings.globalize_path(FileSystem.chart_path.path_join(normalized))
	return DirAccess.dir_exists_absolute(absolute_path)
