extends Node3D

const DEFAULT_HIT_SFX := preload("res://resources/audio/hitsounds/chop.wav")
const DEFAULT_MOVE_SFX := preload("res://resources/audio/hitsounds/chop.wav")
const SFX_PLAYER_COUNT := 8
const JUDGE_POPUP_SCENE := preload("res://scenes/gameplay/judge_popup.tscn")
const RESULT_SCENE_PATH := "res://scenes/result_scene.tscn"
const COMBO_POP_SCALE := Vector2(0.96, 1.12)
const COMBO_POP_DURATION_IN := 0.08
const COMBO_POP_DURATION_OUT := 0.14
const JUDGE_POPUP_OFFSET := Vector3(0.0, 2.0, 0.0)
const SONG_FADE_START_AFTER_LAST_NOTE_MS := 1000.0
const RESULT_DELAY_AFTER_LAST_NOTE_MS := 2000.0
const SONG_FADE_DB_PER_SECOND := 30.0
const MUSIC_BUS := &"Music"
const SKY_BASE_COLOR_PARAM := "base_color"
const SKY_DETAIL_COLOR_PARAM := "detail_color"

class SpawnableNote:
	var note: Note
	var rail: Rail

	func _init(note_value: Note, rail_value: Rail) -> void:
		note = note_value
		rail = rail_value

class OverlayRuntimeState:
	var sprite_ref := ""
	var position := Vector2.ZERO
	var scale := Vector2.ONE
	var rotation := 0.0
	var opacity := 1.0

# notes
var note_scene = preload("res://scenes/gameplay/note.tscn")
var notes: Array[SpawnableNote] = []
var note_spawn_index: int
var next_process_note: Note
var next_process_note_index: int
var touch_notes: Array[SpawnableNote] = []
var spawned_note_nodes: Dictionary = {}
var note_owner_by_note: Dictionary = {}
var processed_notes: Dictionary = {}

# rail
var rail_scene = preload("res://scenes/gameplay/rail.tscn")
var rails: Array[Rail] = []
var spawned_rails: Array[GameRail] = []
var rail_nodes_by_data: Dictionary = {}
var rail_spawn_index: int
var standing_rail: Rail:
	set(value):
		if standing_rail != value:
			var prev_node: GameRail = rail_nodes_by_data.get(standing_rail)
			if prev_node != null:
				prev_node.is_standing = false
			standing_rail = value
			var new_node: GameRail = rail_nodes_by_data.get(value)
			if new_node != null:
				new_node.is_standing = true

# long note states
var is_holding_long_move := false
var pending_move_dir: Note.Dir = Note.Dir.NONE
var holding_long_hit_note: Note = null

var score := Score.new()
var combo := 0
var judgeDisplayDuration := 1
var song_end := 0
var paused := false

@export var player: Player
@export var rail_container: Node3D
@export var songplayer: AudioStreamPlayer

@onready var gameplay_camera = $Camera3D
@onready var hud_root: Control = $Control
@onready var combo_container: VBoxContainer = $Control/VBoxContainer
@onready var combo_label: Label = $Control/VBoxContainer/Combo
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var stage_visualizer: GameplayStageVisualizer = $PlayArea/StageVisualizer

const LEAD_IN_MS := 3000.0

var is_song_playing := false
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player_index := 0
var _hitsound_streams: Dictionary = {}
var _combo_tween: Tween
var _result_transition_started := false
var _last_note_time_ms := 0.0
var _song_volume_db := 0.0
var _timestamp_input_active := false
var _camera_events: Array[CameraEvent] = []
var _overlay_events: Array[OverlayEvent] = []
var _theme_events: Array[ThemeEvent] = []
var _sky_material: ShaderMaterial = null
var _default_sky_base_color := Color(0.075, 0.078, 0.09, 1.0)
var _default_sky_detail_color := Color(0.19, 0.19, 0.22, 1.0)
var _current_rail_color := GameRail.DEFAULT_ACCENT_COLOR
var _overlay_root: Control = null
var _overlay_nodes: Array[TextureRect] = []
var _overlay_texture_paths: Array[String] = []
var _overlay_texture_values: Array[Texture2D] = []

# timeline
var audio_start_target_usec: int = 0
var pause_begin_usec: int = 0

func _ready() -> void:
	_setup_combo_hud()
	_setup_timestamp_input()
	songplayer.bus = MUSIC_BUS
	songplayer.stream = CM.selected_chart.get_stream()
	_song_volume_db = songplayer.volume_db
	_cache_stage_theme_defaults()
	_ensure_overlay_root()
	_prepare_sfx_players()
	reset()

func _exit_tree() -> void:
	_stop_timestamp_input()

func reset() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	for child in rail_container.get_children():
		child.queue_free()

	score = Score.new()
	combo = 0
	judgeDisplayDuration = 1
	song_end = 0

	paused = false
	is_song_playing = false
	pause_begin_usec = 0
	_result_transition_started = false
	_last_note_time_ms = 0.0
	songplayer.volume_db = _song_volume_db

	is_holding_long_move = false
	pending_move_dir = Note.Dir.NONE
	holding_long_hit_note = null
	standing_rail = null

	audio_start_target_usec = Time.get_ticks_usec() + int(LEAD_IN_MS * 1000.0)
	_discard_timestamp_events()

	_update_current_time()
	_rebuild_hitsound_cache()
	_build_game_objects()
	_collect_camera_events()
	_collect_overlay_events()
	_collect_theme_events()
	_apply_runtime_events(Game.current_time)
	_spawn_objects()
	_reset_combo_hud()

func _prepare_sfx_players() -> void:
	if not _sfx_players.is_empty():
		return
	for index in range(SFX_PLAYER_COUNT):
		var sfx_player := AudioStreamPlayer.new()
		sfx_player.name = "GameplaySFXPlayer%d" % index
		sfx_player.bus = "SFX"
		add_child(sfx_player)
		_sfx_players.append(sfx_player)


func _setup_combo_hud() -> void:
	if combo_container == null or combo_label == null:
		return
	combo_container.visible = true
	combo_container.modulate.a = 1.0
	combo_container.scale = Vector2.ONE
	combo_container.resized.connect(_refresh_combo_pivot)
	call_deferred("_refresh_combo_pivot")


func _refresh_combo_pivot() -> void:
	if combo_container == null:
		return
	combo_container.pivot_offset = combo_container.size * 0.5


func _reset_combo_hud() -> void:
	if _combo_tween != null:
		_combo_tween.kill()
	if combo_container != null:
		combo_container.visible = true
		combo_container.modulate.a = 1.0
		combo_container.scale = Vector2.ONE
	_update_combo_display()


func _update_combo_display() -> void:
	if combo_container == null or combo_label == null:
		return
	combo_label.text = str(combo)
	combo_container.visible = true


func _play_combo_pop() -> void:
	if combo_container == null:
		return
	if _combo_tween != null:
		_combo_tween.kill()
	_refresh_combo_pivot()
	combo_container.scale = Vector2.ONE
	_combo_tween = create_tween()
	_combo_tween.set_trans(Tween.TRANS_BACK)
	_combo_tween.set_ease(Tween.EASE_OUT)
	_combo_tween.tween_property(combo_container, "scale", COMBO_POP_SCALE, COMBO_POP_DURATION_IN)
	_combo_tween.tween_property(combo_container, "scale", Vector2.ONE, COMBO_POP_DURATION_OUT)


func _spawn_judge_popup(judgement: int) -> void:
	if judgement == Score.NONE or player == null:
		return
	var popup := JUDGE_POPUP_SCENE.instantiate()
	if popup == null:
		return
	popup.judgement = judgement
	add_child(popup)
	popup.global_position = player.global_position + JUDGE_POPUP_OFFSET

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
	_update_current_time()
	_spawn_objects()
	_process_gameplay_input()
	_check_result_transition()
	_update_standing_rail()
	_check_miss()
	_check_touch_notes()
	_update_song_fade(delta)
	_apply_runtime_events(Game.current_time)

	if Input.is_action_just_pressed("ui_cancel"):
		exit()
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
		_discard_timestamp_events()

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
	Transition.return_to_menu(1)

func _update_current_time() -> void:
	Game.current_time = (
		(Time.get_ticks_usec() - audio_start_target_usec) / 1000.0
	) - Config.offset

func _setup_timestamp_input() -> void:
	if not OS.has_feature("windows"):
		print("Falling back to Godot input.")
		return

	if not TimestampInput.start():
		push_warning("TimestampInput failed to start. Falling back to Godot input.")
		return

	_timestamp_input_active = true
	_discard_timestamp_events()

func _stop_timestamp_input() -> void:
	TimestampInput.stop()
	_timestamp_input_active = false

func _discard_timestamp_events() -> void:
	if not _timestamp_input_active:
		return
	TimestampInput.poll_events()

func _timestamp_to_game_time(timestamp_usec: int) -> float:
	return (
		float(timestamp_usec - audio_start_target_usec) / 1000.0
	) - Config.offset

func _process_gameplay_input() -> void:
	if _timestamp_input_active:
		_process_timestamp_events()
	else:
		_process_builtin_input()

func _process_timestamp_events() -> void:
	var events: Array[RawInputEvent] = TimestampInput.poll_events()
	for event_variant: RawInputEvent in events:
		if event_variant == null:
			continue

		var godot_keycode := int(event_variant.keycode)
		var pressed := bool(event_variant.pressed)
		var event_time := _timestamp_to_game_time(int(event_variant.timestamp_usec))
		_handle_key_event(godot_keycode, pressed, event_time)

func _process_builtin_input() -> void:
	if is_holding_long_move:
		var released := (
			(pending_move_dir == Note.Dir.LEFT and Input.is_action_just_released("action_left")) or
			(pending_move_dir == Note.Dir.RIGHT and Input.is_action_just_released("action_right"))
		)
		if released:
			_move_player_in_direction(pending_move_dir, false, Game.current_time)
			is_holding_long_move = false
			pending_move_dir = Note.Dir.NONE

	if holding_long_hit_note != null:
		if Input.is_action_just_released("action_hit1") or Input.is_action_just_released("action_hit2"):
			holding_long_hit_note = null

	if not is_holding_long_move and holding_long_hit_note == null:
		if Input.is_action_just_pressed("action_left"):
			_move_action(Note.Dir.LEFT, Game.current_time)
		if Input.is_action_just_pressed("action_right"):
			_move_action(Note.Dir.RIGHT, Game.current_time)

	if Input.is_action_just_pressed("action_hit1") or Input.is_action_just_pressed("action_hit2"):
		_input_action(Game.current_time)

func _handle_key_event(keycode: int, pressed: bool, event_time: float) -> void:
	if keycode == int(Config.action_left):
		if pressed:
			if not is_holding_long_move and holding_long_hit_note == null:
				_move_action(Note.Dir.LEFT, event_time)
		elif is_holding_long_move and pending_move_dir == Note.Dir.LEFT:
			_move_player_in_direction(Note.Dir.LEFT, false, event_time)
			is_holding_long_move = false
			pending_move_dir = Note.Dir.NONE
		return

	if keycode == int(Config.action_right):
		if pressed:
			if not is_holding_long_move and holding_long_hit_note == null:
				_move_action(Note.Dir.RIGHT, event_time)
		elif is_holding_long_move and pending_move_dir == Note.Dir.RIGHT:
			_move_player_in_direction(Note.Dir.RIGHT, false, event_time)
			is_holding_long_move = false
			pending_move_dir = Note.Dir.NONE
		return

	if keycode == int(Config.action_hit1) or keycode == int(Config.action_hit2):
		if pressed:
			_input_action(event_time)
		elif holding_long_hit_note != null:
			holding_long_hit_note = null

func _spawn_objects() -> void:
	var spawn_threshold := Game.current_time + GameplayPlayfield.get_visible_travel_time_ms()

	while rail_spawn_index < rails.size() and rails[rail_spawn_index].start_time <= spawn_threshold:
		var rail_data := rails[rail_spawn_index]
		var new_rail: GameRail = rail_scene.instantiate()
		new_rail.rail = rail_data
		new_rail.set_theme_color(_current_rail_color)
		rail_container.add_child(new_rail)
		new_rail.position.y = rail_spawn_index * 0.0002
		spawned_rails.append(new_rail)
		rail_nodes_by_data[rail_data] = new_rail
		new_rail.is_standing = (rail_data == standing_rail)
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
	touch_notes = []
	spawned_note_nodes = {}
	note_owner_by_note = {}
	processed_notes = {}
	spawned_rails = []
	rail_nodes_by_data = {}
	next_process_note = null
	next_process_note_index = 0
	rail_spawn_index = 0
	note_spawn_index = 0

	for rail in CM.parsed_chart.rails:
		rail.sort_points()
		rails.append(rail)

	for rail in rails:
		for note in rail.notes:
			var new_entry := SpawnableNote.new(note, rail)
			notes.append(new_entry)
			note_owner_by_note[note] = rail
			if note.type == Note.NoteType.TRACE or note.type == Note.NoteType.SPIKE:
				touch_notes.append(new_entry)

	notes.sort_custom(_sort_notes)
	rails.sort_custom(_sort_rails)
	touch_notes.sort_custom(_sort_notes)
	GameRail.prebake_for_rails(rails)
	if not notes.is_empty():
		_last_note_time_ms = float(notes[notes.size() - 1].note.time)
		song_end = int(_last_note_time_ms + SONG_FADE_START_AFTER_LAST_NOTE_MS)

	_set_next_note()

func _collect_camera_events() -> void:
	_camera_events.clear()
	if CM.parsed_chart == null:
		return
	for event in CM.parsed_chart.events:
		if event is CameraEvent:
			_camera_events.append(event)

func _collect_overlay_events() -> void:
	_overlay_events.clear()
	if CM.parsed_chart == null:
		return
	for event in CM.parsed_chart.events:
		if event is OverlayEvent:
			_overlay_events.append(event)

func _collect_theme_events() -> void:
	_theme_events.clear()
	if CM.parsed_chart == null:
		return
	for event in CM.parsed_chart.events:
		if event is ThemeEvent:
			_theme_events.append(event)

func _cache_stage_theme_defaults() -> void:
	if world_environment == null or world_environment.environment == null:
		return
	var sky := world_environment.environment.sky
	if sky == null:
		return
	_sky_material = sky.sky_material as ShaderMaterial
	if _sky_material == null:
		return
	if _sky_material.get_shader_parameter(SKY_BASE_COLOR_PARAM) is Color:
		_default_sky_base_color = _sky_material.get_shader_parameter(SKY_BASE_COLOR_PARAM)
	if _sky_material.get_shader_parameter(SKY_DETAIL_COLOR_PARAM) is Color:
		_default_sky_detail_color = _sky_material.get_shader_parameter(SKY_DETAIL_COLOR_PARAM)

func _ensure_overlay_root() -> void:
	if hud_root == null or _overlay_root != null:
		return
	_overlay_root = Control.new()
	_overlay_root.name = "OverlayRuntime"
	_overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_root.clip_contents = false
	hud_root.add_child(_overlay_root)
	hud_root.move_child(_overlay_root, 0)

func _apply_runtime_events(time_ms: float) -> void:
	_apply_theme_events(time_ms)
	_apply_camera_events(time_ms)
	_apply_overlay_events(time_ms)

func _apply_theme_events(time_ms: float) -> void:
	var base_color := _default_sky_base_color
	var detail_color := _default_sky_detail_color
	var rail_color := GameRail.DEFAULT_ACCENT_COLOR
	var active := _find_active_theme_event(time_ms)
	if active != null and not active.frames.is_empty():
		var pair_indices := _find_frame_pair_indices(active.frames, time_ms - active.time)
		var previous: ThemeEventFrame = active.frames[pair_indices.x]
		var next: ThemeEventFrame = active.frames[pair_indices.y]
		var alpha := _frame_ease_alpha(previous, next, time_ms - active.time)
		base_color = previous.bg_color.lerp(next.bg_color, alpha)
		detail_color = previous.bg_color_2.lerp(next.bg_color_2, alpha)
		rail_color = previous.rail_color.lerp(next.rail_color, alpha)
	var next_rail_color := Color(rail_color.r, rail_color.g, rail_color.b, 1.0)
	if not _current_rail_color.is_equal_approx(next_rail_color):
		_current_rail_color = next_rail_color
		for rail_node in spawned_rails:
			if rail_node != null:
				rail_node.set_theme_color(_current_rail_color)
	if _sky_material != null:
		_sky_material.set_shader_parameter(SKY_BASE_COLOR_PARAM, base_color)
		_sky_material.set_shader_parameter(SKY_DETAIL_COLOR_PARAM, detail_color)
	if stage_visualizer != null:
		stage_visualizer.set_theme_colors(base_color, detail_color, _current_rail_color)

func _find_active_theme_event(time_ms: float) -> ThemeEvent:
	var active: ThemeEvent = null
	for event in _theme_events:
		if time_ms < event.time or time_ms > event.end_time:
			continue
		if active == null or event.time >= active.time:
			active = event
	return active

func _apply_camera_events(time_ms: float) -> void:
	if gameplay_camera == null:
		return
	var active := _find_active_camera_event(time_ms)
	if active == null or active.frames.is_empty():
		gameplay_camera.follow_character = true
		gameplay_camera.target_position = Vector2.ZERO
		gameplay_camera.target_zoom = 1.0
		return
	var pair_indices := _find_frame_pair_indices(active.frames, time_ms - active.time)
	var previous: CameraEventFrame = active.frames[pair_indices.x]
	var next: CameraEventFrame = active.frames[pair_indices.y]
	var alpha := _frame_ease_alpha(previous, next, time_ms - active.time)
	gameplay_camera.follow_character = previous.follow_character
	gameplay_camera.target_position = previous.position.lerp(next.position, alpha)
	gameplay_camera.target_zoom = lerpf(previous.zoom, next.zoom, alpha)

func _find_active_camera_event(time_ms: float) -> CameraEvent:
	var active: CameraEvent = null
	for event in _camera_events:
		if time_ms < event.time or time_ms > event.end_time:
			continue
		if active == null or event.time >= active.time:
			active = event
	return active

func _apply_overlay_events(time_ms: float) -> void:
	if _overlay_root == null:
		return
	var active_overlays := _find_active_overlay_events(time_ms)
	_ensure_overlay_node_pool(active_overlays.size())
	var visible_count := 0
	for overlay in active_overlays:
		var state := _evaluate_overlay_state(overlay, time_ms - overlay.time)
		if state == null:
			continue
		var texture := _load_overlay_texture(state.sprite_ref)
		if texture == null:
			continue
		var node := _overlay_nodes[visible_count]
		visible_count += 1
		var center := _overlay_root.size * OverlayEventFrame.anchor_to_vector(overlay.anchor) + state.position
		node.texture = texture
		node.size = texture.get_size()
		node.pivot_offset = node.size * 0.5
		node.position = center - node.size * 0.5
		node.scale = state.scale
		node.rotation = deg_to_rad(state.rotation)
		node.modulate = Color(1.0, 1.0, 1.0, clampf(state.opacity, 0.0, 1.0))
		node.visible = true
		node.z_index = visible_count
	for index in range(visible_count, _overlay_nodes.size()):
		_overlay_nodes[index].visible = false

func _find_active_overlay_events(time_ms: float) -> Array[OverlayEvent]:
	var active_overlays: Array[OverlayEvent] = []
	for event in _overlay_events:
		if time_ms >= event.time and time_ms <= event.end_time:
			active_overlays.append(event)
	active_overlays.sort_custom(func(a: OverlayEvent, b: OverlayEvent) -> bool:
		if a.layer == b.layer:
			return a.time < b.time
		return a.layer < b.layer
	)
	return active_overlays

func _ensure_overlay_node_pool(required_count: int) -> void:
	while _overlay_nodes.size() < required_count:
		var node := TextureRect.new()
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP
		node.visible = false
		_overlay_root.add_child(node)
		_overlay_nodes.append(node)

func _evaluate_overlay_state(event: OverlayEvent, local_time: float) -> OverlayRuntimeState:
	if event.frames.is_empty():
		return null
	var pair_indices := _find_frame_pair_indices(event.frames, local_time)
	var previous: OverlayEventFrame = event.frames[pair_indices.x]
	var next: OverlayEventFrame = event.frames[pair_indices.y]
	var alpha := _frame_ease_alpha(previous, next, local_time)
	var previous_state := _overlay_state_at(event.frames, pair_indices.x)
	var next_state := _overlay_state_at(event.frames, pair_indices.y)
	var state := OverlayRuntimeState.new()
	state.sprite_ref = previous_state.sprite_ref
	state.position = previous_state.position.lerp(next_state.position, alpha)
	state.scale = previous_state.scale.lerp(next_state.scale, alpha)
	state.rotation = lerpf(previous_state.rotation, next_state.rotation, alpha)
	state.opacity = lerpf(previous_state.opacity, next_state.opacity, alpha)
	return state

func _overlay_state_at(frames: Array[OverlayEventFrame], target_index: int) -> OverlayRuntimeState:
	var state := OverlayRuntimeState.new()
	for index in range(clampi(target_index, 0, frames.size() - 1) + 1):
		if not frames[index].sprite.is_empty():
			state.sprite_ref = frames[index].sprite
		if frames[index].has_opacity:
			state.opacity = frames[index].opacity
	var frame := frames[clampi(target_index, 0, frames.size() - 1)]
	state.position = frame.position
	state.scale = frame.scale
	state.rotation = frame.rotation
	return state

func _load_overlay_texture(reference: String) -> Texture2D:
	var chart := CM.selected_chart
	if chart == null or reference.is_empty() or not EventResourceRef.is_valid(reference):
		return null
	var path := EventResourceRef.resolve_sprite(chart, reference)
	var cache_index := _overlay_texture_paths.find(path)
	if cache_index >= 0:
		return _overlay_texture_values[cache_index]
	var texture: Texture2D = null
	if path.begins_with("res://"):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_overlay_texture_paths.append(path)
	_overlay_texture_values.append(texture)
	return texture

func _find_frame_pair_indices(frames: Array, local_time: float) -> Vector2i:
	var previous_index := 0
	var next_index := frames.size() - 1
	for index in range(frames.size()):
		var frame = frames[index]
		if frame.time <= local_time:
			previous_index = index
		if frame.time >= local_time:
			next_index = index
			break
	return Vector2i(previous_index, next_index)

func _frame_ease_alpha(previous: ChartEventFrame, next: ChartEventFrame, local_time: float) -> float:
	if previous == next or next.time <= previous.time:
		return 0.0
	var alpha := clampf((local_time - previous.time) / float(next.time - previous.time), 0.0, 1.0)
	return _apply_event_ease(alpha, next.ease)

func _apply_event_ease(value: float, ease_name: String) -> float:
	match ease_name:
		"in_sine": return 1.0 - cos(value * PI * 0.5)
		"out_sine": return sin(value * PI * 0.5)
		"in_out_sine": return -(cos(PI * value) - 1.0) * 0.5
		"in_quad": return value * value
		"out_quad": return 1.0 - (1.0 - value) * (1.0 - value)
		"in_out_quad": return 2.0 * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 2.0) * 0.5
		"in_cubic": return value * value * value
		"out_cubic": return 1.0 - pow(1.0 - value, 3.0)
		"in_out_cubic": return 4.0 * value * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 3.0) * 0.5
		_:
			return value

func _sort_notes(a: SpawnableNote, b: SpawnableNote) -> bool:
	return a.note.time < b.note.time

func _sort_rails(a: Rail, b: Rail) -> bool:
	return a.points[0].time < b.points[0].time

func _is_rail_active(rail: Rail, time: float = Game.current_time) -> bool:
	return (
		time >= rail.start_time - Score.T.GREAT and
		time <= rail.end_time
	)

func _update_standing_rail(time: float = Game.current_time) -> void:
	if standing_rail != null and _is_rail_active(standing_rail, time):
		return
	var new_rail := _find_closest_active_rail(time)
	if new_rail != null and new_rail != standing_rail:
		standing_rail = new_rail
		player.move_to_rail(new_rail)

func _find_closest_active_rail(time: float = Game.current_time) -> Rail:
	var current_x := player.position.x
	var closest: Rail = null
	var min_dist := INF
	for rail in rails:
		if not _is_rail_active(rail, time):
			continue
		var rail_x := GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(int(time)))
		var dist = abs(rail_x - current_x)
		if dist < min_dist:
			min_dist = dist
			closest = rail
	return closest

func _find_nearest_active_rail(dir: Note.Dir, time: float = Game.current_time) -> Rail:
	var current_x := GameplayPlayfield.normalized_x_to_world(
		standing_rail._get_rail_x_at_time(int(time)) if standing_rail != null else 0.5
	)
	var best: Rail = null
	var min_dist := INF
	for rail in rails:
		if rail == standing_rail or not _is_rail_active(rail, time):
			continue
		var rail_x := GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(int(time)))
		var delta_x := rail_x - current_x
		var is_in_dir := (dir == Note.Dir.LEFT and delta_x < 0.0) or (dir == Note.Dir.RIGHT and delta_x > 0.0)
		if is_in_dir:
			var dist = abs(delta_x)
			if dist < min_dist:
				min_dist = dist
				best = rail
	return best

func _move_player_in_direction(
	dir: Note.Dir,
	play_direction_animation: bool = true,
	time: float = Game.current_time
) -> void:
	var target_rail := _find_nearest_active_rail(dir, time)
	if target_rail != null:
		standing_rail = target_rail
		player.move_to_rail(target_rail, play_direction_animation)

func _check_miss() -> void:
	while next_process_note != null:
		var gap := next_process_note.time - Game.current_time
		if gap < -Score.T.BAD:
			_process_note_result(next_process_note, Score.MISS, gap)
		else:
			break

func _check_touch_notes() -> void:
	for note_entry in touch_notes:
		var note := note_entry.note
		if processed_notes.has(note):
			continue

		var gap := note.time - Game.current_time
		if gap > Score.T.OK:
			continue

		var note_rail := note_entry.rail

		match note.type:
			Note.NoteType.TRACE:
				if gap <= 0:
					if standing_rail == note_rail:
						_process_note_result(note, Score.PERPECT_PLUS, gap)
					else:
						_process_note_result(note, Score.MISS, gap)

			Note.NoteType.SPIKE:
				if gap <= 0:
					if standing_rail == note_rail:
						_process_note_result(note, Score.MISS, gap)
					else:
						processed_notes[note] = Score.NONE
						score.add_spike_dodge(note)
						_increment_combo()
						_update_combo_display()
						_play_combo_pop()
						var note_node: GameNote = spawned_note_nodes.get(note)
						if note_node != null:
							note_node.consume(Score.NONE)

func _input_action(time: float) -> void:
	if next_process_note == null or standing_rail == null:
		return

	if next_process_note.type != Note.NoteType.HIT:
		return

	var target_rail: Rail = note_owner_by_note.get(next_process_note)
	if target_rail == null or standing_rail != target_rail:
		return

	var gap := next_process_note.time - time
	var judgement := score.get_judgement(gap)
	if judgement == Score.NONE:
		return

	var note := next_process_note
	var is_long := note.length > 0
	_process_note_result(note, judgement, gap)
	if is_long:
		holding_long_hit_note = note

func _move_action(dir: Note.Dir, time: float) -> void:
	if (next_process_note != null and
			next_process_note.type == Note.NoteType.MOVE and
			note_owner_by_note.get(next_process_note) == standing_rail and
			next_process_note.dir == dir):

		var gap := next_process_note.time - time
		var judgement := score.get_judgement(gap)
		if judgement != Score.NONE:
			var note := next_process_note
			player.play_move_note_animation(note, dir)
			_process_note_result(note, judgement, gap)
			if note.length > 0:
				is_holding_long_move = true
				pending_move_dir = dir
				return
			else:
				_move_player_in_direction(dir, false, time)
				return

	_move_player_in_direction(dir, true, time)

func process_note(_j: int, note_node: GameNote) -> void:
	spawned_note_nodes.erase(note_node.note)

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

func _process_note_result(note: Note, judgement: int, gap: float) -> void:
	processed_notes[note] = judgement
	score.add_note_result(note, judgement, gap)

	if judgement == Score.MISS:
		combo = 0
	elif judgement != Score.NONE:
		_increment_combo()

	if judgement != Score.NONE:
		_spawn_judge_popup(judgement)

	_update_combo_display()
	if judgement != Score.MISS and judgement != Score.NONE:
		_play_combo_pop()
		player.spawn_hit_stars()

	if judgement != Score.MISS and judgement != Score.NONE and note.type != Note.NoteType.MOVE:
		player.play_hit_animation(note)

	if judgement == Score.MISS:
		_play_miss_sfx()
	elif judgement != Score.NONE:
		_play_note_sfx(note)

	var note_node: GameNote = spawned_note_nodes.get(note)
	if note_node != null:
		note_node.consume(judgement)

	if next_process_note == note:
		_set_next_note()

func _increment_combo() -> void:
	combo += 1
	score.high_combo = max(score.high_combo, combo)

func _check_result_transition() -> void:
	if _result_transition_started:
		return
	if Game.current_time < _last_note_time_ms + RESULT_DELAY_AFTER_LAST_NOTE_MS:
		return

	_result_transition_started = true
	Game.last_result_score = score
	Transition.transition_to(RESULT_SCENE_PATH, 1.0)

func _update_song_fade(delta: float) -> void:
	if song_end <= 0:
		return
	if Game.current_time <= song_end:
		return

	songplayer.volume_db = maxf(-80.0, songplayer.volume_db - (delta * SONG_FADE_DB_PER_SECOND))

func _rebuild_hitsound_cache() -> void:
	_hitsound_streams.clear()
	for hitsound in CM.parsed_chart.hitsounds:
		if hitsound == null or hitsound.stream == null:
			continue
		_hitsound_streams[hitsound.id] = hitsound.stream

func _play_note_sfx(note: Note) -> void:
	var stream := _resolve_note_sfx_stream(note)
	if stream == null:
		return
	_play_stream_sfx(stream)

func _play_miss_sfx() -> void:
	var stream: AudioStream = null
	if stream == null:
		return
	_play_stream_sfx(stream)

func _play_stream_sfx(stream: AudioStream) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var sfx_player := _sfx_players[_next_sfx_player_index]
	_next_sfx_player_index = (_next_sfx_player_index + 1) % _sfx_players.size()
	sfx_player.stream = stream
	sfx_player.play()

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
