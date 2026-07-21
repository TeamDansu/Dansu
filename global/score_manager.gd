extends Node

var scores: Array[Score] = []


func record_play(chart: Chart, score: Score) -> int:
	if chart == null or score == null or chart.db_id <= 0:
		return -1
	if DB.connection == null:
		return -1

	var play_id := int(DB.connection.record_play(chart, score))
	if play_id <= 0:
		push_error("[database] failed to record play: %s" % DB.connection.get_last_error_message())
		return -1

	scores.append(score)
	chart.last_played_at = int(Time.get_unix_time_from_system())
	chart.best_score = maxf(chart.best_score, score.total_score)
	chart.play_count += 1
	chart.current_version_play_count += 1
	return play_id


func get_best_play(chart: Chart) -> Score:
	if chart == null or chart.db_id <= 0 or DB.connection == null:
		return null
	return DB.connection.get_best_play(chart, _create_score)


func get_chart_plays(chart: Chart, limit: int = 50, offset: int = 0) -> Array:
	if chart == null or chart.db_id <= 0 or DB.connection == null:
		return []
	return DB.connection.get_chart_plays(chart, _create_score, limit, offset)


func get_recent_plays(limit: int = 50, offset: int = 0) -> Array:
	if DB.connection == null:
		return []
	return DB.connection.get_recent_plays(_create_score, limit, offset)


func _create_score(_db_id: int) -> Score:
	return Score.new()
