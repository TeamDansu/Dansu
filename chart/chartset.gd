extends RefCounted
class_name ChartSet

var charts: Array[Chart] = []
var db_id: int = -1
var uuid := ""
var folder_name: String


func build_uuid() -> void:
	var hex_chars := "0123456789abcdef"
	uuid = ""
	for i in range(32):
		uuid += hex_chars[randi() % 16]
		if i in [7, 11, 15, 19]:
			uuid += "-"
