extends RefCounted
class_name SkinSerialization

const SkinValidationScript = preload("res://skin/skin_validation.gd")

static func save_skin_document(document, target_file_path: String = "") -> String:
	if document == null or document.skin_data == null:
		return ""

	var target_path: String = target_file_path if target_file_path != "" else document.file_path
	if target_path == "":
		return ""

	FileSystem.ensure_dir(target_path.get_base_dir())
	FileSystem.ensure_dir(target_path.get_base_dir().path_join("sprite"))

	SkinValidationScript.ensure_unique_animation_ids(document.skin_data)
	SkinValidationScript.cleanup_player_slots(document.skin_data)

	var payload := {
		"name": document.skin_data.skin_name,
		"scale": document.skin_data.scale,
		"animations": _build_animation_payload(document.skin_data),
		"player": _build_player_payload(document.skin_data),
	}

	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(payload, "\t"))
	file.store_string("\n")
	file.close()

	document.file_path = target_path
	document.directory_path = target_path.get_base_dir()
	document.sprite_directory_path = document.directory_path.path_join("sprite")
	document.context.skin_file_path = target_path
	document.clear_dirty()
	return target_path

static func clone_skin_to_directory(source_skin_path: String, target_directory_path: String, preferred_name: String) -> String:
	var source_directory := source_skin_path.get_base_dir()
	var source_sprite_directory := source_directory.path_join("sprite")
	var file_name := preferred_name.validate_filename()
	if file_name == "":
		file_name = "skin"
	var target_path: String = _make_unique_skin_file_path(target_directory_path, file_name)
	var target_sprite_directory := target_path.get_base_dir().path_join("sprite")

	FileSystem.ensure_dir(target_path.get_base_dir())
	FileSystem.ensure_dir(target_sprite_directory)

	var source_text := FileAccess.get_file_as_string(source_skin_path)
	var data = JSON.parse_string(source_text)
	if typeof(data) != TYPE_DICTIONARY:
		return ""

	data["name"] = target_path.get_basename().get_file()

	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	file.store_string("\n")
	file.close()

	if DirAccess.dir_exists_absolute(source_sprite_directory):
		for sprite_file_name in DirAccess.get_files_at(source_sprite_directory):
			var source_file := source_sprite_directory.path_join(sprite_file_name)
			var target_file := target_sprite_directory.path_join(sprite_file_name)
			_copy_file(source_file, target_file)

	return target_path

static func import_sprite_files(document, source_paths: PackedStringArray) -> Array[String]:
	var imported: Array[String] = []
	if document == null:
		return imported

	FileSystem.ensure_dir(document.sprite_directory_path)
	for source_path in source_paths:
		if source_path == "":
			continue
		var target_file_name := _make_unique_file_name(document.sprite_directory_path, source_path.get_file())
		var target_path: String = document.sprite_directory_path.path_join(target_file_name)
		var error := _copy_file(source_path, target_path)
		if error == OK:
			imported.append(target_file_name)
	return imported

static func ensure_custom_skin_path() -> String:
	if Config.custom_skin_path != "" and FileAccess.file_exists(ProjectSettings.globalize_path(Config.custom_skin_path)):
		return ProjectSettings.globalize_path(Config.custom_skin_path)

	var target_directory := ProjectSettings.globalize_path("user://skins/default")
	var cloned_path := clone_skin_to_directory(
		ProjectSettings.globalize_path(Config.DEFAULT_SKIN_PATH),
		target_directory,
		"default"
	)
	if cloned_path != "":
		Config.custom_skin_path = ProjectSettings.localize_path(cloned_path)
		Config.save_config()
	return cloned_path

static func ensure_chart_skin_path(chart) -> String:
	if chart == null:
		return ""
	if chart.file_skin != "":
		return ProjectSettings.globalize_path(chart.skin_path)

	var source_path := ensure_custom_skin_path()
	if source_path == "":
		source_path = ProjectSettings.globalize_path(Config.DEFAULT_SKIN_PATH)

	var preferred_name: String = chart.file_name.get_basename()
	if preferred_name == "":
		preferred_name = chart.difficulty if chart.difficulty != "" else "chart_skin"
	var chart_directory := ProjectSettings.globalize_path(chart.folder_path)
	var cloned_path := clone_skin_to_directory(source_path, chart_directory, preferred_name)
	if cloned_path != "":
		chart.file_skin = cloned_path.get_file()
	return cloned_path

static func make_unique_skin_file_path(directory_path: String, preferred_name: String) -> String:
	return _make_unique_skin_file_path(directory_path, preferred_name)

static func _build_animation_payload(skin_data) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for animation in skin_data.animations:
		if animation == null:
			continue
		result.append({
			"id": int(animation.id),
			"frames": animation.frames_file_name.duplicate(),
			"fps": animation.fps,
			"name": animation.name,
			"effect": animation.effect,
			"return_idle": animation.return_idle,
		})
	return result

static func _build_player_payload(skin_data) -> Dictionary:
	var hits: Array[int] = []
	for animation in skin_data.hits:
		if animation != null:
			hits.append(int(animation.id))

	return {
		"idle": _animation_id(skin_data.idle, 1),
		"left": _animation_id(skin_data.left, -1),
		"right": _animation_id(skin_data.right, -1),
		"jump": _animation_id(skin_data.jump, _animation_id(skin_data.idle, 1)),
		"land": _animation_id(skin_data.land, _animation_id(skin_data.idle, 1)),
		"hits": hits,
		"repeat_idle": skin_data.repeat_idle,
	}

static func _animation_id(animation, fallback: int) -> int:
	return int(animation.id) if animation != null else fallback

static func _make_unique_skin_file_path(directory_path: String, preferred_name: String) -> String:
	var base_name := preferred_name.validate_filename()
	if base_name == "":
		base_name = "skin"
	return directory_path.path_join(_make_unique_file_name(directory_path, "%s.json" % base_name))

static func _make_unique_file_name(directory_path: String, file_name: String) -> String:
	var base_name := file_name.get_basename()
	var extension := file_name.get_extension()
	var candidate := file_name
	var index := 2
	while FileAccess.file_exists(directory_path.path_join(candidate)):
		candidate = "%s(%d).%s" % [base_name, index, extension]
		index += 1
	return candidate

static func _copy_file(source_path: String, target_path: String) -> int:
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty() and not FileAccess.file_exists(source_path):
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_OPEN
	file.store_buffer(bytes)
	file.close()
	return OK
