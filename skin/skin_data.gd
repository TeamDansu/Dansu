extends RefCounted
class_name PlayerSkinData

enum TYPE { BUILT_IN, IN_CHART, IN_SKIN_FOLDER }

var player_animation = {}
var skin_name: String = "none"


var type : TYPE
var folder_name: String = ""
var json_name: String = ""

var texture_cache = {}

var animations: Array[PlayerAnimation] = []
var anim_idle: PlayerAnimation = null
var anim_left: PlayerAnimation = null
var anim_right: PlayerAnimation = null
var anim_jump: PlayerAnimation = null
var anim_land: PlayerAnimation = null
var anim_hits: Array[PlayerAnimation] = []
var repeat_idle := false

func get_full_path() -> String:
	match type:
		TYPE.BUILT_IN:
			pass
		TYPE.IN_CHART:
			pass
		TYPE.IN_SKIN_FOLDER:
			pass
	return ""

func parse_objects(_type:TYPE,_folder_name:String,_json_name:String):

	type = _type
	folder_name = _folder_name
	var path = get_full_path()

	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("FILE : %s is missing" , path)
	var json = JSON.parse_string(file.get_as_text())
	skin_name = json["name"]

	if "animations" in json:
		for animation in json["animations"]:
			var _frames = animation.get("frames", [])
			var textures = []
			for _frame in _frames:
				var _texture = load_texture(_frame)
				if _texture:
					textures.append(_texture)
			var new_animation = PlayerAnimation.new()
			new_animation.id = animation.get("id", -1)
			new_animation.textures = textures
			new_animation.fps = animation.get("fps", 10)
			new_animation.animation.get("effect",PlayerAnimation.EFFECT_NONE)
			animations.append(new_animation)
	if "player" in json:
		for id in json["animation"]["hits"]:
			var animation = get_animation_via_id(id)
			if animation:
				anim_hits.append(animation)
		anim_idle = get_animation_via_id(int(json["player"]["idle"]))
		anim_jump = get_animation_via_id(int(json["player"]["jump"]))
		anim_land = get_animation_via_id(int(json["player"]["land"]))
		anim_left = get_animation_via_id(int(json["player"]["left"]))
		anim_right = get_animation_via_id(int(json["player"]["right"]))
		repeat_idle = bool(json["player"]["repeat_idle"])

func get_animation_via_id(id:int) -> PlayerAnimation:
	for animation in animations:
		if animation.id == id:
			return animation
	return null

func load_texture(file_name: String) -> Texture2D:
	if texture_cache.has(file_name):
		return texture_cache[file_name]
	var base_dir = get_full_path()
	var texture_path = base_dir.path_join("sprite").path_join(file_name)
	var _texture: Texture2D = null

	if texture_path.begins_with("res://"):
		_texture = load(texture_path)

	elif FileAccess.file_exists(texture_path):
		var image = Image.new()
		if image.load(texture_path) == OK:
			_texture = ImageTexture.create_from_image(image)
		else:
			_texture = load("res://resorces/sprite/danshe_dance_1.png")

	if _texture:
		texture_cache[file_name] = _texture

	return _texture
