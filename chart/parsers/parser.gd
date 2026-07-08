extends RefCounted
class_name Parser

const PARSER_V1 = "FILE_VERSION_1"

static func parse_meta(chart: Chart) -> bool:
	var file := FileAccess.open(chart.file_path, FileAccess.READ)
	if file == null:
		Notification.notice("Failed to open chart file: %s" % chart.file_path, Notification.Type.ERROR)
		return false

	var parser: MetaParser = null
	var version: String = file.get_line().strip_edges()
	if version == PARSER_V1:
		parser = MetaParserV1.new()

	if parser != null:
		parser.parse(file, chart)
		chart.build_search_string()
		return true

	Notification.notice("Unsupported chart version ! : %s" % version, Notification.Type.ERROR)
	return false

func parse_object(chart: Chart) -> ParseResult:
	var result := ParseResult.new()
	var file := FileAccess.open(chart.file_path, FileAccess.READ)
	if file == null:
		var message := "Failed to open chart file: %s" % chart.file_path
		Notification.notice(message, Notification.Type.ERROR)
		return result.set_error(message)

	var parser: ObjectParser = null
	var version: String = file.get_line().strip_edges()
	if version == PARSER_V1:
		parser = ObjectParserV1.new()

	if parser != null:
		return result.set_success(parser.parse(file, chart))

	var message := "Unsupported chart version ! : %s" % version
	Notification.notice(message, Notification.Type.ERROR)
	return result.set_error(message)
