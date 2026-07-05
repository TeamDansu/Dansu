extends Sprite2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	CM.chart_selected.connect(_groove)
	CM.chartset_selected.connect(_groove)

func _groove(_chartset:ChartSet) -> void:
	# $AnimationPlayer.play("groove")
	pass
