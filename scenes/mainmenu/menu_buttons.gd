extends VBoxContainer

func _ready() -> void:
	$Play.button.pressed.connect(_play)
	$Browse.button.pressed.connect(_play)
	$Options.button.pressed.connect(_open_options)
	$Exit.button.pressed.connect(_exit_game)

func _play() -> void:
	var menu := get_parent()
	if menu != null and menu.has_method("begin_song_select"):
		menu.begin_song_select()

func _chart() -> void:
	$"../Animations".clean_menu_things()

func _open_options() -> void:
	var popup := $"../SettingsPopup"
	if popup != null and popup.has_method("show_popup"):
		popup.show_popup()


func _exit_game() -> void:
	var menu := get_parent()
	if menu != null and menu.has_method("begin_exit"):
		menu.begin_exit()
