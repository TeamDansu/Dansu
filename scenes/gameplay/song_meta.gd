extends Control

func _ready() -> void:
	%Title.text = CM.selected_chart.title
	%Artist.text = CM.selected_chart.artist
	%Info.text = CM.selected_chart.difficulty + "(" +CM.selected_chart.creator + ")"
	%Cover.texture = CM.selected_chart.cover_image
