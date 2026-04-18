extends RefCounted
class_name ChartEditorSelection

signal changed()

var selected_rail: Rail = null
var selected_note: Note = null
var selected_point_index := -1

func clear() -> void:
	if selected_rail == null and selected_note == null and selected_point_index == -1:
		return

	selected_rail = null
	selected_note = null
	selected_point_index = -1
	changed.emit()

func select_rail(rail: Rail) -> void:
	selected_rail = rail
	selected_note = null
	selected_point_index = -1
	changed.emit()

func select_note(rail: Rail, note: Note) -> void:
	selected_rail = rail
	selected_note = note
	selected_point_index = -1
	changed.emit()

func select_point(rail: Rail, point_index: int) -> void:
	selected_rail = rail
	selected_note = null
	selected_point_index = point_index
	changed.emit()

func has_point() -> bool:
	return selected_rail != null and selected_point_index >= 0 and selected_point_index < selected_rail.points.size()

func get_point() -> RailPoint:
	if not has_point():
		return null
	return selected_rail.points[selected_point_index]
