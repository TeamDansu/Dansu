extends VBoxContainer

func _ready() -> void:
	$Play.activated.connect(_play)
	$Browse.activated.connect(_play)
	$Edit.activated.connect(_edit)
	$Options.activated.connect(_open_options)
	$Exit.activated.connect(_exit_game)

func _play() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.begin_song_select(false)


func _edit() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.begin_song_select(true)

func _open_options() -> void:
	var popup := $"../SettingsPopup" as SettingsPopup
	if popup != null:
		popup.show_popup()


func _exit_game() -> void:
	var menu := get_parent() as DansuMainMenu
	if menu != null:
		menu.begin_exit()
