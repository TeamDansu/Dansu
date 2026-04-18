extends Node

@export var progress_bar : ProgressBar
@export var current_chartset_label: Label

var progress: float = 0.0
var loading_timer = 0.0

func _ready() -> void:
	CM._load(false)
	CM.progress_changed.connect(_update_progress)
	CM.chartset_loaded.connect(_chartset_loaded)
	CM.loading_finished.connect(_loading_finished)

func _process(delta):
	loading_timer += delta

func _update_progress(_progress: float) -> void:
	progress = _progress
	progress_bar.value = _progress

func _chartset_loaded(chartset: ChartSet) -> void:
	current_chartset_label.text = ("loading chart: " +chartset.charts[0].title)

func _loading_finished() -> void:
	print("done : %f" %loading_timer)
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	
