extends Control

const SkinSerializationScript = preload("res://skin/skin_serialization.gd")

const RESULT_TICK_STREAM := preload("res://resources/audio/buttons/switch8.ogg")
const RESULT_START_DELAY := 1.0
const FULL_RANK_SEGMENT_DURATION := 0.28
const FINAL_SEGMENT_DURATION := 0.95
const FINAL_SEGMENT_DURATION_MAX := 1.35
const TICK_PLAYER_COUNT := 4
const MAX_SCORE_DISPLAY := 101.0
const RANK_DATA := [
	{"label": "D", "min": 0.0},
	{"label": "C", "min": 70.0},
	{"label": "B", "min": 85.0},
	{"label": "A", "min": 90.0},
	{"label": "S", "min": 95.0},
	{"label": "S+", "min": 99.0},
	{"label": "SS", "min": 100.0},
	{"label": "X+", "min": 101.0},
]

var score = Score.new()

@export var mockup_score = 0
@export var make_fake_score : bool = false
@export var fake_score : float = 90.05

@export var rank : Label
@export var next_rank_score : Label
@export var current_rank_score : Label
@export var score_label : Label

@onready var progress_bar: ProgressBar = $ProgressBar
@onready var player_sprite = $PlayerSprite
@onready var back_button = $Back
@onready var rank_up_particles: CPUParticles2D = $Rank/RankUp
@onready var just_plus_count_label: Label = $PanelContainer/VBoxContainer/GridContainer/JustPlusCount
@onready var just_count_label: Label = $PanelContainer/VBoxContainer/GridContainer/JustCount
@onready var good_count_label: Label = $PanelContainer/VBoxContainer/GridContainer/GoodCount
@onready var okay_count_label: Label = $PanelContainer/VBoxContainer/GridContainer/OkayCount
@onready var nah_count_label: Label = $PanelContainer/VBoxContainer/GridContainer/NahCount
@onready var miss_count_label: Label = $PanelContainer/VBoxContainer/GridContainer/MissCount
@onready var combo_value_label: Label = $PanelContainer/VBoxContainer/HBoxContainer/ComboValue
@onready var avg_value_label: Label = $PanelContainer/VBoxContainer/HBoxContainer2/AVGValue

var _tick_players: Array[AudioStreamPlayer] = []
var _next_tick_player_index := 0
var _tick_cooldown := 0.0
var _target_score := 0.0
var _current_rank_index := 0
var _rank_base_position := Vector2.ZERO
var _rank_base_scale := Vector2.ONE
var _current_rank_score_base_position := Vector2.ZERO
var _next_rank_score_base_position := Vector2.ZERO
var _label_pulse_scale := Vector2.ONE
var _player_sprite_base_position := Vector2.ZERO
var _player_sprite_base_scale := Vector2.ONE
var _player_sprite_tween: Tween

func build_fake_score() -> void:
	score = Score.new()
	score.notes = 1
	score.max_score = 100.0
	score.score = clampf(fake_score, 0.0, MAX_SCORE_DISPLAY)
	score.high_combo = 1
	score.perfect_plus = 1

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_create_tick_players()
	_resolve_score()
	_setup_player_sprite()
	_populate_result_details()

	await get_tree().process_frame
	_cache_animation_bases()
	_apply_rank_state(0)
	_update_live_score(0.0, 0)

	if back_button != null and back_button.button != null and not back_button.button.pressed.is_connected(_on_back_pressed):
		back_button.button.pressed.connect(_on_back_pressed)

	await get_tree().create_timer(RESULT_START_DELAY).timeout
	await _run_result_sequence()

func _resolve_score() -> void:
	if make_fake_score:
		build_fake_score()
		return

	if Game.last_result_score != null:
		score = Game.last_result_score
		return

	build_fake_score()

func _populate_result_details() -> void:
	just_plus_count_label.text = str(score.perfect_plus)
	just_count_label.text = str(score.perfect)
	good_count_label.text = str(score.great)
	okay_count_label.text = str(score.ok)
	nah_count_label.text = str(score.bad)
	miss_count_label.text = str(score.miss)
	combo_value_label.text = "%d/%d" % [score.high_combo, max(score.notes, 1)]
	avg_value_label.text = "-"

func _setup_player_sprite() -> void:
	var skin := PlayerSkinData.new()
	var loaded := false

	if not Config.ignore_chart_skin and CM.selected_chart != null and CM.selected_chart.file_skin != "":
		var chart_skin_path := SkinSerializationScript.ensure_chart_skin_path(CM.selected_chart)
		if chart_skin_path != "":
			loaded = skin.parse_objects(PlayerSkinData.TYPE.IN_CHART, "", chart_skin_path.get_file())

	if not loaded and Config.custom_skin_path != "":
		loaded = skin.parse_objects(
			PlayerSkinData.TYPE.IN_SKIN_FOLDER,
			Config.custom_skin_path.get_base_dir().get_file(),
			Config.custom_skin_path.get_file()
		)

	if not loaded:
		loaded = skin.parse_objects(PlayerSkinData.TYPE.BUILT_IN, "danshe", "skin.json")

	if not loaded:
		return

	player_sprite.skin = skin
	player_sprite.play_animation(skin.idle)
	if skin.idle != null and not skin.idle.frames.is_empty():
		player_sprite.texture = skin.idle.frames[0]
	
	player_sprite._apply_skin_scale()

func _cache_animation_bases() -> void:
	_refresh_label_pivots()
	_rank_base_position = rank.position
	_rank_base_scale = rank.scale
	_current_rank_score_base_position = current_rank_score.position
	_next_rank_score_base_position = next_rank_score.position
	_label_pulse_scale = Vector2.ONE
	_player_sprite_base_position = player_sprite.position
	_player_sprite_base_scale = player_sprite.scale

func _refresh_label_pivots() -> void:
	rank.pivot_offset = rank.size * 0.5
	current_rank_score.pivot_offset = current_rank_score.size * 0.5
	next_rank_score.pivot_offset = next_rank_score.size * 0.5
	score_label.pivot_offset = score_label.size * 0.5

func _create_tick_players() -> void:
	if not _tick_players.is_empty():
		return

	for index in range(TICK_PLAYER_COUNT):
		var tick_player := AudioStreamPlayer.new()
		tick_player.name = "ResultTickPlayer%d" % index
		tick_player.stream = RESULT_TICK_STREAM
		tick_player.bus = "SFX"
		add_child(tick_player)
		_tick_players.append(tick_player)

func _run_result_sequence() -> void:
	_target_score = clampf(score.total_score, 0.0, MAX_SCORE_DISPLAY)
	var final_rank_index := _get_rank_index_for_score(_target_score)
	var display_score := 0.0

	for rank_index in range(final_rank_index):
		var segment_start := _get_rank_min(rank_index)
		var segment_end := _get_rank_min(rank_index + 1)

		display_score = await _animate_score_segment(
			display_score,
			segment_end,
			FULL_RANK_SEGMENT_DURATION,
			false,
			segment_start,
			segment_end,
			rank_index
		)
		_play_player_dance()
		await _play_rank_transition(rank_index + 1)

	var final_rank_min := _get_rank_min(final_rank_index)
	var final_ratio := 0.0
	if _target_score > final_rank_min:
		final_ratio = inverse_lerp(final_rank_min, _get_rank_max(final_rank_index), _target_score)

	var final_duration := lerpf(FINAL_SEGMENT_DURATION, FINAL_SEGMENT_DURATION_MAX, final_ratio)
	await _animate_score_segment(
		display_score,
		_target_score,
		final_duration,
		true,
		final_rank_min,
		_target_score,
		final_rank_index
	)

	_apply_rank_state(final_rank_index)
	_update_live_score(_target_score)

func _animate_score_segment(
	start_score: float,
	end_score: float,
	duration: float,
	ease_out: bool,
	segment_start: float,
	segment_end: float,
	locked_rank_index: int = -1
) -> float:
	if is_equal_approx(start_score, end_score):
		_update_live_score(end_score, locked_rank_index)
		return end_score

	var elapsed := 0.0
	var current_score := start_score

	while elapsed < duration:
		var delta := get_process_delta_time()
		elapsed += delta

		var t := minf(elapsed / duration, 1.0)
		if ease_out:
			t = 1.0 - pow(1.0 - t, 3.0)

		current_score = lerpf(start_score, end_score, t)
		_update_live_score(current_score, locked_rank_index)
		_update_tick_sound(delta, current_score, segment_start, segment_end, ease_out)
		await get_tree().process_frame

	_update_live_score(end_score, locked_rank_index)
	return end_score

func _update_tick_sound(
	delta: float,
	current_score: float,
	segment_start: float,
	segment_end: float,
	ease_out: bool
) -> void:
	if _tick_players.is_empty():
		return

	_tick_cooldown -= delta
	if _tick_cooldown > 0.0:
		return

	var slow_ratio := 0.0
	if ease_out and segment_end > segment_start:
		slow_ratio = clampf(inverse_lerp(segment_start, segment_end, current_score), 0.0, 1.0)

	var total_ratio := 0.0
	if _target_score > 0.0:
		total_ratio = clampf(current_score / _target_score, 0.0, 1.0)

	_tick_cooldown = lerpf(0.032, 0.09, slow_ratio)

	var tick_player := _tick_players[_next_tick_player_index]
	_next_tick_player_index = (_next_tick_player_index + 1) % _tick_players.size()
	tick_player.pitch_scale = lerpf(0.85, 1.22, total_ratio)
	tick_player.play(0.1)

func _play_player_dance() -> void:
	if player_sprite == null or player_sprite.skin == null:
		return
	player_sprite.play_animation(player_sprite.get_hit_animation())
	_play_player_sprite_punch()

func _play_player_sprite_punch() -> void:
	if player_sprite == null:
		return
	if _player_sprite_tween != null:
		_player_sprite_tween.kill()

	player_sprite.position = _player_sprite_base_position
	player_sprite.scale = _player_sprite_base_scale

	_player_sprite_tween = create_tween()
	_player_sprite_tween.set_parallel(true)
	_player_sprite_tween.set_trans(Tween.TRANS_BACK)
	_player_sprite_tween.set_ease(Tween.EASE_OUT)
	_player_sprite_tween.tween_property(
		player_sprite,
		"position",
		_player_sprite_base_position + Vector2(0.0, -18.0),
		0.12
	)
	_player_sprite_tween.tween_property(
		player_sprite,
		"scale",
		Vector2(_player_sprite_base_scale.x * 0.94, _player_sprite_base_scale.y * 1.12),
		0.12
	)
	_player_sprite_tween.finished.connect(func() -> void:
		_player_sprite_tween = create_tween()
		_player_sprite_tween.set_parallel(true)
		_player_sprite_tween.set_trans(Tween.TRANS_BACK)
		_player_sprite_tween.set_ease(Tween.EASE_OUT)
		_player_sprite_tween.tween_property(player_sprite, "position", _player_sprite_base_position, 0.18)
		_player_sprite_tween.tween_property(player_sprite, "scale", _player_sprite_base_scale, 0.18)
	)

func _play_rank_transition(new_rank_index: int) -> void:
	_current_rank_index = new_rank_index

	if rank_up_particles != null:
		rank_up_particles.restart()
		rank_up_particles.emitting = true

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(rank, "position", _rank_base_position + Vector2(0.0, 28.0), 0.12)
	tween.tween_property(rank, "scale", _rank_base_scale * 0.82, 0.12)
	tween.tween_property(rank, "modulate:a", 0.0, 0.12)
	await tween.finished

	_apply_rank_state(new_rank_index)
	rank.position = _rank_base_position + Vector2(0.0, 20.0)
	rank.scale = _rank_base_scale * 1.16
	rank.modulate.a = 0.0

	var rank_tween := create_tween()
	rank_tween.set_parallel(true)
	rank_tween.set_trans(Tween.TRANS_BACK)
	rank_tween.set_ease(Tween.EASE_OUT)
	rank_tween.tween_property(rank, "position", _rank_base_position, 0.2)
	rank_tween.tween_property(rank, "scale", _rank_base_scale, 0.2)
	rank_tween.tween_property(rank, "modulate:a", 1.0, 0.18)

	_pulse_rank_score_labels()
	await rank_tween.finished

func _pulse_rank_score_labels() -> void:
	current_rank_score.position = _current_rank_score_base_position
	next_rank_score.position = _next_rank_score_base_position
	current_rank_score.scale = _label_pulse_scale
	next_rank_score.scale = _label_pulse_scale

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(current_rank_score, "position", _current_rank_score_base_position + Vector2(0.0, -10.0), 0.12)
	tween.tween_property(next_rank_score, "position", _next_rank_score_base_position + Vector2(0.0, -10.0), 0.12)
	tween.tween_property(current_rank_score, "scale", Vector2(1.0, 1.12), 0.12)
	tween.tween_property(next_rank_score, "scale", Vector2(1.0, 1.12), 0.12)

	tween.finished.connect(func() -> void:
		var settle_tween := create_tween()
		settle_tween.set_parallel(true)
		settle_tween.set_trans(Tween.TRANS_BACK)
		settle_tween.set_ease(Tween.EASE_OUT)
		settle_tween.tween_property(current_rank_score, "position", _current_rank_score_base_position, 0.16)
		settle_tween.tween_property(next_rank_score, "position", _next_rank_score_base_position, 0.16)
		settle_tween.tween_property(current_rank_score, "scale", _label_pulse_scale, 0.16)
		settle_tween.tween_property(next_rank_score, "scale", _label_pulse_scale, 0.16)
	)

func _apply_rank_state(rank_index: int) -> void:
	_current_rank_index = rank_index
	var current_rank_label := _get_rank_label(rank_index)
	var current_rank_min := _get_rank_min(rank_index)

	rank.text = current_rank_label
	current_rank_score.text = "%s\n%s" % [current_rank_label, _format_rank_score(current_rank_min)]

	if rank_index + 1 < RANK_DATA.size():
		next_rank_score.text = "%s\n%s" % [
			_get_rank_label(rank_index + 1),
			_format_rank_score(_get_rank_min(rank_index + 1))
		]
	else:
		next_rank_score.text = "MAX\n%s" % _format_rank_score(MAX_SCORE_DISPLAY)

	_apply_rank_colors(rank_index)
	call_deferred("_refresh_label_pivots")

func _update_live_score(display_score: float, locked_rank_index: int = -1) -> void:
	var display_rank_index := _get_rank_index_for_score(display_score)
	if locked_rank_index >= 0:
		display_rank_index = locked_rank_index
	score_label.text = _format_score(display_score)

	if display_rank_index != _current_rank_index:
		_apply_rank_state(display_rank_index)

	var current_rank_min := _get_rank_min(display_rank_index)
	var current_rank_max := _get_rank_max(display_rank_index)
	if current_rank_max <= current_rank_min:
		progress_bar.value = 1.0
		return

	progress_bar.value = clampf(
		inverse_lerp(current_rank_min, current_rank_max, display_score),
		0.0,
		1.0
	)

func _apply_rank_colors(rank_index: int) -> void:
	var current_color := _get_rank_color_for_score(_get_rank_min(rank_index))
	rank.add_theme_color_override("font_color", current_color)
	score_label.add_theme_color_override("font_color", current_color)
	current_rank_score.add_theme_color_override("font_color", current_color)

	if rank_index + 1 < RANK_DATA.size():
		next_rank_score.add_theme_color_override(
			"font_color",
			_get_rank_color_for_score(_get_rank_min(rank_index + 1))
		)
	else:
		next_rank_score.add_theme_color_override("font_color", current_color)

func _get_rank_index_for_score(value: float) -> int:
	var result := 0
	for index in range(RANK_DATA.size()):
		if value >= float(RANK_DATA[index]["min"]):
			result = index
	return result

func _get_rank_color_for_score(value: float) -> Color:
	if value >= 101.0:
		return Color(0.702, 0.846, 0.935, 1.0)
	if value >= 100.0:
		return Color(0.915, 0.643, 0.895, 1.0)
	if value >= 99.0:
		return Color(0.977, 0.872, 0.698, 1.0)
	if value >= 95.0:
		return Color(0.965, 0.925, 0.745, 1.0)
	if value >= 90.0:
		return Color("c6fbb7ff")
	if value >= 85.0:
		return Color(0.826, 0.374, 0.444, 1.0)
	if value >= 70.0:
		return Color(0.22, 0.191, 0.215, 1.0)
	return Color(0.071, 0.063, 0.071, 1.0)

func _get_rank_label(rank_index: int) -> String:
	return str(RANK_DATA[rank_index]["label"])

func _get_rank_min(rank_index: int) -> float:
	return float(RANK_DATA[rank_index]["min"])

func _get_rank_max(rank_index: int) -> float:
	if rank_index + 1 < RANK_DATA.size():
		return _get_rank_min(rank_index + 1)
	return MAX_SCORE_DISPLAY

func _format_score(value: float) -> String:
	return "%.2f%%" % value

func _format_rank_score(value: float) -> String:
	return "%d%%" % int(round(value))

func _on_back_pressed() -> void:
	Transition.return_to_menu(0.6)
