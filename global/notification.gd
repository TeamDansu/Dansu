extends Node

enum Type {NOTICE , WARNING , ERROR}

func _ready() -> void:
	# Setup
	pass


func _process(_delta: float) -> void:
	pass

func notice(message: String,type:Type ):
	match type:
		Type.ERROR:
			push_error(message)
		Type.WARNING:
			print(message)
	## Todo
	## build UI and connect
