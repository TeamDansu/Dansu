extends HBoxContainer


func _ready() -> void:
	$Play.button.pressed.connect(_play)
	$Back.button.pressed.connect(_back)

func _play() -> void:
	CM.parse_selected_chart()
	Transition.transition_to("res://scenes/gameplay/gameplay.tscn",1.0)

func _back() -> void:
	$"../Animations".main_menu()
	$"../Animations".call_menu_things()
