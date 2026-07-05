extends Control

var star = preload("res://scenes/mainmenu/star_button.tscn")
const STAR_APPEAR_DELAY_STEP := 0.035

func _ready() -> void:
	CM.chartset_selected.connect(_update)
	if CM.selected_chartset != null:
		_update(CM.selected_chartset)

func _update(_chartset: ChartSet) -> void:
	for child in get_children():
		child.queue_free()
	if CM.selected_chartset:
		CM.selected_chartset.charts.sort_custom(_sort_by_rating)

		for index in range(CM.selected_chartset.charts.size()):
			var chart: Chart = CM.selected_chartset.charts[index]
			var new_star = star.instantiate()
			new_star.rating = chart.rating
			new_star.chart = chart
			add_child(new_star)
			if new_star.has_method("play_appear_animation"):
				new_star.play_appear_animation(index * STAR_APPEAR_DELAY_STEP)

func _sort_by_rating(a: Chart, b: Chart) -> bool:
	var ar := a.rating
	var br := b.rating
	return ar < br
