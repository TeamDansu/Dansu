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
	parser.parse_object(chart)
	sort_chart_objects()
	return chart

static func sort_chart_objects() -> void:
	for rail: Rail in CM.rails:
		if rail == null:
			continue
		rail.sort_points()
		rail.sort_notes()

static func next_rail_id() -> int:
	var used_ids: Dictionary = {}
	for rail in CM.rails:
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

static func create_note(note_type: int, time_ms: int, dir: int = -1) -> Note:
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
	CM.rails.erase(rail)

static func remove_note(rail: Rail, note: Note) -> void:
	if rail != null:
		rail.notes.erase(note)

static func remove_point(rail: Rail, point_index: int) -> void:
	if rail == null or rail.points.size() <= 2:
		return
	if point_index < 0 or point_index >= rail.points.size():
		return

	rail.points.remove_at(point_index)
	rail.sort_points()

static func can_save(chart: Chart) -> bool:
	return chart != null and not chart.title.strip_edges().is_empty() and not chart.difficulty.strip_edges().is_empty()

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

	var cm = CM
	if chart.chart_set == null:
		chart.chart_set = cm.selected_chartset
	if chart.chart_set == null:
		return false
	if chart.folder_name.is_empty():
		chart.folder_name = chart.chart_set.folder_name

	chart.file_name = chart.difficulty.strip_edges() + Config.FILE_EXTENSION
	FileSystem.ensure_dir(chart.folder_path)

	if not previous_file_path.is_empty() and FileAccess.file_exists(previous_file_path):
		DirAccess.remove_absolute(previous_file_path)
	if FileAccess.file_exists(chart.file_path):
		DirAccess.remove_absolute(chart.file_path)

	var writer := ChartWriter.new()
	var success := writer.write_chart(chart)
	if success:
		chart.build_search_string()
		cm.selected_chart = chart
		if not chart.chart_set.charts.has(chart):
			chart.chart_set.charts.append(chart)
	return success

static func _root() -> Node:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop.root
	return null
