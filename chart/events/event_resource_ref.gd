extends RefCounted
class_name EventResourceRef

const CHART_DIRECTORY_NAME := "eventres"
const BUILTIN_PREFIX := "res/"
const BUILTIN_SPRITE_BASE_PATH := "res://resources/events/sprites"
const BUILTIN_SKIN_BASE_PATH := "res://resources/events/skins"
const INVALID_FILE_NAME_CHARACTERS := ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", ","]

static func is_builtin(reference: String) -> bool:
	return reference.strip_edges().begins_with(BUILTIN_PREFIX)

static func is_valid(reference: String) -> bool:
	var file_name := reference.strip_edges()
	if file_name.begins_with(BUILTIN_PREFIX):
		file_name = file_name.trim_prefix(BUILTIN_PREFIX)
	if file_name.is_empty() or file_name == "." or file_name == "..":
		return false
	for character in INVALID_FILE_NAME_CHARACTERS:
		if file_name.contains(character):
			return false
	return true

static func resolve(chart: Chart, reference: String, builtin_base_path: String) -> String:
	var normalized := reference.strip_edges()
	if not is_valid(normalized):
		return ""
	if is_builtin(normalized):
		return builtin_base_path.path_join(normalized.trim_prefix(BUILTIN_PREFIX))
	if chart == null:
		return ""
	return chart.folder_path.path_join(CHART_DIRECTORY_NAME).path_join(normalized)

static func resolve_sprite(chart: Chart, reference: String) -> String:
	return resolve(chart, reference, BUILTIN_SPRITE_BASE_PATH)

static func resolve_skin(chart: Chart, reference: String) -> String:
	return resolve(chart, reference, BUILTIN_SKIN_BASE_PATH)
