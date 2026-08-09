extends Node

enum Type {NOTICE , WARNING , ERROR}

func notice(message: String, type: Type) -> void:
	match type:
		Type.ERROR:
			push_error(message)
		Type.WARNING:
			push_warning(message)
		Type.NOTICE:
			print(message)
	## Todo
	## build UI and connect
