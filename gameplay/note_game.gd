extends Node3D
class_name GameNote

signal consumed(judge: int, note_node: GameNote)

var note: Note
var rail: Rail
var is_consumed := false

func _ready() -> void:
	if note == null or rail == null:
		return
	position.x = GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(note.time))
	position.z = GameplayPlayfield.local_z_from_start(rail.start_time, note.time)

func consume(judge: int) -> void:
	if is_consumed:
		return

	is_consumed = true
	consumed.emit(judge, self)
	queue_free()
