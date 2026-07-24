extends VBoxContainer

func _ready() -> void:
	$Play.button.pressed.connect(_play)
	$Browse.button.pressed.connect(_play)
	$Options.button.pressed.connect(_open_options)
	$Exit.button.pressed.connect(_exit_game)

func _play() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.begin_song_select()

func _open_options() -> void:
	var popup := $"../SettingsPopup" as SettingsPopup
	if popup != null:
		popup.show_popup()


func _exit_game() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.begin_exit()
