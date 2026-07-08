extends Node3D
class_name Player

const SkinSerializationScript = preload("res://skin/skin_serialization.gd")

@onready var sprite: PlayerSprite = $Sprite3D

var standing_rail: Rail = null
var _is_moving := false

func _ready() -> void:
	_setup_skin()

func _setup_skin() -> void:
	var skin := PlayerSkinData.new()
	var loaded := false

	if not Config.ignore_chart_skin and CM.selected_chart != null:
		if CM.selected_chart.file_skin != "":
			var chart_skin_path := SkinSerializationScript.ensure_chart_skin_path(CM.selected_chart)
			if chart_skin_path != "":
				loaded = skin.parse_objects(PlayerSkinData.TYPE.IN_CHART, "", chart_skin_path.get_file())

	if not loaded and Config.custom_skin_path != "":
		loaded = skin.parse_objects(
			PlayerSkinData.TYPE.IN_SKIN_FOLDER,
			Config.custom_skin_path.get_base_dir().get_file(),
			Config.custom_skin_path.get_file()
		)

	if not loaded:
		skin.parse_objects(
			PlayerSkinData.TYPE.BUILT_IN,
			"danshe",
			"skin.json"
		)

	sprite.skin = skin
	sprite._setup()

func _process(delta: float) -> void:
	if standing_rail == null:
		return
	var target_x := GameplayPlayfield.normalized_x_to_world(
		standing_rail._get_rail_x_at_time(int(Game.current_time))
	)
	if _is_moving:
		position.x = lerp(position.x, target_x, delta * 18.0)
		if abs(position.x - target_x) < 0.01:
			_is_moving = false
			if sprite.skin and _should_return_to_idle_after_move():
				sprite.play_animation(sprite.skin.idle)
	else:
		position.x = target_x

func move_to_rail(rail: Rail, play_direction_animation: bool = true) -> void:
	if rail == standing_rail:
		return
	var prev_x := position.x
	standing_rail = rail
	_is_moving = true

	if sprite.skin and play_direction_animation:
		var target_x := GameplayPlayfield.normalized_x_to_world(
			rail._get_rail_x_at_time(int(Game.current_time))
		)
		var move_animation := sprite.skin.left if target_x < prev_x else sprite.skin.right
		if move_animation != null:
			sprite.play_animation(move_animation)

func play_hit_animation(note: Note = null) -> void:
	if not sprite.skin:
		return

	var custom_animation: PlayerAnimation = null
	if note != null and int(note.animation) != 0:
		custom_animation = sprite.skin.get_animation_via_id(int(note.animation))

	if custom_animation != null:
		sprite.play_animation(custom_animation)
		return

	sprite.play_animation(sprite.get_hit_animation())

func play_move_note_animation(note: Note, dir: Note.Dir = Note.Dir.NONE) -> void:
	if not sprite.skin:
		return

	var custom_animation: PlayerAnimation = null
	if note != null and int(note.animation) != 0:
		custom_animation = sprite.skin.get_animation_via_id(int(note.animation))

	if custom_animation != null:
		sprite.play_animation(custom_animation)
		return

	var default_animation := sprite.get_hit_animation()
	if default_animation != null:
		sprite.play_animation(default_animation)
		return

	if dir == Note.Dir.LEFT and sprite.skin.left != null:
		sprite.play_animation(sprite.skin.left)
		pass
	elif dir == Note.Dir.RIGHT and sprite.skin.right != null:
		sprite.play_animation(sprite.skin.right)
		pass

func _should_return_to_idle_after_move() -> bool:
	if not sprite.skin:
		return false
	return (
		(sprite.skin.left != null and sprite.is_playing_animation(sprite.skin.left)) or
		(sprite.skin.right != null and sprite.is_playing_animation(sprite.skin.right))
	)

func reset() -> void:
	standing_rail = null
	_is_moving = false
	position = Vector3.ZERO
	_setup_skin()
