extends Control

@onready var panel: PanelContainer = $PanelContainer
@onready var rating_hbox: HBoxContainer = %Levels
var rating_displayer = preload("res://scenes/mainmenu/star.tscn")

const NORMAL_BRIGHTNESS := 0.8
const SELECTED_BRIGHTNESS := 1.0
const NORMAL_ALPHA := 0.8
const HOVER_ALPHA := 0.95
const NORMAL_SCALE := Vector2.ONE
const SELECTED_SCALE := Vector2(1.05, 1.05)
const HOVER_SCALE := Vector2(1.1, 1.1)
const CLICK_SCALE := Vector2(0.96, 0.96)

var hover_tween: Tween
var click_tween: Tween

var item: SongListItem = null
var chartset: ChartSet = null
var charts: Array[Chart] = []
var primary_chart: Chart = null
var selected: bool = false
var current_cover_chart: Chart = null
var hovered := false

func _ready() -> void:
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	gui_input.connect(_on_gui_input)
	CM.chart_selected.connect(update_selected)
	CoverLoader.cover_loaded.connect(_on_cover_loaded)
	CoverLoader.cover_failed.connect(_on_cover_failed)
	panel.modulate.a = NORMAL_ALPHA
	check_is_selected()

func _on_enter() -> void:
	hovered = true
	_apply_hover_state()
	%Hover.play()

func _on_exit() -> void:
	hovered = false
	_apply_hover_state()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed()

func _apply_hover_state() -> void:
	if hover_tween:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_trans(Tween.TRANS_BACK)
	hover_tween.set_ease(Tween.EASE_OUT)

	var rest_scale := SELECTED_SCALE if selected else NORMAL_SCALE

	if hovered:
		hover_tween.tween_property(panel, "scale", HOVER_SCALE, 0.15)
		hover_tween.parallel().tween_property(panel, "modulate:a", HOVER_ALPHA, 0.15)
	else:
		hover_tween.tween_property(panel, "scale", rest_scale, 0.2)
		hover_tween.parallel().tween_property(panel, "modulate:a", NORMAL_ALPHA, 0.2)

func set_item(value: SongListItem) -> void:
	item = value
	
	if item == null:
		chartset = null
		charts.clear()
		primary_chart = null
		current_cover_chart = null
		_clear_rating_displays()
		visible = false
		return

	chartset = item.chartset
	charts = item.charts.duplicate()
	primary_chart = item.primary_chart

	_refresh()
	visible = true


func _refresh() -> void:
	var target_chart := primary_chart
	if target_chart == null and not charts.is_empty():
		target_chart = charts[0]

	current_cover_chart = target_chart

	var new_texture: Texture2D = null
	if current_cover_chart != null:
		if current_cover_chart.cover_image != null:
			new_texture = current_cover_chart.cover_image
		else:
			CoverLoader.request_cover(current_cover_chart)

	if %Thumb.texture != new_texture:
		%Thumb.texture = new_texture

	if primary_chart != null:
		%Title.text = primary_chart.title
		%Desc.text = "%s (%s)" % [primary_chart.artist, primary_chart.creator]
	else:
		%Title.text = ""
		%Desc.text = ""
	
	_clear_rating_displays()
	
	charts.sort_custom(_sort_by_rating)
	
	for chart in charts:
		var new_display: TextureRect = rating_displayer.instantiate()
		new_display.self_modulate = Game.get_color_from_rating(chart.rating)
		rating_hbox.add_child(new_display)

	rating_hbox.queue_sort()
	
	check_is_selected()

func check_is_selected():
	selected = charts.has(CM.selected_chart)
	var brightness := SELECTED_BRIGHTNESS if selected else NORMAL_BRIGHTNESS
	panel.self_modulate = Color(brightness, brightness, brightness, 1)
	if not hovered:
		panel.scale = SELECTED_SCALE if selected else NORMAL_SCALE

func update_selected(_chart) -> void:
	check_is_selected()


func _on_cover_loaded(chart: Chart, texture: Texture2D) -> void:
	if chart == null or texture == null:
		return

	if chart != current_cover_chart:
		return
	
	if %Thumb.texture != texture:
		%Thumb.texture = texture

func _on_cover_failed(chart: Chart) -> void:
	if chart != current_cover_chart:
		return

	%Thumb.texture = null

func _pressed() -> void:
	_play_click_animation()
	CM.select_chartset(chartset)
	CM.select_chart(primary_chart)
	%Click.play(0.1)

func _play_click_animation() -> void:
	if click_tween:
		click_tween.kill()

	if hover_tween:
		hover_tween.kill()

	click_tween = create_tween()
	click_tween.set_trans(Tween.TRANS_BACK)
	click_tween.set_ease(Tween.EASE_OUT)
	click_tween.tween_property(panel, "scale", CLICK_SCALE, 0.06)
	click_tween.tween_property(panel, "scale", HOVER_SCALE if hovered else (SELECTED_SCALE if selected else NORMAL_SCALE), 0.14)
	click_tween.parallel().tween_property(panel, "modulate:a", HOVER_ALPHA if hovered else NORMAL_ALPHA, 0.12)

func _sort_by_rating(a: Chart, b: Chart) -> bool:
	var ar := a.rating
	var br := b.rating
	return ar < br

func _clear_rating_displays() -> void:
	for child in rating_hbox.get_children():
		child.queue_free()
