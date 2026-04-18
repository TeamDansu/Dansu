extends Button

@export var cover_art: TextureRect
@export var rating_hbox: HBoxContainer
var rating_displayer = preload("res://scenes/select/thumb_rating_displayer.tscn")

var item: SongListItem = null
var chartset: ChartSet = null
var charts: Array[Chart] = []
var primary_chart: Chart = null
var selected: bool = false
var current_cover_chart: Chart = null

func _ready():
	CM.chart_selected.connect(update_selected)
	CoverLoader.cover_loaded.connect(_on_cover_loaded)
	CoverLoader.cover_failed.connect(_on_cover_failed)

func set_item(value: SongListItem) -> void:
	item = value
	
	if item == null:
		chartset = null
		charts.clear()
		primary_chart = null
		current_cover_chart = null
		visible = false
		return

	chartset = item.chartset
	charts = item.charts
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

	if cover_art.texture != new_texture:
		cover_art.texture = new_texture
	
	for child in rating_hbox.get_children():
		rating_hbox.remove_child(child)
		child.queue_free()
	
	charts.sort_custom(_sort_by_rating)
	
	# $Title.text = primary_chart.title
	
	for chart in charts:
		var new_display: Panel = rating_displayer.instantiate()
		new_display.self_modulate = Game.get_color_from_rating(chart.rating)
		# new_display.get_child(0).text = str(int(chart.rating))
		rating_hbox.add_child(new_display)
	
	check_is_selected()
	_play_fade_out()

func check_is_selected():
	if charts.has(CM.selected_chart):
		cover_art.modulate = Color("#FFFFFF")
		return
	cover_art.modulate = Color("#808080")

func update_selected(_chart) -> void:
	check_is_selected()


func _on_cover_loaded(chart: Chart, texture: Texture2D) -> void:
	if chart == null or texture == null:
		return

	if chart != current_cover_chart:
		return
	
	if cover_art.texture != texture:
		cover_art.texture = texture
		_play_fade_out()

func _play_fade_out():
	$AnimationPlayer.play("cover_loaded")
	$AnimationPlayer.seek(0, true)

func _on_cover_failed(chart: Chart) -> void:
	if chart != current_cover_chart:
		return

	cover_art.texture = null

func _pressed() -> void:
	CM.emit_signal("chartset_selected",chartset)
	CM.emit_signal("chart_selected",primary_chart)
	if charts.size() >= 1:
		pass

func _sort_by_rating(a: Chart, b: Chart) -> bool:
	var ar := a.rating
	var br := b.rating
	return ar < br
