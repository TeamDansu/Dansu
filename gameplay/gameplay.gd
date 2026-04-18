extends Node3D

const DEFAULT_HIT_SFX := preload("res://resorces/audio/hitsounds/chop.wav")
const DEFAULT_MOVE_SFX := preload("res://resorces/audio/hitsounds/chop.wav")
const SFX_PLAYER_COUNT := 8

class SpawnableNote:
	var note: Note
	var rail: Rail

	func _init(note_value: Note, rail_value: Rail) -> void:
		note = note_value
		rail = rail_value

# note
var note_scene = preload("res://scenes/gameplay/note.tscn")
var notes : Array[SpawnableNote] = []
var note_spawn_index: int
var next_process_note : Note
var next_process_note_index : int
var processing_touch_notes : Array[GameNote] = []
var spawned_note_nodes: Dictionary = {}
var note_owner_by_note: Dictionary = {}
var processed_notes: Dictionary = {}

# rail
var rail_scene = preload("res://scenes/gameplay/rail.tscn")
var rails : Array[Rail] = []
var spawned_rails : Array[GameRail] = []
var rail_nodes_by_data: Dictionary = {}
var rail_spawn_index: int
var standing_rail: Rail

var score := Score.new()
var combo := 0
var judgeDisplayDuration := 1
var song_end := 0
var paused := false

@export var player : Node3D
@export var rail_container : Node3D
@export var songplayer : AudioStreamPlayer

const LEAD_IN_MS := 3000.0

var is_song_playing := false
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player_index := 0
var _hitsound_streams: Dictionary = {}

# timeline
var audio_start_target_usec: int = 0
var pause_begin_usec: int = 0

func _ready() -> void:
	songplayer.stream = CM.selected_chart.get_stream()
	_prepare_sfx_players()
	reset()

func reset() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	$AnimationPlayer.play("camera_intro")

	for child in rail_container.get_children():
		child.queue_free()

	score = Score.new()
	combo = 0
	judgeDisplayDuration = 1
	song_end = 0

	paused = false
	is_song_playing = false
	pause_begin_usec = 0

	audio_start_target_usec = Time.get_ticks_usec() + int(LEAD_IN_MS * 1000.0)

	_update_current_time()
	_rebuild_hitsound_cache()
	_build_game_objects()
	_spawn_objects()

func _prepare_sfx_players() -> void:
	if not _sfx_players.is_empty():
		return
	for index in range(SFX_PLAYER_COUNT):
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.name = "GameplaySFXPlayer%d" % index
		sfx_player.bus = "SFX"
		add_child(sfx_player)
		_sfx_players.append(sfx_player)

func _process(delta: float) -> void:
	if paused:
		return

	if not is_song_playing:
		var startup_delay_sec := AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
		var now_usec := Time.get_ticks_usec()
		var play_call_time_usec := audio_start_target_usec - int(startup_delay_sec * 1000000.0)

		if now_usec >= play_call_time_usec:
			songplayer.play()
			is_song_playing = true


		#songplayer.volume_db -= delta * 30.0
		#if Game.current_time > song_end + 2000.0:
			#Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_spawn_objects()

	if Input.is_action_just_pressed("ui_cancel"):
		%PauseMenu.visible = true
		pause()

func stop_song() -> void:
	songplayer.stop()
	is_song_playing = false
	Game.current_time = 0.0

func pause() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	paused = !paused

	if paused:
		pause_begin_usec = Time.get_ticks_usec()

		if is_song_playing:
			songplayer.stream_paused = true
	else:
		var paused_duration_usec := Time.get_ticks_usec() - pause_begin_usec
		audio_start_target_usec += paused_duration_usec

		if is_song_playing:
			songplayer.stream_paused = false

		%PauseMenu.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

func retry() -> void:
	reset()
	paused = false
	%PauseMenu.visible = false
	player.reset()

func exit() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://Scene/main_menu.tscn")

func _update_current_time() -> void:
	Game.current_time = (
		(Time.get_ticks_usec() - audio_start_target_usec) / 1000.0
	) - Config.offset

## TODO: 전역 notes 지우고 rail별로 포인터로 다음 노트 찾기

func _spawn_objects():
	var spawn_threshold := Game.current_time + GameplayPlayfield.get_visible_travel_time_ms()

	while rail_spawn_index < rails.size() and rails[rail_spawn_index].start_time <= spawn_threshold:
		var rail_data := rails[rail_spawn_index]
		var new_rail: GameRail = rail_scene.instantiate()
		new_rail.rail = rail_data
		rail_container.add_child(new_rail)
		spawned_rails.append(new_rail)
		rail_nodes_by_data[rail_data] = new_rail
		rail_spawn_index += 1

	while note_spawn_index < notes.size() and notes[note_spawn_index].note.time <= spawn_threshold:
		var note_entry := notes[note_spawn_index]
		var owner_rail: GameRail = rail_nodes_by_data.get(note_entry.rail)

		if owner_rail != null and not processed_notes.has(note_entry.note):
			var new_note: GameNote = note_scene.instantiate()
			new_note.note = note_entry.note
			new_note.rail = note_entry.rail
			new_note.consumed.connect(process_note)
			owner_rail.note_container.add_child(new_note)
			spawned_note_nodes[note_entry.note] = new_note


		note_spawn_index += 1

func _build_game_objects() -> void:

	rails = []
	notes = []
	processing_touch_notes = []
	spawned_note_nodes = {}
	note_owner_by_note = {}
	processed_notes = {}
	spawned_rails = []
	rail_nodes_by_data = {}
	next_process_note = null
	next_process_note_index = 0
	rail_spawn_index = 0
	note_spawn_index = 0
	standing_rail = null

	for rail in CM.rails:
		rail.sort_points()
		rails.append(rail)

	for rail in rails:
		for note in rail.notes:
			var new_note = SpawnableNote.new(note, rail)
			notes.append(new_note)
			note_owner_by_note[note] = rail

	notes.sort_custom(_sort_notes)
	rails.sort_custom(_sort_rails)
	
	_set_next_note()

func _sort_notes(a: SpawnableNote, b: SpawnableNote) -> bool:
	return a.note.time < b.note.time

func _sort_rails(a: Rail, b: Rail) -> bool:
	return a.points[0].time < b.points[0].time

func _physics_process(_delta: float) -> void:
	if paused:
		return

	_update_current_time()
	_check_miss()

	if Input.is_action_just_pressed("action_left"):
		_player_move_action(Note.Dir.LEFT, Game.current_time)

	if Input.is_action_just_pressed("action_right"):
		_player_move_action(Note.Dir.RIGHT, Game.current_time)

	if Input.is_action_just_pressed("action_hit1") or Input.is_action_just_pressed("action_hit2"):
		_input_action(Game.current_time)

func _check_miss():
	pass

func _check_touch_notes():
	pass

func _input_action(time: float, dir: Note.Dir = Note.Dir.NONE) -> void:
	if next_process_note == null or standing_rail == null:
		return

	var target_rail: Rail = note_owner_by_note.get(next_process_note)
	if target_rail == null or standing_rail != target_rail:
		return

	match next_process_note.type:
		Note.NoteType.MOVE:
			pass
		Note.NoteType.MOVE:
			pass
	var gap := next_process_note.time - time
	var judgement := score.get_judgement(gap)
	if judgement == score.NONE:
		return

	_process_note_result(next_process_note, judgement)

func _player_move_action(dir: Note.Dir, time: float):
	if next_process_note == null:
		return

	var target_rail: Rail = note_owner_by_note.get(next_process_note)
	if standing_rail != target_rail:
		return


func process_note(j: int, note_node: GameNote) -> void:
	spawned_note_nodes.erase(note_node.note)
	processing_touch_notes.erase(note_node)

func _set_next_note() -> void:
	
	next_process_note = null
	
	while next_process_note_index < notes.size():
		var note_entry: SpawnableNote = notes[next_process_note_index]
		var note: Note = note_entry.note

		if processed_notes.has(note):
			next_process_note_index += 1
			continue

		match note.type:
			Note.NoteType.HIT, Note.NoteType.MOVE:
				next_process_note = note
				next_process_note_index += 1
				return
			_:
				next_process_note_index += 1

func _process_note_result(note: Note, judgement: int) -> void:
	processed_notes[note] = judgement
	_play_note_sfx(note)

	var note_node: GameNote = spawned_note_nodes.get(note)
	if note_node != null:
		note_node.consume(judgement)

	if next_process_note == note:
		_set_next_note()

func _rebuild_hitsound_cache() -> void:
	_hitsound_streams.clear()
	for hitsound in CM.hitsounds:
		if hitsound == null or hitsound.stream == null:
			continue
		_hitsound_streams[hitsound.id] = hitsound.stream

func _play_note_sfx(note: Note) -> void:
	var stream := _resolve_note_sfx_stream(note)
	if stream == null:
		return
	_play_stream_sfx(stream)

func _play_stream_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player := _sfx_players[_next_sfx_player_index]
	_next_sfx_player_index = (_next_sfx_player_index + 1) % _sfx_players.size()
	player.stream = stream
	player.play()

func _resolve_note_sfx_stream(note: Note) -> AudioStream:
	if note == null:
		return null
	var chart: Chart = CM.selected_chart
	var hitsound_id := int(note.hitsound)
	if hitsound_id < 0 and chart != null:
		hitsound_id = chart.get_default_hitsound_id(chart.get_default_hitsound_slot_for_note(note))
	if hitsound_id >= 0 and _hitsound_streams.has(hitsound_id):
		return _hitsound_streams[hitsound_id]
	if int(note.type) == int(Note.NoteType.MOVE):
		return DEFAULT_MOVE_SFX
	return DEFAULT_HIT_SFX
