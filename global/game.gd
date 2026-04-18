extends Node
class_name GameState

const CHART_FILE_VERSION = 1
var current_time := 0.0

var color_map = {
	0: Color("a0a0a0"),
	3: Color("1AC9E6"),
	10: Color("1DE45D"),
	13: Color("eacb00ff"),
	14: Color("DE542C"),
	17: Color("C02323"),
	20: Color("DE4CB2"), 
	25: Color("6100b6"),
}

var color_map_test = {
	0: Color("a0a0a0ff"),
	5: Color("1AC9E6ff"),
	10: Color("1DE45Dff"),
	15: Color("eacb00ff"),
	20: Color("DE542Cff"),
	25: Color("C02323ff"),
	30: Color("DE4CB2ff"), 
	35: Color("8b00ffff"),
}

func get_color_from_rating(value: float) -> Color:
	var keys = color_map.keys()
	keys.sort()

	if value <= keys[0]:
		return color_map[keys[0]]
	if value >= keys[-1]:
		return color_map[keys[-1]]

	for i in range(keys.size() - 1):
		var a = keys[i]
		var b = keys[i + 1]
		if value >= a and value <= b:
			var t = (value - a) / float(b - a)
			return color_map[a].lerp(color_map[b], t)
	return color_map[keys[0]]
