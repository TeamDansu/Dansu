extends RefCounted
class_name SkinSerialization

const SkinValidationScript = preload("res://skin/skin_validation.gd")
const SkinRefCleanupScript = preload("res://skin/skin_ref_cleanup.gd")
const CHART_SKINS_DIR_NAME := "skins"
const CHART_SKIN_JSON_NAME := "skin.json"
const CHART_SKIN_SPRITES_DIR_NAME := "sprites"
const LEGACY_SKIN_SPRITES_DIR_NAME := "sprite"

static func save_skin_document(document, target_file_path: String = "") -> String:
	if document == null or document.skin_data == null:
		return ""

	var target_path: String = target_file_path if target_file_path != "" else document.file_path
	if target_path == "":
		return ""

	var previous_directory_path = document.directory_path
	var previous_sprite_directory_path = document.sprite_directory_path
	var sprite_directory_name = document.sprite_directory_name

	FileSystem.ensure_dir(target_path.get_base_dir())
	FileSystem.ensure_dir(target_path.get_base_dir().path_join(sprite_directory_name))
	if previous_directory_path != "" and previous_directory_path != target_path.get_base_dir():
		_copy_directory_contents(previous_sprite_directory_path, target_path.get_base_dir().path_join(sprite_directory_name))

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
	document.sprite_directory_name = sprite_directory_name
	document.sprite_directory_path = document.directory_path.path_join(sprite_directory_name)
	document.context.skin_file_path = target_path
	document.clear_dirty()
	return target_path

static func clone_skin_to_directory(source_skin_path: String, target_directory_path: String, preferred_name: String) -> String:
	var source_directory := source_skin_path.get_base_dir()
	var source_sprite_directory := _find_source_sprite_directory(source_directory)
	var file_name := preferred_name.validate_filename()
	if file_name == "":
		file_name = "skin"
	var target_path: String = _make_unique_skin_file_path(target_directory_path, file_name)
	var target_sprite_directory := target_path.get_base_dir().path_join(LEGACY_SKIN_SPRITES_DIR_NAME)

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
		_copy_directory_contents(source_sprite_directory, target_sprite_directory)

	return target_path

static func clone_skin_to_chart_directory(source_skin_path: String, chart_directory_path: String, preferred_name: String) -> String:
	var source_directory := source_skin_path.get_base_dir()
	var source_sprite_directory := _find_source_sprite_directory(source_directory)
	var target_path := make_unique_chart_skin_file_path(chart_directory_path, preferred_name)
	if target_path == "":
		return ""

	var target_directory := target_path.get_base_dir()
	var target_sprite_directory := target_directory.path_join(CHART_SKIN_SPRITES_DIR_NAME)
	FileSystem.ensure_dir(target_directory)
	FileSystem.ensure_dir(target_sprite_directory)

	var source_text := FileAccess.get_file_as_string(source_skin_path)
	var data = JSON.parse_string(source_text)
	if typeof(data) != TYPE_DICTIONARY:
		return ""

	data["name"] = target_directory.get_file()

	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	file.store_string("\n")
	file.close()

	if DirAccess.dir_exists_absolute(source_sprite_directory):
		_copy_directory_contents(source_sprite_directory, target_sprite_directory)

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
	migrate_chart_skin_layout(chart)
	if chart.file_skin != "":
		return ProjectSettings.globalize_path(chart.skin_path)

	var source_path := ensure_custom_skin_path()
	if source_path == "":
		source_path = ProjectSettings.globalize_path(Config.DEFAULT_SKIN_PATH)

	var preferred_name: String = chart.file_name.get_basename()
	if preferred_name == "":
		preferred_name = chart.difficulty if chart.difficulty != "" else "chart_skin"
	var chart_directory := ProjectSettings.globalize_path(chart.folder_path)
	var cloned_path := clone_skin_to_chart_directory(source_path, chart_directory, preferred_name)
	if cloned_path != "":
		chart.file_skin = cloned_path.get_base_dir().get_file()
	return cloned_path

static func make_unique_skin_file_path(directory_path: String, preferred_name: String) -> String:
	return _make_unique_skin_file_path(directory_path, preferred_name)

static func make_unique_chart_skin_file_path(chart_folder_path: String, preferred_name: String) -> String:
	var skin_directory := _make_unique_chart_skin_directory_path(chart_folder_path, preferred_name)
	if skin_directory == "":
		return ""
	return skin_directory.path_join(CHART_SKIN_JSON_NAME)

static func get_chart_skin_root_path(chart_folder_path: String) -> String:
	return chart_folder_path.path_join(CHART_SKINS_DIR_NAME)

static func delete_obsolete_skin_path(old_skin_file_path: String, preserved_skin_file_path: String = "") -> void:
	if old_skin_file_path == "" or old_skin_file_path == preserved_skin_file_path:
		return

	var old_directory_path := old_skin_file_path.get_base_dir().simplify_path()
	var preserved_directory_path := preserved_skin_file_path.get_base_dir().simplify_path() if preserved_skin_file_path != "" else ""

	if FileAccess.file_exists(old_skin_file_path):
		DirAccess.remove_absolute(old_skin_file_path)

	if old_directory_path == "" or old_directory_path == preserved_directory_path:
		return

	_remove_directory_recursive(old_directory_path.path_join(CHART_SKIN_SPRITES_DIR_NAME))
	_remove_directory_recursive(old_directory_path.path_join(LEGACY_SKIN_SPRITES_DIR_NAME))
	_remove_directory_if_empty(old_directory_path)

static func migrate_chartset_skin_layout(charts: Array[Chart]) -> void:
	if charts.is_empty():
		return

	var chart_folder_path := ProjectSettings.globalize_path(charts[0].folder_path)
	var rename_lookup := {}

	for chart in charts:
		if chart == null:
			continue
		var original_skin_ref := chart.file_skin.strip_edges()
		if original_skin_ref == "":
			continue
		if rename_lookup.has(original_skin_ref):
			continue
		if not _is_legacy_chart_skin_reference(chart_folder_path, original_skin_ref):
			continue

		var migrated_skin_name := _migrate_legacy_chart_skin(chart_folder_path, original_skin_ref)
		if migrated_skin_name == "":
			continue

		rename_lookup[original_skin_ref] = migrated_skin_name

	for old_skin_name in rename_lookup.keys():
		var new_skin_name := String(rename_lookup[old_skin_name])
		SkinRefCleanupScript.rename_skin_references(chart_folder_path, String(old_skin_name), new_skin_name)
		for chart in charts:
			if chart != null and chart.file_skin == String(old_skin_name):
				chart.file_skin = new_skin_name

static func migrate_chart_skin_layout(chart) -> void:
	if chart == null or chart.chart_set == null:
		return
	migrate_chartset_skin_layout(chart.chart_set.charts)

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

static func _make_unique_chart_skin_directory_path(chart_folder_path: String, preferred_name: String) -> String:
	var base_name := preferred_name.validate_filename()
	if base_name == "":
		base_name = "skin"

	var skins_root_path := get_chart_skin_root_path(chart_folder_path)
	FileSystem.ensure_dir(skins_root_path)

	var candidate := base_name
	var index := 2
	while DirAccess.dir_exists_absolute(skins_root_path.path_join(candidate)):
		candidate = "%s(%d)" % [base_name, index]
		index += 1
	return skins_root_path.path_join(candidate)

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

static func _copy_directory_contents(source_directory_path: String, target_directory_path: String) -> void:
	if source_directory_path == "" or not DirAccess.dir_exists_absolute(source_directory_path):
		return
	FileSystem.ensure_dir(target_directory_path)
	for file_name in DirAccess.get_files_at(source_directory_path):
		_copy_file(source_directory_path.path_join(file_name), target_directory_path.path_join(file_name))

static func _remove_directory_recursive(directory_path: String) -> void:
	if directory_path == "" or not DirAccess.dir_exists_absolute(directory_path):
		return

	for child_directory_name in DirAccess.get_directories_at(directory_path):
		_remove_directory_recursive(directory_path.path_join(child_directory_name))

	for child_file_name in DirAccess.get_files_at(directory_path):
		DirAccess.remove_absolute(directory_path.path_join(child_file_name))

	DirAccess.remove_absolute(directory_path)

static func _remove_directory_if_empty(directory_path: String) -> void:
	if directory_path == "" or not DirAccess.dir_exists_absolute(directory_path):
		return
	if not DirAccess.get_directories_at(directory_path).is_empty():
		return
	if not DirAccess.get_files_at(directory_path).is_empty():
		return
	DirAccess.remove_absolute(directory_path)

static func _find_source_sprite_directory(directory_path: String) -> String:
	var new_directory := directory_path.path_join(CHART_SKIN_SPRITES_DIR_NAME)
	if DirAccess.dir_exists_absolute(new_directory):
		return new_directory
	return directory_path.path_join(LEGACY_SKIN_SPRITES_DIR_NAME)

static func _is_legacy_chart_skin_reference(chart_folder_path: String, skin_reference: String) -> bool:
	if skin_reference == "":
		return false
	if skin_reference.get_extension().to_lower() != "json":
		return false
	return FileAccess.file_exists(chart_folder_path.path_join(skin_reference))

static func _migrate_legacy_chart_skin(chart_folder_path: String, legacy_skin_reference: String) -> String:
	var source_skin_path := chart_folder_path.path_join(legacy_skin_reference)
	if not FileAccess.file_exists(source_skin_path):
		return ""

	var preferred_name := legacy_skin_reference.get_basename().validate_filename()
	if preferred_name == "":
		preferred_name = "skin"

	var target_path := make_unique_chart_skin_file_path(chart_folder_path, preferred_name)
	if target_path == "":
		return ""

	var target_directory := target_path.get_base_dir()
	var target_skin_name := target_directory.get_file()
	var target_sprite_directory := target_directory.path_join(CHART_SKIN_SPRITES_DIR_NAME)

	FileSystem.ensure_dir(target_directory)
	FileSystem.ensure_dir(target_sprite_directory)
	_copy_file(source_skin_path, target_path)

	var legacy_sprite_directory := chart_folder_path.path_join(LEGACY_SKIN_SPRITES_DIR_NAME)
	if DirAccess.dir_exists_absolute(legacy_sprite_directory):
		_copy_directory_contents(legacy_sprite_directory, target_sprite_directory)

	var modern_sprite_directory := chart_folder_path.path_join(CHART_SKIN_SPRITES_DIR_NAME)
	if DirAccess.dir_exists_absolute(modern_sprite_directory):
		_copy_directory_contents(modern_sprite_directory, target_sprite_directory)

	return target_skin_name
