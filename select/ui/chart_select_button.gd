extends Button

var chart: Chart

func _ready():
	pressed.connect(_select)
	text = ("%0.2f" % chart.rating).rstrip("0").rstrip(".") + " " + chart.difficulty

func _select():
	CM._select_chart(chart)
	CM._select_chartset(chart.chart_set)
