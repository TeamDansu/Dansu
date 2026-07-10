extends RefCounted
class_name EditorHistory

static func capture(editor: Editor) -> Dictionary:
	var parsed_chart := CM.ensure_parsed_chart()
	return {
		"chart": _capture_chart(editor.chart),
		"timings": _capture_timings(editor.chart),
		"hitsounds": _capture_hitsounds(parsed_chart.hitsounds),
		"rails": _capture_rails(parsed_chart.rails),
		"selection": _capture_selection(editor.selection),
		"current_time": Game.current_time,
		"beat_division": editor.timeline.beat_division if editor.timeline != null else 4,
	}

static func restore(editor: Editor, snapshot: Dictionary) -> void:
	if editor == null or editor.chart == null:
		return
	_restore_chart(editor.chart, snapshot.get("chart", {}))
	editor.chart.cover_image = null
	editor.transport.chart = editor.chart
	editor.transport.load_stream()
	editor.chart.timings = _restore_timings(snapshot.get("timings", []))
	CM.parsed_chart = ParsedChart.new(editor.chart)
	CM.parsed_chart.hitsounds = _restore_hitsounds(editor.chart, snapshot.get("hitsounds", []))
	CM.parsed_chart.rails = _restore_rails(snapshot.get("rails", []))
	editor.timeline = EditorTimeline.new(editor.chart, editor.transport.stream_length_sec)
	editor.timeline.beat_division = int(snapshot.get("beat_division", 4))
	editor.transport.timeline = editor.timeline
	Game.current_time = editor.timeline.clamp_time(float(snapshot.get("current_time", 0.0)))
	editor.hitsound_manager.rebuild_cache()
	editor.selection.clear()
	editor._refresh_metadata_fields()
	editor._rebuild_timing_ui()
	editor._update_slider_range()
	editor._update_beat_division_ui()
	editor._refresh_views()
	_restore_selection(editor, snapshot.get("selection", {}))
	editor._update_time_ui(true)
	editor._update_save_button_state()
	editor.hitsounds_changed.emit()

static func same_snapshot(a: Dictionary, b: Dictionary) -> bool:
	return var_to_str(a) == var_to_str(b)

static func _capture_chart(chart: Chart) -> Dictionary:
	if chart == null:
		return {}
	return {
		"version": chart.version,
		"uuid": chart.uuid,
		"folder_name": chart.folder_name,
		"file_name": chart.file_name,
		"title": chart.title,
		"artist": chart.artist,
		"creator": chart.creator,
		"source": chart.source,
		"tags": chart.tags,
		"difficulty": chart.difficulty,
		"rating": chart.rating,
		"preview_time": chart.preview_time,
		"file_audio": chart.file_audio,
		"file_cover_art": chart.file_cover_art,
		"file_skin": chart.file_skin,
		"default_hitsounds": chart.default_hitsounds,
	}

static func _restore_chart(chart: Chart, data: Dictionary) -> void:
	chart.version = int(data.get("version", chart.version))
	chart.uuid = String(data.get("uuid", chart.uuid))
	chart.folder_name = String(data.get("folder_name", chart.folder_name))
	chart.file_name = String(data.get("file_name", chart.file_name))
	chart.title = String(data.get("title", chart.title))
	chart.artist = String(data.get("artist", chart.artist))
	chart.creator = String(data.get("creator", chart.creator))
	chart.source = String(data.get("source", chart.source))
	chart.tags = String(data.get("tags", chart.tags))
	chart.difficulty = String(data.get("difficulty", chart.difficulty))
	chart.rating = float(data.get("rating", chart.rating))
	chart.preview_time = float(data.get("preview_time", chart.preview_time))
	chart.file_audio = String(data.get("file_audio", chart.file_audio))
	chart.file_cover_art = String(data.get("file_cover_art", chart.file_cover_art))
	chart.file_skin = String(data.get("file_skin", chart.file_skin))
	chart.default_hitsounds = PackedInt32Array(data.get("default_hitsounds", PackedInt32Array([-1, -1, -1, -1, -1])))

static func _capture_timings(chart: Chart) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if chart == null:
		return result
	for timing in chart.timings:
		if timing == null:
			continue
		result.append({"time": timing.time, "bpm": timing.bpm})
	return result

static func _restore_timings(data: Array) -> Array[Timing]:
	var result: Array[Timing] = []
	for item in data:
		var timing := Timing.new()
		timing.time = int(item.get("time", 0))
		timing.bpm = float(item.get("bpm", 120.0))
		result.append(timing)
	return result

static func _capture_hitsounds(hitsounds: Array[HitSound]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hitsound in hitsounds:
		if hitsound == null:
			continue
		result.append({
			"id": hitsound.id,
			"file_name": hitsound.file_name,
		})
	return result

static func _restore_hitsounds(chart: Chart, data: Array) -> Array[HitSound]:
	var result: Array[HitSound] = []
	for item in data:
		var hitsound := HitSound.new()
		hitsound.setup(chart, int(item.get("id", -1)), String(item.get("file_name", "")))
		result.append(hitsound)
	return result

static func _capture_rails(rails: Array[Rail]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for rail in rails:
		if rail == null:
			continue
		var rail_data := {"id": rail.id, "points": [], "notes": []}
		for point in rail.points:
			if point == null:
				continue
			rail_data["points"].append({"x": point.x, "curve": point.curve, "time": point.time})
		for note in rail.notes:
			if note == null:
				continue
			rail_data["notes"].append({
				"time": note.time,
				"type": int(note.type),
				"dir": int(note.dir),
				"length": note.length,
				"animation": note.animation,
				"hitsound": note.hitsound,
			})
		result.append(rail_data)
	return result

static func _restore_rails(data: Array) -> Array[Rail]:
	var result: Array[Rail] = []
	for rail_data in data:
		var rail := Rail.new()
		rail.id = int(rail_data.get("id", -1))
		for point_data in rail_data.get("points", []):
			var point := RailPoint.new()
			point.x = float(point_data.get("x", 0.5))
			point.curve = float(point_data.get("curve", 0.0))
			point.time = int(point_data.get("time", 0))
			rail.points.append(point)
		for note_data in rail_data.get("notes", []):
			var note := Note.new()
			note.time = int(note_data.get("time", 0))
			note.type = int(note_data.get("type", int(Note.NoteType.HIT))) as Note.NoteType
			note.dir = int(note_data.get("dir", int(Note.Dir.NONE))) as Note.Dir
			note.length = int(note_data.get("length", 0))
			note.animation = int(note_data.get("animation", 0))
			note.hitsound = int(note_data.get("hitsound", -1))
			rail.notes.append(note)
		rail.sort_points()
		rail.sort_notes()
		result.append(rail)
	return result

static func _capture_selection(selection: ChartEditorSelection) -> Dictionary:
	if selection == null or selection.selected_rail == null:
		return {"kind": "clear"}
	var data := {
		"kind": "rail",
		"rail_id": selection.selected_rail.id,
		"point_index": -1,
		"note_index": -1,
	}
	if selection.selected_note != null:
		data["kind"] = "note"
		data["note_index"] = selection.selected_rail.notes.find(selection.selected_note)
	elif selection.has_point():
		data["kind"] = "point"
		data["point_index"] = selection.selected_point_index
	return data

static func _restore_selection(editor: Editor, data: Dictionary) -> void:
	var kind := String(data.get("kind", "clear"))
	if kind == "clear":
		editor.selection.clear()
		return
	var rail_id := int(data.get("rail_id", -1))
	var target_rail: Rail = null
	if CM.parsed_chart == null:
		editor.selection.clear()
		return
	for rail in CM.parsed_chart.rails:
		if rail != null and rail.id == rail_id:
			target_rail = rail
			break
	if target_rail == null:
		editor.selection.clear()
		return
	if kind == "note":
		var note_index := int(data.get("note_index", -1))
		if note_index >= 0 and note_index < target_rail.notes.size():
			editor.selection.select_note(target_rail, target_rail.notes[note_index])
			return
	if kind == "point":
		var point_index := int(data.get("point_index", -1))
		if point_index >= 0 and point_index < target_rail.points.size():
			editor.selection.select_point(target_rail, point_index)
			return
	editor.selection.select_rail(target_rail)
