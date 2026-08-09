extends RefCounted
class_name EditorChartOps

const DEFAULT_RAIL_DURATION := 1250
const DEFAULT_RAIL_X := 0.5
const RAIL_MOVE_STEP := 0.01

static func load_selected_chart() -> Chart:
	var chart: Chart = CM.selected_chart
	if chart == null:
		return null

	var parser := Parser.new()
	var result := parser.parse_object(chart)
	if not result.success:
		return null
	CM.parsed_chart = result.parsed_chart
	sort_chart_objects()
	return chart

static func sort_chart_objects() -> void:
	if CM.parsed_chart == null:
		return
	for rail: Rail in CM.parsed_chart.rails:
		if rail == null:
			continue
		rail.sort_points()
		rail.sort_notes()
	CM.parsed_chart.sort_events()

static func next_rail_id() -> int:
	var used_ids: Dictionary = {}
	if CM.parsed_chart == null:
		return 1
	for rail in CM.parsed_chart.rails:
		if rail != null:
			used_ids[rail.id] = true

	var candidate := 1
	while used_ids.has(candidate):
		candidate += 1
	return candidate

static func create_default_rail(time_ms: int) -> Rail:
	var rail := Rail.new()
	var start_point := RailPoint.new()
	var end_point := RailPoint.new()

	rail.id = next_rail_id()

	start_point.x = DEFAULT_RAIL_X
	start_point.curve = 0.0
	start_point.time = time_ms

	end_point.x = DEFAULT_RAIL_X
	end_point.curve = 0.0
	end_point.time = time_ms + DEFAULT_RAIL_DURATION

	rail.points.append(start_point)
	rail.points.append(end_point)
	return rail

static func create_note(note_type: Note.NoteType, time_ms: int, dir: Note.Dir = Note.Dir.NONE) -> Note:
	var note := Note.new()
	note.time = time_ms
	note.type = note_type
	note.dir = dir
	note.length = 0
	note.animation = 0
	note.hitsound = -1
	return note

static func add_point(rail: Rail, time_ms: int, x: float) -> int:
	if rail == null:
		return -1

	var point := RailPoint.new()
	point.time = time_ms
	point.x = clamp(x, 0.0, 1.0)
	point.curve = 0.0

	rail.points.append(point)
	rail.sort_points()
	return rail.points.find(point)

static func move_rail(rail: Rail, direction: float) -> void:
	if rail == null:
		return

	for point in rail.points:
		point.x = clamp(point.x + direction * RAIL_MOVE_STEP, 0.0, 1.0)

static func remove_rail(rail: Rail) -> void:
	if CM.parsed_chart != null:
		CM.parsed_chart.rails.erase(rail)

static func remove_note(rail: Rail, note: Note) -> void:
	if rail != null:
		rail.notes.erase(note)


static func remove_note_placement_conflicts(
	rails: Array[Rail],
	target_rail: Rail,
	time_ms: int,
	note_type: Note.NoteType
) -> void:
	for rail in rails:
		if rail == null:
			continue
		for note_index in range(rail.notes.size() - 1, -1, -1):
			var existing_note: Note = rail.notes[note_index]
			if not _notes_conflict_at_placement(
				existing_note,
				rail == target_rail,
				time_ms,
				note_type
			):
				continue
			rail.notes.remove_at(note_index)


static func _notes_conflict_at_placement(
	existing_note: Note,
	is_same_rail: bool,
	time_ms: int,
	new_note_type: Note.NoteType
) -> bool:
	if existing_note == null or existing_note.time != time_ms:
		return false
	if is_same_rail:
		return true
	return (
		existing_note.type != Note.NoteType.SPIKE
		and new_note_type != Note.NoteType.SPIKE
	)

static func remove_point(rail: Rail, point_index: int) -> void:
	if rail == null or rail.points.size() <= 2:
		return
	if point_index < 0 or point_index >= rail.points.size():
		return

	rail.points.remove_at(point_index)
	rail.sort_points()

static func can_merge_rails(source_rail: Rail, source_point_index: int, target_rail: Rail, target_point_index: int) -> bool:
	if source_rail == null or target_rail == null or source_rail == target_rail:
		return false
	if source_rail.points.size() < 2 or target_rail.points.size() < 2:
		return false

	var source_is_first := source_point_index == 0
	var source_is_last := source_point_index == source_rail.points.size() - 1
	if not source_is_first and not source_is_last:
		return false

	if source_is_first:
		if target_point_index != target_rail.points.size() - 1:
			return false
		if target_rail.end_time > source_rail.points[1].time:
			return false
		return not _time_ranges_overlap(target_rail.end_time, source_rail.end_time, target_rail.start_time, target_rail.end_time)

	if target_point_index != 0:
		return false
	if target_rail.start_time < source_rail.points[source_rail.points.size() - 2].time:
		return false
	return not _time_ranges_overlap(source_rail.start_time, target_rail.start_time, target_rail.start_time, target_rail.end_time)

static func merge_rails(source_rail: Rail, source_point_index: int, target_rail: Rail, target_point_index: int) -> Rail:
	if not can_merge_rails(source_rail, source_point_index, target_rail, target_point_index):
		return null

	if source_point_index == 0:
		var source_first: RailPoint = source_rail.points[0]
		var target_last: RailPoint = target_rail.points[target_rail.points.size() - 1]
		target_last.curve = source_first.curve
		for index in range(1, source_rail.points.size()):
			target_rail.points.append(source_rail.points[index])
		target_rail.notes.append_array(source_rail.notes)
		target_rail.sort_points()
		target_rail.sort_notes()
		remove_rail(source_rail)
		return target_rail

	var source_last: RailPoint = source_rail.points[source_rail.points.size() - 1]
	var target_first: RailPoint = target_rail.points[0]
	source_last.time = target_first.time
	source_last.x = target_first.x
	source_last.curve = target_first.curve
	for index in range(1, target_rail.points.size()):
		source_rail.points.append(target_rail.points[index])
	source_rail.notes.append_array(target_rail.notes)
	source_rail.sort_points()
	source_rail.sort_notes()
	remove_rail(target_rail)
	return source_rail

static func _time_ranges_overlap(start_a: int, end_a: int, start_b: int, end_b: int) -> bool:
	return max(start_a, start_b) < min(end_a, end_b)

static func can_save(chart: Chart) -> bool:
	return (
		chart != null
		and not chart.title.strip_edges().is_empty()
		and not chart.difficulty.strip_edges().is_empty()
		and not has_duplicate_difficulty(chart, chart.difficulty)
	)

static func has_duplicate_difficulty(chart: Chart, difficulty: String) -> bool:
	if chart == null:
		return false

	var chart_set: ChartSet = chart.chart_set if chart.chart_set != null else CM.selected_chartset
	if chart_set == null:
		return false

	var target := difficulty.strip_edges()
	if target.is_empty():
		return false

	for other_chart in chart_set.charts:
		if other_chart == null or other_chart == chart:
			continue
		if other_chart.difficulty.strip_edges() == target:
			return true

	return false

static func save_chart(chart: Chart, previous_file_path: String) -> bool:
	if chart == null:
		return false

	if chart.chart_set == null:
		chart.chart_set = CM.selected_chartset
	if chart.chart_set == null:
		return false
	if chart.chart_set.db_id <= 0 and chart.chart_set.charts.is_empty():
		chart.chart_set.folder_name = CM.make_unique_chartset_folder_name(chart.title.strip_edges())
		chart.folder_name = chart.chart_set.folder_name
	if chart.folder_name.is_empty():
		chart.folder_name = chart.chart_set.folder_name

	var safe_difficulty := chart.difficulty.strip_edges().validate_filename()
	if safe_difficulty.is_empty():
		Notification.notice("difficulty cannot be used as a file name", Notification.Type.WARNING)
		return false
	chart.file_name = safe_difficulty + Config.FILE_EXTENSION
	FileSystem.ensure_dir(chart.folder_path)

	if CM.parsed_chart == null:
		CM.parsed_chart = ParsedChart.new(chart)
	else:
		CM.parsed_chart.chart = chart

	CM.parsed_chart.chart.rating = Rating.calculate_rating(CM.parsed_chart)
	var success := ChartFileStore.save(CM.parsed_chart, previous_file_path)
	if success:
		chart.build_search_string()
		success = CM.register_saved_chart(chart)
	return success

static func prepare_new_chartset_chart() -> Chart:
	var chart_set := ChartSet.new()
	chart_set.build_uuid()
	chart_set.folder_name = CM.make_unique_chartset_folder_name()

	var chart := Chart.new()
	chart.build_uuid()
	chart.chart_set = chart_set
	chart.folder_name = chart_set.folder_name

	CM.parsed_chart = ParsedChart.new(chart)
	CM.select_chartset(chart_set)
	CM.select_chart(chart)
	return chart

static func prepare_new_difficulty_chart() -> Chart:
	var source_chart := CM.selected_chart
	if source_chart == null:
		Notification.notice("no chart selected", Notification.Type.WARNING)
		return null

	var chart_set: ChartSet = source_chart.chart_set if source_chart.chart_set != null else CM.selected_chartset
	if chart_set == null:
		Notification.notice("no chartset selected", Notification.Type.WARNING)
		return null

	var chart := Chart.new()
	chart.build_uuid()
	chart.chart_set = chart_set
	chart.folder_name = chart_set.folder_name
	chart.copy_shared_metadata_from(source_chart)
	chart.rating = 0.0

	CM.parsed_chart = ParsedChart.new(chart)

	CM.select_chartset(chart_set)
	CM.select_chart(chart)
	return chart
