extends Node

func loading_done() -> void:
	$MenuButtons.play("fade")
	$Loading.play("fade")
	$Character.play("to_side")
	$Logo.play("fade")

func clean_menu_things() -> void:
	$MenuButtons.play("fade",-1,-2,true)
	$Logo.play("fade",-1,-2,true)
	$Character.play("out")

func call_menu_things() -> void:
	$MenuButtons.play("fade")
	$Logo.play("fade")
	$Character.play("out",-1,-2,true)

func song_select_scene() -> void:
	$Charts.play("fade")
	$BottomButtons.play("fade")
	$SongInfo_Play.play("fade")
	pass

func main_menu() -> void:
	$Charts.play("fade",-1,-2,true)
	$SongInfo_Play.play("fade",-1,-4,true)
	$BottomButtons.play_backwards("fade")
	pass

func options() -> void:
	pass
