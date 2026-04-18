extends RefCounted
class_name HitSound

const BUILTIN_BASE_PATH := "res://resorces/audio/hitsounds"

var id: int = -1
var file_name: String = ""
var file_path: String = ""
var stream: AudioStream = null

func setup(chart: Chart, id_value: int, file_name_value: String) -> void:
	id = id_value
	file_name = file_name_value.strip_edges()
	load_from_chart(chart)

func load_from_chart(chart: Chart) -> void:
	if file_name.is_empty():
		return

	if file_name.begins_with("res/"):
		file_path = BUILTIN_BASE_PATH.path_join(file_name.trim_prefix("res/"))
	elif chart != null:
		file_path = chart.folder_path.path_join(file_name)
	else:
		file_path = ""

	if file_path.is_empty() or not ResourceLoader.exists(file_path):
		stream = null
		return

	stream = load(file_path) as AudioStream

func is_builtin() -> bool:
	return file_name.begins_with("res/")

func get_display_name() -> String:
	if file_name.is_empty():
		return "Unnamed"
	return file_name.get_file()

static func load_builtin_hitsounds() -> Array[HitSound]:
	var results: Array[HitSound] = []
	var files: PackedStringArray = []
	var dir := DirAccess.open(BUILTIN_BASE_PATH)
	if dir == null:
		return results

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "wav":
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	files.sort()

	for index in range(files.size()):
		var hitsound := HitSound.new()
		hitsound.setup(null, index, "res/%s" % files[index])
		results.append(hitsound)
	return results
