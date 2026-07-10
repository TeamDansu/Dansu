extends Control


func _ready() -> void:
	pass


func _process(_delta: float) -> void:
	var mouse := get_viewport().get_mouse_position()
	var _size := get_viewport_rect().size
	var normalized := mouse / _size
	self.position = normalized * -30
	pass
