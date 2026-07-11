extends MeshInstance3D
@export var player : Node

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	position.x = player.position.x
	pass
