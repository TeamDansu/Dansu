extends HBoxContainer


func _ready() -> void:
	$Play.activated.connect(_play)
	$Back.activated.connect(_back)

func _play() -> void:
	Game.play_selected_chart()

func _back() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.return_to_main_menu()
