extends ChartParser
class_name ObjectParserV1

enum { OBJECT, HITSOUNDS }

func parse(file: FileAccess, chart: Chart) -> bool:
	var mode := -1
	var current_rail: Rail = null
	if chart != null:
		chart.reset_default_hitsounds()

	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		if line.begins_with("@"):
			match line.replace(" ", ""):
				"@HITSOUNDS":
					mode = HITSOUNDS
				"@OBJECT":
					mode = OBJECT
			continue

		match mode:
			OBJECT:
				current_rail = _parse_rail_line(line, current_rail)
			HITSOUNDS:
				_parse_hitsound_line(chart, line)

	return true

func _parse_note_line(line: String) -> Note:
	var parts := line.split(",", false)
	if parts.size() < 3:
		push_error("FILE : WRONG NOTE FORMAT : %s" % line)
		return null

	var new_note := Note.new()
	new_note.time = int(parts[0])
	new_note.type = int(parts[1]) as Note.NoteType
	new_note.length = int(parts[2])

	for i in range(3, parts.size()):
		var token := parts[i].strip_edges()
		var idx := token.find(":")
		if idx == -1:
			continue

		var key := token.substr(0, idx)
		var value := token.substr(idx + 1)
		match key:
			"a":
				new_note.animation = int(value)
			"h":
				new_note.hitsound = int(value)
			"d":
				new_note.dir = int(value) as Note.Dir

	return new_note

func _parse_hitsound_line(chart: Chart, line: String) -> void:
	if line.begins_with("defaults:"):
		var values := line.trim_prefix("defaults:").split(",", false)
		for index in range(min(values.size(), Chart.DEFAULT_HITSOUND_SLOT_COUNT)):
			var value_text := values[index].strip_edges()
			if value_text.is_valid_int():
				chart.set_default_hitsound_id(index, value_text.to_int())
		return

	var separator := ":" if line.find(":") != -1 else ","
	var idx := line.find(separator)
	if idx == -1:
		return

	var id_text := line.substr(0, idx).strip_edges()
	var file_name := line.substr(idx + 1).strip_edges()
	if not id_text.is_valid_int():
		return

	var hitsound_id := int(id_text)
	for existing in CM.hitsounds:
		if existing != null and existing.id == hitsound_id:
			existing.setup(chart, hitsound_id, file_name)
			return

	var hitsound := HitSound.new()
	hitsound.setup(chart, hitsound_id, file_name)
	CM.hitsounds.append(hitsound)

func _parse_rail_line(line: String, current_rail: Rail) -> Rail:
	if line.begins_with("rail:"):
		var id_text := line.trim_prefix("rail:").strip_edges()
		if not id_text.is_valid_int():
			return current_rail

		var new_rail := Rail.new()
		new_rail.id = int(id_text)
		CM.rails.append(new_rail)
		return new_rail

	if line == "end":
		return null
	if current_rail == null:
		return null

	if line.begins_with("[") and line.ends_with("]"):
		line = line.substr(1, line.length() - 2)
		var parts := line.split(",", false)
		if parts.size() < 3:
			return current_rail

		var point := RailPoint.new()
		point.time = int(parts[0])
		point.curve = float(parts[1])
		point.x = float(parts[2])
		current_rail.points.append(point)
	else:
		var note: Note = _parse_note_line(line)
		if note != null:
			current_rail.notes.append(note)

	return current_rail
