extends RefCounted
class_name ParsedChart

var chart: Chart = null
var rails :Array[Rail] = []
var hitsounds: Array[HitSound] = []

func _init(chart_value: Chart = null) -> void:
	chart = chart_value
	rails = []
	hitsounds = []

func get_notes() -> Array[Note]:
	var result: Array[Note] = []
	for rail in rails:
		if rail == null:
			continue
		for note in rail.notes:
			if note != null:
				result.append(note)
	return result
