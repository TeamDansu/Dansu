extends Node3D
class_name GameNote

var move_texture : Texture2D = preload("res://resorces/textures/gameplay/note-move.png")
var spike_texture : Texture2D = preload("res://resorces/textures/gameplay/note-spike.png")
var trace_texture : Texture2D = preload("res://resorces/textures/gameplay/note-trace.png")

@export var mesh : MeshInstance3D
@export var note_sprite: Sprite3D
@export var arrow_sprite: Sprite3D

signal consumed(judge: int, note_node: GameNote)

var note: Note
var rail: Rail
var is_consumed := false

func _ready() -> void:
	if note == null or rail == null:
		return
	position.x = GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(note.time))
	position.z = GameplayPlayfield.local_z_from_start(rail.start_time, note.time)
	_set_note_texture()

func _set_note_texture() -> void:
	match note.type:
		Note.NoteType.NONE:
			visible = false
		Note.NoteType.HIT:
			pass
		Note.NoteType.MOVE:
			note_sprite.texture = move_texture
			match note.dir:
				Note.Dir.LEFT:
					pass
				Note.Dir.RIGHT:
					note_sprite.flip_h = true
		Note.NoteType.TRACE:
			note_sprite.texture = trace_texture
		Note.NoteType.SPIKE:
			note_sprite.texture = spike_texture

func consume(judge: int) -> void:
	if is_consumed:
		return

	is_consumed = true
	consumed.emit(judge, self)
	queue_free()

func _process(_delta):
	pass
