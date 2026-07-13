extends Node
class_name EditorSaveController

@export var editor: Editor
@export var save_button: Button

func save_chart() -> bool:
	if editor == null or editor.chart == null:
		return false
	if not EditorChartOps.can_save(editor.chart):
		return false
	if EditorChartOps.save_chart(editor.chart, editor.previous_file_path):
		editor.previous_file_path = editor.chart.file_path
		update_save_button_state()
		editor.mark_saved_state()
		return true
	return false

func update_save_button_state() -> void:
	if save_button != null and editor != null:
		save_button.disabled = not EditorChartOps.can_save(editor.chart)
