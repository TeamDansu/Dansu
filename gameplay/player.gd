extends Node3D
class_name Player

@onready var sprite: PlayerSprite = $Sprite3D

var standing_rail: Rail = null
var _is_moving := false

func _ready() -> void:
	_setup_skin()

func _setup_skin() -> void:
	var skin := PlayerSkinData.new()
	var loaded := false

	if not Config.ignore_chart_skin:
		if CM.selected_chart.file_skin != "":
			loaded = skin.parse_objects(PlayerSkinData.TYPE.IN_CHART, "", CM.selected_chart.skin_path.get_file())

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
		position.x = lerp(position.x, target_x, delta * 20.0)
		if abs(position.x - target_x) < 0.01:
			_is_moving = false
			if sprite.skin:
				sprite.play_animation(sprite.skin.idle)
	else:
		position.x = target_x

func move_to_rail(rail: Rail, is_hit: bool = false) -> void:
	if rail == standing_rail:
		return
	var prev_x := position.x
	standing_rail = rail
	_is_moving = true

	if sprite.skin:
		if is_hit:
			sprite.play_animation(sprite.get_hit_animation())
		else:
			var target_x := GameplayPlayfield.normalized_x_to_world(
				rail._get_rail_x_at_time(int(Game.current_time))
			)
			if target_x < prev_x:
				sprite.play_animation(sprite.skin.left)
			else:
				sprite.play_animation(sprite.skin.right)

func play_hit_animation() -> void:
	if sprite.skin:
		sprite.play_animation(sprite.get_hit_animation())

func reset() -> void:
	standing_rail = null
	_is_moving = false
	position = Vector3.ZERO
	_setup_skin()
