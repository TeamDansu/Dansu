extends RefCounted
class_name ScoreRank

const MAX_SCORE := 101.0
const DATA := [
	{"label": "D", "min": 0.0, "color": Color(0.071, 0.063, 0.071, 1.0)},
	{"label": "C", "min": 70.0, "color": Color(0.22, 0.191, 0.215, 1.0)},
	{"label": "B", "min": 85.0, "color": Color(0.826, 0.374, 0.444, 1.0)},
	{"label": "A", "min": 90.0, "color": Color("c6fba6ff")},
	{"label": "S", "min": 95.0, "color": Color(0.965, 0.925, 0.745, 1.0)},
	{"label": "S+", "min": 99.0, "color": Color(0.977, 0.872, 0.698, 1.0)},
	{"label": "SS", "min": 100.0, "color": Color(0.915, 0.643, 0.895, 1.0)},
	{"label": "X", "min": 101.0, "color": Color(0.702, 0.846, 0.935, 1.0)},
]

static func index_for_score(value: float) -> int:
	var result := 0
	for index in range(DATA.size()):
		if value >= minimum(index):
			result = index
	return result

static func label_for_score(value: float) -> String:
	return label(index_for_score(value))

static func color_for_score(value: float) -> Color:
	return color(index_for_score(value))

static func label(index: int) -> String:
	return str(DATA[clampi(index, 0, DATA.size() - 1)]["label"])

static func color(index: int) -> Color:
	return DATA[clampi(index, 0, DATA.size() - 1)]["color"] as Color

static func minimum(index: int) -> float:
	return float(DATA[clampi(index, 0, DATA.size() - 1)]["min"])

static func maximum(index: int) -> float:
	return minimum(index + 1) if index + 1 < DATA.size() else MAX_SCORE
