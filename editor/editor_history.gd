extends RefCounted
class_name EditorHistory

static func capture(editor: Editor) -> Dictionary:
	var parsed_chart := CM.ensure_parsed_chart()
	return {
		"chart": _capture_chart(editor.chart),
		"timings": _capture_timings(editor.chart),
		"hitsounds": _capture_hitsounds(parsed_chart.hitsounds),
		"rails": _capture_rails(parsed_chart.rails),
		"events": _capture_events(parsed_chart.events),
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
	CM.parsed_chart.events = _restore_events(snapshot.get("events", []))
	CM.parsed_chart.sort_events()
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

static func capture_events_data(events: Array[ChartEvent]) -> Array[Dictionary]:
	return _capture_events(events)

static func restore_events_data(data: Array) -> Array[ChartEvent]:
	return _restore_events(data)

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

static func _capture_events(events: Array[ChartEvent]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		if event == null:
			continue
		var event_data := {
			"id": event.id,
			"time": event.time,
			"duration": event.duration,
			"frames": [],
		}
		if event is CameraEvent:
			event_data["type"] = "camera"
			for frame in (event as CameraEvent).frames:
				if frame == null:
					continue
				event_data["frames"].append({
					"time": frame.time,
					"ease": frame.ease,
					"follow_character": frame.follow_character,
					"position": frame.position,
					"zoom": frame.zoom,
				})
		elif event is OverlayEvent:
			event_data["type"] = "overlay"
			event_data["layer"] = (event as OverlayEvent).layer
			event_data["anchor"] = (event as OverlayEvent).anchor
			for frame in (event as OverlayEvent).frames:
				if frame == null:
					continue
				event_data["frames"].append({
					"time": frame.time,
					"ease": frame.ease,
					"position": frame.position,
					"scale": frame.scale,
					"rotation": frame.rotation,
					"sprite": frame.sprite,
					"opacity": frame.opacity,
					"has_opacity": frame.has_opacity,
				})
		elif event is ThemeEvent:
			event_data["type"] = "theme"
			for frame in (event as ThemeEvent).frames:
				if frame == null:
					continue
				event_data["frames"].append({
					"time": frame.time,
					"ease": frame.ease,
					"bg_color": frame.bg_color,
					"bg_color_2": frame.bg_color_2,
					"rail_color": frame.rail_color,
				})
		elif event is SkinEvent:
			event_data["type"] = "skin"
			event_data["skin_json"] = (event as SkinEvent).skin_json
		else:
			continue
		result.append(event_data)
	return result

static func _restore_events(data: Array) -> Array[ChartEvent]:
	var result: Array[ChartEvent] = []
	for event_data in data:
		var event: ChartEvent = null
		match String(event_data.get("type", "")):
			"camera":
				var camera := CameraEvent.new()
				for frame_data in event_data.get("frames", []):
					var frame := CameraEventFrame.new()
					frame.time = int(frame_data.get("time", 0))
					frame.ease = String(frame_data.get("ease", ""))
					frame.follow_character = bool(frame_data.get("follow_character", false))
					frame.position = frame_data.get("position", Vector2.ZERO)
					frame.zoom = float(frame_data.get("zoom", 1.0))
					camera.frames.append(frame)
				event = camera
			"overlay":
				var overlay := OverlayEvent.new()
				overlay.layer = int(event_data.get("layer", 0))
				for frame_data in event_data.get("frames", []):
					var frame := OverlayEventFrame.new()
					frame.time = int(frame_data.get("time", 0))
					frame.ease = String(frame_data.get("ease", ""))
					frame.position = frame_data.get("position", Vector2.ZERO)
					var anchor_value = frame_data.get("anchor", "center")
					var frame_anchor := String(anchor_value) if anchor_value is String \
						else OverlayEventFrame.vector_to_anchor(anchor_value as Vector2)
					frame.scale = frame_data.get("scale", Vector2.ONE)
					frame.rotation = float(frame_data.get("rotation", 0.0))
					frame.sprite = String(frame_data.get("sprite", ""))
					frame.opacity = float(frame_data.get("opacity", 1.0))
					frame.has_opacity = bool(frame_data.get("has_opacity", false))
					overlay.frames.append(frame)
					if overlay.anchor == "center" and frame_anchor != "center":
						overlay.anchor = frame_anchor
				var overlay_anchor := String(event_data.get("anchor", overlay.anchor))
				if OverlayEventFrame.is_valid_anchor(overlay_anchor):
					overlay.anchor = overlay_anchor
				event = overlay
			"theme":
				var theme := ThemeEvent.new()
				for frame_data in event_data.get("frames", []):
					var frame := ThemeEventFrame.new()
					frame.time = int(frame_data.get("time", 0))
					frame.ease = String(frame_data.get("ease", ""))
					frame.bg_color = frame_data.get("bg_color", Color.BLACK)
					frame.bg_color_2 = frame_data.get("bg_color_2", Color.BLACK)
					frame.rail_color = frame_data.get("rail_color", Color.WHITE)
					theme.frames.append(frame)
				event = theme
			"skin":
				var skin := SkinEvent.new()
				skin.skin_json = String(event_data.get("skin_json", ""))
				event = skin
		if event == null:
			continue
		event.id = String(event_data.get("id", ""))
		event.time = int(event_data.get("time", 0))
		event.duration = int(event_data.get("duration", 0))
		result.append(event)
	return result

static func _capture_selection(selection: ChartEditorSelection) -> Dictionary:
	if selection != null and selection.selected_event != null:
		var event_index := -1
		if CM.parsed_chart != null:
			event_index = CM.parsed_chart.events.find(selection.selected_event)
		return {
			"kind": "event",
			"event_index": event_index,
			"event_id": selection.selected_event.id,
			"event_time": selection.selected_event.time,
			"frame_index": selection.selected_event_frame_index,
		}
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
	if kind == "event":
		if CM.parsed_chart == null:
			editor.selection.clear()
			return
		var target_event: ChartEvent = null
		var event_index := int(data.get("event_index", -1))
		if event_index >= 0 and event_index < CM.parsed_chart.events.size():
			target_event = CM.parsed_chart.events[event_index]
		if target_event == null \
				or target_event.id != String(data.get("event_id", "")) \
				or target_event.time != int(data.get("event_time", target_event.time)):
			target_event = null
			for event in CM.parsed_chart.events:
				if event != null \
						and event.id == String(data.get("event_id", "")) \
						and event.time == int(data.get("event_time", event.time)):
					target_event = event
					break
		if target_event == null:
			editor.selection.clear()
			return
		editor.selection.select_event(target_event, int(data.get("frame_index", -1)))
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
