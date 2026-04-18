extends RefCounted
class_name FileSystem

static func ensure_dir(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		return
	
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("FILE: failed to make folder : %s", path)


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
	var normalized_hint := extension_hint.to_lower()
	if normalized_hint == "jpeg":
		normalized_hint = "jpg"

	if not normalized_hint.is_empty():
		var hinted_image := _try_load_image_format(bytes, normalized_hint)
		if hinted_image != null:
			return hinted_image

	for format_name in ["png", "jpg", "webp", "bmp", "tga"]:
		if format_name == normalized_hint:
			continue

		var image := _try_load_image_format(bytes, format_name)
		if image != null:
			return image

	return null


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
