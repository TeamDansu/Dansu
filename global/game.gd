extends Node

enum GameStage { Loading, Main, Play, Edit, Browse }
enum MainMenuState { Home, SongSelect }

var stage = GameStage.Loading
var main_menu_state := MainMenuState.Home
var current_time := 0.0
var last_result_score: Score = null
var skin_editor_request = null
var reopen_editor_without_chart_reload := false
var editor_playtest_active := false
var editor_playtest_start_time_ms := 0.0
var editor_playtest_saved_snapshot: Dictionary = {}

var color_map = {
	0: Color("7f9af9ff"),
	5: Color("6466ccff"),
	10: Color("91cc53ff"),
	15: Color("d1bd28ff"),
	20: Color("c94324ff"),
	25: Color("82171fff"),
	30: Color("845696ff"), 
	35: Color("501247ff"),
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


func play_selected_chart() -> void:
	cancel_editor_playtest()
	if CM.parse_selected_chart():
		Transition.transition_to("res://scenes/gameplay/gameplay.tscn",1.0)


func begin_editor_playtest(start_time_ms: float, saved_snapshot: Dictionary) -> void:
	editor_playtest_active = true
	editor_playtest_start_time_ms = start_time_ms
	editor_playtest_saved_snapshot = saved_snapshot.duplicate(true)


func finish_editor_playtest() -> void:
	current_time = editor_playtest_start_time_ms
	editor_playtest_active = false
	reopen_editor_without_chart_reload = true


func cancel_editor_playtest() -> void:
	editor_playtest_active = false
	editor_playtest_start_time_ms = 0.0
	editor_playtest_saved_snapshot.clear()


func take_editor_playtest_saved_snapshot() -> Dictionary:
	var snapshot := editor_playtest_saved_snapshot
	editor_playtest_saved_snapshot = {}
	return snapshot
