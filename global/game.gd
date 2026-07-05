extends Node

enum GameStage { Loading, Main, Play, Edit, Browse }
var stage = GameStage.Loading
const CHART_FILE_VERSION = 1
var current_time := 0.0
var last_result_score: Score = null
var skin_editor_request = null
var reopen_editor_without_chart_reload := false

var color_map = {
	0: Color("7f9af9ff"),
	5: Color("6466ccff"),
	10: Color("91cc53ff"),
	15: Color("d1bd28ff"),
	20: Color("964559"),
	25: Color("602228"),
	30: Color("492c55"), 
	35: Color("230215ff"),
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

func get_color_from_rating(value: float,fade: bool = false) -> Color:
	var keys = color_map.keys()
	keys.sort()

	if value <= keys[0]:
		return color_map[keys[0]]
	if value >= keys[-1]:
		return color_map[keys[-1]]
	
	for i in range(keys.size() - 1):
		var a = keys[i]
		var b = keys[i + 1]
		if fade:
			if value >= a and value <= b:
				var t = (value - a) / float(b - a)
				return color_map[a].lerp(color_map[b], t)
		else:
			if value >= a and value < b:
				return color_map[a]
	return color_map[keys[0]]
