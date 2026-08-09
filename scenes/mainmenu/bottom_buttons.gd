extends HBoxContainer


func _ready() -> void:
	$Play.button.pressed.connect(_play)
	$Back.button.pressed.connect(_back)

func _play() -> void:
	Game.play_selected_chart()

func _back() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.return_to_main_menu()
