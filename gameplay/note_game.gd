extends Node3D
class_name GameNote

const SPAWN_FADE_PORTION := 0.18

var move_texture : Texture2D = preload("res://resources/textures/gameplay/move_note.png")
var spike_texture : Texture2D = preload("res://resources/textures/gameplay/spike_note.png")
var trace_texture : Texture2D = preload("res://resources/textures/gameplay/trace_note.png")

@export var mesh : MeshInstance3D
@export var note_sprite: Sprite3D
@export var arrow_sprite: Sprite3D

signal consumed(judge: int, note_node: GameNote)

var note: Note
var rail: Rail
var is_consumed := false
var _note_base_modulate := Color.WHITE
var _arrow_base_modulate := Color.WHITE
var _spawn_fade_active := false

func _ready() -> void:
	set_process(false)
	if note == null or rail == null:
		return
	position.x = GameplayPlayfield.normalized_x_to_world(rail._get_rail_x_at_time(note.time))
	position.z = GameplayPlayfield.local_z_from_start(rail.start_time, note.time)
	_cache_base_modulates()
	_set_note_texture()
	_initialize_spawn_fade()


func _cache_base_modulates() -> void:
	if note_sprite != null:
		_note_base_modulate = note_sprite.modulate
	if arrow_sprite != null:
		_arrow_base_modulate = arrow_sprite.modulate

func _set_note_texture() -> void:
	note_sprite.flip_h = false
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
	if note_sprite.texture != null:
		note_sprite.offset.y = note_sprite.texture.get_size().y / 2


func _initialize_spawn_fade() -> void:
	if not visible or note_sprite == null:
		return
	_spawn_fade_active = true
	_set_visual_alpha(0.0)
	set_process(true)
	_update_spawn_fade()


func _update_spawn_fade() -> void:
	if not _spawn_fade_active or note == null:
		return
	var visible_travel_time := GameplayPlayfield.get_visible_travel_time_ms()
	if visible_travel_time <= 0.0:
		_spawn_fade_active = false
		_set_visual_alpha(1.0)
		set_process(false)
		return

	var progress := 1.0 - ((float(note.time) - Game.current_time) / visible_travel_time)
	var fade_alpha := clampf(progress / SPAWN_FADE_PORTION, 0.0, 1.0)
	_set_visual_alpha(fade_alpha)
	if fade_alpha >= 1.0:
		_spawn_fade_active = false
		set_process(false)


func _set_visual_alpha(alpha: float) -> void:
	if note_sprite != null:
		note_sprite.modulate = Color(_note_base_modulate.r, _note_base_modulate.g, _note_base_modulate.b, _note_base_modulate.a * alpha)
	if arrow_sprite != null:
		arrow_sprite.modulate = Color(_arrow_base_modulate.r, _arrow_base_modulate.g, _arrow_base_modulate.b, _arrow_base_modulate.a * alpha)

func consume(judge: int) -> void:
	if is_consumed:
		return

	is_consumed = true
	consumed.emit(judge, self)
	queue_free()

func _process(_delta) -> void:
	_update_spawn_fade()
