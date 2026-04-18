extends RefCounted
class_name Parser

const PARSER_V1 = "FILE_VERSION_1"

static func parse_meta(chart: Chart) -> bool:
	var file := FileAccess.open(chart.file_path, FileAccess.READ)
	if file == null:
		push_error("FILE : Failed to open chart file: %s" % chart.file_path)
		return false

	var parser: MetaParser = null
	var version: String = file.get_line().strip_edges()
	if version == PARSER_V1:
		parser = MetaParserV1.new()

	if parser != null:
		parser.parse(file, chart)
		chart.build_search_string()
		return true

	push_error("FILE : Unsupported chart version ! : %s" % version)
	return false

func parse_object(chart: Chart) -> bool:
	_clear()
	var file := FileAccess.open(chart.file_path, FileAccess.READ)
	if file == null:
		push_error("FILE : Failed to open chart file: %s" % chart.file_path)
		return false

	var parser: ObjectParser = null
	var version: String = file.get_line().strip_edges()
	if version == PARSER_V1:
		parser = ObjectParserV1.new()

	if parser != null:
		parser.parse(file, chart)
		return true

	push_error("FILE : Unsupported chart version ! : %s" % version)
	return false

func _clear() -> void:
	var cm = _cm()
	if cm == null:
		return
	cm.rails.clear()
	cm.hitsounds.clear()
	cm.hitsounds.append_array(HitSound.load_builtin_hitsounds())

func _cm() -> ChartManager:
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree:
		return main_loop.root.get_node_or_null("CM")
	return null
