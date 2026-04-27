extends RefCounted
class_name Chart

const DEFAULT_HITSOUND_HIT := 0
const DEFAULT_HITSOUND_MOVE := 1
const DEFAULT_HITSOUND_TRACE := 2
const DEFAULT_HITSOUND_SPIKE := 3
const DEFAULT_HITSOUND_LONGNOTE_RELEASE := 4
const DEFAULT_HITSOUND_SLOT_COUNT := 5

func _init() -> void:
	timings = []
	default_hitsounds = PackedInt32Array([-1, -1, -1, -1, -1])

var version: int = 1
var uuid: String = ""
var filehash: String = ""
var folder_name: String = ""
var file_name: String = ""
var is_built_in := false
var chart_set: ChartSet = null


var skin_path: String:
	get:
		return FileSystem.chart_path.path_join(folder_name).path_join(file_skin)

var file_path: String:
	get:
		return FileSystem.chart_path.path_join(folder_name).path_join(file_name)

var folder_path: String:
	get:
		return FileSystem.chart_path.path_join(folder_name)

var search_string: String = ""
var search_string_lower: String = ""

func build_search_string() -> void:
	search_string = title + "-" + artist + "-" + creator + "-" + tags + "-" + difficulty + "-" + source
	search_string_lower = search_string.to_lower()

var title: String = "?"
var artist: String = "?"
var creator: String = "?"
var source: String = "?"
var tags: String = ""
var difficulty: String = "?"
var rating: float = 0.0

var preview_time := -1.0
var timings: Array[Timing]
var default_hitsounds: PackedInt32Array

var file_audio: String = "song.mp3"
var file_cover_art: String = ""
var file_skin: String = ""

var cover_image: Texture2D

func get_cover_path() -> String:
	if file_cover_art.is_empty():
		return ""
	return folder_path.path_join(file_cover_art)

func load_cover_image_data() -> Image:
	var cover_path := get_cover_path()
	if cover_path.is_empty():
		return null
	return FileSystem.get_image(cover_path)

func get_stream() -> AudioStream:
	if file_audio.is_empty():
		return null

	var full_path := folder_path.path_join(file_audio)
	if not FileAccess.file_exists(full_path):
		return null

	var ext := file_audio.get_extension().to_lower()
	match ext:
		"mp3":
			return AudioStreamMP3.load_from_file(full_path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(full_path)
		"wav":
			return AudioStreamWAV.load_from_file(full_path)
		_:
			push_warning("not supported audio format: %s" % ext)
			return null

func reset_default_hitsounds() -> void:
	default_hitsounds = PackedInt32Array([-1, -1, -1, -1, -1])

func get_default_hitsound_id(slot: int) -> int:
	if slot < 0 or slot >= default_hitsounds.size():
		return -1
	return int(default_hitsounds[slot])

func set_default_hitsound_id(slot: int, hitsound_id: int) -> void:
	if slot < 0:
		return
	while default_hitsounds.size() < DEFAULT_HITSOUND_SLOT_COUNT:
		default_hitsounds.append(-1)
	if slot >= default_hitsounds.size():
		return
	default_hitsounds[slot] = hitsound_id

func get_default_hitsound_slot_for_note(note: Note) -> int:
	if note == null:
		return DEFAULT_HITSOUND_HIT
	match int(note.type):
		int(Note.NoteType.MOVE):
			return DEFAULT_HITSOUND_MOVE
		int(Note.NoteType.TRACE):
			return DEFAULT_HITSOUND_TRACE
		int(Note.NoteType.SPIKE):
			return DEFAULT_HITSOUND_SPIKE
		_:
			return DEFAULT_HITSOUND_HIT
