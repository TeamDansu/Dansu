extends HBoxContainer


func _ready() -> void:
	$Play.activated.connect(_play)
	$Edit.activated.connect(_edit_chart)
	$NewChart.activated.connect(_new_chart)
	$Back.activated.connect(_back)

func _play() -> void:
	Game.play_selected_chart()


func _edit_chart() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.open_selected_chart_editor()


func _new_chart() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.open_new_chart_editor()

func _back() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.return_to_main_menu()
