extends Node

const SAVE_PATH : String = "user://scores"
const FIELD_NAMES = [
	"score", "note", "perfect_plus", "perfect", "good",
	"ok", "bad", "miss", "high_combo", "object_hash"
]

var save_data: Dictionary = {}

func save_score(score: Score):
	if score.uuid == null or score.uuid == "":
		return
	var data: Dictionary = {
		"score": score.total_score,
		"note": score.c_note,
		"perfect_plus": score.c_perfect_plus,
		"perfect": score.c_perfect,
		"good": score.c_great,
		"ok": score.c_ok,
		"bad": score.c_bad,
		"miss": score.c_miss,
		"high_combo": score.high_combo,
		"object_hash": score.object_hash
	}
	if save_data.has(score.uuid):
		save_data[score.uuid].append(data)
	else:
		save_data[score.uuid] = [data]
	Game.save_data_to_file()

func load_data():
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var text = file.get_as_text()
		var parsed = JSON.parse_string(text)
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			for uuid in parsed.keys():
				var new_entries: Array = []
				for entry in parsed[uuid]:
					match typeof(entry):
						TYPE_DICTIONARY:
							var compact_entry: Array = [
								snappedf(entry.get("score", 0.0), 0.0001),
								entry.get("note", 0),
								entry.get("perfect_plus", 0),
								entry.get("perfect", 0),
								entry.get("good", 0),
								entry.get("ok", 0),
								entry.get("bad", 0),
								entry.get("miss", 0),
								entry.get("high_combo", 0),
								entry.get("object_hash", "")
							]
							new_entries.append(compact_entry)
						TYPE_ARRAY:
							var restored_entry := {}
							for i in entry.size():
								if i < FIELD_NAMES.size():
									restored_entry[FIELD_NAMES[i]] = entry[i]
							new_entries.append(restored_entry)
				parsed[uuid] = new_entries
		save_data = parsed
		save_data_to_file()
	else:
		save_data = {}
		save_data_to_file()

func save_data_to_file():
	var data_to_save: Dictionary = {}
	for uuid in save_data.keys():
		var new_entries: Array = []
		for entry in save_data[uuid]:
			match typeof(entry):
				TYPE_DICTIONARY:
					var compact_entry: Array = [
						snappedf(entry.get("score", 0.0), 0.0001),
						entry.get("note", 0),
						entry.get("perfect_plus", 0),
						entry.get("perfect", 0),
						entry.get("good", 0),
						entry.get("ok", 0),
						entry.get("bad", 0),
						entry.get("miss", 0),
						entry.get("high_combo", 0),
						entry.get("object_hash", "")
					]
					new_entries.append(compact_entry)
				TYPE_ARRAY:
					new_entries.append(entry)
		data_to_save[uuid] = new_entries
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(data_to_save)
		file.store_string(json_string)
		file.close()

func get_scores_for_uuid(uuid_to_load: String) -> Array:
	if save_data.has(uuid_to_load):
		return save_data[uuid_to_load]
	else:
		return []
