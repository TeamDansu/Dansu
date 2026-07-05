extends VBoxContainer

func _ready() -> void:
	$Play.button.pressed.connect(_play)
	$Browse.button.pressed.connect(_play)
	$Edit.visible = false

func _play() -> void:
	$"../Animations".clean_menu_things()
	await get_tree().create_timer(0.5).timeout
	$"../Animations".song_select_scene()

func _chart() -> void:
	$"../Animations".clean_menu_things()
