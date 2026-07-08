extends Node
class_name MenuAudioSwitcher

@export var current_audio: AudioStreamPlayer
@export var next_audio: AudioStreamPlayer

@export var fade_time := 0.4
@export var start_position := 0.0

var is_switching := false
var queued_chart: Chart = null
var current_song_key := ""
var switching_song_key := ""
var current_chart_start_sec := 0.0
var switching_chart_start_sec := 0.0

func _ready() -> void:
	if CM.selected_chart:
		current_audio.stream = CM.selected_chart.get_stream()
		current_audio.volume_db = 0.0
		current_chart_start_sec = _get_chart_preview_start_sec(CM.selected_chart)
		current_audio.play(current_chart_start_sec)
		current_song_key = _get_song_key(CM.selected_chart)

	next_audio.volume_db = -80.0

	CM.chart_selected.connect(change_audio)


func change_audio(chart: Chart) -> void:
	if chart == null:
		return

	var requested_song_key := _get_song_key(chart)

	if not is_switching and requested_song_key == current_song_key and current_audio.playing:
		return

	if is_switching and requested_song_key == switching_song_key:
		return

	queued_chart = chart

	if is_switching:
		return

	_process_switch_queue()


func _process_switch_queue() -> void:
	if is_switching:
		return

	is_switching = true

	while queued_chart != null:
		var target_chart := queued_chart
		queued_chart = null

		if target_chart == null:
			continue

		var target_song_key := _get_song_key(target_chart)
		if target_song_key.is_empty():
			continue

		if target_song_key == current_song_key and current_audio.playing:
			continue

		switching_song_key = target_song_key

		next_audio.stop()
		next_audio.stream = target_chart.get_stream()
		next_audio.volume_db = -80.0
		switching_chart_start_sec = _get_chart_preview_start_sec(target_chart)
		next_audio.play(switching_chart_start_sec)

		var tween := create_tween()

		tween.parallel().tween_property(
			current_audio,
			"volume_db",
			-80.0,
			fade_time
		)

		tween.parallel().tween_property(
			next_audio,
			"volume_db",
			0.0,
			fade_time
		)

		await tween.finished

		current_audio.stop()

		var temp := current_audio
		current_audio = next_audio
		next_audio = temp

		current_chart_start_sec = switching_chart_start_sec
		switching_chart_start_sec = 0.0
		current_song_key = target_song_key
		switching_song_key = ""

	is_switching = false


func _get_song_key(chart: Chart) -> String:
	if chart == null:
		return ""

	return "%s::%s" % [chart.folder_name, chart.file_audio]


func get_current_chart_time_msec() -> float:
	if current_audio == null or not current_audio.playing:
		return -1.0

	var audible_sec := (
		current_audio.get_playback_position()
		+ AudioServer.get_time_since_last_mix()
		- AudioServer.get_output_latency()
	)
	audible_sec = maxf(audible_sec, 0.0)
	return (current_chart_start_sec + audible_sec) * 1000.0 - float(Config.offset)


func _get_chart_preview_start_sec(chart: Chart) -> float:
	if chart == null:
		return start_position
	if chart.preview_time >= 0.0:
		return chart.preview_time / 1000.0
	return start_position
