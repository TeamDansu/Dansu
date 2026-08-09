extends RefCounted
class_name FileSystem

const res_skin_path: String = "res://resources/skins/"
const res_hitsounds_path: String = "res://resources/audio/hitsounds/"
const chart_path: String = "user://charts"
const skin_path: String = "user://skins"
const startup_import_dir_name := "import"

static func ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("FILE: failed to make folder : %s", path)


static func unique_file_name(directory_path: String, preferred_name: String, fallback_name := "imported") -> String:
	var safe_name := preferred_name.validate_filename().strip_edges()
	var extension := safe_name.get_extension().to_lower()
	var base_name := safe_name.get_basename().strip_edges()
	if base_name.is_empty():
		base_name = fallback_name.validate_filename().strip_edges()
	if base_name.is_empty():
		base_name = "imported"
	var candidate := base_name if extension.is_empty() else "%s.%s" % [base_name, extension]
	var suffix := 2
	while FileAccess.file_exists(directory_path.path_join(candidate)):
		candidate = "%s_%d" % [base_name, suffix] if extension.is_empty() else "%s_%d.%s" % [base_name, suffix, extension]
		suffix += 1
	return candidate


static func copy_file_unique(source_path: String, target_directory: String, fallback_name := "imported") -> String:
	var normalized_source := source_path.simplify_path()
	if not FileAccess.file_exists(normalized_source):
		return ""
	ensure_dir(target_directory)
	var target_name := unique_file_name(target_directory, normalized_source.get_file(), fallback_name)
	var target_path := target_directory.path_join(target_name)
	var source := FileAccess.open(normalized_source, FileAccess.READ)
	if source == null:
		return ""
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		source.close()
		return ""
	target.store_buffer(source.get_buffer(source.get_length()))
	target.flush()
	target.close()
	source.close()
	return target_path


static func write_text_atomic(path: String, content: String) -> bool:
	var temporary_path := path + ".tmp"
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(content)
	file.flush()
	file.close()
	return replace_file(temporary_path, path)


static func replace_file(source_path: String, target_path: String) -> bool:
	if not FileAccess.file_exists(source_path):
		return false
	ensure_dir(target_path.get_base_dir())
	var absolute_source := ProjectSettings.globalize_path(source_path)
	var absolute_target := ProjectSettings.globalize_path(target_path)
	var backup_path := absolute_target + ".backup"
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	var had_target := FileAccess.file_exists(absolute_target)
	if had_target and DirAccess.rename_absolute(absolute_target, backup_path) != OK:
		return false
	if DirAccess.rename_absolute(absolute_source, absolute_target) != OK:
		if had_target:
			DirAccess.rename_absolute(backup_path, absolute_target)
		return false
	if had_target:
		DirAccess.remove_absolute(backup_path)
	return true


static func process_startup_imports() -> void:
	var import_root := _get_startup_import_root()
	ensure_dir(import_root)
	ensure_dir(ProjectSettings.globalize_path(chart_path))
	ensure_dir(ProjectSettings.globalize_path(skin_path))

	for folder_name in DirAccess.get_directories_at(import_root):
		var source_path := import_root.path_join(folder_name)
		var target_root := _resolve_import_target_root(source_path)
		if target_root == "":
			continue

		var target_path := _make_unique_directory_path(target_root, folder_name)
		if _move_directory(source_path, target_path):
			print("[import] moved %s -> %s" % [source_path, target_path])
		else:
			push_warning("[import] failed to move %s" % source_path)


static func get_image(full_path: String) -> Image:
	if not FileAccess.file_exists(full_path):
		push_warning("cover file not found: %s" % full_path)
		return null

	var bytes := FileAccess.get_file_as_bytes(full_path)
	if bytes.is_empty():
		push_warning("cover file read failed: %s" % full_path)
		return null

	var image := _load_image_from_bytes_loose(bytes, full_path.get_extension())
	if image == null:
		push_warning("cover load failed: %s" % full_path)
		return null
	return image


static func _load_image_from_bytes_loose(bytes: PackedByteArray, extension_hint: String = "") -> Image:
	var detected_format := _detect_image_format(bytes)
	if not detected_format.is_empty():
		return _try_load_image_format(bytes, detected_format)
	var normalized_hint := extension_hint.to_lower().replace("jpeg", "jpg")
	return _try_load_image_format(bytes, normalized_hint) if normalized_hint in ["png", "jpg", "webp", "bmp", "tga"] else null


static func _detect_image_format(bytes: PackedByteArray) -> String:
	if bytes.size() >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4e and bytes[3] == 0x47:
		return "png"
	if bytes.size() >= 3 and bytes[0] == 0xff and bytes[1] == 0xd8 and bytes[2] == 0xff:
		return "jpg"
	if bytes.size() >= 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	if bytes.size() >= 2 and bytes[0] == 0x42 and bytes[1] == 0x4d:
		return "bmp"
	return ""


static func _try_load_image_format(bytes: PackedByteArray, format_name: String) -> Image:
	var image := Image.new()
	var err := FAILED

	match format_name:
		"png":
			err = image.load_png_from_buffer(bytes)
		"jpg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
		"bmp":
			err = image.load_bmp_from_buffer(bytes)
		"tga":
			err = image.load_tga_from_buffer(bytes)
		_:
			return null

	if err == OK:
		return image

	return null


static func _get_startup_import_root() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://").path_join(startup_import_dir_name)
	return OS.get_executable_path().get_base_dir().path_join(startup_import_dir_name)


static func _resolve_import_target_root(source_path: String) -> String:
	if FileAccess.file_exists(source_path.path_join("skin.json")):
		return ProjectSettings.globalize_path(skin_path)

	for file_name in DirAccess.get_files_at(source_path):
		if file_name.ends_with(Config.FILE_EXTENSION):
			return ProjectSettings.globalize_path(chart_path)

	return ""


static func _make_unique_directory_path(parent_path: String, preferred_name: String) -> String:
	var base_name := preferred_name.validate_filename()
	if base_name == "":
		base_name = "imported"

	var candidate := base_name
	var index := 2
	while DirAccess.dir_exists_absolute(parent_path.path_join(candidate)):
		candidate = "%s(%d)" % [base_name, index]
		index += 1
	return parent_path.path_join(candidate)


static func _move_directory(source_path: String, target_path: String) -> bool:
	ensure_dir(target_path.get_base_dir())

	var rename_error := DirAccess.rename_absolute(source_path, target_path)
	if rename_error == OK:
		return true

	if not DirAccess.dir_exists_absolute(source_path):
		return false

	ensure_dir(target_path)

	for child_directory_name in DirAccess.get_directories_at(source_path):
		var child_source_path := source_path.path_join(child_directory_name)
		var child_target_path := target_path.path_join(child_directory_name)
		if not _move_directory(child_source_path, child_target_path):
			return false

	for child_file_name in DirAccess.get_files_at(source_path):
		var child_source_file := source_path.path_join(child_file_name)
		var child_target_file := target_path.path_join(child_file_name)
		if not _move_file(child_source_file, child_target_file):
			return false

	var cleanup_error := DirAccess.remove_absolute(source_path)
	return cleanup_error == OK or not DirAccess.dir_exists_absolute(source_path)


static func _move_file(source_path: String, target_path: String) -> bool:
	var rename_error := DirAccess.rename_absolute(source_path, target_path)
	if rename_error == OK:
		return true

	if not FileAccess.file_exists(source_path):
		return false

	var bytes := FileAccess.get_file_as_bytes(source_path)
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_buffer(bytes)
	file.close()

	if DirAccess.remove_absolute(source_path) != OK:
		return false

	return true
