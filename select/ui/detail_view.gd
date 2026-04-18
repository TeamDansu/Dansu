extends PanelContainer

@export var play_button : Button
@export var edit_button : Button

var chart_button = preload("res://scenes/select/chart_select_button.tscn")
var prev_chartset: ChartSet
var prev_chart: Chart

func _ready() -> void:
	CM.chart_selected.connect(_chart_selected)
	play_button.pressed.connect(_play)
	edit_button.pressed.connect(_edit)

func _play():
	CM.parse_selected_chart()
	get_tree().change_scene_to_file("res://scenes/gameplay/gameplay.tscn")
func _edit():
	if CM.selected_chart and CM.selected_chartset:
		CM.parse_selected_chart()
		get_tree().change_scene_to_file("res://scenes/editor/editor_scene.tscn")


func _chart_selected(chart:Chart):
	if prev_chart != chart:
		_update_chart(chart)
		prev_chart = chart
	if prev_chartset != CM.selected_chartset:
		_update_chartset()

func _update_chart(chart:Chart):

	%Title.text = chart.title
	%Cover.texture = chart.cover_image
	#%Rating.text = str(int(chart.rating))
	#%ChartInfo.text = chart.difficulty + "(" + chart.creator + ")"
	%RatingColor.self_modulate = Game.get_color_from_rating(chart.rating)
	%SongInfo.text = chart.artist + "(" + chart.source + ")"
	
	%AnimationPlayer.play("rating_rect_fade_out")
	%AnimationPlayer.seek(0,false)

func _update_chartset():
	for child in %Charts.get_children():
		child.queue_free()
	for new_chart in CM.selected_chartset.charts:
		var new_button = chart_button.instantiate()
		new_button.chart = new_chart
		%Charts.add_child(new_button)
