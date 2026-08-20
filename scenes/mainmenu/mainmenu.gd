extends Control
class_name DansuMainMenu

const LOGO_IDLE_SCALE := 1.0
const LOGO_PEAK_SCALE := 1.15
const LOGO_DIP_SCALE := 0.96
const LOGO_PULSE_DURATION := 0.34
const LOGO_RETURN_SPEED := 12.0
const EXIT_START_DELAY := 0.4
const EXIT_FADE_DURATION := 1.5
const MIN_LOADING_DISPLAY_SECONDS := 1.0

@export var progress_bar : ProgressBar
@export var current_chartset_label: Label
@export var search_input: LineEdit
@export var sort_option_button: OptionButton
@export var chart_scroll: ChartScroll

@onready var exit_overlay: ColorRect = $ExitOverlay
@onready var audio_1: AudioStreamPlayer = $MenuAudioSwitcher/Audio1
@onready var audio_2: AudioStreamPlayer = $MenuAudioSwitcher/Audio2
@onready var menu_audio_switcher: MenuAudioSwitcher = $MenuAudioSwitcher
@onready var settings_popup: SettingsPopup = $SettingsPopup
@onready var logo: Control = $Logo
@onready var menu_buttons: VBoxContainer = $MenuButtons
@onready var bottom_buttons: HBoxContainer = $BottomButtons
@onready var bottom_play_button: MenuBigButton = $BottomButtons/Play
@onready var bottom_edit_button: MenuBigButton = $BottomButtons/Edit
@onready var new_chart_button: MenuBigButton = $BottomButtons/NewChart
@onready var new_difficulty_button: Button = $ChartInfo/NewDifficulty
@onready var chart_info_panel = $ChartInfo/Panel

var progress: float = 0.0
var loading_timer = 0.0
var is_exiting := false
var is_menu_transitioning := false
var is_editor_mode := false
var _loading_started_msec := 0
var _loading_completion_started := false
var _logo_pulse_time := LOGO_PULSE_DURATION
var _last_logo_half_beat_key := ""
var _last_logo_chart_key := ""
var _last_logo_playback_msec := -1.0

func _enter_tree() -> void:
	if is_node_ready():
		call_deferred("_refresh_chart_browser")

func _ready() -> void:
	_loading_started_msec = Time.get_ticks_msec()

	if progress_bar == null:
		progress_bar = $LoadingProgress/ProgressBar
	if current_chartset_label == null:
		current_chartset_label = $LoadingProgress/Label
	if search_input == null:
		search_input = $Charts/Search/SearchArea/SearchInput
	if sort_option_button == null:
		sort_option_button = $Charts/Search/SearchArea/SortOptionButton
	if chart_scroll == null:
		chart_scroll = $Charts

	exit_overlay.visible = false
	exit_overlay.color.a = 0.0
	logo.offset_transform_enabled = true
	_refresh_logo_pivot()
	_set_button_group_interaction(bottom_buttons, false)

	CM.progress_changed.connect(_update_progress)
	CM.database_sync_finished.connect(_on_database_sync_finished)

	if Game.stage == Game.GameStage.Loading:
		CM._load(false)

	if search_input != null:
		search_input.text_changed.connect(_on_search_text_changed)

	if sort_option_button != null:
		sort_option_button.item_selected.connect(_on_sort_item_selected)
		_setup_sort_options()

	new_difficulty_button.pressed.connect(open_new_difficulty_editor)
	_apply_song_select_mode(false)

func _process(delta):
	if is_exiting:
		return

	loading_timer += delta
	_update_logo_pulse(delta)

	if (
		Game.stage == Game.GameStage.Main
		and Game.main_menu_state == Game.MainMenuState.SongSelect
		and is_editor_mode
		and not is_menu_transitioning
	):
		if Input.is_action_just_pressed("shortcut_create_chartset"):
			open_new_chart_editor()
		elif Input.is_action_just_pressed("shortcut_new_difficulty"):
			open_new_difficulty_editor()
		elif Input.is_action_just_pressed("shortcut_enter_editor"):
			open_selected_chart_editor()


func _input(event: InputEvent) -> void:
	if is_exiting:
		get_viewport().set_input_as_handled()
		return

	if (
		Game.stage == Game.GameStage.Main
		and Game.main_menu_state == Game.MainMenuState.SongSelect
		and event is InputEventKey
		and event.pressed
		and not event.echo
		and event.ctrl_pressed
		and event.keycode == KEY_F5
	):
		_recalculate_all_chart_ratings()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_exiting:
		return

	if event.is_action_pressed("ui_cancel"):
		if is_menu_transitioning:
			get_viewport().set_input_as_handled()
			return

		if settings_popup != null and settings_popup.is_open():
			return

		if Game.main_menu_state == Game.MainMenuState.SongSelect:
			return_to_main_menu()
			get_viewport().set_input_as_handled()


func begin_song_select(editor_mode: bool = false) -> void:
	if is_exiting or is_menu_transitioning:
		return

	if Game.main_menu_state == Game.MainMenuState.SongSelect:
		return

	is_menu_transitioning = true
	_apply_song_select_mode(editor_mode)
	_set_button_group_interaction(menu_buttons, false)
	_set_button_group_interaction(bottom_buttons, false)
	Game.main_menu_state = Game.MainMenuState.SongSelect
	$Animations.clean_menu_things()
	await get_tree().create_timer(0.5).timeout
	if is_exiting or not is_inside_tree():
		return
	$Animations.song_select_scene()
	await $Animations/BottomButtons.animation_finished
	if is_exiting or not is_inside_tree():
		return
	_set_button_group_interaction(bottom_buttons, true)
	new_difficulty_button.disabled = not is_editor_mode
	is_menu_transitioning = false


func return_to_main_menu() -> void:
	if is_exiting or is_menu_transitioning:
		return

	if Game.main_menu_state == Game.MainMenuState.Home:
		return

	is_menu_transitioning = true
	new_difficulty_button.disabled = true
	_set_button_group_interaction(bottom_buttons, false)
	_set_button_group_interaction(menu_buttons, false)
	Game.main_menu_state = Game.MainMenuState.Home
	$Animations.main_menu()
	$Animations.call_menu_things()
	await $Animations/BottomButtons.animation_finished
	if is_exiting or not is_inside_tree():
		return
	_set_button_group_interaction(menu_buttons, true)
	is_menu_transitioning = false


func _set_button_group_interaction(group: Control, enabled: bool) -> void:
	if group == null:
		return

	for child in group.get_children():
		if child is MenuBigButton:
			child.set_interaction_enabled(enabled)


func _apply_song_select_mode(editor_mode: bool) -> void:
	is_editor_mode = editor_mode
	bottom_play_button.visible = not editor_mode
	bottom_edit_button.visible = editor_mode
	new_chart_button.visible = editor_mode
	new_difficulty_button.visible = editor_mode
	new_difficulty_button.disabled = true

	if chart_info_panel != null and chart_info_panel.has_method("set_score_ui_bound"):
		chart_info_panel.set_score_ui_bound(not editor_mode)
	if chart_scroll != null:
		chart_scroll.set_editor_mode(editor_mode)


func begin_exit() -> void:
	if is_exiting:
		return

	is_exiting = true
	if settings_popup != null:
		settings_popup.close_popup()

	exit_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	await get_tree().create_timer(EXIT_START_DELAY).timeout

	exit_overlay.visible = true
	$Switch7.play()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(exit_overlay, "color:a", 1.0, EXIT_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if audio_1 != null:
		tween.tween_property(audio_1, "volume_db", -80.0, EXIT_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if audio_2 != null:
		tween.tween_property(audio_2, "volume_db", -80.0, EXIT_FADE_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	await get_tree().create_timer(EXIT_FADE_DURATION * 0.1).timeout
	$Bye.play()
	await tween.finished
	get_tree().quit()

func _update_progress(_progress: float) -> void:
	progress = _progress
	if progress_bar != null:
		progress_bar.value = _progress

func _on_database_sync_finished(_success: bool) -> void:
	if _loading_completion_started:
		return

	_loading_completion_started = true
	var elapsed_seconds := float(Time.get_ticks_msec() - _loading_started_msec) / 1000.0
	var remaining_seconds := maxf(MIN_LOADING_DISPLAY_SECONDS - elapsed_seconds, 0.0)
	if remaining_seconds > 0.0:
		await get_tree().create_timer(remaining_seconds).timeout
	if not is_inside_tree() or is_exiting:
		return

	_finish_loading()


func _finish_loading() -> void:
	print("[charts] load time %f" %loading_timer)
	_update_progress(1.0)
	if chart_scroll != null:
		chart_scroll.rebuild_items()
	if current_chartset_label != null:
		current_chartset_label.text = "enjoy!"
	Game.stage = Game.GameStage.Main
	Game.main_menu_state = Game.MainMenuState.Home
	$Animations.loading_done()
	_refresh_chart_browser()


func _setup_sort_options() -> void:
	if sort_option_button == null:
		return

	sort_option_button.clear()
	sort_option_button.add_item("title", 0)
	sort_option_button.add_item("artist", 1)
	sort_option_button.add_item("rating", 2)
	sort_option_button.add_item("recent", 3)
	sort_option_button.select(0)


func _on_search_text_changed(new_text: String) -> void:
	if chart_scroll != null:
		chart_scroll.set_search_text(new_text)


func _on_sort_item_selected(index: int) -> void:
	if sort_option_button == null:
		return

	var sort_id := sort_option_button.get_item_id(index)
	if chart_scroll != null:
		chart_scroll.set_sort_mode(sort_id)

func _refresh_chart_browser() -> void:
	if chart_scroll != null:
		chart_scroll.rebuild_items()

func _recalculate_all_chart_ratings() -> void:
	var result := CM.recalculate_all_ratings()
	var updated := int(result.get("updated", 0))
	var failed := int(result.get("failed", 0))
	var total := int(result.get("total", 0))
	var message := "[rating] 전체 차트 재계산 완료: %d/%d" % [updated, total]
	if failed > 0:
		message += " (실패: %d)" % failed
		Notification.notice(message, Notification.Type.WARNING)
	else:
		print(message)

func open_new_chart_editor() -> void:
	if EditorChartOps.prepare_new_chartset_chart() == null:
		return
	Transition.transition_to("res://scenes/chart/editor/editor_scene.tscn", 1)

func open_new_difficulty_editor() -> void:
	if EditorChartOps.prepare_new_difficulty_chart() == null:
		return
	Transition.transition_to("res://scenes/chart/editor/editor_scene.tscn", 1)

func open_selected_chart_editor() -> void:
	if not CM.parse_selected_chart():
		return
	Transition.transition_to("res://scenes/chart/editor/editor_scene.tscn", 1)


func _update_logo_pulse(delta: float) -> void:
	if logo == null:
		return

	var chart := CM.selected_chart
	var playback_msec := _get_logo_chart_time_msec()
	if chart == null or playback_msec < 0.0:
		_last_logo_half_beat_key = ""
		_last_logo_chart_key = ""
		_last_logo_playback_msec = -1.0
		_logo_pulse_time = minf(_logo_pulse_time + delta, LOGO_PULSE_DURATION)
		logo.offset_transform_scale = logo.offset_transform_scale.lerp(
			Vector2.ONE * LOGO_IDLE_SCALE,
			delta * LOGO_RETURN_SPEED
		)
		return

	var chart_key := chart.uuid if not chart.uuid.is_empty() else chart.file_path
	if chart_key != _last_logo_chart_key or playback_msec + 1.0 < _last_logo_playback_msec:
		_last_logo_half_beat_key = ""
		_logo_pulse_time = LOGO_PULSE_DURATION

	var beat_key := _get_logo_beat_key(chart, playback_msec)
	if beat_key != "" and beat_key != _last_logo_half_beat_key:
		_last_logo_half_beat_key = beat_key
		_logo_pulse_time = 0.0

	_last_logo_chart_key = chart_key
	_last_logo_playback_msec = playback_msec
	_logo_pulse_time = minf(_logo_pulse_time + delta, LOGO_PULSE_DURATION)

	var target_scale := Vector2.ONE * _get_logo_pulse_scale(_logo_pulse_time / LOGO_PULSE_DURATION)
	logo.offset_transform_scale = logo.offset_transform_scale.lerp(
		target_scale,
		delta * LOGO_RETURN_SPEED
	)


func _refresh_logo_pivot() -> void:
	if logo == null:
		return

	logo.offset_transform_pivot_ratio = Vector2(0.5, 0.5)


func _get_logo_chart_time_msec() -> float:
	if menu_audio_switcher == null:
		return -1.0
	return menu_audio_switcher.get_current_chart_time_msec()


func _get_logo_beat_key(chart: Chart, playback_msec: float) -> String:
	if chart == null:
		return ""

	var active_timing: Timing = null
	var active_timing_index := -1

	for index in range(chart.timings.size()):
		var timing := chart.timings[index]
		if timing == null or timing.bpm <= 0.0:
			continue
		if timing.time <= playback_msec:
			active_timing = timing
			active_timing_index = index
		else:
			break

	if active_timing == null:
		for index in range(chart.timings.size()):
			var timing := chart.timings[index]
			if timing != null and timing.bpm > 0.0:
				active_timing = timing
				active_timing_index = index
				break

	if active_timing == null:
		return ""

	var beat_msec := 60000.0 / active_timing.bpm
	if beat_msec <= 0.0:
		return ""

	var local_msec := maxf(playback_msec - float(active_timing.time), 0.0)
	var beat_index := int(floor(local_msec / beat_msec))
	return "%d:%d" % [active_timing_index, beat_index]


func _get_logo_pulse_scale(phase: float) -> float:
	var t := clampf(phase, 0.0, 1.0)

	if t < 0.18:
		return lerpf(LOGO_IDLE_SCALE, LOGO_PEAK_SCALE, ease(t / 0.18, 0.45))
	if t < 0.46:
		return lerpf(LOGO_PEAK_SCALE, LOGO_DIP_SCALE, ease((t - 0.18) / 0.28, 1.4))
	return lerpf(LOGO_DIP_SCALE, LOGO_IDLE_SCALE, ease((t - 0.46) / 0.54, 2.0))
