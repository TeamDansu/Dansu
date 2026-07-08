extends RefCounted
class_name ChartWriter

const CHART_FILE_VERSION := 1

func write_chart(parsed_chart: ParsedChart) -> bool:
	if parsed_chart == null or parsed_chart.chart == null:
		push_error("Failed to write chart: parsed chart is missing chart metadata")
		return false

	var chart := parsed_chart.chart
	var file := FileAccess.open(chart.file_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open chart file for writing: %s" % chart.file_path)
		return false

	_write_header(file)
	_write_metadata(file, chart)
	_write_timings(file, chart)
	_write_hitsounds(file, parsed_chart)
	_write_rails(file, parsed_chart.rails)
	file.flush()
	return true

func _write_header(file: FileAccess) -> void:
	file.store_line("FILE_VERSION_" + str(CHART_FILE_VERSION))

func _write_metadata(file: FileAccess, chart: Chart) -> void:
	file.store_line("@METADATA")
	if not chart.uuid:
		chart.build_uuid()
	file.store_line("uuid: %s" % _safe_string(chart.uuid))
	file.store_line("title: %s" % _safe_string(chart.title))
	file.store_line("artist: %s" % _safe_string(chart.artist))
	file.store_line("creator: %s" % _safe_string(chart.creator))
	file.store_line("source: %s" % _safe_string(chart.source))
	file.store_line("preview_time: %s" % _safe_string(chart.preview_time))
	file.store_line("difficulty: %s" % _safe_string(chart.difficulty))
	file.store_line("file_audio: %s" % _safe_string(chart.file_audio))
	file.store_line("file_skin: %s" % _safe_string(chart.file_skin))
	file.store_line("file_cover_art: %s" % _safe_string(chart.file_cover_art))
	file.store_line("version: %s" % _safe_string(chart.version))
	file.store_line("rating: %s" % _safe_string(chart.rating))
	file.store_line("tags: %s" % _safe_string(chart.tags))
	file.store_line("")

func _write_timings(file: FileAccess, chart: Chart) -> void:
	file.store_line("@TIMINGS")
	for timing in chart.timings:
		if timing != null:
			file.store_line("%d,%s" % [timing.time, timing.bpm])
	file.store_line("")
	file.store_line("@ENDMETA")
	file.store_line("")

func _write_hitsounds(file: FileAccess, parsed_chart: ParsedChart) -> void:
	file.store_line("@HITSOUNDS")
	var chart := parsed_chart.chart
	var referenced_ids := _collect_referenced_hitsound_ids(parsed_chart)
	for hitsound in parsed_chart.hitsounds:
		if hitsound == null or hitsound.id < 0:
			continue
		if hitsound.is_builtin() and not referenced_ids.has(hitsound.id):
			continue
		file.store_line("%d:%s" % [hitsound.id, _safe_string(hitsound.file_name)])
	file.store_line("defaults:%s" % ",".join(_default_hitsound_texts(chart)))
	file.store_line("")

func _write_rails(file: FileAccess, rails: Array[Rail]) -> void:
	file.store_line("@OBJECT")
	file.store_line("# rail:{id}")
	file.store_line("# [time,curve,x]")
	file.store_line("# time,type,length,direction(d:optional),animation(a:optional),hitsound(h:optional)")
	file.store_line("# end")

	for rail in rails:
		if rail == null or rail.id < 0:
			continue

		file.store_line("rail:%d" % rail.id)
		for point: RailPoint in rail.points:
			if point != null:
				file.store_line("[%d,%s,%s]" % [int(point.time), _float_to_text(float(point.curve)), _float_to_text(float(point.x))])

		for note: Note in rail.notes:
			if note == null:
				continue

			var tokens: Array[String] = [str(int(note.time)), str(int(note.type)), str(int(note.length))]
			if int(note.animation) != 0:
				tokens.append("a:%d" % int(note.animation))
			if int(note.hitsound) >= 0:
				tokens.append("h:%d" % int(note.hitsound))
			if int(note.type) == 2 and int(note.dir) != -1:
				tokens.append("d:%d" % int(note.dir))
			file.store_line(",".join(tokens))

		file.store_line("end")
		file.store_line("")

	file.store_line("")

func _safe_string(value) -> String:
	return str(value).strip_edges()

func _float_to_text(value: float) -> String:
	var text := str(value)
	if "." in text:
		while text.ends_with("0"):
			text = text.left(text.length() - 1)
		if text.ends_with("."):
			text += "0"
	return text

func _collect_referenced_hitsound_ids(parsed_chart: ParsedChart) -> Dictionary:
	var ids: Dictionary = {}
	if parsed_chart == null:
		return ids
	var chart := parsed_chart.chart
	if chart != null:
		for value in chart.default_hitsounds:
			if int(value) >= 0:
				ids[int(value)] = true
	for rail in parsed_chart.rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null and int(note.hitsound) >= 0:
				ids[int(note.hitsound)] = true
	return ids

func _default_hitsound_texts(chart: Chart) -> Array[String]:
	var values: Array[String] = []
	if chart == null:
		for _index in range(Chart.DEFAULT_HITSOUND_SLOT_COUNT):
			values.append("-1")
		return values
	for index in range(Chart.DEFAULT_HITSOUND_SLOT_COUNT):
		values.append(str(chart.get_default_hitsound_id(index)))
	return values
